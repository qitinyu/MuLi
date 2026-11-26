import { BiliCookie, BiliHttp, J } from './BiliHttp';
import { WbiSign } from './WbiSign';
import { DynamicCard, DynamicPageData, QuickUp, VideoCard } from '../model/BiliModels';
import { pubTimeText, shortCount } from '../common/Format';

const TAG = 'MuLiDynamic';

/**
 * 动态页数据源。
 * 该接口未登录时恒 -101（buvid3 也无效），因此调用前必须已登录；
 * 解析重点在 modules.module_author（作者/时间）、modules.module_dynamic（正文 + 主内容）、
 * modules.module_stat（点赞/评论/转发）。
 */
export class DynamicService {
  static async load(offset: string): Promise<Array<DynamicCard>> {
    return (await DynamicService.loadPage(offset)).cards;
  }

  /**
   * 动态流分页（V2.1.2：动态页要显示「没有更多」与正确的续页，不能再拿
   * 最后一条的 id 当游标——接口给的是 data.offset）。
   */
  static async loadPage(offset: string): Promise<DynamicPageData> {
    const query: Record<string, string> = {};
    query['type'] = 'all';
    query['page'] = '1';
    query['offset'] = offset;
    query['timezone_offset'] = '-480';
    query['features'] = 'itemOpusStyle,listOnlyfans,opusBigCover,onlyfansVote,decorationCard';
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/polymer/web-dynamic/v1/feed/all', query, 'https://t.bilibili.com/');
    const items: Array<Object> = DynamicService.requireItems(body);
    const page: DynamicPageData = new DynamicPageData();
    page.cards = DynamicService.mapItems(items);
    page.offset = J.str(J.obj(body, 'data'), 'offset');
    page.hasMore = J.bool(J.obj(body, 'data'), 'has_more') && page.offset.length > 0;
    return page;
  }

  /**
   * 某个 UP 的全部动态（V2.1.2 动态页顶部快捷 UP 行点选后只看该 UP）。
   *
   * feed/space 必须 wbi 签名，且**不能**带 dm_img_* 系列参数（实测带上恒返回空 items）。
   * 首次请求偶尔 items 为空（服务端缓存预热），这里重试一次。
   */
  static async loadSpace(hostMid: number, offset: string): Promise<Array<DynamicCard>> {
    return (await DynamicService.loadSpacePage(hostMid, offset)).cards;
  }

  /** 某个 UP 的动态分页（用户主页「动态」页签续页也用这条） */
  static async loadSpacePage(hostMid: number, offset: string): Promise<DynamicPageData> {
    const page: DynamicPageData = await DynamicService.fetchSpacePage(hostMid, offset);
    if (page.cards.length === 0 && offset.length === 0) {
      // 首次请求偶发空（服务端缓存预热），重试一次
      const retry: DynamicPageData = await DynamicService.fetchSpacePage(hostMid, offset);
      return retry;
    }
    return page;
  }

  private static async fetchSpacePage(hostMid: number, offset: string): Promise<DynamicPageData> {
    const sign: Record<string, string> = {};
    sign['host_mid'] = `${hostMid}`;
    sign['offset'] = offset;
    sign['timezone_offset'] = '-480';
    sign['features'] = 'itemOpusStyle';
    sign['platform'] = 'web';
    sign['web_location'] = '333.1387';
    const query: Record<string, string> = await WbiSign.signQuery(sign);
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/polymer/web-dynamic/v1/feed/space', query, 'https://space.bilibili.com/');
    const items: Array<Object> = DynamicService.requireItems(body);
    const page: DynamicPageData = new DynamicPageData();
    page.cards = DynamicService.mapItems(items);
    page.offset = J.str(J.obj(body, 'data'), 'offset');
    page.hasMore = J.bool(J.obj(body, 'data'), 'has_more') && page.offset.length > 0;
    return page;
  }

  /**
   * 给一条动态点赞 / 取消点赞（V2.1.2 动态卡片的点赞按钮）。
   *
   * `/x/dynamic/feed/dyn/thumb` 需要登录态 + csrf（bili_jct），up=1 点赞、up=2 取消。
   * 未登录抛错交给页面提示，页面负责把乐观更新回滚。
   *
   * 参数形态照抄官方 web 端（对照 PiliNara dynamics.dart 的 thumbDynamic）：
   * - csrf 在 **query** 上，body 里不放（只放 body 会被判 -400 参数错误）；
   * - body 需要 spmid，缺了同样报参数错误；
   * - referer 是 t.bilibili.com **不带动态 id 后缀**，Origin 由它推导（BiliHttp 统一处理）。
   */
  static async setLike(dynamicId: string, like: boolean): Promise<void> {
    const csrf: string = BiliCookie.csrf();
    if (!BiliCookie.isLogin() || csrf.length === 0) {
      throw new Error('请先登录后再点赞');
    }
    if (dynamicId.length === 0) {
      throw new Error('动态信息还没就绪');
    }
    const query: Record<string, string> = {};
    query['csrf'] = csrf;
    const form: Record<string, string> = {};
    form['dyn_id_str'] = dynamicId;
    form['up'] = like ? '1' : '2';
    form['spmid'] = '333.1365.0.0';
    const body: Record<string, Object> = await BiliHttp.postForm(
      BiliHttp.API_HOST, '/x/dynamic/feed/dyn/thumb', form,
      'https://t.bilibili.com', query);
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `点赞失败（${code}）`);
    }
  }

  /**
   * 动态页顶部快捷 UP 行（V2.1.2）。
   *
   * 主数据源 /x/polymer/web-dynamic/v1/uplist（关注列表 + 未读更新标记），要求登录；
   * 失败或未登录时退化为「从已加载动态里按作者去重」，保证快捷行始终有内容。
   */
  static async quickUps(limit: number): Promise<Array<QuickUp>> {
    const ups: Array<QuickUp> = [];
    try {
      const query: Record<string, string> = {};
      query['up_list_more'] = '1';
      query['platform'] = 'web';
      query['web_location'] = '333.1365';
      const body: Record<string, Object> = await BiliHttp.getJson(
        BiliHttp.API_HOST, '/x/polymer/web-dynamic/v1/uplist', query, 'https://t.bilibili.com/');
      if (J.num(body, 'code') === 0) {
        const data: Record<string, Object> = J.obj(body, 'data');
        const items: Array<Object> = J.arr(data, 'items');
        for (let i = 0; i < items.length && ups.length < limit; i++) {
          const item: Record<string, Object> = items[i] as Record<string, Object>;
          const mid: number = J.num(item, 'mid');
          const face: string = J.str(item, 'face').replace(/^http:/, 'https:');
          if (mid <= 0 || face.length === 0) {
            continue;
          }
          ups.push({
            mid: mid,
            name: J.str(item, 'name'),
            face: face,
            hasUpdate: J.bool(item, 'has_update')
          });
        }
      }
    } catch (err) {
      console.warn(`${TAG} uplist failed: ${String(err)}`);
    }
    return ups;
  }

  /** 从已加载动态里按作者去重补足快捷行（未登录 / uplist 失败时用） */
  static quickUpsFromCards(cards: Array<DynamicCard>, limit: number): Array<QuickUp> {
    const ups: Array<QuickUp> = [];
    const seen: Array<number> = [];
    for (let i = 0; i < cards.length && ups.length < limit; i++) {
      const card: DynamicCard = cards[i];
      if (card.authorMid <= 0 || card.authorFace.length === 0) {
        continue;
      }
      if (seen.indexOf(card.authorMid) >= 0) {
        continue;
      }
      seen.push(card.authorMid);
      ups.push({ mid: card.authorMid, name: card.authorName, face: card.authorFace, hasUpdate: false });
    }
    return ups;
  }

  private static requireItems(body: Record<string, Object>): Array<Object> {
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      if (code === -101) {
        throw new Error('未登录，登录后即可查看动态');
      }
      throw new Error(message.length > 0 ? message : `动态接口返回 ${code}`);
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    return J.arr(data, 'items');
  }

  static mapItems(items: Array<Object>): Array<DynamicCard> {
    const cards: Array<DynamicCard> = [];
    for (let i = 0; i < items.length; i++) {
      const card: DynamicCard | null = DynamicService.mapItem(items[i] as Record<string, Object>);
      if (card !== null) {
        cards.push(card);
      }
    }
    return cards;
  }

  private static mapItem(item: Record<string, Object>): DynamicCard | null {
    const id: string = J.str(item, 'id_str');
    const modules: Record<string, Object> = J.obj(item, 'modules');
    if (id.length === 0) {
      return null;
    }
    const author: Record<string, Object> = J.obj(modules, 'module_author');
    const dynamic: Record<string, Object> = J.obj(modules, 'module_dynamic');
    const stat: Record<string, Object> = J.obj(modules, 'module_stat');
    const desc: Record<string, Object> = J.obj(dynamic, 'desc');
    const major: Record<string, Object> = J.obj(dynamic, 'major');

    const card: DynamicCard = {
      id: id,
      authorName: J.str(author, 'name'),
      authorFace: J.str(author, 'face').replace(/^http:/, 'https:'),
      authorMid: J.num(author, 'mid'),
      pubText: DynamicService.pubText(author),
      text: J.str(desc, 'text'),
      kind: 'text',
      video: null,
      pics: [],
      likeText: DynamicService.countText(stat, 'like'),
      commentText: DynamicService.countText(stat, 'comment'),
      forwardText: DynamicService.countText(stat, 'forward'),
      repostName: '',
      pubLocation: J.str(author, 'pub_location_text'),
      likeCount: DynamicService.countValue(stat, 'like'),
      commentCount: DynamicService.countValue(stat, 'comment'),
      forwardCount: DynamicService.countValue(stat, 'forward'),
      liked: DynamicService.likedState(stat)
    };

    const majorType: string = J.str(major, 'type');
    if (majorType === 'MAJOR_TYPE_ARCHIVE' || majorType === 'MAJOR_TYPE_PGC') {
      const archive: Record<string, Object> = J.obj(major, 'archive');
      const archiveStat: Record<string, Object> = J.obj(archive, 'stat');
      const video: VideoCard = {
        aid: J.num(archive, 'aid'),
        bvid: J.str(archive, 'bvid'),
        cid: 0,
        title: J.str(archive, 'title'),
        cover: J.str(archive, 'cover').replace(/^http:/, 'https:'),
        author: J.str(author, 'name'),
        authorFace: J.str(author, 'face').replace(/^http:/, 'https:'),
        authorMid: J.num(author, 'mid'),
        duration: 0,
        pubTs: J.num(author, 'pub_ts'),
        viewText: J.str(archiveStat, 'play'),
        danmuText: J.str(archiveStat, 'danmaku'),
        likeText: DynamicService.numText(archiveStat, 'like'),
        replyText: DynamicService.numText(archiveStat, 'comment'),
        cornerText: J.str(archive, 'duration_text'),
        followed: false,
        vertical: false
      };
      card.video = video;
      card.kind = 'video';
    } else if (majorType === 'MAJOR_TYPE_DRAW') {
      const draw: Record<string, Object> = J.obj(major, 'draw');
      const pics: Array<Object> = J.arr(draw, 'items');
      const photos: Array<string> = [];
      for (let i = 0; i < pics.length; i++) {
        const src: string = J.str(pics[i] as Record<string, Object>, 'src').replace(/^http:/, 'https:');
        if (src.length > 0) {
          photos.push(src);
        }
      }
      card.pics = photos;
      card.kind = photos.length > 0 ? 'pics' : 'text';
    } else if (majorType === 'MAJOR_TYPE_OPUS') {
      const opus: Record<string, Object> = J.obj(major, 'opus');
      const summary: Record<string, Object> = J.obj(opus, 'summary');
      if (card.text.length === 0) {
        card.text = J.str(summary, 'text');
      }
      const pics: Array<Object> = J.arr(opus, 'pics');
      const photos: Array<string> = [];
      for (let i = 0; i < pics.length; i++) {
        const url: string = J.str(pics[i] as Record<string, Object>, 'url').replace(/^http:/, 'https:');
        if (url.length > 0) {
          photos.push(url);
        }
      }
      if (photos.length > 0) {
        card.pics = photos;
        card.kind = 'pics';
      }
    } else if (majorType === 'MAJOR_TYPE_COMMON' || majorType === 'MAJOR_TYPE_LIVE_RCMD') {
      return null;
    }
    // 转发动态：保留原作者的说明
    const orig: Record<string, Object> = J.obj(item, 'orig');
    if (J.str(orig, 'id_str').length > 0) {
      const origAuthor: Record<string, Object> = J.obj(J.obj(orig, 'modules'), 'module_author');
      card.repostName = J.str(origAuthor, 'name');
      if (card.text.length === 0) {
        card.text = J.str(J.obj(J.obj(J.obj(orig, 'modules'), 'module_dynamic'), 'desc'), 'text');
      }
    }
    if (card.text.length === 0 && card.video === null && card.pics.length === 0) {
      return null;
    }
    return card;
  }

  private static pubText(author: Record<string, Object>): string {
    const text: string = J.str(author, 'pub_time');
    if (text.length > 0) {
      return text;
    }
    return pubTimeText(J.num(author, 'pub_ts'));
  }

  private static countText(stat: Record<string, Object>, key: string): string {
    const node: Record<string, Object> = J.obj(stat, key);
    const count: number = J.num(node, 'count');
    if (count <= 0) {
      return '';
    }
    const text: string = J.str(node, 'count_str');
    return text.length > 0 ? text : shortCount(count);
  }

  /** 原始数值：卡片底部要显示「点赞 1.2万」这类具体数字 */
  private static countValue(stat: Record<string, Object>, key: string): number {
    return J.num(J.obj(stat, key), 'count');
  }

  /** module_stat.like.status：true 表示当前账号已点赞（未登录恒 false） */
  private static likedState(stat: Record<string, Object>): boolean {
    return J.bool(J.obj(stat, 'like'), 'status');
  }

  /**
   * archive.stat 里的数值字段：新版接口直接给「228.3万」这种已格式化字符串，
   * 老版给纯数字，两种都要能显示。
   */
  private static numText(stat: Record<string, Object>, key: string): string {
    const raw: string = J.str(stat, key);
    if (raw.length > 0) {
      return raw;
    }
    const count: number = J.num(stat, key);
    return count > 0 ? shortCount(count) : '';
  }
}