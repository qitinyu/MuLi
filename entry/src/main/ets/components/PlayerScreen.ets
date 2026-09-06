import { VideoItem } from '../models/VideoItem';
import { VideoComment } from '../services/ReplyService';
import common from '@ohos.app.ability.common';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FormatUtils } from '../utils/FormatUtils';
import { loadingIndicator } from '../utils/CommonBuilders';
import { PlayerOverlay } from './PlayerOverlay';
import { DetailScreen } from './DetailScreen';

/**
 * 播放器宿主：承载横屏/竖屏两套播放画面与原生 Video 事件处理；
 * 详情页（简介/评论）由 DetailScreen 呈现，视频区通过 videoArea 注入。
 */
@Component
export struct PlayerScreen {
  @Link episodeListVisible: boolean;
  @Consume showVertical: boolean;
  @Consume landscapePlayback: boolean;
  @Consume currentUrl: string;
  @Consume videoMounted: boolean;
  @Consume playbackStarting: boolean;
  @Consume playbackReady: boolean;
  @Consume playerError: string;
  @Consume playbackCurrentMs: number;
  @Consume playbackDurationMs: number;
  @Consume playbackPaused: boolean;
  @Consume playbackSpeed: number;
  @Consume speedMenuVisible: boolean;
  @Consume playbackControlsVisible: boolean;
  @Consume playbackFinished: boolean;
  @Consume recommendedPlaybackIndex: number;
  @Consume subtitlesEnabled: boolean;
  @Consume videos: VideoItem[];
  @Consume currentIndex: number;
  @Consume pendingResumeMs: number;
  @Consume bottomInset: number;
  private nativeVideoController: VideoController = new VideoController();
  private playbackControlsTimer: number = 0;
  onOpenVideo: (item: VideoItem, showComments: boolean) => void =
    (item: VideoItem, showComments: boolean): void => {};
  onLoadComments: (refresh: boolean) => void = (refresh: boolean): void => {};
  onToggleReplies: (comment: VideoComment) => void = (comment: VideoComment): void => {};
  onLoadSubReplies: (rootId: number, refresh: boolean) => void =
    (rootId: number, refresh: boolean): void => {};
  onSubmitComment: () => void = (): void => {};
  onRetry: () => void = (): void => {};
  onBack: () => void = (): void => {};
  onOpenLandscape: () => void = (): void => {};

  private showPlaybackToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2500,
        bottom: this.bottomInset + 24
      });
    } catch (error) {
      console.error(`Pilihos playback toast failed: ${String(error)}`);
    }
  }

  private randomRecommendationIndex(): number {
    const candidates: number[] = [];
    this.videos.forEach((item: VideoItem, index: number): void => {
      // 推荐接口的部分条目只有 aid/cid，没有 bvid；只要是可识别的真实视频
      // 就可以进入结束推荐，详情页会按 aid/cid 重新解析播放地址。
      const hasVideoIdentity: boolean = item.aid > 0 || item.cid > 0 || item.bvid !== '' || item.playUrl !== '';
      if (!item.placeholder && index !== this.currentIndex && hasVideoIdentity) candidates.push(index);
    });
    if (candidates.length === 0) return -1;
    return candidates[Math.floor(Math.random() * candidates.length)];
  }

  private markPlaybackFinished(): void {
    if (this.playbackFinished || !this.showVertical) return;
    this.playbackFinished = true;
    this.playbackPaused = true;
    this.recommendedPlaybackIndex = this.randomRecommendationIndex();
    // 播放结束：隐藏全部控件，呈现黑屏居中推荐
    this.playbackControlsVisible = false;
  }

  private replayFinishedVideo(): void {
    this.playbackFinished = false;
    this.onRetry();
  }

  private playRecommendedVideo(): void {
    if (this.recommendedPlaybackIndex < 0) return;
    this.currentIndex = this.recommendedPlaybackIndex;
    this.playbackFinished = false;
    this.onOpenVideo(this.videos[this.currentIndex], false);
  }

  private shareCurrentVideo(): void {
    const item: VideoItem = this.videos[this.currentIndex];
    const uri: string = item.bvid !== '' ? `https://www.bilibili.com/video/${item.bvid}/` :
      `https://www.bilibili.com/video/av${item.aid}/`;
    const want: Want = { action: 'ohos.want.action.viewData', uri: uri };
    (getContext(this) as common.UIAbilityContext).startAbility(want)
      .catch((error: BusinessError): void => {
        console.error(`Pilihos share failed: ${error.code} ${error.message}`);
        this.showPlaybackToast('分享失败 [错误码: ' + String(error.code) + ']');
      });
  }

  private onNativeVideoPrepared(info: PreparedInfo): void {
    this.playbackDurationMs = Math.max(0, info.duration * 1000);
    this.playbackStarting = false;
    this.playbackReady = true;
    this.playbackPaused = false;
    // 播放器实例因横竖屏/尺寸切换重建时，续播切换前的进度
    if (this.pendingResumeMs > 1000) {
      const resumeMs: number = this.pendingResumeMs;
      this.pendingResumeMs = 0;
      this.seekPlayback(resumeMs);
    }
  }

  private onNativeVideoUpdate(info: PlaybackInfo): void {
    this.playbackCurrentMs = Math.max(0, info.time * 1000);
    if (!this.playbackFinished && this.playbackDurationMs > 0 &&
      this.playbackCurrentMs >= this.playbackDurationMs - 800) {
      this.markPlaybackFinished();
    }
  }

  private onNativeVideoError(error: BusinessError): void {
    const message: string = `${error.code} ${error.message}`;
    this.playbackReady = false;
    this.playbackStarting = false;
    this.videoMounted = false;
    this.playerError = '视频播放失败: ' + message;
    this.showPlaybackToast(FormatUtils.playbackErrorToast(message));
    console.error(`Pilihos native Video error: ${message}`);
  }

  private async togglePlayback(): Promise<void> {
    if (this.currentUrl === '' || this.playbackStarting) return;
    try {
      if (this.playbackPaused) {
        this.nativeVideoController.start();
        this.playbackPaused = false;
        this.playbackReady = true;
      } else {
        this.nativeVideoController.pause();
        this.playbackPaused = true;
      }
      this.showPlaybackControls();
    } catch (error) {
      this.playerError = '播放控制失败: ' + String(error);
    }
  }

  private showPlaybackControls(): void {
    this.playbackControlsVisible = true;
    if (this.playbackControlsTimer !== 0) {
      clearTimeout(this.playbackControlsTimer);
    }
    this.playbackControlsTimer = setTimeout((): void => {
      if (!this.speedMenuVisible && !this.episodeListVisible) {
        this.playbackControlsVisible = false;
      }
      this.playbackControlsTimer = 0;
    }, 4000);
  }

  private seekPlayback(valueMs: number): void {
    const duration: number = Math.max(0, this.playbackDurationMs);
    const position: number = Math.max(0, Math.min(valueMs, duration > 0 ? duration : valueMs));
    this.playbackCurrentMs = position;
    this.nativeVideoController.setCurrentTime(position / 1000);
  }

  @Builder
  landscapeSurface() {
    Stack() {
      if (this.currentUrl !== '') {
        Video({ src: this.currentUrl, controller: this.nativeVideoController,
          currentProgressRate: this.playbackSpeed })
          .width('100%').height('100%').objectFit(ImageFit.Contain).controls(false).autoPlay(true)
          .onPrepared((info: PreparedInfo): void => { this.onNativeVideoPrepared(info); })
          .onStart((): void => { this.playbackPaused = false; this.playbackReady = true; })
          .onPause((): void => { this.playbackPaused = true; })
          .onUpdate((info: PlaybackInfo): void => { this.onNativeVideoUpdate(info); })
          .onFinish((): void => { this.markPlaybackFinished(); })
          .onError((error: BusinessError): void => { this.onNativeVideoError(error); });
      } else {
        Column({ space: 12 }) {
          if (this.playerError === '') {
            loadingIndicator('正在获取视频播放地址...', '#FFFFFF');
          } else {
            Text(this.playerError).fontColor(Color.White).fontSize(15).textAlign(TextAlign.Center);
          }
          if (this.playerError !== '') {
            Button() {
              Image($r('app.media.bofang')).width(56).height(56).fillColor(Color.White);
            }
            .type(ButtonType.ROUNDED_RECTANGLE).width(76).height(76)
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.onRetry(); });
          }
        }.justifyContent(FlexAlign.Center).width('100%').height('100%');
      }
      PlayerOverlay({
        episodeListVisible: $episodeListVisible,
        onSeek: (valueMs: number): void => { this.seekPlayback(valueMs); },
        onTogglePlay: (): void => { this.togglePlayback(); },
        onShowControls: (): void => { this.showPlaybackControls(); },
        onOpenLandscape: (): void => { this.onOpenLandscape(); },
        onReplay: (): void => { this.replayFinishedVideo(); },
        onPlayRecommended: (): void => { this.playRecommendedVideo(); },
        onShare: (): void => { this.shareCurrentVideo(); }
      });
      Button() {
        Image($r('app.media.fanhui_left')).width(24).height(24);
      }
      .type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
      .backgroundColor('#66000000').borderRadius(22)
      .position({ left: 16, top: 16 })
      .visibility(this.playbackControlsVisible ? Visibility.Visible : Visibility.None)
      .onClick(() => { this.onBack(); });
      Button() {
        Image($r('app.media.qp')).width(22).height(22).fillColor(Color.White);
      }
      .type(ButtonType.Circle).width(44).height(44)
      .backgroundColor('#66000000')
      .position({ right: 16, bottom: 90 })
      .visibility(this.playbackControlsVisible ? Visibility.Visible : Visibility.None)
      .onClick(() => { this.onOpenLandscape(); });
    }
    .width('100%').height('100%').backgroundColor(Color.Black)
    .onClick((): void => { this.showPlaybackControls(); });
  }

  @Builder
  detailVideoInner() {
    if (this.currentUrl === '' && this.videos[this.currentIndex].cover !== '') {
      Image(this.videos[this.currentIndex].cover)
        .width('100%').height('100%').objectFit(ImageFit.Cover);
    }
    if (this.currentUrl !== '') {
      Video({ src: this.currentUrl, controller: this.nativeVideoController,
        currentProgressRate: this.playbackSpeed })
        .width('100%').height('100%').objectFit(ImageFit.Contain).controls(false).autoPlay(true)
        .onPrepared((info: PreparedInfo): void => { this.onNativeVideoPrepared(info); })
        .onStart((): void => { this.playbackPaused = false; this.playbackReady = true; })
        .onPause((): void => { this.playbackPaused = true; })
        .onUpdate((info: PlaybackInfo): void => { this.onNativeVideoUpdate(info); })
        .onFinish((): void => { this.markPlaybackFinished(); })
        .onError((error: BusinessError): void => { this.onNativeVideoError(error); });
      if (!this.videoMounted) {
        Image(this.videos[this.currentIndex].cover)
          .width('100%').height('100%').objectFit(ImageFit.Cover);
        Button() {
          Image($r('app.media.bofang')).width(56).height(56).fillColor(Color.White);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(76).height(76)
        .backgroundColor(Color.Transparent)
        .onClick(() => { this.onRetry(); });
      } else if (this.playbackStarting) {
        Row() {
          loadingIndicator('正在准备视频...', '#FFFFFF');
        }
        .backgroundColor('#99000000').padding(8);
      }
    } else {
      Column({ space: 12 }) {
        if (this.playerError === '') {
          loadingIndicator('正在获取视频播放地址...', '#FFFFFF');
        } else {
          Text(this.playerError).fontColor(Color.White).fontSize(14).textAlign(TextAlign.Center)
            .backgroundColor('#99000000').padding(8);
        }
        if (this.playerError !== '') {
          Button() {
            Image($r('app.media.bofang')).width(56).height(56).fillColor(Color.White);
          }
          .type(ButtonType.ROUNDED_RECTANGLE).width(76).height(76)
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.onRetry(); });
        }
      }.justifyContent(FlexAlign.Center).width('100%').height('100%');
    }
    PlayerOverlay({
      episodeListVisible: $episodeListVisible,
      onSeek: (valueMs: number): void => { this.seekPlayback(valueMs); },
      onTogglePlay: (): void => { this.togglePlayback(); },
      onShowControls: (): void => { this.showPlaybackControls(); },
      onOpenLandscape: (): void => { this.onOpenLandscape(); },
      onReplay: (): void => { this.replayFinishedVideo(); },
      onPlayRecommended: (): void => { this.playRecommendedVideo(); },
      onShare: (): void => { this.shareCurrentVideo(); }
    });
    Button() {
      Image($r('app.media.left_syb')).width(24).height(24);
    }
    .type(ButtonType.ROUNDED_RECTANGLE).width(42).height(42)
    .backgroundColor(Color.Transparent)
    .position({ left: 10, top: 10 })
    .visibility(this.playbackControlsVisible ? Visibility.Visible : Visibility.None)
    .onClick(() => { this.onBack(); });
  }

  build() {
    if (this.landscapePlayback) {
      this.landscapeSurface();
    } else {
      DetailScreen({
        videoArea: (): void => { this.detailVideoInner(); },
        episodeListVisible: $episodeListVisible,
        onOpenRelated: (item: VideoItem, showComments: boolean): void => {
          this.onOpenVideo(item, showComments);
        },
        onLoadComments: (refresh: boolean): void => { this.onLoadComments(refresh); },
        onToggleReplies: (comment: VideoComment): void => { this.onToggleReplies(comment); },
        onLoadSubReplies: (rootId: number, refresh: boolean): void => {
          this.onLoadSubReplies(rootId, refresh);
        },
        onSubmitComment: (): void => { this.onSubmitComment(); },
        onShowControls: (): void => { this.showPlaybackControls(); },
        onOpenLandscape: (): void => { this.onOpenLandscape(); }
      });
    }
  }
}
