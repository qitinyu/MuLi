import { BiliHttp, BiliCookie, J } from './BiliHttp';
import { WbiSign } from './WbiSign';
import { DynamicService } from './DynamicService';
import {
  DynamicCard,
  FollowTag,
  SpaceArchivePage,
  SpaceBangumi,
  SpaceBangumiPage,
  SpaceBundle,
  UserSpace,
  VideoCard
} from '../model/BiliModels';
import { shortCount } from '../common/Format';

const TAG = 'MuLiSpace';

/** 空间接口被风控时的退避间隔（实测 acc/info 连打两次即 -799，必须拉开时间） */
const RETRY_DELAY_MS: number = 1600;

/**
 * 其他用户主页数据源（V2.1.2）。
 *
 * 接口清单与注意点（均为实测结论）：
 * - /x/space/wbi/acc/info 拿昵称/头像/签名/等级/背景图（top_photo_v2.l_img 优先），
 *   **必须 wbi 签名**，且极易被 -352/-412 风控 → 失败后隔 1.6s 重试一次，再失败就在
 *   feed/space 的作者模块里兜底昵称头像；
 * - /x/space/wbi/arc/search 拿投稿列表，**必须 wbi 签名**，时长只有 "mm:ss" 字符串；
 * - /x/polymer/web-dynamic/v1/feed/space 拿该用户的动态，**必须 wbi 签名**，
 *   且**不能**带 dm_img_* 参数，IP 属地只能从这里取；
 * - /x/relation/stat 与 /x/space/navnum 无需签名，稳定返回粉丝数与投稿数。
 */
export class SpaceService {
  /** 主页首屏：资料 + 首屏动态（一次请求喂两个模块，IP 属地从动态里取） */
  static async bundle(mid: number): Promise<SpaceBundle> {
    const result: SpaceBundle = new SpaceBundle();
    let dynamics: Array<DynamicCard> = [];
    try {
      dynamics = await DynamicService.loadSpace(mid, '');
    } catch (err) {
      console.warn(`${TAG} feed/space failed: ${String(err)}`);
    }
    result.dynamics = dynamics;

    const space: UserSpace = await SpaceService.profile(mid);
    // acc/info 拿不到（风控）时用动态作者字段兜底，保证页面不是空白
    if (!space.resolved && dynamics.length > 0) {
      const first: DynamicCard = dynamics[0];
      space.mid = mid;
      space.name = first.authorName;
      space.face = first.authorFace;
    }
    for (let i = 0; i < dynamics.length; i++) {
      if (dynamics[i].pubLocation.length > 0) {
        space.ipLocation = dynamics[i].pubLocation;
        break;
      }
    }
    result.space = space;
    return result;
  }

  /** 仅资料（详情页作者行 / 卡片长按进主页时用） */
  static async profile(mid: number): Promise<UserSpace> {
    const space: UserSpace = new UserSpace();
    space.mid = mid;
    const info: Record<string, Object> | null = await SpaceService.accInfo(mid);
    if (info !== null) {
      SpaceService.fillFromAccInfo(space, info);
      space.resolved = true;
    }
    await SpaceService.fillCounters(space);
    return space;
  }

  private static async accInfo(mid: number): Promise<Record<string, Object> | null> {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const params: Record<string, string> = {};
        params['mid'] = `${mid}`;
        params['token'] = '';
        params['platform'] = 'web';
        params['web_location'] = '1550101';
        const query: Record<string, string> = await WbiSign.signQuery(params);
        const body: Record<string, Object> = await BiliHttp.getJson(
          BiliHttp.API_HOST, '/x/space/wbi/acc/info', query, `https://space.bilibili.com/${mid}`);
        const code: number = J.num(body, 'code');
        if (code === 0) {
          return J.obj(body, 'data');
        }
        console.warn(`${TAG} acc/info code=${code} mid=${mid} attempt=${attempt}`);
        // -352 风控 / -799 请求过于频繁 / -412 封禁：全部按「退避后重试一次」处理
        if (attempt === 0) {
          await SpaceService.delay(RETRY_DELAY_MS);
          WbiSign.invalidate();
        }
      } catch (err) {
        console.warn(`${TAG} acc/info failed: ${String(err)}`);
        if (attempt === 0) {
          await SpaceService.delay(RETRY_DELAY_MS);
        }
      }
    }
    return null;
  }

  private static fillFromAccInfo(space: UserSpace, data: Record<string, Object>): void {
    space.name = J.str(data, 'name');
    space.face = J.str(data, 'face').replace(/^http:/, 'https:');
    space.sign = J.str(data, 'sign');
    space.level = J.num(data, 'level');
    space.cover = SpaceService.coverOf(data);
    space.followed = J.bool(data, 'is_followed');
  }

  /** 顶部背景：top_photo_v2.l_img > top_photo（旧字段无域名）> 空（页面回退头像大图） */
  private static coverOf(data: Record<string, Object>): string {
    const v2: Record<string, Object> = J.obj(data, 'top_photo_v2');
    let cover: string = J.str(v2, 'l_img');
    if (cover.length === 0) {
      cover = J.str(v2, 'l_200h_img');
    }
    if (cover.length === 0) {
      const legacy: string = J.str(data, 'top_photo');
      if (legacy.length > 0) {
        cover = legacy.startsWith('http') ? legacy : `https://i0.hdslb.com/${legacy}`;
      }
    }
    return cover.replace(/^http:/, 'https:');
  }

  /** 粉丝 / 关注 / 投稿数：两个轻接口，任一失败就留空 */
  private static async fillCounters(space: UserSpace): Promise<void> {
    try {
      const query: Record<string, string> = {};
      query['vmid'] = `${space.mid}`;
      const body: Record<string, Object> = await BiliHttp.getJson(
        BiliHttp.API_HOST, '/x/relation/stat', query, `https://space.bilibili.com/${space.mid}`);
      if (J.num(body, 'code') === 0) {
        const data: Record<string, Object> = J.obj(body, 'data');
        space.followerText = shortCount(J.num(data, 'follower'));
        space.followingText = shortCount(J.num(data, 'following'));
      }
    } catch (err) {
      console.warn(`${TAG} relation stat failed: ${String(err)}`);
    }
    try {
      const query: Record<string, string> = {};
      query['mid'] = `${space.mid}`;
      const body: Record<string, Object> = await BiliHttp.getJson(
        BiliHttp.API_HOST, '/x/space/navnum', query, `https://space.bilibili.com/${space.mid}`);
      if (J.num(body, 'code') === 0) {
        space.archiveText = shortCount(J.num(J.obj(body, 'data'), 'video'));
      }
    } catch (err) {
      console.warn(`${TAG} navnum failed: ${String(err)}`);
    }
  }

  /**
   * 投稿列表分页。
   * vlist 里没有 duration 数字字段，只有 "19:33" 这种 length 字符串，需要自己解析成秒。
   */
  static async archives(mid: number, page: number, pageSize: number): Promise<SpaceArchivePage> {
    const result: SpaceArchivePage = new SpaceArchivePage();
    result.page = page;
    const params: Record<string, string> = {};
    params['mid'] = `${mid}`;
    params['ps'] = `${pageSize}`;
    params['pn'] = `${page}`;
    params['order'] = 'pubdate';
    params['platform'] = 'web';
    params['web_location'] = '1550101';
    const query: Record<string, string> = await WbiSign.signQuery(params);
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/space/wbi/arc/search', query, `https://space.bilibili.com/${mid}`);
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `投稿接口返回 ${code}`);
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    const pageInfo: Record<string, Object> = J.obj(data, 'page');
    result.total = J.num(pageInfo, 'count');
    const list: Record<string, Object> = J.obj(data, 'list');
    const vlist: Array<Object> = J.arr(list, 'vlist');
    for (let i = 0; i < vlist.length; i++) {
      const item: Record<string, Object> = vlist[i] as Record<string, Object>;
      const title: string = J.str(item, 'title');
      if (title.length === 0) {
        continue;
      }
      result.cards.push({
        aid: J.num(item, 'aid'),
        bvid: J.str(item, 'bvid'),
        cid: 0,
        title: title,
        cover: J.str(item, 'pic').replace(/^http:/, 'https:'),
        author: J.str(item, 'author'),
        authorFace: '',
        authorMid: mid,
        duration: SpaceService.parseLength(J.str(item, 'length')),
        pubTs: J.num(item, 'created'),
        viewText: `${shortCount(J.num(item, 'play'))}播放`,
        danmuText: `${shortCount(J.num(item, 'video_review'))}弹幕`,
        likeText: '',
        replyText: `${shortCount(J.num(item, 'comment'))}评论`,
        cornerText: '',
        followed: false,
        vertical: false
      });
    }
    result.hasMore = result.cards.length >= pageSize &&
      (result.total === 0 || page * pageSize < result.total);
    console.info(`${TAG} archives mid=${mid} page=${page} got=${result.cards.length} total=${result.total}`);
    return result;
  }

  /**
   * 用户追的番剧 / 影视分页（V2.1.2 主页第三个页签）。
   *
   * type=1 追番、type=2 追剧，两者合并成一次展示（官方主页的「番剧」页签也是合并的）。
   * 接口不需要 wbi、也不需要登录；但用户把追番设为隐私时返回 53013，
   * 此时置 restricted 让页面显示「该用户未公开追番」而不是「还没有追番」。
   */
  static async bangumi(mid: number, page: number, pageSize: number): Promise<SpaceBangumiPage> {
    const result: SpaceBangumiPage = new SpaceBangumiPage();
    result.page = page;
    const typeQuery: Record<string, string> = {};
    typeQuery['type'] = '1';
    typeQuery['follow_status'] = '0';
    typeQuery['pn'] = `${page}`;
    typeQuery['ps'] = `${pageSize}`;
    typeQuery['vmid'] = `${mid}`;
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/space/bangumi/follow/list', typeQuery,
      `https://space.bilibili.com/${mid}`);
    const code: number = J.num(body, 'code');
    if (code === 53013) {
      result.restricted = true;
      return result;
    }
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `番剧接口返回 ${code}`);
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    result.total = J.num(data, 'total');
    const list: Array<Object> = J.arr(data, 'list');
    for (let i = 0; i < list.length; i++) {
      const item: Record<string, Object> = list[i] as Record<string, Object>;
      const title: string = J.str(item, 'title');
      if (title.length === 0) {
        continue;
      }
      const newEp: Record<string, Object> = J.obj(item, 'new_ep');
      let progress: string = J.str(newEp, 'index_show');
      if (progress.length === 0) {
        const total: number = J.num(item, 'total_count');
        progress = total > 0 ? `全 ${total} 话` : '';
      }
      result.items.push({
        seasonId: J.num(item, 'season_id'),
        title: title,
        cover: J.str(item, 'cover').replace(/^http:/, 'https:'),
        totalCount: J.num(item, 'total_count'),
        finished: J.num(item, 'is_finish') === 1,
        typeName: J.str(item, 'season_type_name'),
        progressText: progress,
        viewCount: J.num(J.obj(item, 'stat'), 'view'),
        badge: J.str(item, 'badge')
      });
    }
    result.hasMore = result.items.length >= pageSize &&
      (result.total === 0 || page * pageSize < result.total);
    console.info(`${TAG} bangumi mid=${mid} page=${page} got=${result.items.length} total=${result.total}`);
    return result;
  }

  /** 关注分组列表（/x/relation/tags，data 直接是数组，无需登录判断由页面负责） */
  static async followTags(): Promise<Array<FollowTag>> {
    const result: Array<FollowTag> = [];
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/relation/tags', {}, 'https://space.bilibili.com/');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `分组接口返回 ${code}`);
    }
    const list: Array<Object> = J.arr(body, 'data');
    for (let i = 0; i < list.length; i++) {
      const item: Record<string, Object> = list[i] as Record<string, Object>;
      result.push({
        tagid: J.num(item, 'tagid'),
        name: J.str(item, 'name'),
        count: J.num(item, 'count')
      });
    }
    return result;
  }

  /**
   * 关注 / 取消关注。
   * act=1 关注、act=2 取消（对照 PiliNara relationMod）。
   */
  static async setFollow(mid: number, follow: boolean): Promise<void> {
    SpaceService.requireLogin();
    const query: Record<string, string> = {};
    query['statistics'] = '{"appId":100,"platform":5}';
    query['x-bili-device-req-json'] = '{"platform":"web","device":"pc","spmid":"333.1387"}';
    const form: Record<string, string> = {};
    form['fid'] = `${mid}`;
    form['act'] = follow ? '1' : '2';
    form['re_src'] = '11';
    form['gaia_source'] = 'web_main';
    form['spmid'] = '333.1387';
    form['extend_content'] = `{"entity":"user","entity_id":${mid},"fp":""}`;
    form['csrf'] = BiliCookie.csrf();
    const body: Record<string, Object> = await BiliHttp.postForm(
      BiliHttp.API_HOST, '/x/relation/modify', form,
      `https://space.bilibili.com/${mid}/dynamic`, query);
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `关注操作失败（${code}）`);
    }
  }

  /**
   * 把某个用户放进指定关注分组。
   * tagids=0 表示移回默认分组（对照 PiliNara addUsers 的注释）。
   */
  static async addToTag(mid: number, tagid: number): Promise<void> {
    SpaceService.requireLogin();
    const query: Record<string, string> = {};
    query['x-bili-device-req-json'] = '{"platform":"web","device":"pc","spmid":"333.1387"}';
    const form: Record<string, string> = {};
    form['fids'] = `${mid}`;
    form['tagids'] = `${tagid}`;
    form['csrf'] = BiliCookie.csrf();
    const body: Record<string, Object> = await BiliHttp.postForm(
      BiliHttp.API_HOST, '/x/relation/tags/addUsers', form,
      `https://space.bilibili.com/${mid}/dynamic`, query);
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `分组操作失败（${code}）`);
    }
  }

  /** 加入小黑屋（拉黑）：act=5 */
  static async blockUser(mid: number): Promise<void> {
    SpaceService.requireLogin();
    const query: Record<string, string> = {};
    query['statistics'] = '{"appId":100,"platform":5}';
    query['x-bili-device-req-json'] = '{"platform":"web","device":"pc","spmid":"333.1387"}';
    const form: Record<string, string> = {};
    form['fid'] = `${mid}`;
    form['act'] = '5';
    form['re_src'] = '11';
    form['gaia_source'] = 'web_main';
    form['spmid'] = '333.1387';
    form['extend_content'] = `{"entity":"user","entity_id":${mid},"fp":""}`;
    form['csrf'] = BiliCookie.csrf();
    const body: Record<string, Object> = await BiliHttp.postForm(
      BiliHttp.API_HOST, '/x/relation/modify', form,
      `https://space.bilibili.com/${mid}/dynamic`, query);
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `拉黑失败（${code}）`);
    }
  }

  private static requireLogin(): void {
    if (!BiliCookie.isLogin() || BiliCookie.csrf().length === 0) {
      throw new Error('请先登录后再操作');
    }
  }

  /** "19:33" / "1:02:03" → 秒；解析失败返回 0 */
  private static parseLength(text: string): number {
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
      seconds = seconds * 60 + value;
    }
    return seconds;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}