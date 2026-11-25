import { BiliCookie, BiliHttp, J } from './BiliHttp';
import { AuthService } from './AuthService';
import { FavFolder, LibraryItem } from '../model/BiliModels';
import { shortCount } from '../common/Format';

const TAG = 'MuLiLibrary';

/** 收藏夹一页内容 */
export class FavPage {
  items: Array<LibraryItem> = [];
  hasMore: boolean = false;
}

/** 观看历史一页：max / viewAt 是下一页游标，原样回传即可 */
export class HistoryPage {
  items: Array<LibraryItem> = [];
  hasMore: boolean = false;
  max: number = 0;
  viewAt: number = 0;
}

/**
 * 我的收藏 / 观看历史 / 稍后再看（三个接口都要登录态，不带 wbi 签名）。
 *
 * - 收藏夹列表：`/x/v3/fav/folder/created/list-all`，带 rid 时每个夹会给出 fav_state，
 *   用它就能知道「这条视频已经在哪个夹里」，取消收藏也据此定位；
 * - 收藏夹内容：`/x/v3/fav/resource/list`（pn 从 1 开始，ps 固定 20）；
 * - 观看历史：`/x/web-interface/history/cursor`，游标翻页；
 * - 稍后再看：`/x/v2/history/toview` 一次给全量，增删走 add / del 两个 POST。
 *
 * 收藏 / 稍后再看这类写操作要 csrf（bili_jct），与点赞同源。
 */
export class LibraryService {
  static readonly PAGE_SIZE: number = 20;
  /** 收藏夹封面缓存：接口不返回 cover，取到一次就记住，重开面板不再重复请求 */
  private static coverCache: Map<number, string> = new Map();

  /** 当前账号 mid：cookie 里的 DedeUserID 优先，退到已拉到的资料 */
  static mid(): number {
    const fromCookie: number = BiliCookie.mid();
    if (fromCookie > 0) {
      return fromCookie;
    }
    return AuthService.current().mid;
  }

  // ---------------- 收藏 ----------------

  /** 我的收藏夹列表（不带 rid：不关心某条视频在不在夹里） */
  static async folders(): Promise<Array<FavFolder>> {
    return LibraryService.folderList(0);
  }

  /** 带 rid：每个收藏夹附带「这条视频是否已在其中」 */
  static async foldersOf(aid: number): Promise<Array<FavFolder>> {
    return LibraryService.folderList(Math.max(0, aid));
  }

  private static async folderList(aid: number): Promise<Array<FavFolder>> {
    const mid: number = LibraryService.mid();
    if (mid <= 0) {
      throw new Error('还没拿到账号信息，请重新登录');
    }
    const query: Record<string, string> = {};
    query['up_mid'] = `${mid}`;
    query['type'] = '2';
    if (aid > 0) {
      query['rid'] = `${aid}`;
    }
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/v3/fav/folder/created/list-all', query, 'https://space.bilibili.com/');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      throw new Error(LibraryService.reason(code, J.str(body, 'message'), '收藏夹'));
    }
    const list: Array<Object> = J.arr(J.obj(body, 'data'), 'list');
    const result: Array<FavFolder> = [];
    for (let i = 0; i < list.length; i++) {
      const raw: Record<string, Object> = list[i] as Record<string, Object>;
      const folder: FavFolder = new FavFolder();
      folder.id = J.num(raw, 'id');
      folder.title = J.str(raw, 'title');
      folder.count = J.num(raw, 'media_count');
      folder.contains = J.num(raw, 'fav_state') === 1;
      folder.cover = J.str(raw, 'cover').replace(/^http:/, 'https:');
      // 接口对没设过封面的夹会给空串：面板那边会退回「首字色块」，这里留一条日志便于排查
      if (folder.cover.length === 0) {
        console.info(`${TAG} folder ${folder.id} has no cover, keys=${raw['cover'] === undefined ? 'none' : 'empty'}`);
      }

      if (folder.id > 0) {
        result.push(folder);
      }
    }
    console.info(`${TAG} folders aid=${aid} count=${result.length}`);
    return result;
  }

  /**
   * 收藏夹封面。
   *
   * `/x/v3/fav/folder/created/list-all` 的每条数据里根本没有 cover 字段（实测 keys=none），
   * 所以「收藏夹封面」只能拿夹里最新一条稿件的封面顶上——这也是 b 站网页端收藏夹卡片的做法。
   * 只拉 ps=1 的一条，代价很小；失败 / 空夹返回空串，由面板退回首字色块。
   */
  static async folderCover(mediaId: number, count: number): Promise<string> {
    if (mediaId <= 0 || count <= 0) {
      return '';
    }
    const cached: string | undefined = LibraryService.coverCache.get(mediaId);
    if (cached !== undefined) {
      return cached;
    }
    const query: Record<string, string> = {};
    query['media_id'] = `${mediaId}`;
    query['pn'] = '1';
    query['ps'] = '1';
    query['keyword'] = '';
    query['order'] = 'mtime';
    query['type'] = '0';
    query['tid'] = '0';
    query['platform'] = 'web';
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/v3/fav/resource/list', query, 'https://www.bilibili.com/');
    if (J.num(body, 'code') !== 0) {
      return '';
    }
    const medias: Array<Object> = J.arr(J.obj(body, 'data'), 'medias');
    let cover: string = '';
    for (let i = 0; i < medias.length; i++) {
      const raw: Record<string, Object> = medias[i] as Record<string, Object>;
      // 失效稿件没有可用封面，换下一条（ps=1 时通常就这一条）
      if (J.num(raw, 'attr') !== 0) {
        continue;
      }
      cover = J.str(raw, 'cover').replace(/^http:/, 'https:');
      if (cover.length > 0) {
        break;
      }
    }
    LibraryService.coverCache.set(mediaId, cover);
    console.info(`${TAG} folder cover ${mediaId} = ${cover.length > 0 ? 'ok' : 'empty'}`);
    return cover;
  }

  /** 收藏夹内容（pn 从 1 开始） */
  static async favMedias(mediaId: number, pn: number): Promise<FavPage> {
    const page: FavPage = new FavPage();
    if (mediaId <= 0) {
      return page;
    }
    const query: Record<string, string> = {};
    query['media_id'] = `${mediaId}`;
    query['pn'] = `${Math.max(1, pn)}`;
    query['ps'] = `${LibraryService.PAGE_SIZE}`;
    query['keyword'] = '';
    query['order'] = 'mtime';
    query['type'] = '0';
    query['tid'] = '0';
    query['platform'] = 'web';
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/v3/fav/resource/list', query, 'https://www.bilibili.com/');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      throw new Error(LibraryService.reason(code, J.str(body, 'message'), '收藏内容'));
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    const medias: Array<Object> = J.arr(data, 'medias');
    for (let i = 0; i < medias.length; i++) {
      const raw: Record<string, Object> = medias[i] as Record<string, Object>;
      // attr 非 0 = 稿件已失效（删除 / 仅自己可见），列表里直接跳过，点了也播不了
      if (J.num(raw, 'attr') !== 0) {
        continue;
      }
      const item: LibraryItem = new LibraryItem();
      item.card.aid = J.num(raw, 'id');
      item.card.bvid = J.str(raw, 'bvid');
      item.card.title = J.str(raw, 'title');
      item.card.cover = J.str(raw, 'cover').replace(/^http:/, 'https:');
      item.card.duration = J.num(raw, 'duration');
      item.card.pubTs = J.num(raw, 'pubtime');
      const upper: Record<string, Object> = J.obj(raw, 'upper');
      item.card.author = J.str(upper, 'name');
      item.card.authorMid = J.num(upper, 'mid');
      item.card.authorFace = J.str(upper, 'face').replace(/^http:/, 'https:');
      const cnt: Record<string, Object> = J.obj(raw, 'cnt_info');
      item.card.viewText = `${shortCount(J.num(cnt, 'play'))}播放`;
      item.card.danmuText = shortCount(J.num(cnt, 'danmaku'));
      LibraryService.applyDimension(item, J.obj(raw, 'dimension'));
      item.timeTs = J.num(raw, 'fav_time');
      page.items.push(item);
    }
    page.hasMore = J.bool(data, 'has_more');
    return page;
  }

  /** 收藏 / 取消收藏：addId > 0 收进该夹，delId > 0 从该夹移出（两者可同时给） */
  static async favDeal(aid: number, addId: number, delId: number): Promise<void> {
    const csrf: string = LibraryService.csrf();
    const form: Record<string, string> = {};
    form['rid'] = `${aid}`;
    form['type'] = '2';
    form['csrf'] = csrf;
    if (addId > 0) {
      form['add_media_ids'] = `${addId}`;
    }
    if (delId > 0) {
      form['del_media_ids'] = `${delId}`;
    }
    const body: Record<string, Object> = await BiliHttp.postForm(
      BiliHttp.API_HOST, '/x/v3/fav/resource/deal', form, `https://www.bilibili.com/video/av${aid}/`);
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      throw new Error(LibraryService.reason(code, J.str(body, 'message'), '收藏操作失败'));
    }
    console.info(`${TAG} favDeal aid=${aid} add=${addId} del=${delId}`);
  }

  /**
   * 一次提交多个收藏夹（收藏面板「确定」走这里）。
   *
   * b 站 web 端就是这么发的：add_media_ids / del_media_ids 用逗号拼多个夹 id，
   * 一个请求同时完成「收进 A、从 B 移出」，比按夹逐个请求少一半往返、也不容易被风控。
   */
  static async favDealMany(aid: number, addIds: Array<number>, delIds: Array<number>): Promise<void> {
    if (addIds.length === 0 && delIds.length === 0) {
      return;
    }
    const csrf: string = LibraryService.csrf();
    const form: Record<string, string> = {};
    form['rid'] = `${aid}`;
    form['type'] = '2';
    form['csrf'] = csrf;
    if (addIds.length > 0) {
      form['add_media_ids'] = LibraryService.joinIds(addIds);
    }
    if (delIds.length > 0) {
      form['del_media_ids'] = LibraryService.joinIds(delIds);
    }
    const body: Record<string, Object> = await BiliHttp.postForm(
      BiliHttp.API_HOST, '/x/v3/fav/resource/deal', form, `https://www.bilibili.com/video/av${aid}/`);
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      throw new Error(LibraryService.reason(code, J.str(body, 'message'), '收藏操作失败'));
    }
    console.info(`${TAG} favDealMany aid=${aid} add=${form['add_media_ids']} del=${form['del_media_ids']}`);
  }

  private static joinIds(ids: Array<number>): string {
    const parts: Array<string> = [];
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] > 0) {
        parts.push(`${ids[i]}`);
      }
    }
    return parts.join(',');
  }

  // ---------------- 观看历史 ----------------

  /**
   * 服务端观看历史（游标翻页）。
   * 只保留稿件（business=archive），直播 / 专栏 / 番剧在播放页打不开，留在列表里点了也是报错。
   */
  static async history(max: number, viewAt: number): Promise<HistoryPage> {
    const page: HistoryPage = new HistoryPage();
    if (!BiliCookie.isLogin()) {
      throw new Error('账号未登录，请先登录');
    }
    const query: Record<string, string> = {};
    query['max'] = `${Math.max(0, Math.floor(max))}`;
    query['view_at'] = `${Math.max(0, Math.floor(viewAt))}`;
    query['business'] = '';
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/web-interface/history/cursor', query, 'https://www.bilibili.com/account/history');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      throw new Error(LibraryService.reason(code, J.str(body, 'message'), '观看历史'));
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    const list: Array<Object> = J.arr(data, 'list');
    for (let i = 0; i < list.length; i++) {
      const raw: Record<string, Object> = list[i] as Record<string, Object>;
      const hist: Record<string, Object> = J.obj(raw, 'history');
      if (J.str(hist, 'business') !== 'archive') {
        continue;
      }
      const aid: number = J.num(hist, 'oid');
      const item: LibraryItem = new LibraryItem();
      item.card.aid = aid;
      item.card.bvid = J.str(hist, 'bvid');
      item.card.cid = J.num(hist, 'cid');
      item.card.title = J.str(raw, 'title');
      item.card.cover = J.str(raw, 'cover').replace(/^http:/, 'https:');
      item.card.author = J.str(raw, 'author_name');
      item.card.authorMid = J.num(raw, 'author_mid');
      item.card.authorFace = J.str(raw, 'author_face').replace(/^http:/, 'https:');
      item.card.duration = J.num(raw, 'duration');
      item.progress = J.num(raw, 'progress');
      item.timeTs = J.num(raw, 'view_at');
      if (item.card.aid <= 0 && item.card.bvid.length === 0) {
        continue;
      }
      page.items.push(item);
    }
    const cursor: Record<string, Object> = J.obj(data, 'cursor');
    page.max = J.num(cursor, 'max');
    page.viewAt = J.num(cursor, 'view_at');
    page.hasMore = page.items.length > 0 && page.max > 0;
    console.info(`${TAG} history size=${page.items.length} max=${page.max} more=${page.hasMore}`);
    return page;
  }

  // ---------------- 稍后再看 ----------------

  static async toView(): Promise<Array<LibraryItem>> {
    const result: Array<LibraryItem> = [];
    if (!BiliCookie.isLogin()) {
      throw new Error('账号未登录，请先登录');
    }
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/v2/history/toview', {}, 'https://www.bilibili.com/watchlater/');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      throw new Error(LibraryService.reason(code, J.str(body, 'message'), '稍后再看'));
    }
    const list: Array<Object> = J.arr(J.obj(body, 'data'), 'list');
    for (let i = 0; i < list.length; i++) {
      const raw: Record<string, Object> = list[i] as Record<string, Object>;
      const item: LibraryItem = new LibraryItem();
      item.card.aid = J.num(raw, 'aid');
      item.card.bvid = J.str(raw, 'bvid');
      item.card.cid = J.num(raw, 'cid');
      item.card.title = J.str(raw, 'title');
      item.card.cover = J.str(raw, 'pic').replace(/^http:/, 'https:');
      item.card.duration = J.num(raw, 'duration');
      item.card.pubTs = J.num(raw, 'pubdate');
      const owner: Record<string, Object> = J.obj(raw, 'owner');
      item.card.author = J.str(owner, 'name');
      item.card.authorMid = J.num(owner, 'mid');
      item.card.authorFace = J.str(owner, 'face').replace(/^http:/, 'https:');
      const stat: Record<string, Object> = J.obj(raw, 'stat');
      item.card.viewText = `${shortCount(J.num(stat, 'view'))}播放`;
      item.card.danmuText = shortCount(J.num(stat, 'danmaku'));
      LibraryService.applyDimension(item, J.obj(raw, 'dimension'));
      item.progress = J.num(raw, 'progress');
      item.timeTs = J.num(raw, 'add_at');
      result.push(item);
    }
    console.info(`${TAG} toview size=${result.length}`);
    return result;
  }

  /** 加入稍后再看（已在列表里时服务端同样返回 0） */
  static async addToView(aid: number): Promise<void> {
    if (aid <= 0) {
      throw new Error('视频信息还没就绪');
    }
    const form: Record<string, string> = {};
    form['aid'] = `${aid}`;
    form['csrf'] = LibraryService.csrf();
    const body: Record<string, Object> = await BiliHttp.postForm(
      BiliHttp.API_HOST, '/x/v2/history/toview/add', form, 'https://www.bilibili.com/watchlater/');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      throw new Error(LibraryService.reason(code, J.str(body, 'message'), '加入稍后再看失败'));
    }
    console.info(`${TAG} addToView aid=${aid}`);
  }

  /** 从稍后再看移除 */
  static async removeFromView(aid: number): Promise<void> {
    const form: Record<string, string> = {};
    form['aid'] = `${aid}`;
    form['csrf'] = LibraryService.csrf();
    const body: Record<string, Object> = await BiliHttp.postForm(
      BiliHttp.API_HOST, '/x/v2/history/toview/del', form, 'https://www.bilibili.com/watchlater/');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      throw new Error(LibraryService.reason(code, J.str(body, 'message'), '移除失败'));
    }
    console.info(`${TAG} removeFromView aid=${aid}`);
  }

  // ---------------- 内部 ----------------

  /** 写操作统一的登录 / csrf 校验：未登录时给一句人话，而不是服务端返回码 */
  private static csrf(): string {
    const token: string = BiliCookie.csrf();
    if (!BiliCookie.isLogin()) {
      throw new Error('请先登录后再操作');
    }
    if (token.length === 0) {
      throw new Error('登录态已失效，请重新登录');
    }
    return token;
  }

  /** 封面比例：接口给了 dimension 就顺带标记竖屏 */
  private static applyDimension(item: LibraryItem, dimension: Record<string, Object>): void {
    const width: number = J.num(dimension, 'width');
    const height: number = J.num(dimension, 'height');
    item.card.vertical = width > 0 && height > width;
  }

  private static reason(code: number, message: string, prefix: string): string {
    if (code === -101) {
      return '账号未登录，请先登录';
    }
    if (code === -403) {
      return `${prefix}：没有权限（可能不是自己的收藏夹）`;
    }
    if (code === -400) {
      return `${prefix}：参数无效`;
    }
    if (message.length > 0) {
      return `${prefix}：${message}`;
    }
    return `${prefix}（${code}）`;
  }
}
