import http from '@ohos.net.http';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import util from '@ohos.util';
import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import huks from '@ohos.security.huks';
import { AdvancedFeatures } from '../utils/AdvancedFeatures';

export class AuthSession {
  uid: string = '';
  name: string = '';
  face: string = '';
  cookie: string = '';
  csrf: string = '';
  isLogin: boolean = false;
  dynamicCount: number = 0;
  followingCount: number = 0;
  followerCount: number = 0;
  sign: string = '';
  level: number = 0;
  ipLocation: string = '';
}

class AuthParam {
  key: string = '';
  value: string = '';

  constructor(key: string, value: string) {
    this.key = key;
    this.value = value;
  }
}

class AuthHeaders {
  cookie: string = '';
  referer: string = '';
  contentType: string = '';
}

export class AuthService {
  private static readonly passportBase: string = 'https://passport.bilibili.com';
  private static readonly apiBase: string = 'https://api.bilibili.com';
  private static readonly appKey: string = 'dfca71928277209b';
  private static readonly appSecret: string = 'b5475a8825547a4fc26c7d518eaaa02e';
  private static readonly secureKeyAlias: string = 'pilihos.auth.session';
  private static session: AuthSession | null = null;
  private static credentialPreferences: preferences.Preferences | null = null;

  static currentSession(): AuthSession | null {
    return AuthService.session;
  }

  static async restoreSession(context: common.UIAbilityContext): Promise<AuthSession | null> {
    try {
      await AuthService.ensureCredentialPreferences(context);
      if (AuthService.credentialPreferences === null) return null;
      let cookie: string = AuthService.credentialPreferences.getSync('cookie', '') as string;
      if (cookie === '') {
        const encryptedCookie: string =
          AuthService.credentialPreferences.getSync('cookie_cipher', '') as string;
        if (encryptedCookie !== '') {
          cookie = await AuthService.decryptCookie(encryptedCookie);
        }
      }
      if (cookie === '') return null;
      try {
        return await AuthService.validateCookie(cookie, context);
      } catch (error) {
        const stored: AuthSession | null = AuthService.readStoredSession(cookie);
        if (stored !== null) {
          AuthService.session = stored;
          console.error('Pilihos auth validation deferred after restart: ' + String(error));
          return stored;
        }
        throw new Error(String(error));
      }
    } catch (error) {
      console.error('Pilihos stored auth restore failed: ' + String(error));
      AuthService.session = null;
      return null;
    }
  }

  private static async ensureCredentialPreferences(context?: common.UIAbilityContext): Promise<void> {
    if (AuthService.credentialPreferences !== null || context === undefined) return;
    AuthService.credentialPreferences = await preferences.getPreferences(context, 'pilihos_auth');
  }

  private static async persistCookie(cookie: string, context?: common.UIAbilityContext): Promise<void> {
    await AuthService.ensureCredentialPreferences(context);
    if (AuthService.credentialPreferences === null || cookie === '') return;
    try {
      // Write the durable session value before optional keystore work.
      AuthService.credentialPreferences.putSync('cookie', cookie);
      AuthService.credentialPreferences.flushSync();
      const encryptedCookie: string = await AuthService.encryptCookie(cookie);
      AuthService.credentialPreferences.putSync('cookie_cipher', encryptedCookie);
      AuthService.credentialPreferences.flushSync();
    } catch (error) {
      console.error('Pilihos secure auth persistence failed: ' + String(error));
    }
  }

  private static async ensureSecureKey(): Promise<void> {
    const exists: boolean = await huks.isKeyItemExist(AuthService.secureKeyAlias, {});
    if (exists) return;
    await huks.generateKeyItem(AuthService.secureKeyAlias, {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE,
          value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
        { tag: huks.HuksTag.HUKS_TAG_DIGEST, value: huks.HuksKeyDigest.HUKS_DIGEST_NONE }
      ]
    });
  }

  private static async encryptCookie(cookie: string): Promise<string> {
    await AuthService.ensureSecureKey();
    const nonce: Uint8Array = cryptoFramework.createRandom().generateRandomSync(12).data;
    const encoder = new util.TextEncoder();
    const input: Uint8Array = encoder.encodeInto(cookie);

    let ciphertext: Uint8Array;

    // 使用会话式 API（API 26+）
    const session = await huks.initSession(AuthService.secureKeyAlias, {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT },
        { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce }
      ]
    });
    const updated = await huks.updateSession(session.handle, { inData: input });
    const finished = await huks.finishSession(session.handle, { inData: new Uint8Array(0) });
    ciphertext = AuthService.concatBytes(updated.outData ?? new Uint8Array(0),
      finished.outData ?? new Uint8Array(0));

    return new util.Base64Helper().encodeToStringSync(AuthService.concatBytes(nonce, ciphertext));
  }

  private static async decryptCookie(encrypted: string): Promise<string> {
    await AuthService.ensureSecureKey();
    const bytes: Uint8Array = new util.Base64Helper().decodeSync(encrypted);
    if (bytes.length <= 12) return '';
    const nonce: Uint8Array = bytes.slice(0, 12);
    const ciphertext: Uint8Array = bytes.slice(12);

    let plaintext: Uint8Array;

    // 使用会话式 API（API 26+）
    const session = await huks.initSession(AuthService.secureKeyAlias, {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
        { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce }
      ]
    });
    const updated = await huks.updateSession(session.handle, { inData: ciphertext });
    const finished = await huks.finishSession(session.handle, { inData: new Uint8Array(0) });
    plaintext = AuthService.concatBytes(updated.outData ?? new Uint8Array(0),
      finished.outData ?? new Uint8Array(0));

    return new util.TextDecoder().decodeToString(plaintext);
  }

  private static concatBytes(left: Uint8Array, right: Uint8Array): Uint8Array {
    const result = new Uint8Array(left.length + right.length);
    result.set(left, 0);
    result.set(right, left.length);
    return result;
  }

  static async validateCookie(cookieText: string, context?: common.UIAbilityContext): Promise<AuthSession> {
    const cookie: string = AuthService.normalizeCookie(cookieText);
    if (cookie === '') throw new Error('Cookie 为空');
    const headers: AuthHeaders = new AuthHeaders();
    headers.cookie = cookie;
    headers.referer = 'https://www.bilibili.com/';
    const body: Record<string, Object> = await AuthService.requestJson(
      `${AuthService.apiBase}/x/web-interface/nav`,
      http.RequestMethod.GET,
      headers
    );
    const code: number = Number(body['code'] ?? -1);
    const data: Record<string, Object> = (body['data'] ?? {}) as Record<string, Object>;
    if (code !== 0 || data['isLogin'] !== true) {
      throw new Error(String(body['message'] ?? 'Cookie 无效或已过期'));
    }
    const session: AuthSession = new AuthSession();
    session.uid = String(data['mid'] ?? '');
    session.name = String(data['uname'] ?? '');
    session.face = String(data['face'] ?? '');
    session.cookie = cookie;
    session.csrf = AuthService.findCookie(cookie, 'bili_jct');
    session.isLogin = true;
    await AuthService.loadUserStats(session, headers);
    await AuthService.loadUserProfile(session, headers);
    AuthService.session = session;
    await AuthService.persistCookie(cookie, context);
    await AuthService.persistSession(session);
    return session;
  }

  private static async persistSession(session: AuthSession): Promise<void> {
    if (AuthService.credentialPreferences === null) return;
    try {
      AuthService.credentialPreferences.putSync('session_uid', session.uid);
      AuthService.credentialPreferences.putSync('session_name', session.name);
      AuthService.credentialPreferences.putSync('session_face', session.face);
      AuthService.credentialPreferences.putSync('session_csrf', session.csrf);
      AuthService.credentialPreferences.putSync('session_sign', session.sign);
      AuthService.credentialPreferences.putSync('session_level', String(session.level));
      AuthService.credentialPreferences.putSync('session_ip_location', session.ipLocation);
      AuthService.credentialPreferences.putSync('session_is_login', 'true');
      AuthService.credentialPreferences.flushSync();
    } catch (error) {
      console.error('Pilihos local auth session persistence failed: ' + String(error));
    }
  }

  private static readStoredSession(cookie: string): AuthSession | null {
    if (AuthService.credentialPreferences === null) return null;
    const isLogin: string = AuthService.credentialPreferences.getSync('session_is_login', '') as string;
    const uid: string = AuthService.credentialPreferences.getSync('session_uid', '') as string;
    if (isLogin !== 'true' || uid === '') return null;
    const session: AuthSession = new AuthSession();
    session.uid = uid;
    session.name = AuthService.credentialPreferences.getSync('session_name', '') as string;
    session.face = AuthService.credentialPreferences.getSync('session_face', '') as string;
    session.csrf = AuthService.credentialPreferences.getSync('session_csrf', '') as string;
    session.sign = AuthService.credentialPreferences.getSync('session_sign', '') as string;
    session.level = Number(AuthService.credentialPreferences.getSync('session_level', '0'));
    session.ipLocation = AuthService.credentialPreferences.getSync('session_ip_location', '') as string;
    session.cookie = cookie;
    session.isLogin = true;
    return session;
  }

  private static async loadUserProfile(session: AuthSession, headers: AuthHeaders): Promise<void> {
    try {
      const body: Record<string, Object> = await AuthService.requestJson(
        AuthService.apiBase + '/x/space/myinfo',
        http.RequestMethod.GET,
        headers
      );
      if (Number(body['code'] ?? -1) !== 0) return;
      const data: Record<string, Object> = (body['data'] ?? {}) as Record<string, Object>;
      session.sign = String(data['sign'] ?? '');
      session.ipLocation = String(data['ip_location'] ?? '');
      const levelInfo: Record<string, Object> = (data['level_info'] ?? {}) as Record<string, Object>;
      session.level = Number(data['level'] ?? levelInfo['current_level'] ?? 0);
    } catch (error) {
      console.error('Pilihos user profile request failed: ' + String(error));
    }
  }

  private static async loadUserStats(session: AuthSession, headers: AuthHeaders): Promise<void> {
    try {
      const body: Record<string, Object> = await AuthService.requestJson(
        `${AuthService.apiBase}/x/web-interface/nav/stat`,
        http.RequestMethod.GET,
        headers
      );
      if (Number(body['code'] ?? -1) !== 0) return;
      const data: Record<string, Object> = (body['data'] ?? {}) as Record<string, Object>;
      session.dynamicCount = Number(data['dynamic_count'] ?? 0);
      session.followingCount = Number(data['following'] ?? 0);
      session.followerCount = Number(data['follower'] ?? 0);
    } catch (error) {
      console.error(`Pilihos user stats request failed: ${String(error)}`);
    }
  }
  static async logout(): Promise<void> {
    const session: AuthSession | null = AuthService.session;
    if (session !== null && session.cookie !== '') {
      try {
        const headers: AuthHeaders = new AuthHeaders();
        headers.cookie = session.cookie;
        headers.contentType = 'application/x-www-form-urlencoded';
        await AuthService.requestJson(
          `${AuthService.passportBase}/login/exit/v2`,
          http.RequestMethod.POST,
          headers,
          `biliCSRF=${encodeURIComponent(session.csrf)}`
        );
      } catch (error) {
        console.error(`Pilihos logout request failed: ${String(error)}`);
      }
    }
    AuthService.session = null;
    if (AuthService.credentialPreferences !== null) {
      try {
        AuthService.credentialPreferences.deleteSync('cookie_cipher');
        AuthService.credentialPreferences.deleteSync('cookie');
        AuthService.credentialPreferences.deleteSync('session_uid');
        AuthService.credentialPreferences.deleteSync('session_name');
        AuthService.credentialPreferences.deleteSync('session_face');
        AuthService.credentialPreferences.deleteSync('session_csrf');
        AuthService.credentialPreferences.deleteSync('session_sign');
        AuthService.credentialPreferences.deleteSync('session_level');
        AuthService.credentialPreferences.deleteSync('session_ip_location');
        AuthService.credentialPreferences.deleteSync('session_is_login');
        AuthService.credentialPreferences.flushSync();
      } catch (error) {
        console.error('Pilihos auth persistence clear failed: ' + String(error));
      }
    }
  }

  static normalizeCookie(value: string): string {
    const parts: string[] = value.split(';');
    const valid: string[] = [];
    parts.forEach((part: string): void => {
      const item: string = part.trim();
      const separator: number = item.indexOf('=');
      if (separator > 0) {
        const name: string = item.substring(0, separator).trim();
        const cookieValue: string = item.substring(separator + 1).trim();
        if (name !== '' && cookieValue !== '') valid.push(`${name}=${cookieValue}`);
      }
    });
    return valid.join('; ');
  }

  private static async md5Hex(value: string): Promise<string> {
    const md = cryptoFramework.createMd('MD5');
    const encoder = new util.TextEncoder();
    await md.update({ data: encoder.encodeInto(value) });
    const output = await md.digest();
    let result: string = '';
    output.data.forEach((item: number): void => {
      result += item.toString(16).padStart(2, '0');
    });
    return result;
  }

  private static async signedQuery(params: AuthParam[]): Promise<string> {
    params.push(new AuthParam('appkey', AuthService.appKey));
    params.push(new AuthParam('ts', `${Math.floor(Date.now() / 1000)}`));
    params.sort((left: AuthParam, right: AuthParam): number => left.key.localeCompare(right.key));
    const encoded: string[] = params.map((item: AuthParam): string =>
      `${encodeURIComponent(item.key)}=${encodeURIComponent(item.value)}`);
    const query: string = encoded.join('&');
    const sign: string = await AuthService.md5Hex(query + AuthService.appSecret);
    return `${query}&sign=${sign}`;
  }
  private static findCookie(cookie: string, name: string): string {
    const prefix: string = `${name}=`;
    const item: string | undefined = cookie.split('; ').find((part: string): boolean => part.startsWith(prefix));
    return item === undefined ? '' : item.substring(prefix.length);
  }

  private static cookieListToString(cookies: Object[]): string {
    const values: string[] = [];
    cookies.forEach((raw: Object): void => {
      const item: Record<string, Object> = raw as Record<string, Object>;
      const name: string = String(item['name'] ?? '');
      const value: string = String(item['value'] ?? '');
      if (name !== '' && value !== '') values.push(`${name}=${value}`);
    });
    return values.join('; ');
  }

  private static async requestJson(
    url: string,
    method: http.RequestMethod,
    header: AuthHeaders,
    extraData?: string
  ): Promise<Record<string, Object>> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const requestHeaders: Record<string, string> = {};
      requestHeaders['User-Agent'] = 'Pilihos/1.0.0';
      if (header.cookie !== '') requestHeaders['Cookie'] = header.cookie;
      if (header.referer !== '') requestHeaders['Referer'] = header.referer;
      if (header.contentType !== '') requestHeaders['Content-Type'] = header.contentType;
      const options: http.HttpRequestOptions = {
        method: method,
        header: requestHeaders,
        connectTimeout: 10000,
        readTimeout: 15000
      };
      if (extraData !== undefined) options.extraData = extraData;
      const response: http.HttpResponse = await request.request(url, options);
      return JSON.parse(response.result as string) as Record<string, Object>;
    } finally {
      request.destroy();
    }
  }
}
