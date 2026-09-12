import { VideoItem } from '../models/VideoItem';
import { VideoDetailService } from './VideoDetailService';
import { PlaybackService, PlaybackResolveResult } from './PlaybackService';

/**
 * 视频预加载服务
 * 预先获取视频详情和播放地址，减少打开视频时的加载等待
 */
export class VideoPreloader {
  private static preloadedDetails: Map<number, VideoItem> = new Map();
  private static preloadedUrls: Map<number, string[]> = new Map();
  private static preloadingSet: Set<number> = new Set();
  private static readonly MAX_PRELOAD_COUNT: number = 5;
  private static readonly MAX_CACHE_COUNT: number = 20;

  /**
   * 预加载视频详情
   * @param item 视频条目
   * @param cookie 用户cookie
   */
  static async preloadDetail(item: VideoItem, cookie: string = ''): Promise<void> {
    if (item.aid <= 0 || item.detailLoaded || VideoPreloader.preloadingSet.has(item.aid)) {
      return;
    }
    if (VideoPreloader.preloadedDetails.has(item.aid)) {
      return;
    }
    // 限制预加载数量
    if (VideoPreloader.preloadingSet.size >= VideoPreloader.MAX_PRELOAD_COUNT) {
      return;
    }
    VideoPreloader.preloadingSet.add(item.aid);
    try {
      const detailed: VideoItem = await VideoDetailService.load(item);
      VideoPreloader.preloadedDetails.set(item.aid, detailed);
      // 清理旧缓存
      if (VideoPreloader.preloadedDetails.size > VideoPreloader.MAX_CACHE_COUNT) {
        const firstKey: number = VideoPreloader.preloadedDetails.keys().next().value ?? 0;
        if (firstKey > 0) {
          VideoPreloader.preloadedDetails.delete(firstKey);
          VideoPreloader.preloadedUrls.delete(firstKey);
        }
      }
    } catch (error) {
      console.warn(`Pilihos preload detail failed: ${String(error)}`);
    } finally {
      VideoPreloader.preloadingSet.delete(item.aid);
    }
  }

  /**
   * 预加载视频播放地址
   * @param item 视频条目（需要有 cid）
   * @param cookie 用户cookie
   * @param preferredQn 首选清晰度
   */
  static async preloadUrl(item: VideoItem, cookie: string = '',
    preferredQn: number = 0): Promise<void> {
    if (item.aid <= 0 || item.cid <= 0) {
      return;
    }
    if (VideoPreloader.preloadedUrls.has(item.aid)) {
      return;
    }
    try {
      const result: PlaybackResolveResult =
        await PlaybackService.resolveWithQuality(item, cookie, preferredQn);
      if (result.urls.length > 0) {
        VideoPreloader.preloadedUrls.set(item.aid, result.urls);
      }
    } catch (error) {
      console.warn(`Pilihos preload url failed: ${String(error)}`);
    }
  }

  /**
   * 获取预加载的视频详情
   * @param aid 视频aid
   * @returns 预加载的VideoItem或null
   */
  static getPreloadedDetail(aid: number): VideoItem | null {
    return VideoPreloader.preloadedDetails.get(aid) ?? null;
  }

  /**
   * 获取预加载的播放地址
   * @param aid 视频aid
   * @returns 预加载的URL数组或null
   */
  static getPreloadedUrls(aid: number): string[] | null {
    return VideoPreloader.preloadedUrls.get(aid) ?? null;
  }

  /**
   * 清除指定视频的预加载数据
   * @param aid 视频aid
   */
  static clearPreload(aid: number): void {
    VideoPreloader.preloadedDetails.delete(aid);
    VideoPreloader.preloadedUrls.delete(aid);
  }

  /**
   * 清除所有预加载数据
   */
  static clearAll(): void {
    VideoPreloader.preloadedDetails.clear();
    VideoPreloader.preloadedUrls.clear();
    VideoPreloader.preloadingSet.clear();
  }

  /**
   * 预加载一批视频的详情（用于列表滚动时预加载）
   * @param items 视频列表
   * @param startIndex 起始索引
   * @param cookie 用户cookie
   */
  static preloadBatch(items: VideoItem[], startIndex: number, cookie: string = ''): void {
    const preloadCount: number = Math.min(3, items.length - startIndex);
    for (let i: number = 0; i < preloadCount; i++) {
      const index: number = startIndex + i;
      if (index < items.length) {
        const item: VideoItem = items[index];
        if (!item.placeholder && !item.detailLoaded && item.aid > 0) {
          VideoPreloader.preloadDetail(item, cookie).then((): void => {
            // 详情加载成功后，预加载播放地址
            const detailed: VideoItem | null = VideoPreloader.getPreloadedDetail(item.aid);
            if (detailed !== null && detailed.cid > 0) {
              VideoPreloader.preloadUrl(detailed, cookie);
            }
          });
        }
      }
    }
  }
}
