import { VideoItem } from '../models/VideoItem';
import { BiliHttpClient } from './BiliHttpClient';
import { VideoDetailService } from './VideoDetailService';

class RecommendationQuery {
  build: string = '2001100';
  c_locale: string = 'zh_CN';
  channel: string = 'master';
  column: string = '4';
  device: string = 'pad';
  device_name: string = 'tablet';
  device_type: string = '0';
  disable_rcmd: string = '0';
  flush: string = '5';
  fnval: string = '0';
  fnver: string = '0';
  force_host: string = '2';
  guidance: string = '0';
  https_url_req: string = '1';
  idx: string = '0';
  mobi_app: string = 'android_hd';
  network: string = 'wifi';
  platform: string = 'android';
  player_net: string = '1';
  pull: string = 'true';
  qn: string = '16';
  recsys_mode: string = '0';
  s_locale: string = 'zh_CN';

  toQueryString(): string {
    return `build=${this.build}&c_locale=${this.c_locale}&channel=${this.channel}&column=${this.column}` +
      `&device=${this.device}&device_name=${this.device_name}&device_type=${this.device_type}` +
      `&disable_rcmd=${this.disable_rcmd}&flush=${this.flush}&fnval=${this.fnval}&fnver=${this.fnver}` +
      `&force_host=${this.force_host}&guidance=${this.guidance}&https_url_req=${this.https_url_req}` +
      `&idx=${this.idx}&mobi_app=${this.mobi_app}&network=${this.network}&platform=${this.platform}` +
      `&player_net=${this.player_net}&pull=${this.pull}&qn=${this.qn}&recsys_mode=${this.recsys_mode}` +
      `&s_locale=${this.s_locale}`;
  }
}

export class RecommendationService {
  static readonly PAGE_SIZE: number = 6;

  static async load(page: number = 0): Promise<VideoItem[]> {
    const query: RecommendationQuery = new RecommendationQuery();
    query.idx = `${page}`;
    query.pull = page === 0 ? 'true' : 'false';
    const result: Record<string, Object> = await BiliHttpClient.getAppJson('/x/v2/feed/index', query.toQueryString());
    const data: Record<string, Object> = result['data'] as Record<string, Object>;
    const items: Object[] = data['items'] as Object[];
    const parsed: VideoItem[] = items
      .map((raw: Object) => RecommendationService.parseItem(raw as Record<string, Object>))
      .filter((item: VideoItem) => item.id > 0 && item.cid > 0);
    const unique: VideoItem[] = [];
    const seen: Set<string> = new Set<string>();
    parsed.forEach((item: VideoItem): void => {
      const key: string = item.bvid !== '' ? item.bvid : `${item.aid}`;
      if (!seen.has(key)) {
        seen.add(key);
        unique.push(item);
      }
    });
    const limited: VideoItem[] = unique.slice(0, RecommendationService.PAGE_SIZE);
    const hydrated: VideoItem[] = [];
    for (const item of limited) {
      if (item.publishTime > 0) {
        hydrated.push(item);
        continue;
      }
      try {
        hydrated.push(await VideoDetailService.load(item));
      } catch (error) {
        console.error('Pilihos recommendation detail failed: ' + String(error));
        hydrated.push(item);
      }
    }
    return hydrated;
  }

  private static parseItem(raw: Record<string, Object>): VideoItem {
    const args: Record<string, Object> = (raw['args'] as Record<string, Object>) ?? {};
    const player: Record<string, Object> = (raw['player_args'] as Record<string, Object>) ?? {};
    const reason: string = String(raw['rcmd_reason'] ?? '');
    return {
      id: Number(player['aid'] ?? raw['param'] ?? 0),
      aid: Number(player['aid'] ?? raw['param'] ?? 0),
      bvid: String(raw['bvid'] ?? ''),
      cid: Number(player['cid'] ?? 0),
      title: String(raw['title'] ?? ''),
      author: String(args['up_name'] ?? ''),
      cover: RecommendationService.compactCover(String(raw['cover'] ?? '')),
      viewCount: RecommendationService.parseCount(String(raw['cover_left_text_1'] ?? '0')),
      danmuCount: RecommendationService.parseCount(String(raw['cover_left_text_2'] ?? '0')),
      likeCount: 0,
      commentCount: 0,
      followed: reason === '已关注' || reason === '新关注',
      duration: Number(player['duration'] ?? 0),
      playUrl: '',
      placeholder: false,
      publishTime: RecommendationService.parseTimestamp(
        raw['pubdate'] ?? args['pubdate'] ?? raw['pub_time'] ?? raw['publish_time'] ?? raw['ctime'] ?? 0),
      description: '',
      tags: [],
      detailLoaded: false
    };
  }

  private static parseTimestamp(value: Object): number {
    const parsed: number = Number(value);
    if (Number.isNaN(parsed) || parsed <= 0) return 0;
    return parsed > 100000000000 ? Math.floor(parsed / 1000) : Math.floor(parsed);
  }

  private static parseCount(value: string): number {
    const text: string = value.trim();
    if (text.endsWith('万')) {
      return Math.round(Number(text.substring(0, text.length - 1)) * 10000);
    }
    if (text.endsWith('亿')) {
      return Math.round(Number(text.substring(0, text.length - 1)) * 100000000);
    }
    const parsed: number = Number(text.replace(/,/g, ''));
    return Number.isNaN(parsed) ? 0 : parsed;
  }

  private static compactCover(value: string): string {
    const cover: string = value.trim();
    if (cover === '') return '';
    const atIndex: number = cover.indexOf('@');
    const queryIndex: number = cover.indexOf('?');
    let cutIndex: number = cover.length;
    if (atIndex >= 0 && atIndex < cutIndex) cutIndex = atIndex;
    if (queryIndex >= 0 && queryIndex < cutIndex) cutIndex = queryIndex;
    return `${cover.substring(0, cutIndex)}@320w_180h_1c.webp`;
  }
}
