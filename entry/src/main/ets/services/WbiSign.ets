import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BiliHttp } from './BiliHttp';

/** 混淆表（官方前端写死，取拼接后的 imgKey+subKey 的这 64 个下标再截前 32 位） */
const MIXIN_TABLE: Array<number> = [
  46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19,
  29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21,
  56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
];

/** mixinKey 缓存时长：官方前端也是按天换，这里 6 小时刷一次足够 */
const MIXIN_TTL_MS: number = 6 * 60 * 60 * 1000;

/**
 * B 站 wbi 签名（V2.1.2）。
 *
 * 空间页的 acc/info、arc/search、动态 feed/space 都要求 wbi 签名，缺签直接返回风控 HTML。
 * 签名流程：
 * 1. /x/web-interface/nav 取 wbi_img.img_url / sub_url 的文件名拼成 raw（64 位）；
 * 2. 按 MIXIN_TABLE 重排取前 32 位 = mixinKey；
 * 3. 业务参数加 wts（秒级时间戳）→ 按 key 字典序排序 → encodeURIComponent 拼 query；
 * 4. w_rid = md5(query + mixinKey)，URL 追加 w_rid。
 *
 * md5 走 @kit.CryptoArchitectureKit 的 createMd('MD5')（同步版本，签名场景数据量极小）。
 */
export class WbiSign {
  private static mixinKey: string = '';
  private static fetchedAt: number = 0;
  private static inflight: Promise<string> | null = null;

  /** 取 mixinKey（带缓存 + 并发合流，避免多接口同时打 nav） */
  static async mixin(): Promise<string> {
    const now: number = Date.now();
    if (WbiSign.mixinKey.length > 0 && now - WbiSign.fetchedAt < MIXIN_TTL_MS) {
      return WbiSign.mixinKey;
    }
    if (WbiSign.inflight !== null) {
      return WbiSign.inflight;
    }
    WbiSign.inflight = WbiSign.fetchMixin();
    try {
      const key: string = await WbiSign.inflight;
      return key;
    } finally {
      WbiSign.inflight = null;
    }
  }

  /** 主动作废缓存（接口报 -403 时重试一次用） */
  static invalidate(): void {
    WbiSign.mixinKey = '';
    WbiSign.fetchedAt = 0;
  }

  private static async fetchMixin(): Promise<string> {
    // nav 未登录会返回 code=-101，但 data.wbi_img 依然有值，所以不校验 code
    const body: Record<string, Object> = await BiliHttp.getJson(BiliHttp.API_HOST,
      '/x/web-interface/nav', {}, 'https://www.bilibili.com/');
    const data: Record<string, Object> = body['data'] as Record<string, Object>;
    let imgKey: string = '';
    let subKey: string = '';
    if (data !== undefined && data !== null) {
      const img: Record<string, Object> = data['wbi_img'] as Record<string, Object>;
      if (img !== undefined && img !== null) {
        imgKey = WbiSign.fileStem(`${img['img_url']}`);
        subKey = WbiSign.fileStem(`${img['sub_url']}`);
      }
    }
    if (imgKey.length === 0 || subKey.length === 0) {
      throw new Error('wbi 密钥获取失败');
    }
    const raw: string = imgKey + subKey;
    let mix: string = '';
    for (let i = 0; i < MIXIN_TABLE.length; i++) {
      const index: number = MIXIN_TABLE[i];
      if (index < raw.length) {
        mix += raw.charAt(index);
      }
    }
    WbiSign.mixinKey = mix.substring(0, 32);
    WbiSign.fetchedAt = Date.now();
    return WbiSign.mixinKey;
  }

  /** 从 URL 取文件名去扩展名（如 https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png → 7cd0...） */
  private static fileStem(url: string): string {
    const slash: number = url.lastIndexOf('/');
    const name: string = slash >= 0 ? url.substring(slash + 1) : url;
    const dot: number = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /** 业务参数 → 已签名 query（可空对象） */
  static async signQuery(params: Record<string, string>): Promise<Record<string, string>> {
    const key: string = await WbiSign.mixin();
    const signed: Record<string, string> = {};
    const names: Array<string> = Object.keys(params);
    for (let i = 0; i < names.length; i++) {
      signed[names[i]] = params[names[i]];
    }
    signed['wts'] = `${Math.floor(Date.now() / 1000)}`;
    const sorted: Array<string> = Object.keys(signed).sort();
    let query: string = '';
    for (let i = 0; i < sorted.length; i++) {
      const name: string = sorted[i];
      const value: string = signed[name].replace(/[!'()*]/g, '');
      if (i > 0) {
        query += '&';
      }
      query += `${encodeURIComponent(name)}=${encodeURIComponent(value)}`;
    }
    const rid: string = await WbiSign.md5(query + key);
    const result: Record<string, string> = {};
    for (let i = 0; i < sorted.length; i++) {
      result[sorted[i]] = signed[sorted[i]];
    }
    result['w_rid'] = rid;
    return result;
  }

  /** md5 小写十六进制 */
  private static async md5(text: string): Promise<string> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
    const blob: cryptoFramework.DataBlob = { data: WbiSign.utf8(text) };
    await md.update(blob);
    const out: cryptoFramework.DataBlob = await md.digest();
    let hex: string = '';
    const bytes: Uint8Array = out.data;
    for (let i = 0; i < bytes.length; i++) {
      const part: string = bytes[i].toString(16);
      hex += part.length === 1 ? `0${part}` : part;
    }
    return hex;
  }

  /** UTF-8 编码（手写一份，避免不同 SDK 上 TextEncoder 的 polyfill 差异） */
  private static utf8(text: string): Uint8Array {
    const bytes: Array<number> = [];
    for (let i = 0; i < text.length; i++) {
      let code: number = text.charCodeAt(i);
      if (code < 0x80) {
        bytes.push(code);
      } else if (code < 0x800) {
        bytes.push((code >> 6) | 0xC0, (code & 0x3F) | 0x80);
      } else if (code >= 0xD800 && code <= 0xDBFF) {
        // 代理对：合成完整码点后按 4 字节编码
        const low: number = i + 1 < text.length ? text.charCodeAt(i + 1) : 0;
        if (low >= 0xDC00 && low <= 0xDFFF) {
          code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
          i++;
        }
        bytes.push((code >> 18) | 0xF0, ((code >> 12) & 0x3F) | 0x80,
          ((code >> 6) & 0x3F) | 0x80, (code & 0x3F) | 0x80);
      } else {
        bytes.push((code >> 12) | 0xE0, ((code >> 6) & 0x3F) | 0x80, (code & 0x3F) | 0x80);
      }
    }
    const view: Uint8Array = new Uint8Array(bytes.length);
    for (let i = 0; i < bytes.length; i++) {
      view[i] = bytes[i];
    }
    return view;
  }
}