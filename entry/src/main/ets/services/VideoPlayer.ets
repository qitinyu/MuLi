import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BiliHttp } from './BiliHttp';

const TAG = 'MuLiPlayer';

/**
 * AVPlayer 封装（只负责播放器本身，不碰 UI）。
 *
 * 关键约束：
 * - 必须在 surfaceId 就绪后再 prepare，否则首帧无处输出（黑屏）；
 * - bilibili 的 mp4 直链带时效签名，请求需要 Referer / UA，这里用 setMediaSource 带上自定义头，
 *   若机型拒绝带头的 MediaSource，则回落成 player.url 直连（多数 CDN 允许无 Referer 直取）。
 */
export class VideoPlayer {
  private player: media.AVPlayer | undefined = undefined;
  private surfaceId: string = '';
  private prepared: boolean = false;
  /** 正在 prepare 中（onLoad 与兜底轮询可能同时触发 attachSurface，需去重） */
  private preparing: boolean = false;
  private pendingUrl: string = '';
  private disposed: boolean = false;
  private generation: number = 0;

  /** 播放器状态变化（'playing' / 'paused' / 'completed' 等） */
  onStateChange: (state: string) => void = () => {
  };
  /** 进度（毫秒） */
  onProgress: (positionMs: number, durationMs: number) => void = () => {
  };
  onError: (message: string) => void = () => {
  };
  /** 播放自然结束（单集循环 / 随机连播 / 停止推荐 由页面据此决策） */
  onCompleted: () => void = () => {
  };
  /** 视频真实分辨率（px）：画面容器按这个比例摆，竖屏才不会上下留大片黑边 */
  onVideoSize: (width: number, height: number) => void = () => {
  };

  /** 当前倍速（0.5 / 0.75 / 1 / 1.25 / 1.5 / 2） */
  private speed: number = 1;

  get isPlaying(): boolean {
    return this.player !== undefined && this.player.state === 'playing';
  }

  get positionMs(): number {
    return this.player === undefined ? 0 : Math.max(0, this.player.currentTime);
  }

  get durationMs(): number {
    return this.player === undefined ? 0 : Math.max(0, this.player.duration);
  }

  /** 画布就绪后再调用；若已有待播地址则立刻开始准备 */
  async attachSurface(surfaceId: string): Promise<void> {
    if (surfaceId === undefined || surfaceId === null || surfaceId.length === 0) {
      return;
    }
    const changed: boolean = surfaceId !== this.surfaceId;
    this.surfaceId = surfaceId;
    if (this.pendingUrl.length === 0) {
      return;
    }
    // onLoad 与兜底轮询可能同时触发，正在准备时只需更新 surfaceId，别重复 prepare（否则会互相 release）
    if (this.preparing) {
      return;
    }
    if (!this.prepared) {
      await this.prepare(this.pendingUrl);
      return;
    }
    // 画布迟到 / 换了画布：prepared 之后已不能改 surfaceId，只能重建播放器把画面接上新画布
    if (changed && this.player !== undefined) {
      await this.prepare(this.pendingUrl);
    }
  }

  /** 设置播放源并准备（画布未就绪时先记下，等 attachSurface） */
  async setSource(url: string): Promise<void> {
    this.pendingUrl = url;
    if (this.surfaceId.length === 0 || this.preparing) {
      return;
    }
    await this.prepare(url);
  }

  private async prepare(url: string): Promise<void> {
    await this.release();
    this.preparing = true;
    this.disposed = false;
    this.generation++;
    const generation: number = this.generation;
    let player: media.AVPlayer;
    try {
      player = await media.createAVPlayer();
    } catch (err) {
      this.preparing = false;
      console.error(`${TAG} createAVPlayer failed: ${String(err)}`);
      this.onError('播放器初始化失败');
      return;
    }
    this.player = player;

    // 关键时序（踩过坑）：
    // - surfaceId 只能在 initialized 状态设置；
    // - videoScaleType 只能在 prepared/playing/paused/completed 状态设置，在 initialized 设会报
    //   5400102 "unsupport video scale operation"（该错误经由 error 回调冒泡，会误报成播放失败）。
    // 因此必须「先设源 → 等 initialized 挂画布 → prepare → prepared 时再设缩放模式」。
    player.on('stateChange', (state: media.AVPlayerState) => {
      if (generation !== this.generation || this.player !== player) {
        return;
      }
      console.info(`${TAG} state=${state}`);
      if (state === 'initialized') {
        if (this.surfaceId.length > 0) {
          try {
            player.surfaceId = this.surfaceId;
          } catch (err) {
            console.warn(`${TAG} attach surface at initialized failed: ${String(err)}`);
          }
        }
        player.prepare().then(() => {
          console.info(`${TAG} prepare resolved`);
        }).catch((err: BusinessError) => {
          console.error(`${TAG} prepare failed: ${err.code} ${err.message}`);
          this.onError('视频准备失败');
        });
      } else if (state === 'prepared') {
        this.prepared = true;
        this.preparing = false;
        this.applyScaleType(player);
        this.reportVideoSize(player);
        this.onProgress(player.currentTime, player.duration);
        this.onStateChange(state);
        // 新建的 player 默认是 1.0x，若页面此前设过倍速需重新应用（切清晰度/挂画布会重建 player）
        if (this.speed !== 1) {
          this.applySpeed(player, this.speed);
        }
        player.play().catch((err: BusinessError) => {
          console.warn(`${TAG} autoplay ignored: ${String(err)}`);
        });
      } else if (state === 'completed') {
        // 播完先同步状态，再把决策交给页面（循环 / 连播 / 停止推荐）
        this.onStateChange(state);
        this.onCompleted();
      } else if (state === 'playing' || state === 'paused' || state === 'stopped') {
        this.onStateChange(state);
      }
    });
    player.on('timeUpdate', (positionMs: number) => {
      if (generation !== this.generation || this.player !== player) {
        return;
      }
      this.onProgress(Math.max(0, positionMs), Math.max(0, player.duration));
    });
    player.on('durationUpdate', (durationMs: number) => {
      if (generation !== this.generation || this.player !== player) {
        return;
      }
      this.onProgress(Math.max(0, player.currentTime), Math.max(0, durationMs));
    });
    player.on('error', (error: BusinessError) => {
      if (generation !== this.generation || this.player !== player) {
        return;
      }
      console.error(`${TAG} error ${error.code} ${error.message}`);
      this.onError(`播放失败（${error.code}）`);
    });

    // 设源：先用带 Referer/UA 的 MediaSource，被拒则退回直链（多数 CDN 允许无 Referer 直取）
    let sourced: boolean = false;
    try {
      const headers: Record<string, string> = {
        'User-Agent': BiliHttp.UA,
        'Referer': 'https://www.bilibili.com/',
        'Origin': 'https://www.bilibili.com'
      };
      const source: media.MediaSource = media.createMediaSourceWithUrl(url, headers);
      await player.setMediaSource(source);
      sourced = true;
      console.info(`${TAG} media source accepted`);
    } catch (err) {
      console.warn(`${TAG} media source rejected, fallback to direct url: ${String(err)}`);
    }
    if (!sourced) {
      player.url = url;
    }
  }

  /**
   * 画面填充方式。
   *
   * 默认的 `VIDEO_SCALE_TYPE_FIT` 注释写的是「拉伸到与窗口一致」——不保比例，画面会被压扁/拉长；
   * `VIDEO_SCALE_TYPE_FIT_CROP` 则是裁掉长边。两者都会让画面「看起来少一块」。
   * 这里优先用 API 20 起的 SCALED_ASPECT：保持比例、短边留黑，画面不会被裁。
   */
  private applyScaleType(player: media.AVPlayer): void {
    try {
      player.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_SCALED_ASPECT;
    } catch (err) {
      try {
        player.videoScaleType = media.VideoScaleType.VIDEO_SCALE_TYPE_FIT;
      } catch (nested) {
        console.warn(`${TAG} scale type ignored: ${String(nested)}`);
      }
    }
  }

  /** 把视频真实宽高报给页面：竖屏连播要按它算画面容器高度（AVPlayer 只在 prepared 之后才有值） */
  private reportVideoSize(player: media.AVPlayer): void {
    try {
      const width: number = player.width;
      const height: number = player.height;
      if (width > 0 && height > 0) {
        this.onVideoSize(width, height);
      }
    } catch (err) {
      console.warn(`${TAG} read video size failed: ${String(err)}`);
    }
  }

  /** 映射倍速浮点数到 AVPlayer 的 PlaybackSpeed 枚举（部分倍速 SDK 无精确枚举则回落最接近值） */
  private static toPlaybackSpeed(speed: number): media.PlaybackSpeed {
    if (speed <= 0.5) {
      return media.PlaybackSpeed.SPEED_FORWARD_0_50_X;
    }
    if (speed <= 0.75) {
      return media.PlaybackSpeed.SPEED_FORWARD_0_75_X;
    }
    if (speed <= 1) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
    }
    if (speed <= 1.25) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
    }
    if (speed <= 1.5) {
      return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
    }
    return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
  }

  private applySpeed(player: media.AVPlayer, speed: number): void {
    try {
      player.setSpeed(VideoPlayer.toPlaybackSpeed(speed));
    } catch (err) {
      console.warn(`${TAG} setSpeed ignored: ${String(err)}`);
    }
  }

  /** 设置倍速：0.5 / 0.75 / 1 / 1.25 / 1.5 / 2，可在播放中调用 */
  setSpeed(speed: number): void {
    this.speed = speed;
    if (this.player !== undefined && this.prepared) {
      this.applySpeed(this.player, speed);
    }
  }

  getSpeed(): number {
    return this.speed;
  }

  async play(): Promise<void> {
    if (this.player === undefined) {
      return;
    }
    try {
      await this.player.play();
    } catch (err) {
      console.warn(`${TAG} play ignored: ${String(err)}`);
    }
  }

  async pause(): Promise<void> {
    if (this.player === undefined) {
      return;
    }
    try {
      await this.player.pause();
    } catch (err) {
      console.warn(`${TAG} pause ignored: ${String(err)}`);
    }
  }

  async toggle(): Promise<void> {
    if (this.isPlaying) {
      await this.pause();
      return;
    }
    // 播完后再点播放键：走「从头重播」的串行实现，否则部分机型直接 play 无效
    if (this.player !== undefined && this.player.state === 'completed') {
      await this.replay();
      return;
    }
    await this.play();
  }

  /**
   * 从头重播（播完再播 / 单集循环 / 点「重播视频」）。
   *
   * 踩坑记录：completed 是「终态」，此时 seek() 与紧跟的 play() 会互相抢时序——
   * seek 的 Promise 还没落地，play() 已经发出，播放器把这次 seek 丢掉，
   * 表现就是「点重播后画面在播、进度却仍停在接近结尾的位置」（实测停在 3:37/3:53）。
   * 因此这里改成串行：先把播放器拉出终态 → await seek(0) → 确认回到开头再 play()。
   */
  async replay(): Promise<void> {
    const player: media.AVPlayer | undefined = this.player;
    if (player === undefined || !this.prepared) {
      return;
    }
    console.info(`${TAG} replay begin state=${player.state} pos=${player.currentTime} dur=${player.duration}`);
    try {
      if (player.state === 'completed' || player.state === 'stopped') {
        // 先离开终态：部分机型在 completed 下直接 seek 会被忽略
        await player.play();
      }
      await player.seek(0);
      console.info(`${TAG} replay seeked state=${player.state} pos=${player.currentTime}`);
      if (player.state !== 'playing') {
        await player.play();
      }
      console.info(`${TAG} replay end state=${player.state} pos=${player.currentTime}`);
    } catch (err) {
      // 兜底：实在回不去就重建播放源从头放（宁可重新缓冲，也不要停在结尾）
      console.error(`${TAG} replay failed: ${String(err)}`);
      if (this.pendingUrl.length > 0) {
        await this.prepare(this.pendingUrl);
      }
    }
  }

  seek(positionMs: number): void {
    if (this.player === undefined || !this.prepared) {
      return;
    }
    try {
      this.player.seek(Math.max(0, Math.floor(positionMs)));
    } catch (err) {
      console.warn(`${TAG} seek ignored: ${String(err)}`);
    }
  }

  async release(): Promise<void> {
    const player: media.AVPlayer | undefined = this.player;
    this.player = undefined;
    this.prepared = false;
    this.preparing = false;
    this.generation++;
    if (player === undefined) {
      return;
    }
    try {
      player.off('stateChange');
      player.off('timeUpdate');
      player.off('durationUpdate');
      player.off('error');
      await player.release();
      console.info(`${TAG} released`);
    } catch (err) {
      console.warn(`${TAG} release ignored: ${String(err)}`);
    }
  }
}