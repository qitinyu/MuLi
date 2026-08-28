import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BiliHttpClient } from './BiliHttpClient';
import { AdvancedFeatures } from '../utils/AdvancedFeatures';

/**
 * 视频播放器服务
 * 支持 API 24+ 设备，通过 AdvancedFeatures 开关控制增强功能
 */
export class VideoPlayerService {
  private player: media.AVPlayer | undefined;
  private currentState: media.AVPlayerState = 'idle';
  private lastError: string = '';
  private errorCallback: ((message: string) => void) | null = null;
  private timeUpdateCallback: ((currentMs: number, durationMs: number) => void) | null = null;
  private stateChangeCallback: ((state: media.AVPlayerState) => void) | null = null;
  private generation: number = 0;
  private preparing: boolean = false;

  get state(): media.AVPlayerState {
    return this.currentState;
  }

  get errorMessage(): string {
    return this.lastError;
  }

  onError(callback: (message: string) => void): void {
    this.errorCallback = callback;
  }

  onTimeUpdate(callback: (currentMs: number, durationMs: number) => void): void {
    this.timeUpdateCallback = callback;
  }

  onStateChange(callback: (state: media.AVPlayerState) => void): void {
    this.stateChangeCallback = callback;
  }

  private emitTimeUpdate(player: media.AVPlayer): void {
    if (this.timeUpdateCallback !== null) {
      this.timeUpdateCallback(Math.max(0, player.currentTime), Math.max(0, player.duration));
    }
  }

  /**
   * 准备播放
   * API 24/25 或开关关闭时使用基础播放方式
   */
  async prepare(url: string, surfaceId: string, referer: string, cookie: string = ''): Promise<void> {
    await this.release();
    const generation: number = this.generation;
    this.lastError = '';
    if (url === '' || surfaceId === '') {
      throw new Error('播放源或视频画布为空');
    }

    const player: media.AVPlayer = await media.createAVPlayer();
    this.player = player;
    this.preparing = true;
    console.info(`Pilihos AVPlayer prepare: surface=${surfaceId}, url=${this.describeUrl(url)}`);

    // 根据开关状态选择事件监听方式
    let usingMediaSource: boolean = false;
    if (AdvancedFeatures.isEnhancedPlayerEnabled()) {
      // API 26 增强模式：使用 reason 参数
      player.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason): void => {
        if (generation !== this.generation || this.player !== player) return;
        this.currentState = state;
        if (this.stateChangeCallback !== null) this.stateChangeCallback(state);
        console.info(`Pilihos AVPlayer state: ${state}, reason=${reason}`);
      });
    } else {
      // API 24/25 基础模式：不使用 reason 参数
      player.on('stateChange', (state: media.AVPlayerState): void => {
        if (generation !== this.generation || this.player !== player) return;
        this.currentState = state;
        if (this.stateChangeCallback !== null) this.stateChangeCallback(state);
        console.info(`Pilihos AVPlayer state: ${state}`);
      });
    }

    player.on('timeUpdate', (_currentMs: number): void => {
      if (generation !== this.generation || this.player !== player) return;
      this.emitTimeUpdate(player);
    });
    player.on('durationUpdate', (_durationMs: number): void => {
      if (generation !== this.generation || this.player !== player) return;
      this.emitTimeUpdate(player);
    });
    player.on('videoSizeChange', (width: number, height: number): void => {
      if (generation !== this.generation || this.player !== player) return;
      console.info(`Pilihos AVPlayer video size: ${width}x${height}`);
    });

    player.on('error', (error: BusinessError): void => {
      if (generation !== this.generation || this.player !== player) return;
      this.lastError = `${error.code} ${error.message}`;
      console.error(`Pilihos AVPlayer error: ${this.lastError}`);
      // prepare 期间不能触发页面重试/释放，否则 catch 中会对已释放实例 reset。
      if (!this.preparing && this.errorCallback !== null) {
        this.errorCallback(this.lastError);
      }
    });

    // 根据开关状态选择媒体源设置方式
    if (AdvancedFeatures.isEnhancedPlayerEnabled()) {
      // API 26 增强模式：使用 setMediaSource + 自定义 HTTP 头
      const headers: Record<string, string> = {
        'User-Agent': BiliHttpClient.browserUserAgent,
        'Referer': referer === '' ? 'https://www.bilibili.com/' : referer,
        'Origin': 'https://www.bilibili.com'
      };
      if (cookie !== '') {
        headers['Cookie'] = cookie;
      }
      const source: media.MediaSource = media.createMediaSourceWithUrl(url, headers);
      try {
        await player.setMediaSource(source);
        usingMediaSource = true;
        console.info('Pilihos AVPlayer media source accepted');
      } catch (error) {
        console.warn(`Pilihos MediaSource setup failed, using direct URL: ${String(error)}`);
        player.url = url;
      }
    } else {
      // API 24/25 fallback: direct URL is the only compatible path.
      console.info('Pilihos: Using basic player mode (API 24/25)');
      player.url = url;
    }

    player.surfaceId = surfaceId;
    player.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT;
    console.info(`Pilihos AVPlayer surface assigned: ${surfaceId}`);
    await this.waitForInitialized(player);
    try {
      await player.prepare();
      console.info(`Pilihos AVPlayer prepared: state=${this.currentState}, size=${player.width}x${player.height}, surface=${surfaceId}`);
    } catch (error) {
      this.preparing = false;
      // Some device builds reject a header-backed MediaSource for a signed
      // Bilibili URL. Reset the same player and retry with its direct URL.
      if (!usingMediaSource) throw new Error(String(error));
      console.warn(`Pilihos MediaSource prepare failed, retrying direct URL: ${String(error)}`);
      await player.reset();
      player.url = url;
      player.surfaceId = surfaceId;
      this.preparing = true;
      try {
        await player.prepare();
      } catch (retryError) {
        throw new Error(`原始错误: ${String(error)}; 直链重试错误: ${String(retryError)}`);
      } finally {
        this.preparing = false;
      }
    }
    this.preparing = false;
    this.emitTimeUpdate(player);
    console.info(`Pilihos AVPlayer output: size=${player.width}x${player.height}, state=${player.state}`);

    try {
      const tracks: Array<media.MediaDescription> = await player.getTrackDescription();
      const trackSummary: string[] = tracks.map((track: media.MediaDescription): string =>
        `type=${String(track['trackType'] ?? track['mediaType'] ?? 'unknown')}, codec=${String(track['codecMimeType'] ?? '')}`);
      console.info(`Pilihos AVPlayer tracks: ${tracks.length}, ${trackSummary.join(';')}`);
    } catch (error) {
      console.warn(`Pilihos AVPlayer track inspection failed: ${String(error)}`);
    }
  }

  async play(): Promise<void> {
    if (this.player === undefined) {
      throw new Error('播放器尚未准备完成');
    }
    this.player.setVolume(1.0);
    await this.player.play();
    console.info('Pilihos AVPlayer play requested');
  }

  async pause(): Promise<void> {
    if (this.player !== undefined && this.currentState === 'playing') {
      await this.player.pause();
    }
  }

  seek(timeMs: number): void {
    if (this.player === undefined) return;
    try {
      this.player.seek(Math.max(0, timeMs));
    } catch (error) {
      console.warn(`Pilihos seek ignored before player is ready: ${String(error)}`);
    }
  }

  setSpeed(speed: number): void {
    if (this.player === undefined) return;
    let playbackSpeed: media.PlaybackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    if (speed === 0.5) playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_0_50_X;
    else if (speed === 0.75) playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    else if (speed === 1.25) playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    else if (speed === 1.5) playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
    else if (speed === 2.0) playbackSpeed = media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
    try {
      this.player.setSpeed(playbackSpeed);
    } catch (error) {
      console.warn(`Pilihos speed change ignored before player is ready: ${String(error)}`);
    }
  }

  async release(): Promise<void> {
    this.generation += 1;
    this.preparing = false;
    const player: media.AVPlayer | undefined = this.player;
    this.player = undefined;
    this.currentState = 'idle';
    this.lastError = '';
    if (player !== undefined) {
      try {
        await player.release();
      } catch (error) {
        console.warn(`Pilihos AVPlayer release failed: ${String(error)}`);
      }
    }
  }

  private describeUrl(url: string): string {
    const queryIndex: number = url.indexOf('?');
    const withoutQuery: string = queryIndex >= 0 ? url.substring(0, queryIndex) : url;
    return withoutQuery.length > 180 ? withoutQuery.substring(0, 180) : withoutQuery;
  }

  private async waitForInitialized(player: media.AVPlayer): Promise<void> {
    // url/setMediaSource 的状态切换可能在下一次事件循环才完成。
    // prepare 只能从 initialized 或 stopped 状态调用。
    for (let attempt: number = 0; attempt < 10; attempt++) {
      const state: media.AVPlayerState = player.state;
      this.currentState = state;
      if (state === 'initialized' || state === 'stopped') return;
      if (state === 'released' || state === 'error') {
        throw new Error(`播放器状态错误: ${state}`);
      }
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 50);
      });
    }
    const finalState: media.AVPlayerState = player.state;
    this.currentState = finalState;
    if (finalState !== 'initialized' && finalState !== 'stopped') {
      throw new Error(`播放器未初始化，当前状态: ${finalState}`);
    }
  }
}
