import { BiliCookie, BiliHttp, J } from './BiliHttp';
import { pubTimeText } from '../common/Format';

const TAG = 'MuLiComment';

/** 一条视频评论（扁平化：接口原始结构层次太深，组件层只看这些字段） */
export class VideoComment {
  rpid: string = '';
  mid: number = 0;
  name: string = '';
  face: string = '';
  level: number = 0;
  message: string = '';
  like: number = 0;
  ctime: number = 0;
  /** 楼中楼回复数 */
  rcount: number = 0;
  /** 是否是 UP 主本人的评论 */
  fromUp: boolean = false;
  /** 已点赞（接口 action == 1，需登录 cookie） */
  liked: boolean = false;
  /** 父评论 rpid：楼中楼层才有（顶层评论为空） */
  parentRpid: string = '';
  /** 「回复 @某人」里的昵称：由父 rpid 在本楼层内解析得到，解析不到就留空 */
  replyToName: string = '';
  /** reply/main 自带的楼中楼预览（最多 2~3 条），用于展开时先展示，省一次请求 */
  preview: Array<VideoComment> = [];

  /** 展示用：发布时间文案 */
  timeText(): string {
    return pubTimeText(this.ctime);
  }
}

/** 一页评论 */
export class CommentFeed {
  items: Array<VideoComment> = [];
  /** 评论总数（接口的 all_count） */
  total: number = 0;
  /** 下一页游标：请求时原样传回 next 参数 */
  cursor: string = '';
  isEnd: boolean = true;
}

/** 一页楼中楼回复 */
export class SubReplyFeed {
  items: Array<VideoComment> = [];
  total: number = 0;
  page: number = 1;
  hasMore: boolean = false;
}

/**
 * 视频评论服务。
 *
 * 顶层评论：`/x/v2/reply/main`（网页端当前在用，20 条 + 游标分页）
 * - 旧版 `/x/v2/reply` 现在只回 3 条（服务端对网页端做了收敛），不要再用；
 * - mode = 2 按时间，mode = 3 按热度；分页把上次响应里的 cursor.next 作为下一次的 next。
 *
 * 楼中楼：`/x/v2/reply/reply?root=<顶层 rpid>&pn=<页码>&ps=10`
 * - 这里用的是**页码**分页，不是游标；总数看 page.count；
 * - 子回复的 `parent` 是父评论 rpid（数字），需要在本楼层内映射成昵称才能显示「回复 @某人」。
 */
export class CommentService {
  static readonly MODE_TIME: number = 2;
  static readonly MODE_HOT: number = 3;
  private static readonly PAGE_SIZE: string = '20';
  private static readonly SUB_PAGE_SIZE: string = '10';

  static async list(aid: number, mode: number, cursor: string): Promise<CommentFeed> {
    const feed: CommentFeed = new CommentFeed();
    if (aid <= 0) {
      return feed;
    }
    const query: Record<string, string> = {};
    query['type'] = '1';
    query['oid'] = `${aid}`;
    query['mode'] = `${mode}`;
    query['next'] = cursor.length > 0 ? cursor : '0';
    query['ps'] = CommentService.PAGE_SIZE;
    query['plat'] = '1';
    query['web_location'] = '1315875';
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/v2/reply/main', query, 'https://www.bilibili.com/');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `评论加载失败（${code}）`);
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    const cursorObj: Record<string, Object> = J.obj(data, 'cursor');
    feed.total = J.num(cursorObj, 'all_count');
    feed.cursor = J.str(cursorObj, 'next');
    feed.isEnd = J.bool(cursorObj, 'is_end');
    const replies: Array<Object> = J.arr(data, 'replies');
    const items: Array<VideoComment> = [];
    for (let i = 0; i < replies.length; i++) {
      const item: VideoComment = CommentService.toComment(replies[i] as Record<string, Object>);
      if (item.rpid.length > 0) {
        items.push(item);
      }
    }
    feed.items = items;
    console.info(`${TAG} aid=${aid} mode=${mode} got=${items.length} total=${feed.total} end=${feed.isEnd}`);
    return feed;
  }

  /** 楼中楼：root 是顶层评论的 rpid，page 从 1 开始 */
  static async subList(aid: number, rootRpid: string, page: number): Promise<SubReplyFeed> {
    const feed: SubReplyFeed = new SubReplyFeed();
    feed.page = page;
    if (aid <= 0 || rootRpid.length === 0) {
      return feed;
    }
    const query: Record<string, string> = {};
    query['oid'] = `${aid}`;
    query['type'] = '1';
    query['root'] = rootRpid;
    query['pn'] = `${page}`;
    query['ps'] = CommentService.SUB_PAGE_SIZE;
    query['web_location'] = '333.1365';
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/v2/reply/reply', query, 'https://www.bilibili.com/');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `回复加载失败（${code}）`);
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    const pageInfo: Record<string, Object> = J.obj(data, 'page');
    feed.total = J.num(pageInfo, 'count');
    const replies: Array<Object> = J.arr(data, 'replies');
    const items: Array<VideoComment> = [];
    for (let i = 0; i < replies.length; i++) {
      const item: VideoComment = CommentService.toComment(replies[i] as Record<string, Object>);
      if (item.rpid.length > 0) {
        items.push(item);
      }
    }
    feed.items = items;
    feed.hasMore = page * Number(CommentService.SUB_PAGE_SIZE) < feed.total && items.length > 0;
    console.info(`${TAG} sub root=${rootRpid} page=${page} got=${items.length} total=${feed.total}`);
    return feed;
  }

  private static toComment(raw: Record<string, Object>): VideoComment {
    const item: VideoComment = new VideoComment();
    const member: Record<string, Object> = J.obj(raw, 'member');
    const content: Record<string, Object> = J.obj(raw, 'content');
    const levelInfo: Record<string, Object> = J.obj(member, 'level_info');
    item.rpid = J.str(raw, 'rpid_str');
    if (item.rpid.length === 0) {
      item.rpid = `${J.num(raw, 'rpid')}`;
    }
    item.mid = J.num(member, 'mid');
    item.name = J.str(member, 'uname');
    item.face = J.str(member, 'avatar').replace(/^http:/, 'https:');
    item.level = J.num(levelInfo, 'current_level');
    item.message = J.str(content, 'message');
    item.like = J.num(raw, 'like');
    item.ctime = J.num(raw, 'ctime');
    item.rcount = J.num(raw, 'rcount');
    item.liked = J.num(raw, 'action') === 1;
    item.fromUp = false;
    // parent：新接口给 rpid 数字，老结构可能给对象，两种都兼容
    const parentRaw: Object | undefined = raw['parent'];
    if (parentRaw !== undefined && parentRaw !== null) {
      if (typeof parentRaw === 'number') {
        item.parentRpid = `${parentRaw}`;
      } else if (typeof parentRaw === 'string') {
        item.parentRpid = parentRaw as string;
      } else if (typeof parentRaw === 'object') {
        const parentObj: Record<string, Object> = parentRaw as Record<string, Object>;
        item.parentRpid = J.str(parentObj, 'rpid');
        if (item.parentRpid.length === 0) {
          item.parentRpid = `${J.num(parentObj, 'rpid')}`;
        }
        item.replyToName = J.str(J.obj(parentObj, 'member'), 'uname');
      }
    }
    // reply/main 会带 2 条楼中楼预览：先存下来，展开时立刻有内容
    const previewRaw: Array<Object> = J.arr(raw, 'replies');
    if (previewRaw.length > 0) {
      const preview: Array<VideoComment> = [];
      for (let i = 0; i < previewRaw.length; i++) {
        const sub: VideoComment = CommentService.toComment(previewRaw[i] as Record<string, Object>);
        if (sub.rpid.length > 0) {
          preview.push(sub);
        }
      }
      item.preview = preview;
    }
    return item;
  }

  /**
   * 把楼中楼里「回复 @某人」的昵称补全。
   *
   * 子回复只带 parent rpid，昵称得在本楼层内查：root 自己一条，其余由已加载的子回复补齐。
   * 查不到（父评论在更后面还没加载）就留空，UI 只显示「回复」不带 @。
   */
  static resolveReplyTargets(items: Array<VideoComment>, root: VideoComment): void {
    const names: Map<string, string> = new Map<string, string>();
    if (root.rpid.length > 0 && root.name.length > 0) {
      names.set(root.rpid, root.name);
    }
    for (let i = 0; i < items.length; i++) {
      if (items[i].rpid.length > 0 && items[i].name.length > 0) {
        names.set(items[i].rpid, items[i].name);
      }
    }
    for (let i = 0; i < items.length; i++) {
      const item: VideoComment = items[i];
      if (item.replyToName.length > 0) {
        continue;
      }
      if (item.parentRpid.length === 0 || item.parentRpid === item.rpid) {
        continue;
      }
      const name: string | undefined = names.get(item.parentRpid);
      if (name !== undefined && name.length > 0) {
        item.replyToName = name;
      }
    }
  }

  /** 补一次「是不是 UP 主」的判定（作者 mid 只有播放页知道） */
  static markUpper(items: Array<VideoComment>, authorMid: number): Array<VideoComment> {
    if (authorMid <= 0) {
      return items;
    }
    for (let i = 0; i < items.length; i++) {
      items[i].fromUp = items[i].mid === authorMid;
    }
    return items;
  }

  /**
   * 发评论 / 回复。
   * root 为空 = 发顶层评论；root 有值 + parent 有值 = 回复楼中楼里的某一条。
   */
  static async post(aid: number, message: string, rootRpid: string, parentRpid: string): Promise<void> {
    const text: string = message.trim();
    if (text.length === 0) {
      throw new Error('内容不能为空');
    }
    if (aid <= 0) {
      throw new Error('视频信息还没就绪');
    }
    const csrf: string = BiliCookie.csrf();
    if (!BiliCookie.isLogin() || csrf.length === 0) {
      throw new Error('请先登录后再评论');
    }
    const form: Record<string, string> = {};
    form['oid'] = `${aid}`;
    form['type'] = '1';
    form['plat'] = '1';
    form['message'] = text;
    form['csrf'] = csrf;
    if (rootRpid.length > 0) {
      form['root'] = rootRpid;
    }
    if (parentRpid.length > 0) {
      form['parent'] = parentRpid;
    }
    const body: Record<string, Object> = await BiliHttp.postForm(
      BiliHttp.API_HOST, '/x/v2/reply/add', form, `https://www.bilibili.com/video/av${aid}/`);
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const msg: string = J.str(body, 'message');
      throw new Error(msg.length > 0 ? msg : `发布失败（${code}）`);
    }
    console.info(`${TAG} posted aid=${aid} root=${rootRpid} parent=${parentRpid} len=${text.length}`);
  }
}
