import { VideoItem } from '../models/VideoItem';
import { BiliHttpClient } from './BiliHttpClient';
import { WbiService } from './WbiService';

export class SearchUser {
  mid: number = 0;
  uname: string = '';
  face: string = '';
  sign: string = '';
  fans: number = 0;
  videoCount: number = 0;
  level: number = 0;
  liveRoomId: number = 0;
}

export class SearchSeason {
  seasonId: number = 0;
  title: string = '';
  cover: string = '';
  indexShow: string = '';
  typeName: string = '';
}

export interface SearchResultBatch {
  videos: VideoItem[];
  users: SearchUser[];
  seasons: SearchSeason[];
}

export class SearchService {
  static async search(type: string, keyword: string, cookie: string = ''): Promise<SearchResultBatch> {
    const signed: string = await WbiService.sign([
      `search_type=${type}`,
      `keyword=${keyword}`,
      'page=1',
      'page_size=20'
    ]);
    const result: Record<string, Object> =
      await BiliHttpClient.getJsonQuery('/x/web-interface/wbi/search/type', signed, cookie);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '搜索接口返回错误'));
    }
    const data: Record<string, Object> = (result['data'] as Record<string, Object>) ?? {};
    const rawResults: Object[] = (data['result'] as Object[]) ?? [];
    const batch: SearchResultBatch = { videos: [], users: [], seasons: [] };
    rawResults.forEach((raw: Object): void => {
      const record: Record<string, Object> = raw as Record<string, Object>;
      const itemType: string = String(record['type'] ?? '');
      if (itemType === 'video') {
        const video: VideoItem | null = SearchService.parseVideo(record);
        if (video !== null) batch.videos.push(video);
      } else if (itemType === 'bili_user') {
        batch.users.push(SearchService.parseUser(record));
      } else if (itemType === 'media_bangumi' || itemType === 'media_ft') {
        const season: SearchSeason = SearchService.parseSeason(record, itemType);
        if (season.seasonId > 0) batch.seasons.push(season);
      }
    });
    return batch;
  }

  private static parseVideo(raw: Record<string, Object>): VideoItem | null {
    const aid: number = Number(raw['aid'] ?? 0);
    const bvid: string = String(raw['bvid'] ?? '');
    if (aid <= 0 && bvid === '') return null;
    return {
      id: aid > 0 ? aid : Number(raw['id'] ?? 0),
      aid: aid,
      bvid: bvid,
      cid: 0,
      title: SearchService.cleanHtml(String(raw['title'] ?? '')),
      author: String(raw['author'] ?? ''),
      authorFace: '',
      cover: SearchService.normalizeCover(String(raw['pic'] ?? '')),
      viewCount: Number(raw['play'] ?? 0),
      danmuCount: Number(raw['video_review'] ?? 0),
      likeCount: 0,
      commentCount: 0,
      followed: false,
      duration: SearchService.parseDuration(String(raw['duration'] ?? '')),
      playUrl: '',
      placeholder: false,
      publishTime: SearchService.parseTimestamp(raw['pubdate'] ?? raw['pubtime'] ?? 0),
      description: SearchService.cleanHtml(String(raw['description'] ?? '')),
      tags: [],
      detailLoaded: false
    };
  }

  private static parseUser(raw: Record<string, Object>): SearchUser {
    const user: SearchUser = new SearchUser();
    user.mid = Number(raw['mid'] ?? 0);
    user.uname = SearchService.cleanHtml(String(raw['uname'] ?? ''));
    user.face = SearchService.normalizeCover(String(raw['upic'] ?? ''));
    user.sign = SearchService.cleanHtml(String(raw['usign'] ?? ''));
    user.fans = Number(raw['fans'] ?? 0);
    user.videoCount = Number(raw['videos'] ?? 0);
    user.level = Number(raw['level'] ?? 0);
    user.liveRoomId = Number(raw['room_id'] ?? 0);
    return user;
  }

  private static parseSeason(raw: Record<string, Object>, itemType: string): SearchSeason {
    const season: SearchSeason = new SearchSeason();
    season.seasonId = Number(raw['season_id'] ?? 0);
    season.title = SearchService.cleanHtml(String(raw['title'] ?? ''));
    season.cover = SearchService.normalizeCover(String(raw['cover'] ?? ''));
    season.indexShow = String(raw['index_show'] ?? '');
    season.typeName = itemType === 'media_bangumi' ? '番剧' : '影视';
    return season;
  }

  private static cleanHtml(value: string): string {
    return value.replace(/<[^>]*>/g, '').replace(/&quot;/g, '"').replace(/&amp;/g, '&');
  }

  private static normalizeCover(value: string): string {
    if (value === '') return '';
    return value.startsWith('//') ? 'https:' + value : value;
  }

  private static parseDuration(value: string): number {
    const parts: string[] = value.split(':');
    if (parts.length === 2) return Number(parts[0]) * 60 + Number(parts[1]);
    if (parts.length === 3) return Number(parts[0]) * 3600 + Number(parts[1]) * 60 + Number(parts[2]);
    return 0;
  }

  private static parseTimestamp(value: Object): number {
    const text: string = String(value ?? '').trim();
    if (text === '') return 0;
    const parsed: number = Number(text);
    if (!Number.isNaN(parsed)) {
      if (parsed <= 0) return 0;
      return parsed > 100000000000 ? Math.floor(parsed / 1000) : Math.floor(parsed);
    }
    const date: Date = new Date(text);
    const dateMillis: number = date.getTime();
    if (Number.isNaN(dateMillis) || dateMillis <= 0) return 0;
    return Math.floor(dateMillis / 1000);
  }
}
