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
    repostName: ''
  };
}