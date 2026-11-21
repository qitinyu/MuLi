import { BiliHttp, J } from './BiliHttp';
import { LiveCard } from '../model/BiliModels';
import { shortCount } from '../common/Format';

const TAG = 'MuLiLive';

/**
 * 直播页数据源。
 * 实测 xlive/web-interface/v1/second/getList 无 cookie 时恒 -352，
 * 因此改用 room/v1/room/get_user_recommend：分页有效、字段足够渲染卡片。
 * 注意 data 本身就是数组（不是 { list: [] }），解析时要兼容两种形状。
 */
export class LiveService {
  static async load(page: number): Promise<Array<LiveCard>> {
    const query: Record<string, string> = {};
    query['page'] = `${page}`;
    query['page_size'] = '12';
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.LIVE_HOST, '/room/v1/room/get_user_recommend', query, 'https://live.bilibili.com/');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      throw new Error(message.length > 0 ? message : `直播接口返回 ${code}`);
    }
    const raw: Object | undefined = body['data'];
    let list: Array<Object> = [];
    if (Array.isArray(raw)) {
      list = raw as Array<Object>;
    } else {
      list = J.arr(J.obj(body, 'data'), 'list');
    }
    const cards: Array<LiveCard> = [];
    for (let i = 0; i < list.length; i++) {
      const item: Record<string, Object> = list[i] as Record<string, Object>;
      const card: LiveCard = {
        roomId: J.num(item, 'roomid'),
        uid: J.num(item, 'uid'),
        title: J.str(item, 'title'),
        uname: J.str(item, 'uname'),
        face: J.str(item, 'face').replace(/^http:/, 'https:'),
        cover: J.str(item, 'user_cover').length > 0
          ? J.str(item, 'user_cover').replace(/^http:/, 'https:')
          : J.str(item, 'system_cover').replace(/^http:/, 'https:'),
        onlineText: J.str(J.obj(item, 'watched_show'), 'text_small').length > 0
          ? J.str(J.obj(item, 'watched_show'), 'text_small')
          : shortCount(J.num(item, 'online')),
        areaName: J.str(item, 'areaName')
      };
      if (card.roomId > 0 && card.title.length > 0) {
        cards.push(card);
      }
    }
    console.info(`${TAG} loaded ${cards.length} rooms at page ${page}`);
    return cards;
  }
}