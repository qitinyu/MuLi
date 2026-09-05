import { BiliHttpClient } from './BiliHttpClient';

export class AnimeSeason {
  seasonId: number = 0;
  title: string = '';
  cover: string = '';
  badge: string = '';
  ratingText: string = '';
  indexShow: string = '';
  viewCount: number = 0;
  followCount: number = 0;
  danmakuCount: number = 0;
}

export class AnimeEpisode {
  epId: number = 0;
  cid: number = 0;
  title: string = '';
  longTitle: string = '';
  badge: string = '';
  durationMs: number = 0;
}

export class AnimeSeasonDetail {
  title: string = '';
  cover: string = '';
  badge: string = '';
  evaluate: string = '';
  styles: string[] = [];
  score: string = '';
  scoreCount: number = 0;
  episodes: AnimeEpisode[] = [];
}

export class AnimeService {
  static async loadRank(): Promise<AnimeSeason[]> {
    const query: Record<string, string> = {};
    query['season_type'] = '1';
    query['day'] = '3';
    const result: Record<string, Object> = await BiliHttpClient.getJson('/pgc/web/rank/list', query);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '番剧榜单获取失败'));
    }
    const rankResult: Record<string, Object> = (result['result'] ?? {}) as Record<string, Object>;
    const rawList: Object[] = (rankResult['list'] as Object[]) ?? [];
    return rawList.map((raw: Object): AnimeSeason => AnimeService.parseSeason(raw as Record<string, Object>))
      .filter((season: AnimeSeason): boolean => season.seasonId > 0 && season.title !== '');
  }

  static async loadSeasonDetail(seasonId: number): Promise<AnimeSeasonDetail> {
    const query: Record<string, string> = {};
    query['season_id'] = String(seasonId);
    const result: Record<string, Object> = await BiliHttpClient.getJson('/pgc/view/web/season', query);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '番剧详情获取失败'));
    }
    const data: Record<string, Object> = (result['result'] ?? result['data'] ?? {}) as Record<string, Object>;
    const detail: AnimeSeasonDetail = new AnimeSeasonDetail();
    detail.title = String(data['title'] ?? '');
    detail.cover = String(data['cover'] ?? '');
    detail.badge = String(data['badge'] ?? '');
    detail.evaluate = String(data['evaluate'] ?? '');
    const rating: Record<string, Object> = (data['rating'] ?? {}) as Record<string, Object>;
    const score: number = Number(rating['score'] ?? 0);
    detail.score = score > 0 ? score.toFixed(1) : '';
    detail.scoreCount = Number(rating['count'] ?? 0);
    const rawStyles: Object[] = (data['styles'] as Object[]) ?? [];
    rawStyles.forEach((raw: Object): void => {
      const style: string = typeof raw === 'string'
        ? String(raw)
        : String((raw as Record<string, Object>)['name'] ?? '');
      if (style !== '' && !detail.styles.includes(style)) detail.styles.push(style);
    });
    const rawEpisodes: Object[] = (data['episodes'] as Object[]) ?? [];
    detail.episodes = rawEpisodes.map((raw: Object): AnimeEpisode =>
      AnimeService.parseEpisode(raw as Record<string, Object>))
      .filter((episode: AnimeEpisode): boolean => episode.epId > 0 && episode.cid > 0);
    return detail;
  }

  static async resolveEpisodeUrl(epId: number, cid: number): Promise<string> {
    const query: Record<string, string> = {};
    query['ep_id'] = String(epId);
    query['cid'] = String(cid);
    query['qn'] = '64';
    query['fnval'] = '0';
    query['fnver'] = '0';
    query['platform'] = 'html5';
    query['high_quality'] = '1';
    query['otype'] = 'json';
    const result: Record<string, Object> = await BiliHttpClient.getJson('/pgc/player/web/playurl', query);
    const code: number = Number(result['code'] ?? -1);
    if (code !== 0) {
      throw new Error(String(result['message'] ?? '该集暂不支持播放（可能需要大会员）'));
    }
    const data: Record<string, Object> = (result['result'] ?? result['data'] ?? {}) as Record<string, Object>;
    const durl: Object[] = (data['durl'] as Object[]) ?? [];
    for (const raw of durl) {
      const entry: Record<string, Object> = raw as Record<string, Object>;
      const url: string = String(entry['url'] ?? '');
      if (url !== '') return url;
    }
    throw new Error('没有可用的播放地址');
  }

  private static parseSeason(raw: Record<string, Object>): AnimeSeason {
    const season: AnimeSeason = new AnimeSeason();
    season.seasonId = Number(raw['season_id'] ?? 0);
    season.title = AnimeService.stripHtml(String(raw['title'] ?? ''));
    season.cover = String(raw['cover'] ?? '');
    season.badge = String(raw['badge'] ?? '');
    season.ratingText = String(raw['rating'] ?? '');
    const stat: Record<string, Object> = (raw['stat'] ?? {}) as Record<string, Object>;
    season.viewCount = Number(stat['view'] ?? 0);
    season.followCount = Number(stat['follow'] ?? 0);
    season.danmakuCount = Number(stat['danmaku'] ?? 0);
    const newEp: Record<string, Object> = (raw['new_ep'] ?? {}) as Record<string, Object>;
    season.indexShow = String(newEp['index_show'] ?? '');
    return season;
  }

  private static parseEpisode(raw: Record<string, Object>): AnimeEpisode {
    const episode: AnimeEpisode = new AnimeEpisode();
    episode.epId = Number(raw['id'] ?? 0);
    episode.cid = Number(raw['cid'] ?? 0);
    episode.title = String(raw['title'] ?? '');
    episode.longTitle = String(raw['long_title'] ?? '');
    episode.badge = String(raw['badge'] ?? '');
    episode.durationMs = Number(raw['duration'] ?? 0);
    return episode;
  }

  private static stripHtml(value: string): string {
    return value.replace(/<[^>]*>/g, '').trim();
  }
}
