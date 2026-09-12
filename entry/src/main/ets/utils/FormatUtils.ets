import { VideoItem } from '../models/VideoItem';

export class FormatUtils {
  static formatCount(value: number): string {
    if (value >= 100000000) return `${(value / 100000000).toFixed(2).replace(/\.00$/, '')}亿`;
    if (value >= 10000) return `${(value / 10000).toFixed(1).replace(/\.0$/, '')}万`;
    return `${value}`;
  }

  static formatPublishTime(timestamp: number): string {
    if (timestamp <= 0) return '发布时间未知';
    const seconds: number = Math.max(0, Math.floor(Date.now() / 1000) - timestamp);
    if (seconds < 3600) return String(Math.max(1, Math.floor(seconds / 60))) + '分钟前';
    if (seconds < 86400) return String(Math.floor(seconds / 3600)) + '小时前';
    if (seconds < 259200) return `${Math.floor(seconds / 86400)}天前`;
    const date: Date = new Date(timestamp * 1000);
    return `${String(date.getFullYear()).substring(2)}/${date.getMonth() + 1}/${date.getDate()}`;
  }

  static formatPublishDate(timestamp: number): string {
    if (timestamp <= 0) return '发布时间未知';
    const date: Date = new Date(timestamp * 1000);
    const month: string = String(date.getMonth() + 1).padStart(2, '0');
    const day: string = String(date.getDate()).padStart(2, '0');
    const hour: string = String(date.getHours()).padStart(2, '0');
    const minute: string = String(date.getMinutes()).padStart(2, '0');
    return String(date.getFullYear()) + '-' + month + '-' + day + ' ' + hour + ':' + minute;
  }

  static formatPlaybackTime(valueMs: number): string {
    const totalSeconds: number = Math.max(0, Math.floor(valueMs / 1000));
    const hours: number = Math.floor(totalSeconds / 3600);
    const minutes: number = Math.floor((totalSeconds % 3600) / 60);
    const seconds: number = totalSeconds % 60;
    const minuteText: string = String(minutes).padStart(2, '0');
    const secondText: string = String(seconds).padStart(2, '0');
    if (hours > 0) return String(hours).padStart(2, '0') + ':' + minuteText + ':' + secondText;
    return minuteText + ':' + secondText;
  }

  static levelColor(level: number): string {
    if (level >= 6) return '#F39800';
    if (level >= 4) return '#23ADE5';
    return '#BFBFBF';
  }

  static levelBadge(level: number): Resource {
    const normalized: number = Math.max(0, Math.min(6, Math.floor(level)));
    if (normalized === 1) return $r('app.media.Lv1');
    if (normalized === 2) return $r('app.media.Lv2');
    if (normalized === 3) return $r('app.media.Lv3');
    if (normalized === 4) return $r('app.media.Lv4');
    if (normalized === 5) return $r('app.media.Lv5');
    if (normalized >= 6) return $r('app.media.Lv6');
    return $r('app.media.Lv0');
  }

  static playbackErrorToast(errorMessage: string): string {
    const text: string = errorMessage.trim();
    const matched: RegExpMatchArray | null = text.match(/(?:code|错误码)\D*(-?\d+)/i);
    const leadingCode: RegExpMatchArray | null = text.match(/^(-?\d+)/);
    const code: string = matched !== null ? matched[1] :
      (leadingCode !== null ? leadingCode[1] : 'PLAYBACK_ERROR');
    const detail: string = text === '' ? '未知播放器错误' : text;
    return `视频播放/加载失败 [错误码: ${code}] ${detail}`;
  }

  static playbackUrlDescription(url: string): string {
    const queryIndex: number = url.indexOf('?');
    const withoutQuery: string = queryIndex >= 0 ? url.substring(0, queryIndex) : url;
    return withoutQuery.length > 180 ? withoutQuery.substring(0, 180) : withoutQuery;
  }

  static isPortraitVideo(item: VideoItem, badgeEnabled: boolean): boolean {
    if (!badgeEnabled) return false;
    const width: number = Number(item?.videoWidth ?? 0);
    const height: number = Number(item?.videoHeight ?? 0);
    return width > 0 && height > 0 && width < height;
  }

  static currentAspect(item: VideoItem): number {
    const width: number = Number(item?.videoWidth ?? 0);
    const height: number = Number(item?.videoHeight ?? 0);
    if (width > 0 && height > 0) {
      // 限制在 9:16 ~ 16:9 之间，防止极端比例撑破布局
      return Math.min(16 / 9, Math.max(9 / 16, width / height));
    }
    return 16 / 9;
  }
}
