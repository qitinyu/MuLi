import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BiliCookie, BiliHttp, J } from './BiliHttp';
import { QrSession, QR_EXPIRED, QR_SCANNED, QR_SUCCESS, QR_WAITING, UserProfile } from '../model/BiliModels';

const TAG = 'MuLiAuth';

/** 扫码轮询结果 */
export class QrPollResult {
  code: number = QR_WAITING;
  message: string = '';
  /** code=0 时是否已拿到登录 cookie（false 表示扫码成功但 cookie 缺失，需要提示重试） */
  filled: boolean = false;
}

/** 短信验证码发送结果：区分「网络失败」「服务端风控要求图形校验」「发送成功」 */
export class SmsSendResult {
  ok: boolean = false;
  code: number = 0;
  message: string = '';
  /** 服务端要求先过图形校验（geetest），本机无法直接完成 */
  captchaRequired: boolean = false;
}

/** 账号自检的一行结果（关于页「登录诊断」用） */
export class AuthDiagLine {
  label: string = '';
  value: string = '';
  ok: boolean = false;

  constructor(label: string, value: string, ok: boolean) {
    this.label = label;
    this.value = value;
    this.ok = ok;
  }
}

/** 落盘的资料快照：只存展示字段，不存 cookie */
interface ProfileCache {
  mid: number;
  name: string;
  face: string;
  level: number;
  expCurrent: number;
  expNext: number;
  bcoin: number;
  coin: number;
  sign: string;
  ipLocation: string;
  follower: number;
  following: number;
  likes: number;
  publicOnly: boolean;
}

/**
 * 账号服务：二维码登录（passport 扫码）+ 用户资料汇总 + 登出。
 *
 * 登录态完全由 cookie 承载（SESSDATA / bili_jct / DedeUserID），
 * 轮询成功时 passport 通过 Set-Cookie 下发，交给 BiliCookie 合并并落盘。
 */
export class AuthService {
  private static profile: UserProfile = new UserProfile();
  private static readonly PROFILE_STORE: string = 'muli_profile';
  private static ctx: common.UIAbilityContext | undefined = undefined;

  static current(): UserProfile {
    return AuthService.profile;
  }

  /**
   * 绑定 AbilityContext 并把上次的资料读回来。
   * 资料必须落盘：nav 被风控挡回时如果内存里也没有，界面就只剩「已登录 + 一排 0」。
   */
  static bind(context: common.UIAbilityContext): void {
    AuthService.ctx = context;
    AuthService.restore();
  }

  /** 资料快照的 preferences 实例（同步打开，调用前必须已 bind） */
  private static profileStore(): preferences.Preferences {
    const ctx: common.UIAbilityContext = AuthService.ctx as common.UIAbilityContext;
    const options: preferences.Options = { name: AuthService.PROFILE_STORE };
    return preferences.getPreferencesSync(ctx, options);
  }

  private static restore(): void {
    const ctx: common.UIAbilityContext | undefined = AuthService.ctx;
    if (ctx === undefined || !BiliCookie.isLogin()) {
      return;
    }
    try {
      const store: preferences.Preferences = AuthService.profileStore();
      const raw: string = store.getSync('json', '') as string;
      if (raw.length === 0) {
        return;
      }
      const cache: ProfileCache = JSON.parse(raw) as ProfileCache;
      const profile: UserProfile = new UserProfile();
      profile.isLogin = true;
      profile.mid = cache.mid;
      profile.name = cache.name;
      profile.face = cache.face;
      profile.level = cache.level;
      profile.expCurrent = cache.expCurrent;
      profile.expNext = cache.expNext;
      profile.bcoin = cache.bcoin;
      profile.coin = cache.coin;
      profile.sign = cache.sign;
      profile.ipLocation = cache.ipLocation;
      profile.follower = cache.follower;
      profile.following = cache.following;
      profile.likes = cache.likes;
      profile.publicOnly = cache.publicOnly;
      AuthService.profile = profile;
      console.info(`${TAG} profile restored mid=${profile.mid} name=${profile.name}`);
    } catch (err) {
      console.warn(`${TAG} profile restore failed: ${String(err)}`);
    }
  }

  /** 把当前资料写盘（无 context 或未登录时跳过） */
  static persist(): void {
    const ctx: common.UIAbilityContext | undefined = AuthService.ctx;
    if (ctx === undefined) {
      return;
    }
    try {
      const profile: UserProfile = AuthService.profile;
      if (!profile.isLogin) {
        return;
      }
      const cache: ProfileCache = {
        mid: profile.mid,
        name: profile.name,
        face: profile.face,
        level: profile.level,
        expCurrent: profile.expCurrent,
        expNext: profile.expNext,
        bcoin: profile.bcoin,
        coin: profile.coin,
        sign: profile.sign,
        ipLocation: profile.ipLocation,
        follower: profile.follower,
        following: profile.following,
        likes: profile.likes,
        publicOnly: profile.publicOnly
      };
      const store: preferences.Preferences = AuthService.profileStore();
      store.putSync('json', JSON.stringify(cache));
      store.flush();
    } catch (err) {
      console.warn(`${TAG} profile persist failed: ${String(err)}`);
    }
  }

  /**
   * 接管外部（浏览器侧）拿到的资料。
   * 原生接口被风控挡回 but 浏览器里登录态有效时，用它先把界面填上。
   */
  static adoptProfile(profile: UserProfile): void {
    AuthService.profile = profile;
    AuthService.persist();
  }

  /** 生成登录二维码：返回扫码 URL 与轮询 key */
  static async generateQr(): Promise<QrSession> {
    const query: Record<string, string> = {};
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.PASSPORT_HOST, '/x/passport-login/web/qrcode/generate', query,
      'https://www.bilibili.com/');
    if (J.num(body, 'code') !== 0) {
      throw new Error(J.str(body, 'message').length > 0 ? J.str(body, 'message') : '二维码生成失败');
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    const session: QrSession = new QrSession();
    session.url = J.str(data, 'url');
    session.key = J.str(data, 'qrcode_key');
    if (session.key.length === 0 || session.url.length === 0) {
      throw new Error('二维码数据不完整');
    }
    console.info(`${TAG} qr generated key len=${session.key.length} url len=${session.url.length}`);
    return session;
  }

  /**
   * 轮询扫码状态。
   * 86101 = 未扫码，86090 = 已扫码待确认，86038 = 已过期，0 = 成功（此时 cookie 已写入 BiliCookie）。
   */
  static async pollQr(key: string): Promise<QrPollResult> {
    const query: Record<string, string> = {};
    query['qrcode_key'] = key;
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.PASSPORT_HOST, '/x/passport-login/web/qrcode/poll', query,
      'https://www.bilibili.com/');
    const data: Record<string, Object> = J.obj(body, 'data');
    const result: QrPollResult = new QrPollResult();
    result.code = J.num(data, 'code');
    result.message = J.str(data, 'message');
    console.info(`${TAG} qr poll code=${result.code} msg=${result.message} cookieLen=${BiliCookie.value('SESSDATA').length}`);
    if (result.code === QR_SUCCESS) {
      // 优先用返回 url 里的 cookie 补全登录态：真机实测 Set-Cookie 未必透传到 response.cookies
      const loginUrl: string = J.str(data, 'url');
      const filled: boolean = BiliCookie.mergeFromLoginUrl(loginUrl);
      result.filled = filled || BiliCookie.isLogin();
      console.info(`${TAG} qr login urlFilled=${filled} sessdataLen=${BiliCookie.value('SESSDATA').length}`);
    }
    if (J.num(body, 'code') !== 0 && result.code === 0) {
      result.code = -1;
      result.message = J.str(body, 'message');
    }
    return result;
  }

  static isLogin(): boolean {
    return BiliCookie.isLogin();
  }

  /**
   * 拉资料并带重试。
   * 扫码/短信登录成功后立即请求 nav 偶发被风控挡回 isLogin=false，
   * 这里重试几次，避免明明登录成功却停在「无法获取登录信息」。
   */
  static async loadProfileWithRetry(times: number): Promise<UserProfile> {
    let profile: UserProfile = await AuthService.loadProfile();
    for (let i = 1; i < times && !profile.isLogin && BiliCookie.isLogin(); i++) {
      await AuthService.delay(i === 1 ? 300 : 600);
      profile = await AuthService.loadProfile();
    }
    return profile;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  /** 发送手机号验证码；返回结果而不是抛错，方便 UI 区分「风控要图形校验」与网络错误 */
  static async sendSmsCode(tel: string): Promise<SmsSendResult> {
    const result: SmsSendResult = new SmsSendResult();
    const form: Record<string, string> = {};
    form['tel'] = tel;
    form['cid'] = '86';
    form['source'] = 'main-fe-header';
    form['platform'] = 'web';
    form['csrf'] = BiliCookie.csrf();
    const body: Record<string, Object> = await BiliHttp.postForm(
      BiliHttp.PASSPORT_HOST, '/x/passport-login/web/sms/send', form,
      'https://passport.bilibili.com/login');
    result.code = J.num(body, 'code');
    result.message = J.str(body, 'message');
    result.ok = result.code === 0;
    // -352 / -105 / 86203 与「验证码错误」都是 passport 要求先过 geetest 图校验的表现
    result.captchaRequired = !result.ok && (
      result.code === -352 || result.code === -105 || result.code === 86203 ||
        result.message.indexOf('验证码') >= 0 || result.message.indexOf('风控') >= 0);
    console.info(`${TAG} sms send code=${result.code} msg=${result.message} captcha=${result.captchaRequired}`);
    return result;
  }

  /** 手机号 + 验证码登录：成功后 cookie 由 Set-Cookie 落进 BiliCookie */
  static async loginBySms(tel: string, code: string): Promise<void> {
    const form: Record<string, string> = {};
    form['tel'] = tel;
    form['code'] = code;
    form['cid'] = '86';
    form['source'] = 'main-fe-header';
    form['csrf'] = BiliCookie.csrf();
    const body: Record<string, Object> = await BiliHttp.postForm(
      BiliHttp.PASSPORT_HOST, '/x/passport-login/web/login/sms', form,
      'https://www.bilibili.com/');
    const resultCode: number = J.num(body, 'code');
    if (resultCode !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `登录失败（${resultCode}）`);
    }
  }

  /** 拉取完整用户资料：nav → myinfo → 公开空间资料，逐级兜底 */
  static async loadProfile(): Promise<UserProfile> {
    const profile: UserProfile = new UserProfile();
    const previous: UserProfile = AuthService.profile;
    if (!BiliCookie.isLogin()) {
      AuthService.profile = profile;
      return profile;
    }
    try {
      const navQuery: Record<string, string> = {};
      const body: Record<string, Object> = await BiliHttp.getJson(
        BiliHttp.API_HOST, '/x/web-interface/nav', navQuery);
      const data: Record<string, Object> = J.obj(body, 'data');
      if (J.num(body, 'code') !== 0 || !J.bool(data, 'isLogin')) {
        // nav 是登录态的唯一权威接口，但它对陌生设备/新 cookie 会短暂判未登录；
        // 这里用 myinfo、公开空间资料逐级兜底，至少让界面显示真实身份。
        console.warn(`${TAG} nav not login code=${J.num(body, 'code')} msg=${J.str(body, 'message')} ` +
          `isLogin=${J.bool(data, 'isLogin')} cookies=[${BiliCookie.authKeys()}]`);
        AuthService.profile = await AuthService.resolveWithoutNav(previous);
        AuthService.persist();
        return AuthService.profile;
      }
      console.info(`${TAG} nav ok mid=${J.num(data, 'mid')} uname=${J.str(data, 'uname')} level=${J.num(data, 'level')}`);
      profile.isLogin = true;
      profile.mid = J.num(data, 'mid');
      profile.name = J.str(data, 'uname');
      profile.face = J.str(data, 'face');
      profile.level = J.num(data, 'level');
      profile.coin = J.num(data, 'money');
      const wallet: Record<string, Object> = J.obj(data, 'wallet');
      profile.bcoin = J.num(wallet, 'bcoin_balance');
      if (profile.coin === 0) {
        profile.coin = J.num(wallet, 'coin_balance');
      }
      const levelInfo: Record<string, Object> = J.obj(data, 'level_info');
      if (profile.level === 0) {
        profile.level = J.num(levelInfo, 'current_level');
      }
      profile.expCurrent = J.num(levelInfo, 'current_exp');
      profile.expNext = J.num(levelInfo, 'next_exp');
      await AuthService.fillRelation(profile);
      await AuthService.fillDetail(profile);
    } catch (err) {
      console.error(`${TAG} load profile failed: ${String(err)}`);
      profile.isLogin = BiliCookie.isLogin();
    }
    AuthService.profile = AuthService.inherit(profile, previous);
    AuthService.persist();
    return AuthService.profile;
  }

  /**
   * 新结果为空时沿用上一次已知的资料。
   * 避免「一次接口抖动」把已经显示正确的头像昵称清空，
   * 也保证浏览器侧兜底拿到的资料不会被后续失败的请求覆盖。
   */
  private static inherit(fresh: UserProfile, previous: UserProfile): UserProfile {
    if (fresh.name.length > 0 || previous.name.length === 0) {
      return fresh;
    }
    fresh.name = previous.name;
    fresh.face = previous.face;
    fresh.mid = previous.mid;
    fresh.level = previous.level;
    fresh.coin = previous.coin;
    fresh.bcoin = previous.bcoin;
    fresh.sign = previous.sign;
    fresh.ipLocation = previous.ipLocation;
    fresh.follower = previous.follower;
    fresh.following = previous.following;
    fresh.likes = previous.likes;
    fresh.expCurrent = previous.expCurrent;
    fresh.expNext = previous.expNext;
    fresh.isLogin = fresh.isLogin || previous.isLogin;
    return fresh;
  }

  /**
   * nav 失败时的兜底链：myinfo → 公开空间资料。
   * myinfo 只要 SESSDATA 有效就会返回 mid / name / face；
   * 连 myinfo 也不认时，用 cookie 里的 DedeUserID 读公开空间资料，
   * 至少让「头像 / 昵称 / 等级 / 粉丝」显示正确，而不是一排 0。
   */
  private static async resolveWithoutNav(previous: UserProfile): Promise<UserProfile> {
    const identity: UserProfile = await AuthService.loadIdentityFallback();
    if (identity.mid > 0 && identity.name.length > 0) {
      return AuthService.inherit(identity, previous);
    }
    const cookieMid: number = BiliCookie.mid();
    const mid: number = cookieMid > 0 ? cookieMid : previous.mid;
    if (mid > 0) {
      const pub: UserProfile = await AuthService.publicCard(mid);
      if (pub.name.length > 0) {
        return AuthService.inherit(pub, previous);
      }
    }
    return AuthService.inherit(identity, previous);
  }

  /**
   * 公开空间资料（/x/web-interface/card）：不需要登录态，只需要 mid。
   * 拿不到 B币 / 硬币这类私有字段，因此打上 publicOnly 标记。
   */
  private static async publicCard(mid: number): Promise<UserProfile> {
    const profile: UserProfile = new UserProfile();
    const query: Record<string, string> = {};
    query['mid'] = `${mid}`;
    try {
      const body: Record<string, Object> = await BiliHttp.getJson(
        BiliHttp.API_HOST, '/x/web-interface/card', query);
      if (J.num(body, 'code') !== 0) {
        console.warn(`${TAG} public card code=${J.num(body, 'code')} mid=${mid}`);
        return profile;
      }
      const card: Record<string, Object> = J.obj(J.obj(body, 'data'), 'card');
      const cardMid: number = J.num(card, 'mid');
      profile.isLogin = true;
      profile.publicOnly = true;
      profile.mid = cardMid > 0 ? cardMid : mid;
      profile.name = J.str(card, 'name');
      profile.face = J.str(card, 'face');
      profile.sign = J.str(card, 'sign');
      profile.level = J.num(J.obj(card, 'level_info'), 'current_level');
      profile.follower = J.num(card, 'fans');
      profile.following = J.num(card, 'attention');
      console.info(`${TAG} public card ok mid=${profile.mid} name=${profile.name} level=${profile.level}`);
    } catch (err) {
      console.error(`${TAG} public card failed: ${String(err)}`);
    }
    return profile;
  }

  /**
   * 登录诊断：把「cookie 有没有、nav 认不认、公开资料能不能读」逐项列出来。
   * 登录态问题只能靠这几项定位，界面上的「已登录但没数据」本身不含信息量。
   */
  static async diagnose(): Promise<Array<AuthDiagLine>> {
    const lines: Array<AuthDiagLine> = [];
    const sessLen: number = BiliCookie.value('SESSDATA').length;
    const mid: number = BiliCookie.mid();
    lines.push(new AuthDiagLine('登录凭证', sessLen > 0 ? `SESSDATA 已保存（${sessLen} 字符）` : '没有 SESSDATA，需要登录',
      sessLen > 0));
    lines.push(new AuthDiagLine('设备指纹', `buvid3 ${BiliCookie.buvid3.length} 字符 · b_nut ${BiliCookie.bNut}`,
      BiliCookie.buvid3.length > 0));
    lines.push(new AuthDiagLine('账号 mid', mid > 0 ? `${mid}` : 'cookie 里没有 DedeUserID', mid > 0));
    try {
      const body: Record<string, Object> = await BiliHttp.getJson(BiliHttp.API_HOST, '/x/web-interface/nav', {});
      const code: number = J.num(body, 'code');
      const isLogin: boolean = J.bool(J.obj(body, 'data'), 'isLogin');
      lines.push(new AuthDiagLine('nav 接口',
        `code ${code} · ${J.str(body, 'message')} · isLogin=${isLogin}`, code === 0 && isLogin));
    } catch (err) {
      lines.push(new AuthDiagLine('nav 接口', `请求失败：${String(err)}`, false));
    }
    try {
      const body: Record<string, Object> = await BiliHttp.getJson(BiliHttp.API_HOST, '/x/space/myinfo', {});
      const code: number = J.num(body, 'code');
      lines.push(new AuthDiagLine('myinfo 接口', `code ${code} · ${J.str(body, 'message')}`, code === 0));
    } catch (err) {
      lines.push(new AuthDiagLine('myinfo 接口', `请求失败：${String(err)}`, false));
    }
    if (mid > 0) {
      const pub: UserProfile = await AuthService.publicCard(mid);
      lines.push(new AuthDiagLine('公开资料', pub.name.length > 0
        ? `${pub.name} · LV${pub.level} · ${pub.follower} 粉丝`
        : '读取失败', pub.name.length > 0));
    }
    return lines;
  }

  /**
   * myinfo 兜底：nav 被风控挡回时用 myinfo 再确认一次身份。
   * myinfo 只要 SESSDATA 有效就会返回 mid / name / face，比 nav 宽容得多。
   */
  private static async loadIdentityFallback(): Promise<UserProfile> {
    const profile: UserProfile = new UserProfile();
    if (!BiliCookie.isLogin()) {
      return profile;
    }
    try {
      const body: Record<string, Object> = await BiliHttp.getJson(BiliHttp.API_HOST, '/x/space/myinfo', {});
      if (J.num(body, 'code') === 0) {
        const data: Record<string, Object> = J.obj(body, 'data');
        profile.isLogin = true;
        profile.mid = J.num(data, 'mid');
        profile.name = J.str(data, 'name');
        profile.face = J.str(data, 'face');
        profile.sign = J.str(data, 'sign');
        profile.level = J.num(data, 'level');
        profile.ipLocation = J.str(data, 'ip_location');
        console.info(`${TAG} identity fallback ok mid=${profile.mid}`);
        await AuthService.fillRelation(profile);
        return profile;
      }
    } catch (err) {
      console.error(`${TAG} identity fallback failed: ${String(err)}`);
    }
    profile.isLogin = BiliCookie.isLogin();
    return profile;
  }

  /** 粉丝 / 关注：relation/stat 无需登录即可读 */
  private static async fillRelation(profile: UserProfile): Promise<void> {
    try {
      const query: Record<string, string> = {};
      query['vmid'] = `${profile.mid}`;
      const body: Record<string, Object> = await BiliHttp.getJson(
        BiliHttp.API_HOST, '/x/relation/stat', query);
      if (J.num(body, 'code') !== 0) {
        return;
      }
      const data: Record<string, Object> = J.obj(body, 'data');
      profile.follower = J.num(data, 'follower');
      profile.following = J.num(data, 'following');
    } catch (err) {
      console.error(`${TAG} relation stat failed: ${String(err)}`);
    }
  }

  /** 个性签名 / IP 属地 / 获赞 */
  private static async fillDetail(profile: UserProfile): Promise<void> {
    try {
      const body: Record<string, Object> = await BiliHttp.getJson(
        BiliHttp.API_HOST, '/x/space/myinfo', {});
      if (J.num(body, 'code') === 0) {
        const data: Record<string, Object> = J.obj(body, 'data');
        profile.sign = J.str(data, 'sign');
        profile.ipLocation = J.str(data, 'ip_location');
        const likes: Record<string, Object> = J.obj(data, 'likes');
        if (profile.likes === 0 && J.num(likes, 'total') > 0) {
          profile.likes = J.num(likes, 'total');
        }
      }
    } catch (err) {
      console.error(`${TAG} myinfo failed: ${String(err)}`);
    }
    try {
      const query: Record<string, string> = {};
      query['mid'] = `${profile.mid}`;
      const body: Record<string, Object> = await BiliHttp.getJson(
        BiliHttp.API_HOST, '/x/space/upstat', query);
      if (J.num(body, 'code') === 0) {
        const data: Record<string, Object> = J.obj(body, 'data');
        profile.likes = J.num(J.obj(data, 'likes'), 'total');
      }
    } catch (err) {
      console.error(`${TAG} upstat failed: ${String(err)}`);
    }
  }

  static async logout(context: common.UIAbilityContext): Promise<void> {
    try {
      const csrf: string = BiliCookie.csrf();
      if (csrf.length > 0) {
        const form: Record<string, string> = {};
        form['biliCSRF'] = csrf;
        await BiliHttp.postForm(BiliHttp.PASSPORT_HOST, '/login/exit/v2', form,
          'https://www.bilibili.com/');
      }
    } catch (err) {
      console.error(`${TAG} logout request failed: ${String(err)}`);
    }
    await BiliCookie.clearAuth(context);
    AuthService.profile = new UserProfile();
    AuthService.clearCache();
  }

  /** 退出登录后清掉资料快照，避免下次启动把旧账号显示回来 */
  private static clearCache(): void {
    const ctx: common.UIAbilityContext | undefined = AuthService.ctx;
    if (ctx === undefined) {
      return;
    }
    try {
      const store: preferences.Preferences = AuthService.profileStore();
      store.deleteSync('json');
      store.flush();
    } catch (err) {
      console.warn(`${TAG} clear profile cache failed: ${String(err)}`);
    }
  }
}

export { QR_EXPIRED, QR_SCANNED, QR_SUCCESS, QR_WAITING };