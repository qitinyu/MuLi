import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { LibraryItem, VideoDetail } from '../model/BiliModels';

const TAG = 'MuLiHistory';

/**
 * 本机观看历史。
 *
 * 为什么要自建一份：播放走的是本站自己的 AVPlayer，不会给 b 站发心跳，
 * 所以「在这个 App 里看过什么」服务端历史里根本没有 —— 只看服务端接口的话，
 * 刚看完一条就打开观看历史会发现它不在里面。
 *
 * 因此这里按 bvid 记一份本地流水（最多 200 条，越新越靠前），
 * 观看历史页把本地记录与服务端历史按时间合并去重后展示：
 * 本机看过的有进度、服务端看过（网页 / 其它端）的也在，两边都不丢。
 *
 * 存储形态：单 key 的 JSON 数组，短键名（b/a/c/t/v/u...）压体积。
 */
interface HistoryRecord {
  b: string;
  a: number;
  c: number;
  t: string;
  v: string;
  u: string;
  f: string;
  m: number;
  d: number;
  p: number;
  ts: number;
}

export class HistoryStore {
  private static readonly STORE: string = 'muli_history';
  private static readonly KEY: string = 'items';
  /** 最多保留条数：再多也没人翻，反而拖慢首屏序列化 */
  private static readonly LIMIT: number = 200;

  private static cache: Array<LibraryItem> = [];
  private static ready: boolean = false;

  private static async store(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    return preferences.getPreferences(context, HistoryStore.STORE);
  }

  /** 首次读取磁盘，之后走内存缓存 */
  static async ensure(context: common.UIAbilityContext): Promise<void> {
    if (HistoryStore.ready) {
      return;
    }
    HistoryStore.ready = true;
    try {
      const store: preferences.Preferences = await HistoryStore.store(context);
      const text: string = store.getSync(HistoryStore.KEY, '') as string;
      HistoryStore.cache = HistoryStore.decode(text);
      console.info(`${TAG} loaded ${HistoryStore.cache.length} local records`);
    } catch (err) {
      HistoryStore.cache = [];
      console.warn(`${TAG} load failed: ${String(err)}`);
    }
  }

  /** 当前本地记录（新的在前） */
  static list(): Array<LibraryItem> {
    return HistoryStore.cache.slice();
  }

  static count(): number {
    return HistoryStore.cache.length;
  }

  /**
   * 记录 / 更新一条：同一 bvid 直接覆盖并提到最前，
   * 这样同一视频反复看不刷屏，进度也总是最后一次的。
   */
  static async record(context: common.UIAbilityContext, detail: VideoDetail, progressSec: number): Promise<void> {
    const key: string = detail.bvid.length > 0 ? detail.bvid : `${detail.aid}`;
    if (key.length === 0 || key === '0') {
      return;
    }
    await HistoryStore.ensure(context);
    const item: LibraryItem = new LibraryItem();
    item.card.aid = detail.aid;
    item.card.bvid = detail.bvid;
    item.card.cid = detail.cid;
    item.card.title = detail.title;
    item.card.cover = detail.cover;
    item.card.author = detail.authorName;
    item.card.authorFace = detail.authorFace;
    item.card.authorMid = detail.authorMid;
    item.card.duration = detail.duration;
    item.card.pubTs = detail.pubTs;
    item.card.viewText = detail.viewText;
    item.card.danmuText = detail.danmuText;
    item.progress = Math.max(0, Math.floor(progressSec));
    item.timeTs = Math.floor(Date.now() / 1000);
    item.local = true;
    const next: Array<LibraryItem> = [];
    next.push(item);
    for (let i = 0; i < HistoryStore.cache.length; i++) {
      const existing: LibraryItem = HistoryStore.cache[i];
      const existingKey: string = existing.card.bvid.length > 0 ? existing.card.bvid : `${existing.card.aid}`;
      if (existingKey === key) {
        continue;
      }
      next.push(existing);
      if (next.length >= HistoryStore.LIMIT) {
        break;
      }
    }
    HistoryStore.cache = next;
    await HistoryStore.persist(context);
  }

  /** 只删本地这条；服务端历史不受影响 */
  static async remove(context: common.UIAbilityContext, bvid: string): Promise<void> {
    await HistoryStore.ensure(context);
    const kept: Array<LibraryItem> = [];
    for (let i = 0; i < HistoryStore.cache.length; i++) {
      if (HistoryStore.cache[i].card.bvid !== bvid) {
        kept.push(HistoryStore.cache[i]);
      }
    }
    HistoryStore.cache = kept;
    await HistoryStore.persist(context);
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    HistoryStore.cache = [];
    HistoryStore.ready = true;
    await HistoryStore.persist(context);
  }

  private static async persist(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await HistoryStore.store(context);
      store.putSync(HistoryStore.KEY, HistoryStore.encode(HistoryStore.cache));
      await store.flush();
    } catch (err) {
      console.warn(`${TAG} persist failed: ${String(err)}`);
    }
  }

  private static encode(items: Array<LibraryItem>): string {
    const rows: Array<HistoryRecord> = [];
    for (let i = 0; i < items.length; i++) {
      const item: LibraryItem = items[i];
      const row: HistoryRecord = {
        b: item.card.bvid,
        a: item.card.aid,
        c: item.card.cid,
        t: item.card.title,
        v: item.card.cover,
        u: item.card.author,
        f: item.card.authorFace,
        m: item.card.authorMid,
        d: item.card.duration,
        p: item.progress,
        ts: item.timeTs
      };
      rows.push(row);
    }
    return JSON.stringify(rows);
  }

  private static decode(text: string): Array<LibraryItem> {
    const result: Array<LibraryItem> = [];
    if (text.length === 0) {
      return result;
    }
    let parsed: Object;
    try {
      parsed = JSON.parse(text);
    } catch (err) {
      return result;
    }
    if (!Array.isArray(parsed)) {
      return result;
    }
    const rows: Array<Object> = parsed as Array<Object>;
    for (let i = 0; i < rows.length; i++) {
      const row: Record<string, Object> = rows[i] as Record<string, Object>;
      const item: LibraryItem = new LibraryItem();
      item.card.bvid = HistoryStore.str(row, 'b');
      item.card.aid = HistoryStore.num(row, 'a');
      item.card.cid = HistoryStore.num(row, 'c');
      item.card.title = HistoryStore.str(row, 't');
      item.card.cover = HistoryStore.str(row, 'v');
      item.card.author = HistoryStore.str(row, 'u');
      item.card.authorFace = HistoryStore.str(row, 'f');
      item.card.authorMid = HistoryStore.num(row, 'm');
      item.card.duration = HistoryStore.num(row, 'd');
      item.progress = HistoryStore.num(row, 'p');
      item.timeTs = HistoryStore.num(row, 'ts');
      item.local = true;
      if (item.card.bvid.length > 0 || item.card.aid > 0) {
        result.push(item);
      }
    }
    return result;
  }

  private static str(row: Record<string, Object>, key: string): string {
    const value: Object | undefined = row[key];
    return typeof value === 'string' ? value as string : '';
  }

  private static num(row: Record<string, Object>, key: string): number {
    const value: Object | undefined = row[key];
    if (typeof value === 'number') {
      return value as number;
    }
    return 0;
  }
}
