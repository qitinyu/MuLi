import { VideoItem } from '../models/VideoItem';
import { RecommendationService, RecommendationBatch } from '../services/RecommendationService';
import { VideoDetailService } from '../services/VideoDetailService';
import { FilterWords } from '../utils/FilterWords';
import { PlaybackMemory } from '../utils/PlaybackMemory';
import { VideoPreloader } from '../services/VideoPreloader';
import common from '@ohos.app.ability.common';

export interface FeedInitDeps {
  showToast: (msg: string) => void;
  keepRefreshContent: boolean;
}

/**
 * 推荐流管理 ViewModel
 * 管理首页推荐列表的加载、刷新、加载更多，以及相关视频列表加载
 */
export class FeedViewModel {
  videos: VideoItem[] = [];
  loading: boolean = false;
  loadError: string = '';
  loadingMore: boolean = false;
  relatedVideos: VideoItem[] = [];
  relatedLoading: boolean = false;

  private page: number = 0;
  private recommendationIndex: string = '0';
  private hasMoreRecommendations: boolean = true;
  private relatedRequest: number = 0;
  private refreshRunning: boolean = false;
  private keepRefreshContent: boolean = false;
  private showToast: (msg: string) => void = (): void => {};

  init(deps: FeedInitDeps): void {
    this.showToast = deps.showToast;
    this.keepRefreshContent = deps.keepRefreshContent;
  }

  setKeepRefreshContent(value: boolean): void {
    this.keepRefreshContent = value;
  }

  private static placeholderVideos(): VideoItem[] {
    const result: VideoItem[] = [];
    for (let index: number = 0; index < 10; index++) {
      result.push({
        id: index + 1, aid: 0, bvid: '', cid: 0, title: '', author: '', cover: '',
        viewCount: 0, danmuCount: 0, likeCount: 0, commentCount: 0,
        followed: false, duration: 0, playUrl: '', placeholder: true, publishTime: 0, description: '', tags: [], detailLoaded: false
      });
    }
    return result;
  }

  static createPlaceholder(): VideoItem[] {
    return FeedViewModel.placeholderVideos();
  }

  async loadRecommendations(cookie: string): Promise<void> {
    this.loading = true;
    this.loadError = '';
    try {
      const batch: RecommendationBatch = await RecommendationService.loadBatch('0');
      if (batch.items.length > 0) {
        this.page = 0;
        this.recommendationIndex = batch.nextIndex;
        this.videos = batch.items.filter((item: VideoItem): boolean =>
          !FilterWords.isVideoFiltered(item.title));
        this.hasMoreRecommendations = true;
        // 触发预加载
        VideoPreloader.preloadBatch(this.videos, 0, cookie);
      }
    } catch (error) {
      this.loadError = '推荐加载失败，请检查网络';
      console.error(`Pilihos recommendation failed: ${String(error)}`);
    } finally {
      this.loading = false;
    }
  }

  async refreshRecommendations(cookie: string): Promise<void> {
    if (this.loadingMore) return;
    this.loadError = '';
    try {
      const batch: RecommendationBatch = await RecommendationService.loadBatch('0', true);
      const fresh: VideoItem[] = batch.items;
      if (fresh.length > 0) {
        this.recommendationIndex = batch.nextIndex;
        const existing: Set<string> = new Set<string>(this.videos.map((item: VideoItem): string =>
          item.bvid !== '' ? item.bvid : `${item.aid}`));
        const additions: VideoItem[] = fresh.filter((item: VideoItem): boolean => {
          const key: string = item.bvid !== '' ? item.bvid : `${item.aid}`;
          return !existing.has(key);
        });
        this.videos = this.keepRefreshContent ? additions.concat(this.videos) : fresh;
        this.page = 0;
        this.hasMoreRecommendations = true;
      }
    } catch (error) {
      this.loadError = '推荐刷新失败，请检查网络';
      console.error(`Pilihos recommendation refresh failed: ${String(error)}`);
    }
  }

  async loadMoreRecommendations(cookie: string): Promise<void> {
    if (this.loadingMore || this.loading || !this.hasMoreRecommendations) return;
    this.loadingMore = true;
    try {
      const batch: RecommendationBatch = await RecommendationService.loadBatch(this.recommendationIndex);
      const next: VideoItem[] = batch.items.filter((item: VideoItem): boolean =>
        !FilterWords.isVideoFiltered(item.title));
      if (next.length > 0) {
        this.page += 1;
        const cursorAdvanced: boolean = batch.nextIndex !== this.recommendationIndex;
        if (cursorAdvanced) {
          this.recommendationIndex = batch.nextIndex;
        } else {
          this.hasMoreRecommendations = false;
        }
        const existing: Set<string> = new Set<string>(this.videos.map((item: VideoItem): string =>
          item.bvid !== '' ? item.bvid : `${item.aid}`));
        const additions: VideoItem[] = next.filter((item: VideoItem): boolean => {
          const key: string = item.bvid !== '' ? item.bvid : `${item.aid}`;
          return !existing.has(key);
        });
        this.videos = this.videos.concat(additions);
        this.hasMoreRecommendations = cursorAdvanced;
        // 触发预加载新加载的视频
        VideoPreloader.preloadBatch(this.videos, this.videos.length - additions.length, cookie);
      } else {
        this.hasMoreRecommendations = false;
      }
    } catch (error) {
      console.error(`Pilihos load more recommendation failed: ${String(error)}`);
    } finally {
      this.loadingMore = false;
    }
  }

  async refreshCurrentPage(contentTab: number, cookie: string): Promise<void> {
    if (this.refreshRunning) return;
    this.refreshRunning = true;
    try {
      if (contentTab === 1) {
        await this.refreshRecommendations(cookie);
      }
    } finally {
      this.refreshRunning = false;
    }
  }

  async loadRelatedVideos(currentVideo: VideoItem): Promise<void> {
    if (currentVideo.placeholder || currentVideo.aid <= 0) {
      this.relatedVideos = [];
      this.relatedLoading = false;
      return;
    }
    const requestId: number = this.relatedRequest + 1;
    this.relatedRequest = requestId;
    this.relatedLoading = true;
    try {
      const list: VideoItem[] = await VideoDetailService.loadRelated(currentVideo);
      const seen: Set<string> = new Set<string>([currentVideo.bvid !== '' ? currentVideo.bvid : `${currentVideo.aid}`]);
      const fresh: VideoItem[] = list.filter((candidate: VideoItem): boolean => {
        const key: string = candidate.bvid !== '' ? candidate.bvid : `${candidate.aid}`;
        if (seen.has(key)) return false;
        seen.add(key);
        return !FilterWords.isVideoFiltered(candidate.title)
          && PlaybackMemory.progressOf(candidate.aid) <= 0;
      });
      if (requestId === this.relatedRequest) this.relatedVideos = fresh;
    } catch (error) {
      console.warn(`Pilihos related videos failed: ${String(error)}`);
      if (requestId === this.relatedRequest) this.relatedVideos = [];
    } finally {
      if (requestId === this.relatedRequest) this.relatedLoading = false;
    }
  }

  appendVideo(video: VideoItem): void {
    this.videos = this.videos.concat([video]);
  }

  updateVideo(updated: VideoItem): void {
    this.videos = this.videos.map((candidate: VideoItem): VideoItem =>
      candidate.id === updated.id ? updated : candidate);
  }

  replaceAll(newVideos: VideoItem[]): void {
    this.videos = newVideos;
  }
}
