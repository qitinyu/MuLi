/**
 * bilibili 数据模型（推荐 / 热门 / 直播 / 动态 / 用户）。
 * 一律使用扁平化后的展示字段：接口里的数值、时间、封面 URL 在 service 层就处理完，
 * 组件层只负责渲染，不再关心原始 JSON 结构。
 */

/** 视频卡片：推荐流、排行榜、动态里的视频共用同一结构 */
export interface VideoCard {
  aid: number;
  bvid: string;
  cid: number;
  title: string;
  cover: string;
  author: string;
  authorFace: string;
  authorMid: number;
  /** 时长（秒），0 表示未知 */
  duration: number;
  /** 发布时间（秒级时间戳） */
  pubTs: number;
  viewText: string;
  danmuText: string;
  likeText: string;
  replyText: string;
  /** 封面左上角角标：排行榜的名次等 */
  cornerText: string;
  followed: boolean;
  /** 竖屏视频（依据接口 dimension 的宽高判断，卡片第二行给「竖屏」提示） */
  vertical: boolean;
  /** 分区名（如「单机游戏」）：只有相关推荐接口会带，播放页推荐行用来解释「为什么推这条」 */
  tname?: string;
}

/** 直播卡片 */
export interface LiveCard {
  roomId: number;
  uid: number;
  title: string;
  uname: string;
  face: string;
  cover: string;
  onlineText: string;
  areaName: string;
}

/** 动态卡片类型 */
export type DynamicKind = 'video' | 'pics' | 'text';

/** 动态卡片 */
export interface DynamicCard {
  id: string;
  authorName: string;
  authorFace: string;
  authorMid: number;
  pubText: string;
  text: string;
  kind: DynamicKind;
  video: VideoCard | null;
  pics: Array<string>;
  likeText: string;
  commentText: string;
  forwardText: string;
  repostName: string;
  /** 发布 IP 属地（module_author.pub_location_text，多数为空串） */
  pubLocation: string;
  /** 点赞 / 评论 / 转发原始数值：卡片上要显示具体数字而不是「1.2万」 */
  likeCount: number;
  commentCount: number;
  forwardCount: number;
  /** 当前账号是否已点赞（module_stat.like.status），卡片按钮据此显示实心/空心 */
  liked: boolean;
}

/** feed/space 一页：动态 + 翻页游标 */
export class DynamicPageData {
  cards: Array<DynamicCard> = [];
  /** 下一页游标（接口 data.offset，空串表示没有下一页） */
  offset: string = '';
  hasMore: boolean = false;
}

/**
 * 其他用户的空间资料（V2.1.2 用户主页）。
 *
 * 数据来源：/x/space/wbi/acc/info（需 wbi 签名，易被风控）+ relation/stat + navnum。
 * IP 属地：空间接口本身不下发该字段，只能取该用户最近一条动态的
 * module_author.pub_location_text（经常为空），取不到按「未知」显示。
 */
export class UserSpace {
  mid: number = 0;
  name: string = '';
  face: string = '';
  sign: string = '';
  level: number = 0;
  /** 顶部背景图：top_photo_v2.l_img > top_photo > 空（空则回退头像大图） */
  cover: string = '';
  ipLocation: string = '';
  followerText: string = '';
  followingText: string = '';
  /** 投稿数 */
  archiveText: string = '';
  /** 获赞数 */
  likeText: string = '';
  /** 是否已关注（acc/info 的 is_followed） */
  followed: boolean = false;
  /** 资料是否解析成功：false 时页面标题/头像用兜底提示 */
  resolved: boolean = false;

  clone(): UserSpace {
    const copy: UserSpace = new UserSpace();
    copy.mid = this.mid;
    copy.name = this.name;
    copy.face = this.face;
    copy.sign = this.sign;
    copy.level = this.level;
    copy.cover = this.cover;
    copy.ipLocation = this.ipLocation;
    copy.followerText = this.followerText;
    copy.followingText = this.followingText;
    copy.archiveText = this.archiveText;
    copy.likeText = this.likeText;
    copy.followed = this.followed;
    copy.resolved = this.resolved;
    return copy;
  }
}

export function emptyUserSpace(): UserSpace {
  return new UserSpace();
}

/** 空间投稿列表的一页 */
export class SpaceArchivePage {
  cards: Array<VideoCard> = [];
  /** 当前页码（1 起） */
  page: number = 1;
  /** 投稿总数 */
  total: number = 0;
  hasMore: boolean = false;
}

/**
 * 用户追的番剧 / 影视（V2.1.2 用户主页第三个页签）。
 *
 * 数据源 /x/space/bangumi/follow/list（type=1 追番、type=2 追剧），
 * 无需 wbi、无需登录，但用户把「收藏夹 / 追番」设为隐私时返回 53013。
 */
export interface SpaceBangumi {
  seasonId: number;
  title: string;
  cover: string;
  /** 总集数（total_count） */
  totalCount: number;
  /** 是否完结 */
  finished: boolean;
  /** 分类名，如「国创」「纪录片」 */
  typeName: string;
  /** 更新进度文案，如「更新至第267话」「全 12 话」 */
  progressText: string;
  /** 播放量（stat.view 原始值） */
  viewCount: number;
  /** 角标文案，如「大会员」 */
  badge: string;
}

export function emptySpaceBangumi(): SpaceBangumi {
  return {
    seasonId: 0, title: '', cover: '', totalCount: 0, finished: false,
    typeName: '', progressText: '', viewCount: 0, badge: ''
  };
}

/** 番剧列表的一页 */
export class SpaceBangumiPage {
  items: Array<SpaceBangumi> = [];
  page: number = 1;
  total: number = 0;
  hasMore: boolean = false;
  /** 用户把追番列表设为隐私：页面据此显示提示而不是「还没有追番」 */
  restricted: boolean = false;
}

/** 关注分组（/x/relation/tags） */
export interface FollowTag {
  tagid: number;
  name: string;
  count: number;
}

export function emptyFollowTag(): FollowTag {
  return { tagid: 0, name: '', count: 0 };
}

/**
 * 用户主页首屏包：资料 + 首屏动态。
 * 两件事共用一次 feed/space 请求：动态列表本身要渲染，IP 属地也只能从动态的
 * module_author.pub_location_text 里取（空间接口不下发该字段）。
 */
export class SpaceBundle {
  space: UserSpace = new UserSpace();
  dynamics: Array<DynamicCard> = [];
}

/** 打开用户主页的路由参数（pushPathByName('user', param)） */
export class UserOpenParam {
  mid: number = 0;

  constructor(mid: number) {
    this.mid = mid;
  }
}

/**
 * 动态页顶部「快捷 UP 主」行的一个头像项。
 * 数据源有两个：关注列表接口 uplist（完整、有序）+ 已加载动态里的作者去重（兜底）。
 */
export interface QuickUp {
  mid: number;
  name: string;
  face: string;
  /** 有未读更新：接口给 has_update 时头像加小圆点 */
  hasUpdate: boolean;
}

export function emptyQuickUp(): QuickUp {
  return { mid: 0, name: '', face: '', hasUpdate: false };
}

/** 当前登录用户资料（nav + nav/stat + myinfo + upstat 汇总） */
export class UserProfile {
  isLogin: boolean = false;
  mid: number = 0;
  name: string = '';
  face: string = '';
  level: number = 0;
  expCurrent: number = 0;
  expNext: number = 0;
  bcoin: number = 0;
  coin: number = 0;
  sign: string = '';
  ipLocation: string = '';
  following: number = 0;
  follower: number = 0;
  likes: number = 0;
  /**
   * 资料来自公开接口（space card）而不是登录态接口。
   * 出现这种情况说明 cookie 还在但 nav 判定未登录，
   * 界面上照常显示头像昵称，但 B币 / 硬币这类私有数据不可用。
   */
  publicOnly: boolean = false;

  clone(): UserProfile {
    const copy: UserProfile = new UserProfile();
    copy.isLogin = this.isLogin;
    copy.mid = this.mid;
    copy.name = this.name;
    copy.face = this.face;
    copy.level = this.level;
    copy.expCurrent = this.expCurrent;
    copy.expNext = this.expNext;
    copy.bcoin = this.bcoin;
    copy.coin = this.coin;
    copy.sign = this.sign;
    copy.ipLocation = this.ipLocation;
    copy.following = this.following;
    copy.follower = this.follower;
    copy.likes = this.likes;
    copy.publicOnly = this.publicOnly;
    return copy;
  }
}

/** 视频详情（播放页用）：view 接口的展示字段 + 播放地址 */
export class VideoDetail {
  aid: number = 0;
  bvid: string = '';
  cid: number = 0;
  title: string = '';
  cover: string = '';
  desc: string = '';
  pubTs: number = 0;
  duration: number = 0;
  viewText: string = '';
  danmuText: string = '';
  likeText: string = '';
  /** 点赞数原值：本地点赞 / 取消后要在这个数上 ±1 再格式化，不能拿「1.2万」这种文案反算 */
  likeCount: number = 0;
  coinText: string = '';
  favText: string = '';
  shareText: string = '';
  replyText: string = '';
  authorName: string = '';
  authorFace: string = '';
  authorMid: number = 0;
  /** 粉丝数（relation/stat 补充，拉取失败留空） */
  followerText: string = '';
  /** 投稿数（space/navnum 补充，拉取失败留空） */
  archiveText: string = '';

  clone(): VideoDetail {
    const copy: VideoDetail = new VideoDetail();
    copy.aid = this.aid;
    copy.bvid = this.bvid;
    copy.cid = this.cid;
    copy.title = this.title;
    copy.cover = this.cover;
    copy.desc = this.desc;
    copy.pubTs = this.pubTs;
    copy.duration = this.duration;
    copy.viewText = this.viewText;
    copy.danmuText = this.danmuText;
    copy.likeText = this.likeText;
    copy.likeCount = this.likeCount;
    copy.coinText = this.coinText;
    copy.favText = this.favText;
    copy.shareText = this.shareText;
    copy.replyText = this.replyText;
    copy.authorName = this.authorName;
    copy.authorFace = this.authorFace;
    copy.authorMid = this.authorMid;
    copy.followerText = this.followerText;
    copy.archiveText = this.archiveText;
    return copy;
  }
}

/** UP 主统计（详情页作者行副标题用） */
export class AuthorStat {
  followerText: string = '';
  archiveText: string = '';
}

/** 打开视频播放页的路由参数（pushPathByName('video', param)） */
export class VideoOpenParam {
  bvid: string = '';
  aid: number = 0;
  cid: number = 0;
  /**
   * 进入播放页后自动切到评论 Tab 并展开评论输入框（V2.1.2：动态卡片上的「评论」按钮）。
   */
  focusComment: boolean = false;

  constructor(bvid: string, aid: number, cid: number) {
    this.bvid = bvid;
    this.aid = aid;
    this.cid = cid;
  }
}

/** 二维码登录会话 */
export class QrSession {
  url: string = '';
  key: string = '';
}

/** 扫码轮询结果码 */
export const QR_EXPIRED: number = 86038;
export const QR_WAITING: number = 86101;
export const QR_SCANNED: number = 86090;
export const QR_SUCCESS: number = 0;

/**
 * 空卡片工厂。
 * @Prop 装饰的接口类型属性必须有初值，而 ArkTS 不支持内联对象字面量类型，
 * 因此把「零值卡片」收敛到模型层，组件只 import 这两个函数。
 */
export function emptyVideoCard(): VideoCard {
  return {
    aid: 0,
    bvid: '',
    cid: 0,
    title: '',
    cover: '',
    author: '',
    authorFace: '',
    authorMid: 0,
    duration: 0,
    pubTs: 0,
    viewText: '',
    danmuText: '',
    likeText: '',
    replyText: '',
    cornerText: '',
    followed: false,
    vertical: false
  };
}

export function emptyLiveCard(): LiveCard {
  return {
    roomId: 0,
    uid: 0,
    title: '',
    uname: '',
    face: '',
    cover: '',
    onlineText: '',
    areaName: ''
  };
}

export function emptyDynamicCard(): DynamicCard {
  return {
    id: '',
    authorName: '',
    authorFace: '',
    authorMid: 0,
    pubText: '',
    text: '',
    kind: 'text',
    video: null,
    pics: [],
    likeText: '',
    commentText: '',
    forwardText: '',
    repostName: '',
    pubLocation: '',
    likeCount: 0,
    commentCount: 0,
    forwardCount: 0,
    liked: false
  };
}

/** 收藏夹（我的收藏里的一个文件夹） */
export class FavFolder {
  id: number = 0;
  title: string = '';
  /** 夹内视频数 */
  count: number = 0;
  /** 当前视频是否已在这个夹里：只有带 rid 查询时接口才会给 */
  contains: boolean = false;
  /** 夹封面（夹内第一条视频的封面，空夹没有），收藏面板做成封面墙用 */
  cover: string = '';
}

/**
 * 收藏 / 观看历史 / 稍后再看 三个列表共用的一条记录。
 *
 * card 复用推荐流那套字段（标题 / 封面 / UP 主 / 时长），
 * 额外两项是这三个列表才有的：进度（秒）与时间戳（收藏时间 / 观看时间 / 添加到稍后再看的时间）。
 */
export class LibraryItem {
  card: VideoCard = emptyVideoCard();
  /** 已观看时长（秒）：收藏列表恒为 0 */
  progress: number = 0;
  /** 秒级时间戳 */
  timeTs: number = 0;
  /** 本机观看记录（服务端历史里没有这条时用来提示「本机」） */
  local: boolean = false;
}

export function emptyLibraryItem(): LibraryItem {
  return new LibraryItem();
}