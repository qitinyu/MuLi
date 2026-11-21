import { BiliHttp, J } from './BiliHttp';
import { AuthorStat, VideoDetail } from '../model/BiliModels';
import { shortCount, pubTimeText } from '../common/Format';

const TAG = 'MuLiVideo';

/**
 * 视频详情与播放地址。
 *
 * 播放地址说明（实测）：
 * - 走 web 端 `platform=html5&high_quality=1` 分支，返回的是 **单文件 mp4（含音轨）**，
 *   可以直接交给 AVPlayer；若用默认 web 分支则返回分离的 video/audio 两条 DASH 流，需要做混流，不适合首版。
 * - 编码实际为 H.264，qn 请求 80 时服务端通常回落 64（720P），以返回的 data.quality 为准。
 */
export class VideoService {
  /** 视频详情（标题 / 播放量 / 简介 / UP 主） */
  static async detail(bvid: string, aid: number): Promise<VideoDetail> {
    const query: Record<string, string> = {};
    if (bvid.length > 0) {
      query['bvid'] = bvid;
    } else {
      query['aid'] = `${aid}`;
    }
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/web-interface/view', query);
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `视频详情返回 ${code}`);
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    const owner: Record<string, Object> = J.obj(data, 'owner');
    const stat: Record<string, Object> = J.obj(data, 'stat');
    const item: VideoDetail = new VideoDetail();
    item.aid = J.num(data, 'aid');
    item.bvid = J.str(data, 'bvid');
    item.cid = J.num(data, 'cid');
    item.title = J.str(data, 'title');
    item.cover = J.str(data, 'pic').replace(/^http:/, 'https:');
    item.desc = J.str(data, 'desc');
    item.pubTs = J.num(data, 'pubdate');
    item.duration = J.num(data, 'duration');
    item.viewText = `${shortCount(J.num(stat, 'view'))}播放`;
    item.danmuText = shortCount(J.num(stat, 'danmaku'));
    item.likeText = shortCount(J.num(stat, 'like'));
    item.coinText = shortCount(J.num(stat, 'coin'));
    item.favText = shortCount(J.num(stat, 'favorite'));
    item.shareText = shortCount(J.num(stat, 'share'));
    item.replyText = shortCount(J.num(stat, 'reply'));
    item.authorName = J.str(owner, 'name');
    item.authorFace = J.str(owner, 'face').replace(/^http:/, 'https:');
    item.authorMid = J.num(owner, 'mid');
    // 多 P 视频：cid 可能是 cid 列表，取第一 P
    const pages: Array<Object> = J.arr(data, 'pages');
    if (item.cid === 0 && pages.length > 0) {
      item.cid = J.num(pages[0] as Record<string, Object>, 'cid');
    }
    return item;
  }

  /**
   * 取可直接交给 AVPlayer 的单文件播放地址。
   *
   * 只用一套参数会偶发「该视频暂无可用播放地址」——不同稿件可用的分支不一样：
   * 1) html5 + fnval=16：首选，返回单文件 mp4（含音轨），画质通常 720P；
   * 2) html5 且不带 fnval：部分稿件在 1) 里只给 DASH，这一档会回落成 mp4；
   * 3) pc + fnval=0：旧版 durl 分支，只在低清晰度下可用，作为最后兜底。
   * 三档都拿不到时，把服务端最后一次的提示原样抛出去，不再统一显示「暂无地址」。
   */
  static async playUrl(bvid: string, cid: number, aid: number, qn: number = 0): Promise<string> {
    if (cid <= 0) {
      throw new Error('缺少分 P 信息，无法获取播放地址');
    }
    const base: Record<string, string> = {};
    if (bvid.length > 0) {
      base['bvid'] = bvid;
    } else {
      base['avid'] = `${aid}`;
    }
    base['cid'] = `${cid}`;
    const attempts: Array<Record<string, string>> = [
      {
        'qn': qn > 0 ? `${qn}` : '80',
        'fnval': '16',
        'fourk': '1',
        'platform': 'html5',
        'high_quality': '1'
      },
      {
        'qn': '64',
        'platform': 'html5',
        'high_quality': '1'
      },
      {
        'qn': '32',
        'fnval': '0',
        'platform': 'pc'
      }
    ];
    let lastMessage: string = '';
    let dashOnly: boolean = false;
    for (let i = 0; i < attempts.length; i++) {
      const query: Record<string, string> = {};
      const baseKeys: Array<string> = Object.keys(base);
      for (let k = 0; k < baseKeys.length; k++) {
        query[baseKeys[k]] = base[baseKeys[k]];
      }
      const attemptKeys: Array<string> = Object.keys(attempts[i]);
      for (let k = 0; k < attemptKeys.length; k++) {
        query[attemptKeys[k]] = attempts[i][attemptKeys[k]];
      }
      let body: Record<string, Object>;
      try {
        body = await BiliHttp.getJson(BiliHttp.API_HOST, '/x/player/playurl', query, 'https://www.bilibili.com/');
      } catch (err) {
        lastMessage = err instanceof Error ? err.message : '播放地址请求失败';
        continue;
      }
      const code: number = J.num(body, 'code');
      if (code !== 0) {
        lastMessage = VideoService.playErrorMessage(code, J.str(body, 'message'));
        if (code === -10403 || code === -404) {
          break;
        }
        continue;
      }
      const data: Record<string, Object> = J.obj(body, 'data');
      const durl: Array<Object> = J.arr(data, 'durl');
      if (durl.length > 0) {
        const url: string = J.str(durl[0] as Record<string, Object>, 'url').replace(/^http:/, 'https:');
        if (url.length > 0) {
          console.info(`${TAG} playUrl ok branch=${i} quality=${J.num(data, 'quality')} host=${VideoService.hostOf(url)}`);
          return url;
        }
      }
      const dash: Record<string, Object> = J.obj(data, 'dash');
      if (Object.keys(dash).length > 0) {
        dashOnly = true;
      }
    }
    if (lastMessage.length > 0) {
      throw new Error(lastMessage);
    }
    if (dashOnly) {
      throw new Error('该视频仅提供 DASH 流，暂不可播放');
    }
    throw new Error('该视频暂无可用播放地址');
  }

  /** 把服务端的返回码翻译成用户能看懂的一句话 */
  private static playErrorMessage(code: number, message: string): string {
    if (code === -404) {
      return '视频不存在或已失效';
    }
    if (code === -10403) {
      return '该视频为充电专属 / 大会员专享，暂不可播放';
    }
    if (code === -352) {
      return '请求被服务端风控拦截，请稍后再试';
    }
    if (code === -400) {
      return '播放参数无效，请重试';
    }
    return message.length > 0 ? message : `播放地址返回 ${code}`;
  }

  /** 发布时间文案，供播放页副标题使用 */
  static publishedText(ts: number): string {
    return pubTimeText(ts);
  }

  /**
   * UP 主粉丝数 / 投稿数（参考图作者行副标题）。
   * 两个接口互相独立，任一失败只留空该字段，绝不影响详情与播放。
   */
  static async authorStat(mid: number): Promise<AuthorStat> {
    const stat: AuthorStat = new AuthorStat();
    if (mid <= 0) {
      return stat;
    }
    const followerJob: Promise<void> = VideoService.fetchFollower(mid).then((text: string): void => {
      stat.followerText = text;
    }).catch((): void => {
      // 风控或网络失败：保持空字符串，作者行只显示已有字段
    });
    const archiveJob: Promise<void> = VideoService.fetchArchive(mid).then((text: string): void => {
      stat.archiveText = text;
    }).catch((): void => {
    });
    await Promise.all([followerJob, archiveJob]);
    return stat;
  }

  private static async fetchFollower(mid: number): Promise<string> {
    const query: Record<string, string> = {};
    query['vmid'] = `${mid}`;
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/relation/stat', query, 'https://space.bilibili.com/');
    if (J.num(body, 'code') !== 0) {
      return '';
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    const follower: number = J.num(data, 'follower');
    return follower > 0 ? shortCount(follower) : '';
  }

  private static async fetchArchive(mid: number): Promise<string> {
    const query: Record<string, string> = {};
    query['mid'] = `${mid}`;
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/space/navnum', query, 'https://space.bilibili.com/');
    if (J.num(body, 'code') !== 0) {
      return '';
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    const video: number = J.num(data, 'video');
    return video > 0 ? shortCount(video) : '';
  }

  private static hostOf(url: string): string {
    const start: number = url.indexOf('://');
    if (start < 0) {
      return '';
    }
    const rest: string = url.substring(start + 3);
    const slash: number = rest.indexOf('/');
    return slash > 0 ? rest.substring(0, slash) : rest;
  }
}