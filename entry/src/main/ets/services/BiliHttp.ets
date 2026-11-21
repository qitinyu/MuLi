import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { common, Want } from '@kit.AbilityKit';

/**
 * bilibili HTTP 网关。
 * 职责：统一 UA / Referer / Origin、维护 cookie（buvid3 设备指纹 + 登录态）、JSON 容错解析。
 *
 * 风控要点（实测）：
 * - 不带 buvid3 的请求会被 -352 拦截（直播接口尤甚），buvid3 必须持久化后复用；
 * - 登录态由 SESSDATA / bili_jct / DedeUserID 三个 cookie 组成，扫码成功时由 Set-Cookie 下发。
 */
const TAG = 'MuLiNet';

class BiliCookie {
  static readonly BUVID_STORE: string = 'muli_device';
  static readonly AUTH_STORE: string = 'muli_auth';

  static buvid3: string = '';
  static buvid4: string = '';
  /** 登录态 cookie 原文（不含设备指纹） */
  static authCookie: string = '';
  /**
   * b_nut = 浏览器「首次访问」时间戳。
   * b 站风控会校验它是否稳定，早期实现每次请求都取当前时间，
   * 导致同一个账号的指纹在服务端看起来每次都在变，nav 因此判未登录。
   */
  static bNut: number = 0;
  /** 是否已从官方 spi 接口取到真实设备指纹（取到后不再重复请求） */
  private static fingerprintReady: boolean = false;

  static async init(context: common.UIAbilityContext): Promise<void> {
    try {
      const device: preferences.Preferences = await preferences.getPreferences(context, BiliCookie.BUVID_STORE);
      BiliCookie.buvid3 = device.getSync('buvid3', '') as string;
      BiliCookie.buvid4 = device.getSync('buvid4', '') as string;
      BiliCookie.bNut = Math.floor(Number(device.getSync('b_nut', 0)) || 0);
      const auth: preferences.Preferences = await preferences.getPreferences(context, BiliCookie.AUTH_STORE);
      BiliCookie.authCookie = auth.getSync('cookie', '') as string;
    } catch (err) {
      console.error(`${TAG} cookie init failed: ${String(err)}`);
    }
    const persisted: boolean = BiliCookie.buvid3.length > 0 && BiliCookie.buvid4.length > 0;
    if (BiliCookie.buvid3.length === 0) {
      BiliCookie.buvid3 = BiliCookie.randomBuvid();
    }
    if (BiliCookie.buvid4.length === 0) {
      BiliCookie.buvid4 = BiliCookie.randomBuvid4();
    }
    if (BiliCookie.bNut === 0) {
      BiliCookie.bNut = Math.floor(Date.now() / 1000);
    }
    await BiliCookie.persistDevice(context);
    // 本地随机指纹会被风控判定为「陌生设备」，nav 等登录态接口直接判未登录，
    // 所以只在**第一次启动（磁盘里还没有指纹）**时补一次 spi。
    // 注意：spi 每次请求都会下发全新的 buvid3/buvid4，如果每次启动都刷一遍，
    // 服务端看到的就是「同一个账号每次启动都在换设备」，已有的 SESSDATA 会被判无效。
    if (!persisted) {
      await BiliCookie.ensureFingerprint();
      await BiliCookie.persistDevice(context);
    } else {
      BiliCookie.fingerprintReady = true;
    }
    console.info(`${TAG} cookie init done b3Len=${BiliCookie.buvid3.length} b4Len=${BiliCookie.buvid4.length} ` +
      `authKeys=${BiliCookie.authKeys()} nut=${BiliCookie.bNut}`);
  }

  /**
   * 用官方 /x/frontend/finger/spi 取真实设备指纹。
   * 这是「扫码成功但 nav 一直说没登录」的另一半原因：随机 buvid3 没有服务端记录。
   */
  static async ensureFingerprint(): Promise<void> {
    if (BiliCookie.fingerprintReady) {
      return;
    }
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(
        'https://api.bilibili.com/x/frontend/finger/spi', {
          method: http.RequestMethod.GET,
          header: {
            'User-Agent': BiliHttp.UA,
            'Referer': 'https://www.bilibili.com/'
          },
          connectTimeout: 6000,
          readTimeout: 8000,
          expectDataType: http.HttpDataType.STRING
        });
      const text: string = typeof response.result === 'string' ? response.result as string : '';
      if (text.length === 0) {
        return;
      }
      const body: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const data: Record<string, Object> = J.obj(body, 'data');
      const b3: string = J.str(data, 'b_3');
      const b4: string = J.str(data, 'b_4');
      if (b3.length > 0) {
        BiliCookie.buvid3 = b3;
      }
      if (b4.length > 0) {
        BiliCookie.buvid4 = b4;
      }
      BiliCookie.fingerprintReady = b3.length > 0;
      console.info(`${TAG} fingerprint from spi b3Len=${b3.length} b4Len=${b4.length}`);
    } catch (err) {
      console.warn(`${TAG} spi fingerprint failed: ${String(err)}`);
    } finally {
      request.destroy();
    }
  }

  private static async persistDevice(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, BiliCookie.BUVID_STORE);
      store.putSync('buvid3', BiliCookie.buvid3);
      store.putSync('buvid4', BiliCookie.buvid4);
      store.putSync('b_nut', BiliCookie.bNut);
      store.flushSync();
    } catch (err) {
      console.error(`${TAG} persist device failed: ${String(err)}`);
    }
  }

  /** 供页面在同步了 WebView 指纹后落盘（Web 登录的设备指纹必须与后续请求一致） */
  static async persistFingerprint(context: common.UIAbilityContext): Promise<void> {
    await BiliCookie.persistDevice(context);
  }

  /** 诊断用：当前登录态 cookie 里有哪些 key（不打印值，避免日志泄露凭据） */
  static authKeys(): string {
    const text: string = BiliCookie.authCookie;
    if (text.length === 0) {
      return '';
    }
    const segments: Array<string> = text.split(';');
    const keys: Array<string> = [];
    for (let i = 0; i < segments.length; i++) {
      const segment: string = segments[i].trim();
      const eq: number = segment.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const key: string = segment.substring(0, eq);
      const value: string = segment.substring(eq + 1);
      if (key === 'SESSDATA') {
        // 记录裸逗号个数：非 0 说明历史版本解码过，发送前会被规范化
        keys.push(`SESSDATA(${value.length},comma=${value.split(',').length - 1})`);
      } else {
        keys.push(`${key}(${value.length})`);
      }
    }
    return keys.join(',');
  }

  static async saveAuth(context: common.UIAbilityContext, cookie: string): Promise<void> {
    BiliCookie.authCookie = cookie;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, BiliCookie.AUTH_STORE);
      store.putSync('cookie', cookie);
      store.flushSync();
    } catch (err) {
      console.error(`${TAG} persist auth failed: ${String(err)}`);
    }
  }

  static async clearAuth(context: common.UIAbilityContext): Promise<void> {
    BiliCookie.authCookie = '';
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, BiliCookie.AUTH_STORE);
      store.deleteSync('cookie');
      store.flushSync();
    } catch (err) {
      console.error(`${TAG} clear auth failed: ${String(err)}`);
    }
  }

  static header(): string {
    const parts: Array<string> = [];
    const auth: string = BiliCookie.authHeaderText();
    // WebView 登录会把设备指纹一起同步进 authCookie，这里先去重，
    // 否则同一个 Cookie 头里出现两个 buvid3，服务端可能取到错误那个。
    if (auth.indexOf('buvid3=') < 0) {
      parts.push(`buvid3=${BiliCookie.buvid3}`);
    }
    if (BiliCookie.buvid4.length > 0 && auth.indexOf('buvid4=') < 0) {
      parts.push(`buvid4=${BiliCookie.buvid4}`);
    }
    if (auth.indexOf('b_nut=') < 0) {
      parts.push(`b_nut=${BiliCookie.bNut > 0 ? BiliCookie.bNut : Math.floor(Date.now() / 1000)}`);
    }
    if (auth.length > 0) {
      parts.push(auth);
    }
    return parts.join('; ');
  }

  /**
   * 登录态 cookie 的「可发送文本」。
   *
   * 关键：b 站的 SESSDATA 本身是 URL 编码形态（内部逗号写作 %2C）。
   * 早期实现从 data.url 里取 cookie 时做了 decodeURIComponent，
   * 把 %2C 还原成裸逗号存了下来；裸逗号在 Cookie 头里会被部分服务端当成
   * 分隔符处理，于是 nav 恒返回 -101「账号未登录」—— 明明已登录却没有任何数据。
   * 这里统一在发送前把 SESSDATA 的裸逗号写回 %2C（幂等），
   * 既能修好历史存下的 cookie，也不影响新登录。
   */
  private static authHeaderText(): string {
    const text: string = BiliCookie.authCookie;
    if (text.length === 0 || text.indexOf('SESSDATA=') < 0 || text.indexOf(',') < 0) {
      return text;
    }
    const segments: Array<string> = text.split(';');
    for (let i = 0; i < segments.length; i++) {
      const segment: string = segments[i].trim();
      const eq: number = segment.indexOf('=');
      if (eq <= 0 || segment.substring(0, eq) !== 'SESSDATA') {
        continue;
      }
      const value: string = segment.substring(eq + 1);
      if (value.indexOf(',') >= 0) {
        segments[i] = `SESSDATA=${value.split(',').join('%2C')}`;
      }
    }
    return segments.join('; ');
  }

  static csrf(): string {
    return BiliCookie.value('bili_jct');
  }

  static isLogin(): boolean {
    return BiliCookie.value('SESSDATA').length > 0;
  }

  /**
   * 登录态里记录的账号 mid（DedeUserID）。
   * nav 被风控挡回时它是唯一还能确定「当前是谁」的线索，
   * 有了 mid 就能用公开空间接口把头像昵称补上。
   */
  static mid(): number {
    const text: string = BiliCookie.value('DedeUserID');
    if (text.length === 0) {
      return 0;
    }
    const parsed: number = Number(text);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
  }

  static value(name: string): string {
    const text: string = BiliCookie.authCookie;
    if (text.length === 0) {
      return '';
    }
    const segments: Array<string> = text.split(';');
    for (let i = 0; i < segments.length; i++) {
      const segment: string = segments[i].trim();
      const eq: number = segment.indexOf('=');
      if (eq > 0 && segment.substring(0, eq) === name) {
        return segment.substring(eq + 1);
      }
    }
    return '';
  }

  /** 把服务端 Set-Cookie 合并进登录态：同名覆盖，其余保留 */
  static mergeSetCookie(raw: string): void {
    if (raw === undefined || raw === null || raw.length === 0) {
      return;
    }
    const incoming: Array<string> = raw.split(',');
    const merged: Array<string> = [];
    const existing: Array<string> = BiliCookie.authCookie.length > 0 ? BiliCookie.authCookie.split(';') : [];
    for (let i = 0; i < existing.length; i++) {
      const pair: string = existing[i].trim();
      if (pair.length > 0) {
        merged.push(pair);
      }
    }
    for (let i = 0; i < incoming.length; i++) {
      const piece: string = incoming[i].trim();
      const first: string = piece.split(';')[0].trim();
      const eq: number = first.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const key: string = first.substring(0, eq);
      let replaced: boolean = false;
      for (let j = 0; j < merged.length; j++) {
        const eq2: number = merged[j].indexOf('=');
        if (eq2 > 0 && merged[j].substring(0, eq2) === key) {
          merged[j] = first;
          replaced = true;
          break;
        }
      }
      if (!replaced) {
        merged.push(first);
      }
    }
    BiliCookie.authCookie = merged.join('; ');
  }

  /**
   * 从扫码轮询成功返回的 data.url 里提取登录 cookie。
   * passport 在 code=0 时把 SESSDATA / bili_jct / DedeUserID 放在 url 的 query 上，
   * 而部分网络栈不会把跨域 Set-Cookie 透传给 http.HttpResponse.cookies，
   * 只依赖 header 会导致「扫码成功但登录态不更新」，因此这里做二次兜底。
   */
  static mergeFromLoginUrl(url: string): boolean {
    if (url === undefined || url === null || url.length === 0) {
      return false;
    }
    const mark: number = url.indexOf('?');
    if (mark < 0) {
      return false;
    }
    const keys: Array<string> = ['SESSDATA', 'bili_jct', 'DedeUserID', 'DedeUserID__ckMd5', 'sid', 'refresh_token'];
    const query: string = url.substring(mark + 1);
    const segments: Array<string> = query.split('&');
    const merged: Array<string> = BiliCookie.authCookie.length > 0 ? BiliCookie.authCookie.split(';') : [];
    let found: boolean = false;
    for (let i = 0; i < segments.length; i++) {
      const segment: string = segments[i];
      const eq: number = segment.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const key: string = segment.substring(0, eq);
      if (keys.indexOf(key) < 0) {
        continue;
      }
      // data.url 里的值可能被 URL 编码过一次，也可能被编码过两次。
      // b 站 SESSDATA 的真实值本身就带 %2C，只要没有 %25（即 % 被再次编码）就保持原样，
      // 否则会把 %2C 解成裸逗号，服务端解析截断后判「账号未登录」。
      const rawValue: string = segment.substring(eq + 1);
      let value: string = rawValue;
      if (rawValue.indexOf('%25') >= 0) {
        try {
          value = decodeURIComponent(rawValue);
        } catch (err) {
          value = rawValue;
        }
      }
      const pair: string = `${key}=${value}`;
      found = true;
      let replaced: boolean = false;
      for (let j = 0; j < merged.length; j++) {
        const trimmed: string = merged[j].trim();
        const eq2: number = trimmed.indexOf('=');
        if (eq2 > 0 && trimmed.substring(0, eq2) === key) {
          merged[j] = pair;
          replaced = true;
          break;
        }
      }
      if (!replaced) {
        merged.push(pair);
      }
    }
    if (found) {
      BiliCookie.authCookie = merged.join('; ');
    }
    return found;
  }

  /**
   * 合并 Web 组件里读到的 cookie（"k=v; k2=v2" 形态）。
   *
   * 这里刻意「全量同步」而不是只挑登录三件套：
   * 网页登录时下发 SESSDATA 的环境里还带着 WebView 自己的 buvid3 / buvid4 / _uuid / b_lsid 等
   * 风控指纹，只搬 SESSDATA 会让服务端认为「登录态来自别的设备」，
   * nav 直接返回「账号未登录」—— 表现就是「显示已登录但没有数据」。
   */
  static mergeRawCookie(raw: string): boolean {
    if (raw === undefined || raw === null || raw.length === 0) {
      return false;
    }
    // 纯播放/渲染偏好，与登录态无关，跳过以免把 Cookie 头撑得过长
    const skip: Array<string> = [
      'CURRENT_FNVAL', 'CURRENT_QUALITY', 'header_theme_version', 'home_fee', 'PVID', 'buvid_fp_plain'
    ];
    const segments: Array<string> = raw.split(';');
    let found: boolean = false;
    for (let i = 0; i < segments.length; i++) {
      const segment: string = segments[i].trim();
      const eq: number = segment.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const key: string = segment.substring(0, eq);
      const value: string = segment.substring(eq + 1);
      if (value.length === 0 || skip.indexOf(key) >= 0) {
        continue;
      }
      BiliCookie.upsert(`${key}=${value}`);
      if (key === 'buvid3') {
        BiliCookie.buvid3 = value;
      } else if (key === 'buvid4') {
        BiliCookie.buvid4 = value;
      } else if (key === 'b_nut') {
        const nut: number = Math.floor(Number(value));
        if (nut > 0) {
          BiliCookie.bNut = nut;
        }
      } else if (key === 'SESSDATA') {
        found = true;
      }
    }
    return found;
  }

  /** 同名覆盖写入登录态 cookie */
  private static upsert(pair: string): void {
    const eq: number = pair.indexOf('=');
    if (eq <= 0) {
      return;
    }
    const key: string = pair.substring(0, eq);
    const merged: Array<string> = BiliCookie.authCookie.length > 0 ? BiliCookie.authCookie.split(';') : [];
    for (let i = 0; i < merged.length; i++) {
      const trimmed: string = merged[i].trim();
      const eq2: number = trimmed.indexOf('=');
      if (eq2 > 0 && trimmed.substring(0, eq2) === key) {
        merged[i] = pair;
        BiliCookie.authCookie = merged.join('; ');
        return;
      }
    }
    merged.push(pair);
    BiliCookie.authCookie = merged.join('; ');
  }

  private static randomBuvid(): string {
    const hex: string = '0123456789ABCDEF';
    let uuid: string = '';
    for (let i = 0; i < 36; i++) {
      if (i === 8 || i === 13 || i === 18 || i === 23) {
        uuid += '-';
        continue;
      }
      uuid += hex[Math.floor(Math.random() * 16)];
    }
    return `${uuid}infoc`;
  }

  private static randomBuvid4(): string {
    const hex: string = '0123456789ABCDEF';
    let text: string = '';
    for (let i = 0; i < 32; i++) {
      text += hex[Math.floor(Math.random() * 16)];
    }
    return `${text}-${Math.floor(Date.now() / 1000)}-026111-virtual`;
  }
}

export class BiliHttp {
  static readonly UA: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static readonly API_HOST: string = 'api.bilibili.com';
  static readonly PASSPORT_HOST: string = 'passport.bilibili.com';
  static readonly LIVE_HOST: string = 'api.live.bilibili.com';

  private static headers(referer: string, withCookie: boolean): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': BiliHttp.UA,
      'Referer': referer,
      'Origin': 'https://www.bilibili.com',
      'Accept': 'application/json, text/plain, */*'
    };
    if (withCookie) {
      headers['Cookie'] = BiliCookie.header();
    }
    return headers;
  }

  static async getJson(host: string, path: string, query: Record<string, string>,
    referer: string = 'https://www.bilibili.com/'): Promise<Record<string, Object>> {
    const keys: Array<string> = Object.keys(query);
    let queryText: string = '';
    for (let i = 0; i < keys.length; i++) {
      if (i > 0) {
        queryText += '&';
      }
      queryText += `${encodeURIComponent(keys[i])}=${encodeURIComponent(query[keys[i]])}`;
    }
    const url: string = queryText.length > 0
      ? `https://${host}${path}?${queryText}`
      : `https://${host}${path}`;
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: BiliHttp.headers(referer, true),
        connectTimeout: 10000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.STRING
      });
      BiliCookie.mergeSetCookie(response.cookies);
      return BiliHttp.parse(response.result);
    } finally {
      request.destroy();
    }
  }

  static async postForm(host: string, path: string, form: Record<string, string>,
    referer: string = 'https://www.bilibili.com/'): Promise<Record<string, Object>> {
    const keys: Array<string> = Object.keys(form);
    let body: string = '';
    for (let i = 0; i < keys.length; i++) {
      if (i > 0) {
        body += '&';
      }
      body += `${encodeURIComponent(keys[i])}=${encodeURIComponent(form[keys[i]])}`;
    }
    const headers: Record<string, string> = BiliHttp.headers(referer, true);
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(`https://${host}${path}`, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        connectTimeout: 10000,
        readTimeout: 15000,
        expectDataType: http.HttpDataType.STRING
      });
      BiliCookie.mergeSetCookie(response.cookies);
      return BiliHttp.parse(response.result);
    } finally {
      request.destroy();
    }
  }

  private static parse(result: Object | string): Record<string, Object> {
    if (typeof result === 'string') {
      const text: string = (result as string).trim();
      try {
        return JSON.parse(text) as Record<string, Object>;
      } catch (err) {
        const start: number = text.indexOf('{');
        const end: number = text.lastIndexOf('}');
        if (start >= 0 && end > start) {
          try {
            return JSON.parse(text.substring(start, end + 1)) as Record<string, Object>;
          } catch (nested) {
            throw new Error(`响应解析失败：${text.substring(0, 64)}`);
          }
        }
        throw new Error(`响应解析失败：${text.substring(0, 64)}`);
      }
    }
    return result as Record<string, Object>;
  }
}

/** 从响应体取字段的安全助手（接口字段经常缺失，缺失即取默认值） */
export class J {
  static obj(source: Record<string, Object> | null | undefined, key: string): Record<string, Object> {
    if (source === null || source === undefined) {
      return {};
    }
    const value: Object | undefined = source[key];
    if (value === undefined || value === null || typeof value !== 'object') {
      return {};
    }
    return value as Record<string, Object>;
  }

  static arr(source: Record<string, Object> | null | undefined, key: string): Array<Object> {
    if (source === null || source === undefined) {
      return [];
    }
    const value: Object | undefined = source[key];
    if (value === undefined || value === null || !Array.isArray(value)) {
      return [];
    }
    return value as Array<Object>;
  }

  static str(source: Record<string, Object> | null | undefined, key: string): string {
    if (source === null || source === undefined) {
      return '';
    }
    const value: Object | undefined = source[key];
    if (value === undefined || value === null) {
      return '';
    }
    const kind: string = typeof value;
    // 接口里同一个字段可能既是字符串又是对象（如 rcmd_reason），
    // 直接 String(value) 会渲染成「[object Object]」，这里只接受基本类型。
    if (kind === 'string' || kind === 'number' || kind === 'boolean') {
      return `${value}`;
    }
    return '';
  }

  static num(source: Record<string, Object> | null | undefined, key: string): number {
    if (source === null || source === undefined) {
      return 0;
    }
    const value: Object | undefined = source[key];
    if (value === undefined || value === null) {
      return 0;
    }
    const parsed: number = Number(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  static bool(source: Record<string, Object> | null | undefined, key: string): boolean {
    if (source === null || source === undefined) {
      return false;
    }
    const value: Object | undefined = source[key];
    return value === true || Number(value) === 1;
  }
}

export { BiliCookie };