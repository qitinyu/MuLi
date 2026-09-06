import { VideoItem } from '../models/VideoItem';
import { VideoComment } from '../services/ReplyService';
import { QualityOption } from '../services/PlaybackService';
import { PlaybackMemory } from '../utils/PlaybackMemory';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import audio from '@ohos.multimedia.audio';
import { BusinessError } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { FormatUtils } from '../utils/FormatUtils';
import { loadingIndicator } from '../utils/CommonBuilders';
import { PlayerOverlay } from './PlayerOverlay';
import { DetailScreen } from './DetailScreen';
import { DanmakuOverlay } from './DanmakuOverlay';

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
  @Consume playbackQualities: QualityOption[];
  @Consume currentQn: number;
  @Consume qualityMenuVisible: boolean;
  @Consume videos: VideoItem[];
  @Consume currentIndex: number;
  @Consume pendingResumeMs: number;
  @Consume playMode: number;
  @Consume verticalExpanded: boolean;
  @Consume danmakuEnabled: boolean;
  @Consume bottomInset: number;
  private nativeVideoController: VideoController = new VideoController();
  private playbackControlsTimer: number = 0;
  private initialHideTimer: number = -1;
  @State hudText: string = '';
  @State hudVisible: boolean = false;
  private hudTimer: number = -1;
  private surfaceWidth: number = 0;
  private gestureMode: string = '';
  private seekBaseMs: number = 0;
  private seekPreviewMs: number = 0;
  private startBrightness: number = 0.5;
  private startVolume: number = 8;
  private originalBrightness: number = -1;
  private holdSpeedBase: number = 1.0;
  onOpenVideo: (item: VideoItem, showComments: boolean) => void =
    (item: VideoItem, showComments: boolean): void => {};
  onLoadComments: (refresh: boolean) => void = (refresh: boolean): void => {};
  onToggleReplies: (comment: VideoComment) => void = (comment: VideoComment): void => {};
  onLoadSubReplies: (rootId: number, refresh: boolean) => void =
    (rootId: number, refresh: boolean): void => {};
  onSubmitComment: () => void = (): void => {};
  onSendDanmaku: () => void = (): void => {};
  onDetailAction: (action: string) => void = (action: string): void => {};
  onLikeComment: (comment: VideoComment) => void = (comment: VideoComment): void => {};
  onFollowAuthor: (on: boolean) => void = (on: boolean): void => {};
  onSetPlayMode: (mode: number) => void = (mode: number): void => {};
  onFollowGroup: () => void = (): void => {};
  onRetry: () => void = (): void => {};
  onQualitySwitch: (qn: number) => void = (qn: number): void => {};
  onBack: () => void = (): void => {};
  onBackHome: () => void = (): void => {};
  onToggleControls: () => void = (): void => {};
  onOpenLandscape: () => void = (): void => {};
  onCloseLandscape: () => void = (): void => {};

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
    // 播放模式：单集循环 / 随机连播（竖屏化连播）
    if (this.playMode === 1) {
      this.replayFinishedVideo();
      return;
    }
    if (this.playMode === 2) {
      this.playNextRandom();
      return;
    }
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
    this.savePlaybackProgress();
    this.currentIndex = this.recommendedPlaybackIndex;
    this.playbackFinished = false;
    this.onOpenVideo(this.videos[this.currentIndex], false);
  }

  private savePlaybackProgress(): void {
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.placeholder || item.aid <= 0) return;
    if (this.playbackCurrentMs < 5000) return;
    PlaybackMemory.record(getContext(this) as common.UIAbilityContext, item.aid, this.playbackCurrentMs);
  }

  private shareCurrentVideo(): void {
    const item: VideoItem = this.videos[this.currentIndex];
    const uri: string = item.bvid !== '' ? `https://www.bilibili.com/video/${item.bvid}/` :
      `https://www.bilibili.com/video/av${item.aid}/`;
    try {
      const sharedData: systemShare.SharedData = new systemShare.SharedData({
        utd: 'general.url',
        content: uri
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(sharedData);
      controller.show(getContext(this) as common.UIAbilityContext,
        { selectionMode: systemShare.SelectionMode.SINGLE })
        .catch((error: BusinessError): void => {
          console.error(`Pilihos share failed: ${error.code} ${error.message}`);
          this.showPlaybackToast('分享失败 [错误码: ' + String(error.code) + ']');
        });
    } catch (shareError) {
      this.showPlaybackToast('分享失败: ' + String(shareError));
    }
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
    // 清晰度切换失败时自动回退默认清晰度重试一次
    if (this.currentQn > 0) {
      console.warn(`Pilihos quality switch failed, reverting: qn=${this.currentQn}, ${message}`);
      this.currentQn = 0;
      this.onRetry();
      return;
    }
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

  private togglePlaybackControls(): void {
    if (this.playbackControlsVisible) {
      // 点动隐藏：清掉两套自动隐藏定时器后直接收起
      if (this.playbackControlsTimer !== 0) {
        clearTimeout(this.playbackControlsTimer);
        this.playbackControlsTimer = 0;
      }
      if (this.initialHideTimer !== -1) {
        clearTimeout(this.initialHideTimer);
        this.initialHideTimer = -1;
      }
      this.playbackControlsVisible = false;
    } else {
      this.showPlaybackControls();
    }
  }

  private showPlaybackControls(): void {
    if (this.initialHideTimer !== -1) {
      // 用户主动唤起后交给常规的 4s 自动隐藏周期
      clearTimeout(this.initialHideTimer);
      this.initialHideTimer = -1;
    }
    this.playbackControlsVisible = true;
    if (this.playbackControlsTimer !== 0) {
      clearTimeout(this.playbackControlsTimer);
    }
    this.playbackControlsTimer = setTimeout((): void => {
      if (!this.speedMenuVisible && !this.episodeListVisible && !this.qualityMenuVisible) {
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

  aboutToDisappear(): void {
    if (this.initialHideTimer !== -1) {
      clearTimeout(this.initialHideTimer);
      this.initialHideTimer = -1;
    }
    // 离开播放器时还原手势调节前的系统亮度
    if (this.originalBrightness >= 0) {
      const brightness: number = this.originalBrightness;
      this.originalBrightness = -1;
      window.getLastWindow(getContext(this) as common.UIAbilityContext).then((win: window.Window): void => {
        win.setWindowBrightness(brightness);
      }).catch((error: BusinessError): void => {
        console.warn(`Pilihos brightness restore failed: ${String(error)}`);
      });
    }
  }

  private showHud(text: string): void {
    this.hudText = text;
    this.hudVisible = true;
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
    }
    this.hudTimer = setTimeout((): void => {
      this.hudVisible = false;
      this.hudTimer = -1;
    }, 900);
  }

  private formatHudTime(valueMs: number): string {
    const totalSeconds: number = Math.max(0, Math.floor(valueMs / 1000));
    const minutes: number = Math.floor(totalSeconds / 60);
    const seconds: number = totalSeconds % 60;
    return `${minutes}:${String(seconds).padStart(2, '0')}`;
  }

  private onHoldSpeedStart(): void {
    if (this.currentUrl === '') return;
    this.holdSpeedBase = this.playbackSpeed;
    this.playbackSpeed = 2;
    this.showHud('2倍速快进中');
  }

  private onHoldSpeedEnd(): void {
    if (this.playbackSpeed === 2 && this.holdSpeedBase !== 2) {
      this.playbackSpeed = this.holdSpeedBase;
    }
  }

  private onSeekStart(): void {
    this.gestureMode = 'seek';
    this.seekBaseMs = this.playbackCurrentMs;
    this.seekPreviewMs = this.playbackCurrentMs;
  }

  private onSeekUpdate(event: GestureEvent): void {
    if (this.currentUrl === '' || this.gestureMode !== 'seek') return;
    const duration: number = this.playbackDurationMs;
    this.seekPreviewMs = Math.max(0, Math.min(this.seekBaseMs + event.offsetX * 150,
      duration > 0 ? duration : this.seekBaseMs + event.offsetX * 150));
    const forward: boolean = this.seekPreviewMs >= this.seekBaseMs;
    this.showHud(`${forward ? '快进' : '快退'} ${this.formatHudTime(this.seekPreviewMs)} / ${this.formatHudTime(this.playbackDurationMs)}`);
  }

  private onSeekEnd(): void {
    if (this.gestureMode === 'seek') {
      this.seekPlayback(this.seekPreviewMs);
      this.showPlaybackControls();
    }
    this.gestureMode = '';
  }

  private onVerticalStart(): void {
    this.gestureMode = '';
    audio.getAudioManager().getVolume(audio.AudioVolumeType.MEDIA).then((volume: number): void => {
      this.startVolume = volume;
    }).catch((): void => {
      this.startVolume = 8;
    });
    window.getLastWindow(getContext(this) as common.UIAbilityContext).then((win: window.Window): void => {
      const brightness: number = win.getWindowProperties().brightness;
      if (brightness > 0) {
        this.startBrightness = brightness;
        if (this.originalBrightness < 0) this.originalBrightness = brightness;
      }
    }).catch((): void => {
      this.startBrightness = 0.5;
    });
  }

  private onVerticalUpdate(event: GestureEvent): void {
    if (this.currentUrl === '') return;
    const dy: number = event.offsetY;
    if (this.gestureMode === '') {
      if (this.verticalExpanded && dy < -14) {
        // 竖屏化：上滑切换下一个视频
        this.gestureMode = 'swipeNext';
        return;
      }
      const localX: number = event.fingerList.length > 0 ? event.fingerList[0].localX : this.surfaceWidth / 2;
      this.gestureMode = localX < this.surfaceWidth / 2 ? 'brightness' : 'volume';
    }
    if (this.gestureMode === 'brightness') {
      const brightness: number = Math.max(0.05, Math.min(1, this.startBrightness - dy / 500));
      window.getLastWindow(getContext(this) as common.UIAbilityContext).then((win: window.Window): void => {
        win.setWindowBrightness(brightness);
      }).catch((): void => {});
      this.showHud(`亮度 ${Math.round(brightness * 100)}%`);
    } else if (this.gestureMode === 'volume') {
      const volume: number = Math.max(0, Math.min(15, Math.round(this.startVolume - dy / 500 * 15)));
      audio.getAudioManager().setVolume(audio.AudioVolumeType.MEDIA, volume).catch((): void => {});
      this.showHud(`音量 ${volume}/15`);
    }
  }

  private onVerticalEnd(event: GestureEvent): void {
    if (this.gestureMode === 'swipeNext' && event.offsetY < -50) {
      this.playNextRandom();
    }
    this.gestureMode = '';
  }

  /**
   * 随机连播与上滑共用：切到下一个推荐视频（保持竖屏化状态）
   */
  private playNextRandom(): void {
    this.savePlaybackProgress();
    this.recommendedPlaybackIndex = this.randomRecommendationIndex();
    if (this.recommendedPlaybackIndex < 0) {
      this.showPlaybackToast('没有可播放的推荐视频');
      return;
    }
    this.playRecommendedVideo();
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
      if (this.danmakuEnabled && this.currentUrl !== '') {
        DanmakuOverlay({
          cid: this.videos[this.currentIndex].cid,
          playing: !this.playbackPaused,
          positionMs: this.playbackCurrentMs,
          speedFactor: this.playbackSpeed
        })
      }
      PlayerOverlay({
        episodeListVisible: $episodeListVisible,
        onSeek: (valueMs: number): void => { this.seekPlayback(valueMs); },
        onTogglePlay: (): void => { this.togglePlayback(); },
        onShowControls: (): void => { this.showPlaybackControls(); },
        onOpenLandscape: (): void => { if (this.landscapePlayback) { this.onCloseLandscape(); } else { this.onOpenLandscape(); } },
        onReplay: (): void => { this.replayFinishedVideo(); },
        onPlayRecommended: (): void => { this.playRecommendedVideo(); },
        onShare: (): void => { this.shareCurrentVideo(); },
        onQualitySwitch: (qn: number): void => { this.onQualitySwitch(qn); }
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
        Image($r('app.media.home')).width(22).height(22).fillColor(Color.White);
      }
      .type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
      .backgroundColor('#66000000').borderRadius(22)
      .position({ left: 68, top: 16 })
      .visibility(this.playbackControlsVisible ? Visibility.Visible : Visibility.None)
      .onClick(() => { this.onBackHome(); });
      if (this.hudVisible) {
        Text(this.hudText)
          .fontSize(14).fontColor(Color.White)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor('#99000000').borderRadius(18)
      }
    }
    .width('100%').height('100%').backgroundColor(Color.Black)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.surfaceWidth = Number(newArea.width);
    })
    .gesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
      .onActionStart((event: GestureEvent): void => { this.onSeekStart(); })
      .onActionUpdate((event: GestureEvent): void => { this.onSeekUpdate(event); })
      .onActionEnd((event: GestureEvent): void => { this.onSeekEnd(); }))
    .gesture(PanGesture({ fingers: 1, direction: PanDirection.Vertical })
      .onActionStart((event: GestureEvent): void => { this.onVerticalStart(); })
      .onActionUpdate((event: GestureEvent): void => { this.onVerticalUpdate(event); })
      .onActionEnd((event: GestureEvent): void => { this.onVerticalEnd(event); }))
    .gesture(TapGesture().onAction((): void => { this.showPlaybackControls(); }))
    .gesture(TapGesture({ count: 2 }).onAction((): void => { this.togglePlayback(); }))
    .gesture(LongPressGesture({ repeat: false, duration: 500 })
      .onActionStart((event: GestureEvent): void => { this.onHoldSpeedStart(); })
      .onActionEnd((event: GestureEvent): void => { this.onHoldSpeedEnd(); }))
    .gesture(TapGesture().onAction((): void => { this.togglePlaybackControls(); }))
    .gesture(TapGesture({ count: 2 }).onAction((): void => { this.togglePlayback(); }))
    .gesture(LongPressGesture({ repeat: false, duration: 500 })
      .onActionStart((event: GestureEvent): void => { this.onHoldSpeedStart(); })
      .onActionEnd((event: GestureEvent): void => { this.onHoldSpeedEnd(); }))
    .bindSheet($$this.episodeListVisible, this.landscapeEpisodeSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true
    });
  }

  @Builder
  landscapeEpisodeSheet() {
    Column() {
      Text('暂无更多选集')
        .fontSize(14).fontColor('#30363D').width('100%').textAlign(TextAlign.Center)
        .padding({ top: 18, bottom: 24 });
    }.width('100%').padding({ bottom: this.bottomInset + 8 })
      .backgroundColor('#F7F8FA');
  }

  @Builder
  gestureLayer() {
    Stack() {
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
    if (this.danmakuEnabled && this.currentUrl !== '') {
      DanmakuOverlay({
        cid: this.videos[this.currentIndex].cid,
        playing: !this.playbackPaused,
        positionMs: this.playbackCurrentMs,
        speedFactor: this.playbackSpeed
      })
    }
    PlayerOverlay({
      episodeListVisible: $episodeListVisible,
      onSeek: (valueMs: number): void => { this.seekPlayback(valueMs); },
      onTogglePlay: (): void => { this.togglePlayback(); },
      onShowControls: (): void => { this.showPlaybackControls(); },
      onOpenLandscape: (): void => { if (this.landscapePlayback) { this.onCloseLandscape(); } else { this.onOpenLandscape(); } },
      onReplay: (): void => { this.replayFinishedVideo(); },
      onPlayRecommended: (): void => { this.playRecommendedVideo(); },
      onShare: (): void => { this.shareCurrentVideo(); },
      onQualitySwitch: (qn: number): void => { this.onQualitySwitch(qn); }
    });
    Button() {
      Image($r('app.media.left_syb')).width(24).height(24);
    }
    .type(ButtonType.ROUNDED_RECTANGLE).width(42).height(42)
    .backgroundColor(Color.Transparent)
    .position({ left: 10, top: 10 })
    .visibility(this.playbackControlsVisible ? Visibility.Visible : Visibility.None)
    .onClick(() => { this.onBack(); });
    Button() {
      Image($r('app.media.home')).width(22).height(22).fillColor(Color.White);
    }
    .type(ButtonType.ROUNDED_RECTANGLE).width(42).height(42)
    .backgroundColor(Color.Transparent)
    .position({ left: 56, top: 10 })
    .visibility(this.playbackControlsVisible ? Visibility.Visible : Visibility.None)
    .onClick(() => { this.onBackHome(); });
    if (this.hudVisible) {
      Text(this.hudText)
        .fontSize(14).fontColor(Color.White)
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor('#99000000').borderRadius(18)
    }
    }
    .width('100%').height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.surfaceWidth = Number(newArea.width);
    })
    .gesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
      .onActionStart((event: GestureEvent): void => { this.onSeekStart(); })
      .onActionUpdate((event: GestureEvent): void => { this.onSeekUpdate(event); })
      .onActionEnd((event: GestureEvent): void => { this.onSeekEnd(); }))
    .gesture(PanGesture({ fingers: 1, direction: PanDirection.Vertical })
      .onActionStart((event: GestureEvent): void => { this.onVerticalStart(); })
      .onActionUpdate((event: GestureEvent): void => { this.onVerticalUpdate(event); })
      .onActionEnd((event: GestureEvent): void => { this.onVerticalEnd(event); }))
  }

  build() {
    if (this.landscapePlayback) {
      this.landscapeSurface();
    } else {
      DetailScreen({
        videoArea: (): void => { this.gestureLayer(); },
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
        onSendDanmaku: (): void => { this.onSendDanmaku(); },
        onDetailAction: (action: string): void => { this.onDetailAction(action); },
        onLikeComment: (comment: VideoComment): void => { this.onLikeComment(comment); },
        onFollowAuthor: (on: boolean): void => { this.onFollowAuthor(on); },
        onFollowGroup: (): void => { this.onFollowGroup(); },
        onSetPlayMode: (mode: number): void => { this.onSetPlayMode(mode); },
        onShowControls: (): void => { this.showPlaybackControls(); },
        onToggleControls: (): void => { this.togglePlaybackControls(); },
        onOpenLandscape: (): void => { this.onOpenLandscape(); }
      });
    }
  }
}
