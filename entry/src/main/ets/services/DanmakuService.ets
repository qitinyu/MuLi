import http from '@ohos.net.http';
import { BiliHttpClient } from './BiliHttpClient';
import { FilterWords } from '../utils/FilterWords';

export interface DanmakuItem {
  timeMs: number;
  mode: number; // 1=滚动 4=底部 5=顶部
  color: number; // 0xRRGGBB
  text: string;
}

/**
 * 弹幕管线：拉取分段 XML 弹幕流、按弹幕过滤词过滤、提交新弹幕。
 */
export class DanmakuService {
  private static SEGMENT_COUNT: number = 8;

  static async load(cid: number): Promise<DanmakuItem[]> {
    if (cid <= 0) return [];
    const allItems: DanmakuItem[] = [];
    const promises: Promise<DanmakuItem[]>[] = [];
    for (let seg: number = 1; seg <= DanmakuService.SEGMENT_COUNT; seg++) {
      promises.push(DanmakuService.loadSegment(cid, seg));
    }
    const results: DanmakuItem[][] = await Promise.all(promises);
    const seen: Set<string> = new Set();
    for (const items of results) {
      for (const item of items) {
        const key: string = `${item.timeMs}_${item.text}`;
        if (!seen.has(key)) {
          seen.add(key);
          allItems.push(item);
        }
      }
    }
    allItems.sort((a: DanmakuItem, b: DanmakuItem): number => a.timeMs - b.timeMs);
    console.info(`Pilihos danmaku loaded: ${allItems.length} items (from ${DanmakuService.SEGMENT_COUNT} segments)`);
    return allItems;
  }

  private static async loadSegment(cid: number, seg: number): Promise<DanmakuItem[]> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const suffix: string = seg === 1 ? '' : `_${seg}`;
      const response: http.HttpResponse = await request.request(
        `https://comment.bilibili.com/${cid}${suffix}.xml`, {
          method: http.RequestMethod.GET,
          header: {
            'User-Agent': BiliHttpClient.browserUserAgent,
            'Referer': 'https://www.bilibili.com/'
          },
          connectTimeout: 8000,
          readTimeout: 12000
        });
      const xml: string = response.result as string;
      return DanmakuService.parseXml(xml);
    } catch (error) {
      return [];
    } finally {
      request.destroy();
    }
  }

  static parseXml(xml: string): DanmakuItem[] {
    const items: DanmakuItem[] = [];
    const pattern: RegExp = /<d p="([^"]*)"[^>]*>([^<]*)<\/d>/g;
    let match: RegExpExecArray | null = pattern.exec(xml);
    while (match !== null) {
      const fields: string[] = match[1].split(',');
      const text: string = DanmakuService.decodeEntities(match[2]).trim();
      if (fields.length >= 4 && text !== '') {
        const mode: number = Number(fields[1]);
        // 仅支持滚动/底部/顶部三种常规模式，跳过高级弹幕与代码弹幕
        if ((mode === 1 || mode === 4 || mode === 5) && !FilterWords.isDanmakuFiltered(text)) {
          items.push({
            timeMs: Math.floor(Number(fields[0]) * 1000),
            mode: mode,
            color: Number(fields[3]) & 0xFFFFFF,
            text: text
          });
        }
      }
      match = pattern.exec(xml);
    }
    items.sort((a: DanmakuItem, b: DanmakuItem): number => a.timeMs - b.timeMs);
    console.info(`Pilihos danmaku loaded: ${items.length} items after filter`);
    return items;
  }

  static async send(cookie: string, csrf: string, cid: number, message: string,
    progressMs: number): Promise<void> {
    if (cid <= 0) throw new Error('视频 cid 缺失');
    if (cookie === '' || csrf === '') throw new Error('登录凭证缺失，请重新登录');
    const request: http.HttpRequest = http.createHttp();
    const body: string = [
      `oid=${cid}`,
      'type=1',
      `msg=${encodeURIComponent(message)}`,
      `csrf=${encodeURIComponent(csrf)}`,
      `csrf_token=${encodeURIComponent(csrf)}`,
      `progress=${Math.max(0, Math.floor(progressMs))}`,
      'color=16777215',
      'fontsize=25',
      'pool=0',
      'mode=1',
      `rnd=${Math.floor(Date.now() / 1000)}`,
      'plat=1'
    ].join('&');
    try {
      const response: http.HttpResponse = await request.request(
        'https://api.bilibili.com/x/v2/reply/dm', {
          method: http.RequestMethod.POST,
          header: {
            'User-Agent': BiliHttpClient.browserUserAgent,
            'Referer': `https://www.bilibili.com/video/av${cid}/`,
            'Origin': 'https://www.bilibili.com',
            'Content-Type': 'application/x-www-form-urlencoded',
            'Cookie': cookie
          },
          extraData: body,
          connectTimeout: 10000,
          readTimeout: 15000
        });
      const raw: string = String(response.result ?? '');
      let code: number = -1;
      let message: string = '';
      try {
        const result: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
        code = Number(result['code'] ?? -1);
        message = String(result['message'] ?? '');
      } catch (parseError) {
        // 非 JSON 响应（风控页/空响应），截取片段辅助定位
        if (raw.indexOf('"code":0') >= 0) return;
        const snippet: string = raw.substring(0, 60).replace(/\s+/g, ' ');
        throw new Error(snippet === '' ? '服务无有效响应' : snippet);
      }
      if (code !== 0) {
        throw new Error(`${code}: ${message || '发送失败'}`);
      }
    } finally {
      request.destroy();
    }
  }

  private static decodeEntities(text: string): string {
    return text
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, '\'')
      .replace(/&amp;/g, '&');
  }
}
