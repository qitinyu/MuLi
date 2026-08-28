import { VideoItem } from '../models/VideoItem';
import { BiliHttpClient } from './BiliHttpClient';

export interface DynamicBatch {
  items: VideoItem[];
  authors: DynamicAuthor[];
  offset: string;
  hasMore: boolean;
}

export class DynamicAuthor {
  name: string = '';
  face: string = '';
  publishTime: number = 0;
}

class DynamicQuery {
  type: string = 'video';
  offset: string = '';
  features: string = 'itemOpusStyle,listOnlyfans,onlyfansQaCard';
  web_location: string = '333.1365';

  toRecord(): Record<string, string> {
    const result: Record<string, string> = {};
    result['type'] = this.type;
    result['offset'] = this.offset;
    result['features'] = this.features;
    result['web_location'] = this.web_location;
    return result;
  }
}

export class DynamicService {
  static async loadVideos(cookie: string, offset: string = ''): Promise<DynamicBatch> {
    const query: DynamicQuery = new DynamicQuery();
    query.offset = offset;
    const result: Record<string, Object> = await BiliHttpClient.getJson(
      '/x/polymer/web-dynamic/v1/feed/all',
      query.toRecord(),
      cookie);
    if (Number(result['code'] ?? -1) !== 0) throw new Error(String(result['message'] ?? '动态加载失败'));
    const data: Record<string, Object> = (result['data'] as Record<string, Object>) ?? {};
    const rawItems: Object[] = (data['items'] as Object[]) ?? [];
    const items: VideoItem[] = [];
    const authors: DynamicAuthor[] = [];
    rawItems.forEach((raw: Object, index: number): void => {
      const rawRecord: Record<string, Object> = raw as Record<string, Object>;
      const author: DynamicAuthor | null = DynamicService.parseAuthor(rawRecord);
      if (author !== null && !authors.some((candidate: DynamicAuthor): boolean => candidate.name === author.name)) {
        authors.push(author);
      }
      const item: VideoItem | null = DynamicService.parseItem(rawRecord, index);
      if (item !== null) items.push(item);
    });
    return { items: items, authors: authors, offset: String(data['offset'] ?? ''), hasMore: Boolean(data['has_more'] ?? false) };
  }

  private static parseAuthor(raw: Record<string, Object>): DynamicAuthor | null {
    const modules: Record<string, Object> = (raw['modules'] as Record<string, Object>) ?? {};
    const author: Record<string, Object> = (modules['module_author'] as Record<string, Object>) ?? {};
    const name: string = String(author['name'] ?? '');
    const face: string = String(author['face'] ?? '');
    const rawTime: number = Number(author['pub_ts'] ?? 0);
    const publishTime: number = rawTime > 100000000000 ? Math.floor(rawTime / 1000) : rawTime;
    const now: number = Math.floor(Date.now() / 1000);
    if (name === '' || face === '' || publishTime <= 0 || now - publishTime > 172800) return null;
    return { name: name, face: face, publishTime: publishTime };
  }

  private static parseItem(raw: Record<string, Object>, index: number): VideoItem | null {
    const modules: Record<string, Object> = (raw['modules'] as Record<string, Object>) ?? {};
    const author: Record<string, Object> = (modules['module_author'] as Record<string, Object>) ?? {};
    const dynamic: Record<string, Object> = (modules['module_dynamic'] as Record<string, Object>) ?? {};
    const major: Record<string, Object> = (dynamic['major'] as Record<string, Object>) ?? {};
    const archive: Record<string, Object> = (major['archive'] as Record<string, Object>) ?? {};
    const title: string = String(archive['title'] ?? '');
    const bvid: string = String(archive['bvid'] ?? '');
    const aid: number = Number(archive['aid'] ?? 0);
    if (title === '' || (bvid === '' && aid <= 0)) return null;
    const stat: Record<string, Object> = (archive['stat'] as Record<string, Object>) ?? {};
    const desc: Record<string, Object> = (dynamic['desc'] as Record<string, Object>) ?? {};
    const pubTs: number = Number(author['pub_ts'] ?? 0);
    return {
      id: aid > 0 ? aid : index + 1, aid: aid, bvid: bvid, cid: 0, title: title,
      author: String(author['name'] ?? ''), cover: DynamicService.compactCover(String(archive['cover'] ?? '')),
      viewCount: Number(stat['播放'] ?? stat['view'] ?? 0), danmuCount: Number(stat['弹幕'] ?? stat['danmaku'] ?? 0),
      likeCount: Number(stat['赞'] ?? stat['like'] ?? 0), commentCount: Number(stat['评论'] ?? stat['reply'] ?? 0),
      shareCount: Number(stat['转发'] ?? stat['share'] ?? 0),
      followed: true, duration: Number(archive['duration'] ?? 0), playUrl: '', placeholder: false,
      publishTime: pubTs > 100000000000 ? Math.floor(pubTs / 1000) : pubTs,
      description: String(desc['text'] ?? ''), tags: [], detailLoaded: false
    };
  }

  private static compactCover(value: string): string {
    const cover: string = value.trim();
    if (cover === '') return '';
    const atIndex: number = cover.indexOf('@');
    const queryIndex: number = cover.indexOf('?');
    let cutIndex: number = cover.length;
    if (atIndex >= 0 && atIndex < cutIndex) cutIndex = atIndex;
    if (queryIndex >= 0 && queryIndex < cutIndex) cutIndex = queryIndex;
    return cover.substring(0, cutIndex) + '@320w_180h_1c.webp';
  }
}
