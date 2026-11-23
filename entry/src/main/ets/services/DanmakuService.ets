import { BiliCookie, BiliHttp, J } from './BiliHttp';

const TAG = 'MuLiDanmaku';
/** 单条视频最多取多少条弹幕：再多画布也画不过来，先截断保证列表本身不占内存 */
const MAX_ITEMS: number = 6000;

/**
 * 一条弹幕。
 *
 * mode 与 b 站一致：1/2/3 滚动（右→左），4 底部固定，5 顶部固定；
 * 7（高级弹幕）/ 8（代码弹幕）/ 9（BAS）在解析阶段就丢掉，画布渲染不了也不该画。
 */
export class DanmakuItem {
  timeMs: number = 0;
  mode: number = 1;
  /** #RRGGBB */
  color: string = '#FFFFFF';
  text: string = '';

  constructor(timeMs: number, mode: number, color: string, text: string) {
    this.timeMs = timeMs;
    this.mode = mode;
    this.color = color;
    this.text = text;
  }
}

/**
 * 弹幕服务：拉列表 + 发弹幕。
 *
 * 拉取走 XML 接口 `/x/v1/dm/list.so?oid={cid}`（实测返回完整弹幕池，服务端 gzip，http 栈自动解压），
 * 比 protobuf 的 seg.so 少一个手写 varint 解析，字段也够用（时间 / 模式 / 颜色 / 正文）。
 */
export class DanmakuService {
  static async list(cid: number): Promise<Array<DanmakuItem>> {
    if (cid <= 0) {
      return [];
    }
    const query: Record<string, string> = {};
    query['oid'] = `${cid}`;
    const xml: string = await BiliHttp.getText(
      BiliHttp.API_HOST, '/x/v1/dm/list.so', query, `https://www.bilibili.com/video/av${cid}/`);
    return DanmakuService.parse(xml);
  }

  /** 发送弹幕（需要登录 + csrf） */
  static async send(cid: number, bvid: string, text: string, progressMs: number): Promise<void> {
    const message: string = text.trim();
    if (message.length === 0) {
      throw new Error('弹幕内容不能为空');
    }
    if (cid <= 0) {
      throw new Error('分 P 信息还没就绪');
    }
    const csrf: string = BiliCookie.csrf();
    if (!BiliCookie.isLogin() || csrf.length === 0) {
      throw new Error('请先登录后再发弹幕');
    }
    const form: Record<string, string> = {};
    form['type'] = '1';
    form['oid'] = `${cid}`;
    form['msg'] = message;
    form['bvid'] = bvid;
    // b 站 progress 单位是毫秒
    form['progress'] = `${Math.max(0, Math.floor(progressMs))}`;
    form['mode'] = '1';
    form['fontsize'] = '25';
    form['color'] = '16777215';
    form['pool'] = '0';
    form['plat'] = '1';
    form['csrf'] = csrf;
    const referer: string = bvid.length > 0
      ? `https://www.bilibili.com/video/${bvid}` : 'https://www.bilibili.com/';
    const body: Record<string, Object> = await BiliHttp.postForm(
      BiliHttp.API_HOST, '/x/v2/dm/post', form, referer);
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const msg: string = J.str(body, 'message');
      throw new Error(msg.length > 0 ? msg : `弹幕发送失败（${code}）`);
    }
  }

  /**
   * 解析 XML 弹幕。
   *
   * 结构：`<d p="出现秒,模式,字号,颜色,发送时间,池,用户哈希,行号">正文</d>`
   * 不用正则整段匹配：弹幕正文里可能带尖括号转义，逐段 indexOf 更稳，也少一次大字符串回溯。
   */
  private static parse(xml: string): Array<DanmakuItem> {
    const out: Array<DanmakuItem> = [];
    if (xml === undefined || xml === null || xml.length < 16) {
      return out;
    }
    const open: string = '<d p="';
    let from: number = 0;
    while (out.length < MAX_ITEMS) {
      const start: number = xml.indexOf(open, from);
      if (start < 0) {
        break;
      }
      const pStart: number = start + open.length;
      const pEnd: number = xml.indexOf('"', pStart);
      if (pEnd < 0) {
        break;
      }
      const bodyStart: number = xml.indexOf('>', pEnd);
      const bodyEnd: number = bodyStart < 0 ? -1 : xml.indexOf('</d>', bodyStart);
      if (bodyStart < 0 || bodyEnd < 0) {
        break;
      }
      const p: string = xml.substring(pStart, pEnd);
      const raw: string = DanmakuService.decode(xml.substring(bodyStart + 1, bodyEnd));
      from = bodyEnd + 4;
      const text: string = DanmakuService.clean(raw);
      if (text.length === 0) {
        continue;
      }
      const fields: Array<string> = p.split(',');
      if (fields.length < 4) {
        continue;
      }
      const seconds: number = Number(fields[0]);
      const mode: number = Math.floor(Number(fields[1]));
      const colorValue: number = Math.floor(Number(fields[3]));
      if (!Number.isFinite(seconds) || seconds < 0) {
        continue;
      }
      if (mode !== 1 && mode !== 2 && mode !== 3 && mode !== 4 && mode !== 5) {
        continue;
      }
      out.push(new DanmakuItem(Math.round(seconds * 1000), mode,
        DanmakuService.hex(colorValue), text));
    }
    // 时间升序：播放时按游标顺序取，不用每次从头扫
    out.sort((a: DanmakuItem, b: DanmakuItem): number => a.timeMs - b.timeMs);
    console.info(`${TAG} parsed ${out.length} items from ${xml.length} chars`);
    return out;
  }

  /** 正文清理：去掉换行 / 连续空白，过长截断（画布一行放不下也没意义） */
  private static clean(text: string): string {
    let value: string = text.replace(/[\r\n\t]/g, ' ');
    value = value.split('  ').join(' ').trim();
    return value.length > 120 ? value.substring(0, 120) : value;
  }

  /** XML 实体还原（弹幕正文允许出现 & < > " '） */
  private static decode(text: string): string {
    if (text.indexOf('&') < 0) {
      return text;
    }
    let value: string = text;
    value = value.split('&lt;').join('<');
    value = value.split('&gt;').join('>');
    value = value.split('&quot;').join('"');
    value = value.split('&#39;').join('\'');
    value = value.split('&apos;').join('\'');
    value = value.split('&nbsp;').join(' ');
    // &amp; 最后处理，避免把 &amp;lt; 还原成 <
    value = value.split('&amp;').join('&');
    return value;
  }

  /** 十进制颜色转 #RRGGBB；0 视为白色（默认弹幕色） */
  private static hex(value: number): string {
    const color: number = Number.isFinite(value) && value > 0 ? Math.floor(value) : 0xFFFFFF;
    let text: string = (color & 0xFFFFFF).toString(16).toUpperCase();
    while (text.length < 6) {
      text = `0${text}`;
    }
    return `#${text}`;
  }
}
