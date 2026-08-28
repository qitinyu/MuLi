import { VideoItem } from '../models/VideoItem';
import { BiliHttpClient } from './BiliHttpClient';

class SearchQuery {
  search_type: string = 'video';
  keyword: string = '';
  page: string = '1';
  page_size: string = '20';
  order: string = 'totalrank';

  toQueryString(): string {
    return `search_type=${encodeURIComponent(this.search_type)}` +
      `&keyword=${encodeURIComponent(this.keyword)}` +
      `&page=${encodeURIComponent(this.page)}` +
      `&page_size=${encodeURIComponent(this.page_size)}` +
      `&order=${encodeURIComponent(this.order)}`;
  }
}

export class SearchService {
  static async searchVideo(keyword: string, page: number = 1): Promise<VideoItem[]> {
    const query: SearchQuery = new SearchQuery();
    query.keyword = keyword;
    query.page = String(page);
    const response: Record<string, Object> = await BiliHttpClient.getJsonQuery(
      '/x/web-interface/search/type', query.toQueryString());
    if (Number(response['code'] ?? -1) !== 0) {
      throw new Error(String(response['message'] ?? '搜索接口返回错误'));
    }
    const data: Record<string, Object> = (response['data'] as Record<string, Object>) ?? {};
    const rawResults: Object[] = (data['result'] as Object[]) ?? [];
    return rawResults.map((raw: Object): VideoItem => SearchService.parseResult(raw as Record<string, Object>))
      .filter((item: VideoItem): boolean => item.id > 0 && item.title !== '');
  }

  private static parseResult(raw: Record<string, Object>): VideoItem {
    const aid: number = Number(raw['aid'] ?? 0);
    const bvid: string = String(raw['bvid'] ?? '');
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
      publishTime: 0,
      description: '',
      tags: [],
      detailLoaded: false
    };
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
}
