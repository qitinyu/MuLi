import { BiliHttp, J } from './BiliHttp';
import { VideoCard } from '../model/BiliModels';
import { shortCount } from '../common/Format';

const TAG = 'MuLiRcmd';

/**
 * 首页推荐流（web 端首页信息流）。
 * 翻页靠 fresh_idx 递增：第一页 brush=0，之后 brush=1 表示「换一批」，
 * fresh_idx 与 fresh_idx_1h 必须同步递增，否则服务端会返回重复内容。
 */
export class RecommendService {
  /** 拉一页推荐，返回卡片列表（失败时抛出带说明的异常）；pageSize 决定一次拉多少条 */
  static async load(freshIdx: number, pageSize: number = 12): Promise<Array<VideoCard>> {
    const query: Record<string, string> = {};
    query['ps'] = `${pageSize > 0 ? pageSize : 12}`;
    query['fresh_type'] = '4';
    query['feed_version'] = 'V8';
    query['platform'] = 'web';
    query['homepage_ver'] = '1';
    query['fresh_idx'] = `${freshIdx}`;
    query['fresh_idx_1h'] = `${freshIdx}`;
    query['brush'] = freshIdx > 1 ? '1' : '0';

    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/web-interface/index/top/feed/rcmd', query, 'https://www.bilibili.com/');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `推荐接口返回 ${code}`);
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    const list: Array<Object> = J.arr(data, 'item');
    const cards: Array<VideoCard> = [];
    for (let i = 0; i < list.length; i++) {
      const card: VideoCard | null = RecommendService.mapItem(list[i] as Record<string, Object>);
      if (card !== null) {
        cards.push(card);
      }
    }
    console.info(`${TAG} loaded ${cards.length} items at fresh_idx=${freshIdx}`);
    return cards;
  }

  /**
   * 竖屏混排池。
   *
   * 首页推荐用的 rcmd 信息流接口不返回 dimension（实测所有条目都没有这个字段），
   * 没法判断哪条是竖屏，于是「竖屏视频展示」开关一直是空转——开了也看不到任何竖屏视频。
   * 这里改从「热门」接口（/x/web-interface/popular，带 dimension）取一批，
   * 只保留真实的竖屏视频当作混排池，由首页按固定间隔插进推荐流。
   */
  static async loadVerticalPool(): Promise<Array<VideoCard>> {
    const query: Record<string, string> = {};
    query['ps'] = '50';
    query['pn'] = '1';
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/web-interface/popular', query, 'https://www.bilibili.com/v/popular/all');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      throw new Error(`热门接口返回 ${code}`);
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    const list: Array<Object> = J.arr(data, 'list');
    const pool: Array<VideoCard> = [];
    for (let i = 0; i < list.length; i++) {
      const card: VideoCard | null = RecommendService.mapRankItem(list[i] as Record<string, Object>);
      if (card !== null && card.vertical) {
        pool.push(card);
      }
    }
    // 打散：热门接口顺序固定，不洗牌的话每次刷新竖屏视频都插在同一个位置
    for (let i = pool.length - 1; i > 0; i--) {
      const j: number = Math.floor(Math.random() * (i + 1));
      const tmp: VideoCard = pool[i];
      pool[i] = pool[j];
      pool[j] = tmp;
    }
    console.info(`${TAG} vertical pool ${pool.length} of ${list.length} items`);
    return pool;
  }

  /** 热门 / 排行榜这类「带 dimension」的条目 → 卡片（竖屏判定只在有 dimension 时才成立） */
  private static mapRankItem(item: Record<string, Object>): VideoCard | null {
    const owner: Record<string, Object> = J.obj(item, 'owner');
    const stat: Record<string, Object> = J.obj(item, 'stat');
    const dimension: Record<string, Object> = J.obj(item, 'dimension');
    const width: number = J.num(dimension, 'width');
    const height: number = J.num(dimension, 'height');
    const card: VideoCard = {
      aid: J.num(item, 'aid'),
      bvid: J.str(item, 'bvid'),
      cid: J.num(item, 'cid'),
      title: J.str(item, 'title'),
      cover: J.str(item, 'pic').replace(/^http:/, 'https:'),
      author: J.str(owner, 'name'),
      authorFace: J.str(owner, 'face').replace(/^http:/, 'https:'),
      authorMid: J.num(owner, 'mid'),
      duration: J.num(item, 'duration'),
      pubTs: J.num(item, 'pubdate'),
      viewText: J.num(stat, 'view') > 0 ? `${shortCount(J.num(stat, 'view'))}播放` : '',
      danmuText: J.num(stat, 'danmaku') > 0 ? `${shortCount(J.num(stat, 'danmaku'))}弹幕` : '',
      likeText: J.num(stat, 'like') > 0 ? shortCount(J.num(stat, 'like')) : '',
      replyText: J.num(stat, 'reply') > 0 ? shortCount(J.num(stat, 'reply')) : '',
      cornerText: '',
      followed: false,
      vertical: width > 0 && height > width
    };
    if (card.bvid.length === 0 || card.title.length === 0) {
      return null;
    }
    return card;
  }

  /**
   * 单条推荐 → 卡片。
   * 信息流里混有直播卡（goto=live）与广告（goto=ad），这里只保留视频，
   * 直播卡交给直播页消费，广告直接跳过。
   */
  private static mapItem(item: Record<string, Object>): VideoCard | null {
    const goto: string = J.str(item, 'goto');
    if (goto === 'ad') {
      return null;
    }
    const owner: Record<string, Object> = J.obj(item, 'owner');
    const stat: Record<string, Object> = J.obj(item, 'stat');
    // 竖屏判定：dimension 给的是视频原始分辨率，高大于宽即竖屏（接口缺失时按横屏处理）
    const dimension: Record<string, Object> = J.obj(item, 'dimension');
    const width: number = J.num(dimension, 'width');
    const height: number = J.num(dimension, 'height');
    const card: VideoCard = {
      aid: J.num(item, 'id'),
      bvid: J.str(item, 'bvid'),
      cid: J.num(item, 'cid'),
      title: J.str(item, 'title'),
      cover: J.str(item, 'pic').replace(/^http:/, 'https:'),
      author: J.str(owner, 'name'),
      authorFace: J.str(owner, 'face').replace(/^http:/, 'https:'),
      authorMid: J.num(owner, 'mid'),
      duration: J.num(item, 'duration'),
      pubTs: J.num(item, 'pubdate'),
      viewText: J.num(stat, 'view') > 0 ? `${shortCount(J.num(stat, 'view'))}播放` : '',
      danmuText: J.num(stat, 'danmaku') > 0 ? `${shortCount(J.num(stat, 'danmaku'))}弹幕` : '',
      likeText: J.num(stat, 'like') > 0 ? shortCount(J.num(stat, 'like')) : '',
      replyText: J.num(stat, 'reply') > 0 ? shortCount(J.num(stat, 'reply')) : '',
      cornerText: '',
      followed: J.bool(item, 'is_followed'),
      vertical: width > 0 && height > width
    };
    if (card.aid === 0 && card.bvid.length === 0) {
      return null;
    }
    if (card.title.length === 0) {
      return null;
    }
    // rcmd_reason 老版本是字符串，新版本是 {reason_type, icon_url, text} 对象，两种都兼容
    const reason: Record<string, Object> = J.obj(item, 'rcmd_reason');
    const reasonText: string = J.str(reason, 'text');
    card.cornerText = reasonText.length > 0 ? reasonText : J.str(item, 'rcmd_reason');
    return card;
  }
}