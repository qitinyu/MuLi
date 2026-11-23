import { BiliCookie, BiliHttp, J } from './BiliHttp';

const TAG = 'MuLiInteractive';

/** 当前账号对某条视频的互动状态（未登录时全为 false） */
export class VideoRelation {
  liked: boolean = false;
  coined: boolean = false;
  favored: boolean = false;
}

/**
 * 视频互动：点赞 / 投币 / 收藏。
 *
 * 状态读 `/x/web-interface/archive/relation`（一个请求拿三项，比分别查 has/like 省两次往返），
 * 写入读 `/x/web-interface/archive/like`（like=1 点赞、like=2 取消），两者都要登录态 + csrf。
 */
export class InteractiveService {
  static async relation(aid: number): Promise<VideoRelation> {
    const result: VideoRelation = new VideoRelation();
    if (aid <= 0 || !BiliCookie.isLogin()) {
      return result;
    }
    const query: Record<string, string> = {};
    query['aid'] = `${aid}`;
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/web-interface/archive/relation', query, `https://www.bilibili.com/video/av${aid}/`);
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      // 未登录 / 风控都是正常分支：调用方按「未点赞」渲染，不弹错
      console.info(`${TAG} relation skipped code=${code}`);
      return result;
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    result.liked = J.bool(data, 'like');
    result.coined = J.num(data, 'coin') > 0 || J.bool(data, 'coin');
    result.favored = J.bool(data, 'favorite');
    return result;
  }

  /** 点赞 / 取消点赞；失败抛错给页面回滚乐观更新 */
  static async setLike(aid: number, like: boolean): Promise<void> {
    if (aid <= 0) {
      throw new Error('视频信息还没就绪');
    }
    const csrf: string = BiliCookie.csrf();
    if (!BiliCookie.isLogin() || csrf.length === 0) {
      throw new Error('请先登录后再点赞');
    }
    const form: Record<string, string> = {};
    form['aid'] = `${aid}`;
    form['like'] = like ? '1' : '2';
    form['csrf'] = csrf;
    const body: Record<string, Object> = await BiliHttp.postForm(
      BiliHttp.API_HOST, '/x/web-interface/archive/like', form, `https://www.bilibili.com/video/av${aid}/`);
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `点赞失败（${code}）`);
    }
    console.info(`${TAG} setLike aid=${aid} like=${like}`);
  }
}
