import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class VideoPlayerService {
  private player: media.AVPlayer | undefined;
  private currentState: media.AVPlayerState = 'idle';
  private lastError: string = '';

  get state(): media.AVPlayerState {
    return this.currentState;
  }

  get errorMessage(): string {
    return this.lastError;
  }

  async prepare(url: string, surfaceId: string): Promise<void> {
    await this.release();
    this.lastError = '';
    if (url === '' || surfaceId === '') {
      throw new Error('播放源或视频画布为空');
    }

    const player: media.AVPlayer = await media.createAVPlayer();
    this.player = player;
    player.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason): void => {
      this.currentState = state;
      console.info(`Pilihos AVPlayer state: ${state}, reason=${reason}`);
    });
    player.on('error', (error: BusinessError): void => {
      this.lastError = `${error.code} ${error.message}`;
      console.error(`Pilihos AVPlayer error: ${this.lastError}`);
    });

    const headers: Record<string, string> = {
      'User-Agent': 'Pilihos/1.0.0',
      'Referer': 'https://www.bilibili.com/',
      'Origin': 'https://www.bilibili.com'
    };
    const source: media.MediaSource = media.createMediaSourceWithUrl(url, headers);
    await player.setMediaSource(source);
    player.surfaceId = surfaceId;
    await player.prepare();

    try {
      const tracks: Array<media.MediaDescription> = await player.getTrackDescription();
      console.info(`Pilihos AVPlayer tracks: ${tracks.length}`);
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
  }

  async pause(): Promise<void> {
    if (this.player !== undefined && this.currentState === 'playing') {
      await this.player.pause();
    }
  }

  async release(): Promise<void> {
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
}
