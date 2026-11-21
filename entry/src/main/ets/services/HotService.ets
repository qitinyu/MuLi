import { BiliHttp, J } from './BiliHttp';
import { VideoCard } from '../model/BiliModels';
import { shortCount } from '../common/Format';

const TAG = 'MuLiHot';

/**
 * 热门页数据源。
 * 排行榜接口一次给约 100 条且无分页，因此「加载更多」只是把剩余条目继续铺到列表中。
 * 名次用接口返回的顺序 +1 计算，写入 cornerText。
 */
export class HotService {
  static async load(): Promise<Array<VideoCard>> {
    const query: Record<string, string> = {};
    query['rid'] = '0';
    query['type'] = 'all';
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/web-interface/ranking/v2', query,
      'https://www.bilibili.com/v/popular/rank/all');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `热门接口返回 ${code}`);
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    const list: Array<Object> = J.arr(data, 'list');
    const cards: Array<VideoCard> = [];
    for (let i = 0; i < list.length; i++) {
      const item: Record<string, Object> = list[i] as Record<string, Object>;
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
        viewText: `${shortCount(J.num(stat, 'view'))}播放`,
        danmuText: `${shortCount(J.num(stat, 'danmaku'))}弹幕`,
        likeText: shortCount(J.num(stat, 'like')),
        replyText: shortCount(J.num(stat, 'reply')),
        cornerText: `${i + 1}`,
        followed: false,
        vertical: width > 0 && height > width
      };
      if (card.title.length > 0) {
        cards.push(card);
      }
    }
    console.info(`${TAG} loaded ${cards.length} ranking items`);
    return cards;
  }
}