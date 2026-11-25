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

  /**
   * 相关推荐：播放页用，按当前视频取「相似稿件」。
   *
   * 之前播放页下方那列借的是首页信息流（`/x/web-interface/index/top/feed/rcmd`），
   * 那个接口是按账号口味随机出的，跟正在看的视频毫无关系，所以出现「看装机视频、推美妆」这种跳脱。
   * 这里换成播放页右侧同款 `/x/web-interface/archive/related`：服务端按分区 / 标签 / 共同观众算关联，
   * 顺序本身就是相关度排序，原样保留即可。
   */
  static async related(bvid: string, pageSize: number = 20): Promise<Array<VideoCard>> {
    const cards: Array<VideoCard> = [];
    if (bvid.length === 0) {
      return cards;
    }
    const query: Record<string, string> = {};
    query['bvid'] = bvid;
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/web-interface/archive/related', query, `https://www.bilibili.com/video/${bvid}/`);
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      throw new Error(J.str(body, 'message').length > 0 ? J.str(body, 'message') : `相关推荐返回 ${code}`);
    }
    // data 直接是数组（不是 {list: []}），番剧 / 课程条目 goto 不是 av，bvid 为空自然被过滤掉
    const list: Array<Object> = J.arr(body, 'data');
    for (let i = 0; i < list.length; i++) {
      const card: VideoCard | null = RecommendService.mapRelatedItem(list[i] as Record<string, Object>);
      if (card !== null) {
        cards.push(card);
      }
      if (cards.length >= pageSize) {
        break;
      }
    }
    console.info(`${TAG} related bvid=${bvid} got ${cards.length}/${list.length}`);
    return cards;
  }

  /**
   * 首页信息流（「混乱」推荐池）：竖屏连播的上滑下一条与随机连播用这个。
   *
   * 竖屏是刷视频的场景，跟着当前这条找相似会越刷越窄（看装机就一直装机），
   * 所以这里故意回到首页信息流——按账号口味混着出，什么分区都可能出现。
   * fresh_idx 随机给一个，避免每次刷新都拿到同一批。
   */
  static async feedPool(pageSize: number = 20): Promise<Array<VideoCard>> {
    return RecommendService.load(Math.floor(Math.random() * 60) + 2, pageSize);
  }

  /**
   * 相关推荐，失败时退回首页信息流。
   *
   * 老视频 / 极冷门稿件偶尔返回空数组，这时候宁可给一批「不相关但能看」的，
   * 也不要让播放页的推荐区空着——调用方只关心「拿到一批卡片」。
   */
  static async relatedOrFeed(bvid: string, pageSize: number = 20): Promise<Array<VideoCard>> {
    try {
      const list: Array<VideoCard> = await RecommendService.related(bvid, pageSize);
      if (list.length > 0) {
        return list;
      }
    } catch (err) {
      console.warn(`${TAG} related failed, fallback to feed: ${String(err)}`);
    }
    try {
      return await RecommendService.load(Math.floor(Math.random() * 50) + 2, pageSize);
    } catch (err) {
      console.warn(`${TAG} feed fallback failed: ${String(err)}`);
      return [];
    }
  }

  /** 相关推荐单条 → 卡片（字段与热门接口基本一致，多一个 tname 分区名） */
  private static mapRelatedItem(item: Record<string, Object>): VideoCard | null {
    const bvid: string = J.str(item, 'bvid');
    const title: string = J.str(item, 'title');
    if (bvid.length === 0 || title.length === 0) {
      return null;
    }
    const owner: Record<string, Object> = J.obj(item, 'owner');
    const stat: Record<string, Object> = J.obj(item, 'stat');
    const dimension: Record<string, Object> = J.obj(item, 'dimension');
    const width: number = J.num(dimension, 'width');
    const height: number = J.num(dimension, 'height');
    const view: number = J.num(stat, 'view');
    const card: VideoCard = {
      aid: J.num(item, 'aid'),
      bvid: bvid,
      cid: J.num(item, 'cid'),
      title: title,
      cover: J.str(item, 'pic').replace(/^http:/, 'https:'),
      author: J.str(owner, 'name'),
      authorFace: J.str(owner, 'face').replace(/^http:/, 'https:'),
      authorMid: J.num(owner, 'mid'),
      duration: J.num(item, 'duration'),
      pubTs: J.num(item, 'pubdate'),
      viewText: view > 0 ? `${shortCount(view)}播放` : '',
      danmuText: J.num(stat, 'danmaku') > 0 ? `${shortCount(J.num(stat, 'danmaku'))}弹幕` : '',
      likeText: J.num(stat, 'like') > 0 ? shortCount(J.num(stat, 'like')) : '',
      replyText: J.num(stat, 'reply') > 0 ? shortCount(J.num(stat, 'reply')) : '',
      cornerText: '',
      followed: false,
      vertical: width > 0 && height > width,
      tname: J.str(item, 'tname')
    };
    return card;
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