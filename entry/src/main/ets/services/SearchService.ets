import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BiliCookie, BiliHttp, J } from './BiliHttp';
import { VideoCard } from '../model/BiliModels';
import { shortCount } from '../common/Format';

const TAG = 'MuLiSearch';

/** 搜索结果里的 UP 主 */
export class SearchUser {
  mid: number = 0;
  uname: string = '';
  face: string = '';
  sign: string = '';
  fans: number = 0;
  videos: number = 0;
  level: number = 0;
  /** 直播间号，> 0 说明该 UP 有直播（不代表正在直播，本版不做开播校验） */
  roomId: number = 0;
  /** 当前账号是否已关注（未登录恒为 false） */
  following: boolean = false;
}

/** 搜索结果里的番剧 / 影视 */
export class SearchMedia {
  seasonId: number = 0;
  title: string = '';
  cover: string = '';
  /** 「全 12 话」「2024-04-30 上映」这类更新信息，接口可能为空 */
  indexShow: string = '';
  /** 番剧 / 电影 / 纪录片 … */
  typeName: string = '';
  areas: string = '';
  styles: string = '';
  /** 评分（media_score.score），0 表示无 */
  score: number = 0;
  /** 总集数（eps 长度），0 表示未知 */
  epCount: number = 0;

  /** 卡片副标题：优先用接口的更新信息，其次用集数兜底 */
  subText(): string {
    if (this.indexShow.length > 0) {
      return this.indexShow;
    }
    if (this.epCount > 0) {
      return `共 ${this.epCount} 话`;
    }
    return this.typeName;
  }
}

/** 一页搜索结果（三种类型共用一套分页字段） */
export class SearchBatch {
  videos: Array<VideoCard> = [];
  users: Array<SearchUser> = [];
  medias: Array<SearchMedia> = [];
  page: number = 1;
  /** 总页数（接口给 0 表示未知） */
  totalPages: number = 0;
  /** 命中总数 */
  total: number = 0;
}

/**
 * 搜索服务。
 *
 * 接口：`/x/web-interface/search/type`（网页端当前在用的搜索接口）
 * - 必须带 cookie（至少 buvid3 指纹），否则会被 412 拦成一段 HTML；
 * - 返回的 title / usign 里带 `<em class="keyword">` 高亮标签，pic / upic / cover 常是 `//` 协议相对地址；
 * - search_type：video / bili_user / media_bangumi（番剧）/ media_ft（影视）；
 * - order 只对 video 生效：totalrank 综合 / click 播放多 / pubdate 最新 / dm 弹幕多。
 *
 * 另外提供热搜、输入联想、关注态与关注操作。
 * 搜索历史放在独立的 preferences 里：只是本机记录，不与账号同步。
 */
export class SearchService {
  static readonly TYPE_VIDEO: string = 'video';
  static readonly TYPE_USER: string = 'bili_user';
  static readonly TYPE_BANGUMI: string = 'media_bangumi';
  static readonly TYPE_FT: string = 'media_ft';

  static readonly ORDER_DEFAULT: string = 'totalrank';
  static readonly ORDER_CLICK: string = 'click';
  static readonly ORDER_NEW: string = 'pubdate';
  static readonly ORDER_DANMU: string = 'dm';

  private static readonly STORE: string = 'muli_search';
  private static readonly HISTORY_KEY: string = 'history';
  private static readonly HISTORY_MAX: number = 12;

  /** 搜索一页。type 取 TYPE_*，order 仅视频有效（传空表示综合） */
  static async search(type: string, keyword: string, page: number, order: string): Promise<SearchBatch> {
    const batch: SearchBatch = new SearchBatch();
    batch.page = page;
    const query: Record<string, string> = {};
    query['search_type'] = type;
    query['keyword'] = keyword;
    query['page'] = `${page}`;
    query['page_size'] = '20';
    if (type === SearchService.TYPE_VIDEO && order.length > 0) {
      query['order'] = order;
    }
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/web-interface/search/type', query, 'https://search.bilibili.com/');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `搜索失败（${code}）`);
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    batch.total = J.num(data, 'numResults');
    batch.totalPages = J.num(data, 'numPages');
    const list: Array<Object> = J.arr(data, 'result');
    for (let i = 0; i < list.length; i++) {
      const raw: Record<string, Object> = list[i] as Record<string, Object>;
      if (type === SearchService.TYPE_VIDEO) {
        const card: VideoCard = SearchService.toCard(raw);
        if (card.bvid.length > 0) {
          batch.videos.push(card);
        }
      } else if (type === SearchService.TYPE_USER) {
        const user: SearchUser = SearchService.toUser(raw);
        if (user.mid > 0) {
          batch.users.push(user);
        }
      } else {
        const media: SearchMedia = SearchService.toMedia(raw);
        if (media.seasonId > 0) {
          batch.medias.push(media);
        }
      }
    }
    const got: number = type === SearchService.TYPE_VIDEO ? batch.videos.length
      : (type === SearchService.TYPE_USER ? batch.users.length : batch.medias.length);
    console.info(`${TAG} "${keyword}" type=${type} page=${page} got=${got} total=${batch.total} pages=${batch.totalPages}`);
    return batch;
  }

  /** 热搜词（搜索首页层），失败返回空数组 */
  static async hotWords(): Promise<Array<string>> {
    try {
      const query: Record<string, string> = {};
      query['limit'] = '10';
      const body: Record<string, Object> = await BiliHttp.getJson(
        BiliHttp.API_HOST, '/x/web-interface/search/square', query, 'https://www.bilibili.com/');
      if (J.num(body, 'code') !== 0) {
        return [];
      }
      const trending: Record<string, Object> = J.obj(J.obj(body, 'data'), 'trending');
      const list: Array<Object> = J.arr(trending, 'list');
      const words: Array<string> = [];
      for (let i = 0; i < list.length && words.length < 10; i++) {
        const word: string = J.str(list[i] as Record<string, Object>, 'keyword');
        if (word.length > 0 && words.indexOf(word) < 0) {
          words.push(word);
        }
      }
      return words;
    } catch (err) {
      console.warn(`${TAG} hot words failed: ${String(err)}`);
      return [];
    }
  }

  /** 输入联想，失败返回空数组 */
  static async suggest(term: string): Promise<Array<string>> {
    if (term.length === 0) {
      return [];
    }
    try {
      const query: Record<string, string> = {};
      query['term'] = term;
      query['main_ver'] = 'v1';
      query['highlight'] = term;
      const body: Record<string, Object> = await BiliHttp.getJson(
        's.search.bilibili.com', '/main/suggest', query, 'https://search.bilibili.com/');
      const result: Record<string, Object> = J.obj(body, 'result');
      const tags: Array<Object> = J.arr(result, 'tag');
      const words: Array<string> = [];
      for (let i = 0; i < tags.length && words.length < 10; i++) {
        const tag: Record<string, Object> = tags[i] as Record<string, Object>;
        let value: string = J.str(tag, 'value');
        if (value.length === 0) {
          value = J.str(tag, 'term');
        }
        if (value.length > 0 && words.indexOf(value) < 0) {
          words.push(value);
        }
      }
      return words;
    } catch (err) {
      return [];
    }
  }

  /** 关注态查询：attribute 2 = 已关注，6 = 互粉，128 = 特别关注 */
  static async following(mid: number): Promise<boolean> {
    if (mid <= 0 || !BiliCookie.isLogin()) {
      return false;
    }
    try {
      const query: Record<string, string> = {};
      query['fid'] = `${mid}`;
      const body: Record<string, Object> = await BiliHttp.getJson(
        BiliHttp.API_HOST, '/x/relation', query, `https://space.bilibili.com/${mid}`);
      if (J.num(body, 'code') !== 0) {
        return false;
      }
      const attribute: number = J.num(J.obj(body, 'data'), 'attribute');
      return attribute === 2 || attribute === 6 || attribute === 128;
    } catch (err) {
      return false;
    }
  }

  /** 关注 / 取关（需要登录 + bili_jct） */
  static async follow(mid: number, on: boolean): Promise<void> {
    const csrf: string = BiliCookie.csrf();
    if (!BiliCookie.isLogin() || csrf.length === 0) {
      throw new Error('请先登录后再关注');
    }
    const form: Record<string, string> = {};
    form['fid'] = `${mid}`;
    form['act'] = on ? '1' : '2';
    form['re_src'] = '11';
    form['csrf'] = csrf;
    const body: Record<string, Object> = await BiliHttp.postForm(
      BiliHttp.API_HOST, '/x/relation/modify', form, `https://space.bilibili.com/${mid}`);
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `操作失败（${code}）`);
    }
  }

  /** 搜索结果 → 通用视频卡片（字段口径与推荐流一致，直接复用列表样式） */
  private static toCard(item: Record<string, Object>): VideoCard {
    const card: VideoCard = {
      aid: J.num(item, 'aid'),
      bvid: J.str(item, 'bvid'),
      cid: 0,
      title: SearchService.plainText(J.str(item, 'title')),
      cover: SearchService.coverUrl(J.str(item, 'pic')),
      author: J.str(item, 'author'),
      authorFace: SearchService.coverUrl(J.str(item, 'upic')),
      authorMid: J.num(item, 'mid'),
      duration: SearchService.durationSeconds(J.str(item, 'duration')),
      pubTs: J.num(item, 'pubdate'),
      viewText: `${shortCount(J.num(item, 'play'))}播放`,
      danmuText: `${shortCount(J.num(item, 'video_review'))}弹幕`,
      likeText: '',
      replyText: shortCount(J.num(item, 'review')),
      cornerText: '',
      followed: false,
      vertical: false
    };
    return card;
  }

  private static toUser(raw: Record<string, Object>): SearchUser {
    const user: SearchUser = new SearchUser();
    user.mid = J.num(raw, 'mid');
    user.uname = SearchService.plainText(J.str(raw, 'uname'));
    user.face = SearchService.coverUrl(J.str(raw, 'upic'));
    user.sign = SearchService.plainText(J.str(raw, 'usign'));
    user.fans = J.num(raw, 'fans');
    user.videos = J.num(raw, 'videos');
    user.level = J.num(raw, 'level');
    user.roomId = J.num(raw, 'room_id');
    return user;
  }

  private static toMedia(raw: Record<string, Object>): SearchMedia {
    const media: SearchMedia = new SearchMedia();
    media.seasonId = J.num(raw, 'season_id');
    media.title = SearchService.plainText(J.str(raw, 'title'));
    media.cover = SearchService.coverUrl(J.str(raw, 'cover'));
    media.indexShow = SearchService.plainText(J.str(raw, 'index_show'));
    media.typeName = J.str(raw, 'season_type_name');
    media.areas = J.str(raw, 'areas');
    media.styles = SearchService.plainText(J.str(raw, 'styles'));
    media.score = J.num(J.obj(raw, 'media_score'), 'score');
    media.epCount = J.arr(raw, 'eps').length;
    return media;
  }

  /** 去掉高亮标签与常见实体，避免把 `<em>` 直接显示出来 */
  private static plainText(html: string): string {
    if (html.length === 0) {
      return '';
    }
    return html
      .replace(/<[^>]*>/g, '')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, '\'')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&');
  }

  private static coverUrl(pic: string): string {
    if (pic.length === 0) {
      return '';
    }
    if (pic.startsWith('//')) {
      return `https:${pic}`;
    }
    return pic.replace(/^http:/, 'https:');
  }

  /** 搜索结果的时长是 "m:ss" / "h:mm:ss" 文本，转成秒 */
  private static durationSeconds(text: string): number {
    if (text.length === 0) {
      return 0;
    }
    const parts: Array<string> = text.split(':');
    let seconds: number = 0;
    for (let i = 0; i < parts.length; i++) {
      const value: number = Number(parts[i]);
      if (!Number.isFinite(value)) {
        return 0;
      }
      seconds = seconds * 60 + Math.floor(value);
    }
    return seconds;
  }

  // ---------------- 搜索历史 ----------------

  static async loadHistory(context: common.UIAbilityContext): Promise<Array<string>> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, SearchService.STORE);
      const text: string = store.getSync(SearchService.HISTORY_KEY, '') as string;
      if (text.length === 0) {
        return [];
      }
      const parsed: Array<string> = JSON.parse(text) as Array<string>;
      return parsed;
    } catch (err) {
      console.warn(`${TAG} load history failed: ${String(err)}`);
      return [];
    }
  }

  /** 写入一条历史：去重后置顶，超出上限截断 */
  static async addHistory(context: common.UIAbilityContext, keyword: string): Promise<Array<string>> {
    const word: string = keyword.trim();
    if (word.length === 0) {
      return SearchService.loadHistory(context);
    }
    const current: Array<string> = await SearchService.loadHistory(context);
    const next: Array<string> = [word];
    for (let i = 0; i < current.length; i++) {
      if (current[i] !== word && next.length < SearchService.HISTORY_MAX) {
        next.push(current[i]);
      }
    }
    await SearchService.writeHistory(context, next);
    return next;
  }

  /** 删除单条历史（长按历史词时用） */
  static async removeHistory(context: common.UIAbilityContext, keyword: string): Promise<Array<string>> {
    const current: Array<string> = await SearchService.loadHistory(context);
    const next: Array<string> = [];
    for (let i = 0; i < current.length; i++) {
      if (current[i] !== keyword) {
        next.push(current[i]);
      }
    }
    await SearchService.writeHistory(context, next);
    return next;
  }

  static async clearHistory(context: common.UIAbilityContext): Promise<void> {
    await SearchService.writeHistory(context, []);
  }

  private static async writeHistory(context: common.UIAbilityContext, list: Array<string>): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, SearchService.STORE);
      store.putSync(SearchService.HISTORY_KEY, JSON.stringify(list));
      await store.flush();
    } catch (err) {
      console.warn(`${TAG} write history failed: ${String(err)}`);
    }
  }
}
