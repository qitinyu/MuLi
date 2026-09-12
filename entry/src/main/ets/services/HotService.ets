import { VideoItem } from '../models/VideoItem';
import { BiliHttpClient } from './BiliHttpClient';

export class HotService {
  static async loadPopular(page: number = 1): Promise<VideoItem[]> {
    const query: Record<string, string> = {};
    query['ps'] = '20';
    query['pn'] = String(page);
    const result: Record<string, Object> = await BiliHttpClient.getJson('/x/web-interface/popular', query);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '热门榜单获取失败'));
    }
    const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
    const rawList: Object[] = (data['list'] as Object[]) ?? [];
    return rawList.map((raw: Object): VideoItem => HotService.parseItem(raw as Record<string, Object>))
      .filter((item: VideoItem): boolean => item.aid > 0 && item.title !== '');
  }

  private static parseItem(raw: Record<string, Object>): VideoItem {
    const owner: Record<string, Object> = (raw['owner'] ?? {}) as Record<string, Object>;
    const stat: Record<string, Object> = (raw['stat'] ?? {}) as Record<string, Object>;
    const reason: Record<string, Object> = (raw['rcmd_reason'] ?? {}) as Record<string, Object>;
    const dimension: Record<string, Object> = (raw['dimension'] ?? {}) as Record<string, Object>;
    const aid: number = Number(raw['aid'] ?? 0);
    const tags: string[] = [];
    const reasonText: string = String(reason['content'] ?? '');
    if (reasonText !== '') tags.push(reasonText);
    return {
      id: aid,
      aid: aid,
      bvid: String(raw['bvid'] ?? ''),
      cid: Number(raw['cid'] ?? 0),
      title: String(raw['title'] ?? ''),
      author: String(owner['name'] ?? ''),
      authorMid: Number(owner['mid'] ?? 0),
      authorFace: String(owner['face'] ?? ''),
      cover: HotService.compactCover(String(raw['pic'] ?? '')),
      viewCount: Number(stat['view'] ?? 0),
      danmuCount: Number(stat['danmaku'] ?? 0),
      likeCount: Number(stat['like'] ?? 0),
      commentCount: Number(stat['reply'] ?? 0),
      shareCount: Number(stat['share'] ?? 0),
      followed: false,
      duration: Number(raw['duration'] ?? 0),
      playUrl: '',
      placeholder: false,
      publishTime: Number(raw['pubdate'] ?? 0),
      description: String(raw['desc'] ?? ''),
      tags: tags,
      detailLoaded: false,
      videoWidth: Number(dimension['width'] ?? 0),
      videoHeight: Number(dimension['height'] ?? 0)
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
