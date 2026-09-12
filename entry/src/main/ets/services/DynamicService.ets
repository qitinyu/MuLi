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
  mid: number = 0;
  publishTime: number = 0;
}

export interface DynamicStat {
  like: number;
  comment: number;
  share: number;
}

export interface DynamicPic {
  url: string;
  width: number;
  height: number;
}

export type DynamicEntryType = 'video' | 'pics' | 'text';

export class DynamicEntry {
  id: string = '';
  type: DynamicEntryType = 'text';
  authorName: string = '';
  authorFace: string = '';
  authorMid: number = 0;
  publishTime: number = 0;
  text: string = '';
  video: VideoItem | null = null;
  pics: DynamicPic[] = [];
  repostName: string = '';
  repostText: string = '';
  repostVideo: VideoItem | null = null;
  stat: DynamicStat = { like: 0, comment: 0, share: 0 };
}

export interface DynamicFeedBatch {
  entries: DynamicEntry[];
  authors: DynamicAuthor[];
  offset: string;
  hasMore: boolean;
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
    return { name: name, face: face, mid: Number(author['mid'] ?? 0), publishTime: publishTime };
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

  static async loadFeed(cookie: string, offset: string = ''): Promise<DynamicFeedBatch> {
    const query: DynamicQuery = new DynamicQuery();
    query.offset = offset;
    const result: Record<string, Object> = await BiliHttpClient.getJson(
      '/x/polymer/web-dynamic/v1/feed/all', query.toRecord(), cookie);
    if (Number(result['code'] ?? -1) !== 0) throw new Error(String(result['message'] ?? '动态加载失败'));
    const data: Record<string, Object> = (result['data'] as Record<string, Object>) ?? {};
    const rawItems: Object[] = (data['items'] as Object[]) ?? [];
    const entries: DynamicEntry[] = [];
    const authors: DynamicAuthor[] = [];
    rawItems.forEach((raw: Object): void => {
      const rawRecord: Record<string, Object> = raw as Record<string, Object>;
      const entry: DynamicEntry | null = DynamicService.parseEntry(rawRecord);
      if (entry === null) return;
      entries.push(entry);
      const author: DynamicAuthor = new DynamicAuthor();
      author.name = entry.authorName;
      author.face = entry.authorFace;
      author.publishTime = entry.publishTime;
      if (author.name !== '' && author.face !== '' &&
        !authors.some((candidate: DynamicAuthor): boolean => candidate.name === author.name)) {
        authors.push(author);
      }
    });
    return {
      entries: entries,
      authors: authors,
      offset: String(data['offset'] ?? ''),
      hasMore: Boolean(data['has_more'] ?? false)
    };
  }

  private static parseEntry(raw: Record<string, Object>): DynamicEntry | null {
    const id: string = String(raw['id_str'] ?? '');
    const modules: Record<string, Object> = (raw['modules'] as Record<string, Object>) ?? {};
    const author: Record<string, Object> = (modules['module_author'] as Record<string, Object>) ?? {};
    const dynamic: Record<string, Object> = (modules['module_dynamic'] as Record<string, Object>) ?? {};
    const statModule: Record<string, Object> = (modules['module_stat'] as Record<string, Object>) ?? {};
    const name: string = String(author['name'] ?? '');
    const face: string = String(author['face'] ?? '');
    if (name === '') return null;
    const pubTs: number = Number(author['pub_ts'] ?? 0);
    const entry: DynamicEntry = new DynamicEntry();
    entry.id = id;
    entry.authorName = name;
    entry.authorFace = face;
    entry.authorMid = Number(author['mid'] ?? 0);
    entry.publishTime = pubTs > 100000000000 ? Math.floor(pubTs / 1000) : pubTs;
    entry.text = String(((dynamic['desc'] ?? {}) as Record<string, Object>)['text'] ?? '');
    const stat: Record<string, Object> = (statModule['like'] as Record<string, Object>) ?? {};
    const commentStat: Record<string, Object> = (statModule['comment'] as Record<string, Object>) ?? {};
    const forwardStat: Record<string, Object> = (statModule['forward'] as Record<string, Object>) ?? {};
    entry.stat = {
      like: Number(stat['count'] ?? 0),
      comment: Number(commentStat['count'] ?? 0),
      share: Number(forwardStat['count'] ?? 0)
    };
    const major: Record<string, Object> = (dynamic['major'] as Record<string, Object>) ?? {};
    const majorType: string = String(major['type'] ?? '');
    if (majorType === 'MAJOR_TYPE_ARCHIVE') {
      entry.type = 'video';
      entry.video = DynamicService.parseVideoItem(
        (major['archive'] as Record<string, Object>) ?? {},
        entry.text, entry.authorName, entry.authorFace, entry.publishTime);
    } else if (majorType === 'MAJOR_TYPE_DRAW') {
      entry.type = 'pics';
      entry.pics = DynamicService.parsePics((major['draw'] as Record<string, Object>) ?? {});
    } else if (majorType === 'MAJOR_TYPE_OPUS') {
      entry.type = 'pics';
      entry.pics = DynamicService.parsePics((major['opus'] as Record<string, Object>) ?? {});
    } else if (entry.text === '') {
      return null;
    } else {
      entry.type = 'text';
    }
    const orig: Object | undefined = raw['orig'];
    if (orig !== undefined && orig !== null) {
      const origRecord: Record<string, Object> = orig as Record<string, Object>;
      const origModules: Record<string, Object> = (origRecord['modules'] as Record<string, Object>) ?? {};
      const origAuthor: Record<string, Object> =
        (origModules['module_author'] as Record<string, Object>) ?? {};
      entry.repostName = String(origAuthor['name'] ?? '');
      if (entry.repostName !== '') {
        const origDynamic: Record<string, Object> =
          (origModules['module_dynamic'] as Record<string, Object>) ?? {};
        const origMajor: Record<string, Object> = (origDynamic['major'] as Record<string, Object>) ?? {};
        entry.repostText = String(((origDynamic['desc'] ?? {}) as Record<string, Object>)['text'] ?? '');
        if (String(origMajor['type'] ?? '') === 'MAJOR_TYPE_ARCHIVE') {
          const origPubTs: number = Number(origAuthor['pub_ts'] ?? 0);
          entry.repostVideo = DynamicService.parseVideoItem(
            (origMajor['archive'] as Record<string, Object>) ?? {},
            entry.repostText, entry.repostName,
            String(origAuthor['face'] ?? ''),
            origPubTs > 100000000000 ? Math.floor(origPubTs / 1000) : origPubTs);
        }
      }
    }
    if (entry.type === 'text' && entry.repostName === '') return null;
    return entry;
  }

  private static parsePics(major: Record<string, Object>): DynamicPic[] {
    const rawPics: Object[] = (major['items'] as Object[]) ?? (major['pics'] as Object[]) ?? [];
    const pics: DynamicPic[] = [];
    rawPics.forEach((raw: Object): void => {
      const pic: Record<string, Object> = raw as Record<string, Object>;
      const url: string = String(pic['src'] ?? pic['url'] ?? pic['pic_src'] ?? '');
      if (url === '') return;
      pics.push({ url: url, width: Number(pic['width'] ?? 0), height: Number(pic['height'] ?? 0) });
    });
    return pics;
  }

  private static parseVideoItem(archive: Record<string, Object>, fallbackText: string,
    authorName: string, authorFace: string, publishTime: number): VideoItem | null {
    const title: string = String(archive['title'] ?? '');
    const bvid: string = String(archive['bvid'] ?? '');
    const aid: number = Number(archive['aid'] ?? 0);
    if (title === '' || (bvid === '' && aid <= 0)) return null;
    const stat: Record<string, Object> = (archive['stat'] as Record<string, Object>) ?? {};
    return {
      id: aid > 0 ? aid : 1, aid: aid, bvid: bvid, cid: Number(archive['cid'] ?? 0), title: title,
      author: authorName, authorFace: authorFace,
      cover: DynamicService.compactCover(String(archive['cover'] ?? '')),
      viewCount: Number(stat['view'] ?? 0), danmuCount: Number(stat['danmaku'] ?? 0),
      likeCount: Number(stat['like'] ?? 0), commentCount: Number(stat['reply'] ?? 0),
      shareCount: 0,
      followed: false, duration: Number(archive['duration'] ?? 0), playUrl: '', placeholder: false,
      publishTime: publishTime,
      description: fallbackText, tags: [], detailLoaded: false
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
