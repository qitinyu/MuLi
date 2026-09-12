import http from '@ohos.net.http';
import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';

export class BiliHttpClient {
  private static readonly apiBase: string = 'https://api.bilibili.com';
  private static readonly appBase: string = 'https://app.bilibili.com';
  static readonly browserUserAgent: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /**
   * 设备标识持久化：buvid3 每次启动变化会加剧风控（-412/-352），
   * 首次生成后落盘，之后启动复用同一 buvid3。
   * 若请求先于本方法发生（临时 buvid 已生成），持久化现有值，保持会话内一致。
   */
  static async initDeviceIdentity(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, 'pilihos_client');
      if (BiliHttpClient.cachedBuvid === '') {
        const saved: string = store.getSync('buvid3', '') as string;
        if (saved !== '') {
          BiliHttpClient.cachedBuvid = saved;
          return;
        }
      }
      BiliHttpClient.randomBuvid();
      store.putSync('buvid3', BiliHttpClient.cachedBuvid);
      store.flushSync();
      console.info(`Pilihos device identity persisted: buvid3=${BiliHttpClient.cachedBuvid}`);
    } catch (error) {
      console.warn(`Pilihos device identity init failed: ${String(error)}`);
    }
  }

  static async getJson(path: string, query: Record<string, string>, cookie: string = ''): Promise<Record<string, Object>> {
    const request: http.HttpRequest = http.createHttp();
    const queryText: string = Object.keys(query)
      .map((key: string) => `${encodeURIComponent(key)}=${encodeURIComponent(query[key])}`)
      .join('&');
    const url: string = `${BiliHttpClient.apiBase}${path}?${queryText}`;
    const headers: Record<string, string> = BiliHttpClient.buildHeaders(cookie);
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 10000,
        readTimeout: 15000
      });
      return BiliHttpClient.parseResponse(response.result);
    } finally {
      request.destroy();
    }
  }

  static async getJsonHost(host: string, path: string, query: Record<string, string>, cookie: string = ''): Promise<Record<string, Object>> {
    const request: http.HttpRequest = http.createHttp();
    const queryText: string = Object.keys(query)
      .map((key: string) => `${encodeURIComponent(key)}=${encodeURIComponent(query[key])}`)
      .join('&');
    const url: string = `https://${host}${path}?${queryText}`;
    const headers: Record<string, string> = BiliHttpClient.buildHeaders(cookie);
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 10000,
        readTimeout: 15000
      });
      return BiliHttpClient.parseResponse(response.result);
    } finally {
      request.destroy();
    }
  }

  static async postJsonHost(host: string, path: string, body: Record<string, Object>,
    cookie: string = ''): Promise<Record<string, Object>> {
    const request: http.HttpRequest = http.createHttp();
    const headers: Record<string, string> = BiliHttpClient.buildHeaders(cookie);
    headers['Content-Type'] = 'application/json';
    try {
      const response: http.HttpResponse = await request.request(`https://${host}${path}`, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        connectTimeout: 10000,
        readTimeout: 15000
      });
      return BiliHttpClient.parseResponse(response.result);
    } finally {
      request.destroy();
    }
  }

  static async getJsonQuery(path: string, queryText: string, cookie: string = ''): Promise<Record<string, Object>> {
    const request: http.HttpRequest = http.createHttp();
    const headers: Record<string, string> = BiliHttpClient.buildHeaders(cookie);
    try {
      const response: http.HttpResponse = await request.request(`${BiliHttpClient.apiBase}${path}?${queryText}`, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 10000,
        readTimeout: 15000
      });
      return BiliHttpClient.parseResponse(response.result);
    } finally {
      request.destroy();
    }
  }

  /**
   * 通用 POST 表单请求（互动接口：点赞/投币/收藏/评论等）
   */
  static async postForm(path: string, form: Record<string, string>, cookie: string): Promise<Record<string, Object>> {
    return BiliHttpClient.postFormHost(BiliHttpClient.apiBase.replace('https://', ''), path, form, cookie);
  }

  // host 形态（api.vc.bilibili.com 等非主站域名）
  static async postFormHost(host: string, path: string, form: Record<string, string>, cookie: string): Promise<Record<string, Object>> {
    const request: http.HttpRequest = http.createHttp();
    const headers: Record<string, string> = BiliHttpClient.buildHeaders(cookie);
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    const body: string = Object.keys(form)
      .map((key: string) => `${encodeURIComponent(key)}=${encodeURIComponent(form[key])}`)
      .join('&');
    try {
      const response: http.HttpResponse = await request.request(`https://${host}${path}`, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: body,
        connectTimeout: 10000,
        readTimeout: 15000
      });
      return BiliHttpClient.parseResponse(response.result);
    } finally {
      request.destroy();
    }
  }

  static async getAppJson(path: string, queryText: string): Promise<Record<string, Object>> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(`${BiliHttpClient.appBase}${path}?${queryText}`, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': BiliHttpClient.browserUserAgent },
        connectTimeout: 10000,
        readTimeout: 15000
      });
      return BiliHttpClient.parseResponse(response.result);
    } finally {
      request.destroy();
    }
  }

  // 安全响应解析：http 插件在 Content-Type 为 JSON 时可能返回对象、异常时返回带杂质的字符串
  private static parseResponse(result: Object | string): Record<string, Object> {
    if (typeof result === 'string') {
      const text: string = (result as string).trim();
      try {
        return JSON.parse(text) as Record<string, Object>;
      } catch (error) {
        // 兼容 JSON 前后有杂质的情况：截取首个 { 到最后一个 }
        const start: number = text.indexOf('{');
        const end: number = text.lastIndexOf('}');
        if (start >= 0 && end > start) {
          try {
            return JSON.parse(text.substring(start, end + 1)) as Record<string, Object>;
          } catch (_nestedError) {
            // 携带服务端响应片段，便于真机定位（如风控页/HTML 错误页）
            throw new Error(`响应解析失败: ${text.substring(0, 80)}`);
          }
        }
        throw new Error(`响应解析失败: ${text.substring(0, 80)}`);
      }
    }
    return result as Record<string, Object>;
  }

  private static buildHeaders(cookie: string): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': BiliHttpClient.browserUserAgent,
      'Referer': 'https://www.bilibili.com/',
      'Origin': 'https://www.bilibili.com'
    };
    if (cookie !== '') {
      headers['Cookie'] = cookie;
    } else {
      // 匿名请求携带随机 buvid3，避免风控接口（如直播 API）返回 -352
      headers['Cookie'] = 'buvid3=' + BiliHttpClient.randomBuvid();
    }
    return headers;
  }

  private static randomBuvid(): string {
    if (BiliHttpClient.cachedBuvid !== '') return BiliHttpClient.cachedBuvid;
    const hex: string = '0123456789ABCDEF';
    let uuid: string = '';
    for (let i = 0; i < 36; i++) {
      if (i === 8 || i === 13 || i === 18 || i === 23) {
        uuid += '-';
        continue;
      }
      uuid += hex[Math.floor(Math.random() * 16)];
    }
    BiliHttpClient.cachedBuvid = uuid + 'infoc';
    return BiliHttpClient.cachedBuvid;
  }

  private static cachedBuvid: string = '';
}
