import { BiliHttp, J } from './BiliHttp';
import { DynamicCard, VideoCard } from '../model/BiliModels';
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
    const query: Record<string, string> = {};
    query['type'] = 'all';
    query['page'] = '1';
    query['offset'] = offset;
    query['timezone_offset'] = '-480';
    query['features'] = 'itemOpusStyle,listOnlyfans,opusBigCover,onlyfansVote,decorationCard';
    const body: Record<string, Object> = await BiliHttp.getJson(
      BiliHttp.API_HOST, '/x/polymer/web-dynamic/v1/feed/all', query, 'https://t.bilibili.com/');
    const code: number = J.num(body, 'code');
    if (code !== 0) {
      const message: string = J.str(body, 'message');
      if (code === -101) {
        throw new Error('未登录，登录后即可查看动态');
      }
      throw new Error(message.length > 0 ? message : `动态接口返回 ${code}`);
    }
    const data: Record<string, Object> = J.obj(body, 'data');
    const items: Array<Object> = J.arr(data, 'items');
    const cards: Array<DynamicCard> = [];
    for (let i = 0; i < items.length; i++) {
      const card: DynamicCard | null = DynamicService.mapItem(items[i] as Record<string, Object>);
      if (card !== null) {
        cards.push(card);
      }
    }
    console.info(`${TAG} loaded ${cards.length} dynamics, offset=${offset}`);
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
      repostName: ''
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
        likeText: '',
        replyText: '',
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
}