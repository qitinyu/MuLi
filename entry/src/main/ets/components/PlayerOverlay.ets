import { VideoItem } from '../models/VideoItem';
import { PlaybackService, QualityOption } from '../services/PlaybackService';
import { FormatUtils } from '../utils/FormatUtils';

@Component
export struct PlayerOverlay {
  @Consume currentUrl: string;
  @Consume playbackControlsVisible: boolean;
  @Consume playbackCurrentMs: number;
  @Consume playbackDurationMs: number;
  @Consume playbackPaused: boolean;
  @Consume playbackSpeed: number;
  @Consume speedMenuVisible: boolean;
  @Consume subtitlesEnabled: boolean;
  @Consume playbackQualities: QualityOption[];
  @Consume currentQn: number;
  @Consume qualityMenuVisible: boolean;
  @Consume landscapePlayback: boolean;
  @Consume playbackFinished: boolean;
  @Consume recommendedPlaybackIndex: number;
  @Consume relatedVideos: VideoItem[];
  @Link episodeListVisible: boolean;
  onSeek: (valueMs: number) => void = (valueMs: number): void => {};
  onTogglePlay: () => void = (): void => {};
  onShowControls: () => void = (): void => {};
  onOpenLandscape: () => void = (): void => {};
  onReplay: () => void = (): void => {};
  onPlayRecommended: () => void = (): void => {};
  onShare: () => void = (): void => {};
  onQualitySwitch: (qn: number) => void = (qn: number): void => {};

  private currentQualityLabel(): string {
    const matched: QualityOption | undefined = this.playbackQualities.find(
      (option: QualityOption): boolean => option.qn === this.currentQn);
    if (matched !== undefined) return matched.label;
    return PlaybackService.qualityLabel(this.currentQn);
  }

  @Builder
  qualityTool() {
    Column() {
      Text(this.currentQualityLabel()).fontSize(12).fontWeight(FontWeight.Medium)
        .fontColor(Color.White).maxLines(1)
    }.width(42).height(42).justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.qualityMenuVisible = !this.qualityMenuVisible;
        this.speedMenuVisible = false;
        this.episodeListVisible = false;
        this.onShowControls();
      })
      .bindMenu(this.qualityMenuVisible, this.qualityMenu(), {
        placement: Placement.Top,
        enableArrow: true,
        showInSubWindow: true
      });
  }

  @Builder
  qualityMenu() {
    Column({ space: 2 }) {
      Text('清晰度').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#20252B')
        .width('100%').height(30).textAlign(TextAlign.Center);
      Text('自动').fontSize(12)
        .fontColor(this.currentQn === 0 ? '#1677A8' : '#1E252D')
        .fontWeight(this.currentQn === 0 ? FontWeight.Bold : FontWeight.Normal)
        .width('100%').height(28).textAlign(TextAlign.Center)
        .onClick(() => {
          this.qualityMenuVisible = false;
          this.onQualitySwitch(0);
        });
      if (this.playbackQualities.length === 0) {
        Text('暂无可选清晰度').fontSize(12).fontColor('#858C94')
          .width('100%').height(28).textAlign(TextAlign.Center);
      }
      ForEach(this.playbackQualities, (option: QualityOption) => {
        Text(option.label).fontSize(12)
          .fontColor(option.qn === this.currentQn ? '#1677A8' : '#1E252D')
          .fontWeight(option.qn === this.currentQn ? FontWeight.Bold : FontWeight.Normal)
          .width('100%').height(28).textAlign(TextAlign.Center)
          .onClick(() => {
            this.qualityMenuVisible = false;
            this.onQualitySwitch(option.qn);
          });
      }, (option: QualityOption) => `qn_${option.qn}`);
    }.width(104).padding({ top: 8, bottom: 8 }).backgroundColor('#F7F8FA')
      .borderRadius(10).shadow({ radius: 10, color: '#33000000', offsetX: 0, offsetY: 3 });
  }

  @Builder
  playbackTool(iconName: string, action: () => void) {
    Column() {
      if (iconName === 'list') {
        Image($r('app.media.list')).width(24).height(24).fillColor(Color.White);
      } else if (iconName === 'speed') {
        Image($r('app.media.speed')).width(24).height(24).fillColor(Color.White);
      } else if (iconName === 'zm') {
        Image($r('app.media.zm')).width(24).height(24).fillColor(Color.White)
          .opacity(this.subtitlesEnabled ? 1 : 0.55);
      } else {
        Image($r('app.media.qp')).width(24).height(24).fillColor(Color.White);
      }
    }.width(42).height(42).justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(action)
      .bindMenu(iconName === 'speed' && this.speedMenuVisible, this.speedMenu(), {
        placement: Placement.Bottom,
        enableArrow: true,
        showInSubWindow: true
      });
  }

  @Builder
  speedMenu() {
    Column({ space: 2 }) {
      Text('倍速').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#20252B')
        .width('100%').height(30).textAlign(TextAlign.Center);
      ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], (speed: number) => {
        Text(speed === 1.0 ? '1.0x（原速度）' : speed.toFixed(2) + 'x').fontSize(12)
          .fontColor(speed === this.playbackSpeed ? '#1677A8' : '#1E252D')
          .fontWeight(speed === this.playbackSpeed ? FontWeight.Bold : FontWeight.Normal)
          .width('100%').height(28).textAlign(TextAlign.Center)
          .onClick(() => {
            this.playbackSpeed = speed;
            this.speedMenuVisible = false;
            this.onShowControls();
          });
      }, (speed: number) => `${speed}`);
    }.width(112).padding({ top: 8, bottom: 8 }).backgroundColor('#F7F8FA')
      .borderRadius(10).shadow({ radius: 10, color: '#33000000', offsetX: 0, offsetY: 3 });
  }

  @Builder
  playbackInlineButton() {
    Button() {
      if (this.playbackPaused) {
        Image($r('app.media.bofang')).width(30).height(30).fillColor(Color.White);
      } else {
        Image($r('app.media.stop')).width(30).height(30).fillColor(Color.White);
      }
    }
    .type(ButtonType.ROUNDED_RECTANGLE).width(42).height(32)
    .backgroundColor(Color.Transparent)
    .onClick(() => { this.onTogglePlay(); });
  }

  @Builder
  playbackControls() {
    if (this.playbackControlsVisible) {
      Stack() {
        Column({ space: 4 }) {
          Row({ space: 6 }) {
            Text(FormatUtils.formatPlaybackTime(this.playbackCurrentMs)).fontSize(11).fontColor(Color.White);
            Slider({
              value: this.playbackCurrentMs,
              min: 0,
              max: Math.max(1000, this.playbackDurationMs),
              step: 1000
            })
              .layoutWeight(1).height(24)
              .blockColor('#FFFFFF').selectedColor('#F04B55').trackColor('#66FFFFFF')
              .onChange((value: number): void => { this.onSeek(value); });
            Text(FormatUtils.formatPlaybackTime(this.playbackDurationMs)).fontSize(11).fontColor(Color.White);
          }.width('100%').height(24).alignItems(VerticalAlign.Center);
          Row() {
            this.playbackInlineButton();
            this.qualityTool();
            this.playbackTool('list', () => {
              this.episodeListVisible = !this.episodeListVisible;
              this.speedMenuVisible = false;
              this.onShowControls();
            });
            this.playbackTool('speed', () => {
              this.speedMenuVisible = !this.speedMenuVisible;
              this.episodeListVisible = false;
              this.onShowControls();
            });
            this.playbackTool('zm', () => {
              this.subtitlesEnabled = !this.subtitlesEnabled;
              this.onShowControls();
            });
            this.playbackTool('qp', () => {
              // 竖屏时进入横屏；横屏时作为返回竖屏入口
              this.onOpenLandscape();
              this.onShowControls();
            });
          }.width('100%').justifyContent(FlexAlign.SpaceBetween).padding({ left: 4, right: 14 });
        }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 2 });
      }.width('100%').height(78).alignContent(Alignment.Bottom)
        .position({ left: 0, right: 0, bottom: 0 }).zIndex(3)
        .transition({ type: TransitionType.Insert, translate: { y: 78 }, opacity: 0 })
        .animation({ duration: 260, curve: Curve.EaseOut });
    }
  }

  @Builder
  playbackFinishedOverlay() {
    if (this.playbackFinished && this.recommendedPlaybackIndex >= 0
      && this.recommendedPlaybackIndex < this.relatedVideos.length) {
      // 播放结束：播放区黑屏，相关推荐视频居中展示
      Column().width('100%').height('100%').backgroundColor(Color.Black).zIndex(5);
      Column({ space: 14 }) {
        Text('为你推荐').fontSize(12).fontColor('#B3FFFFFF').width('100%');
        Row({ space: 10 }) {
          Image(this.relatedVideos[this.recommendedPlaybackIndex].cover)
            .width(120).height(68).objectFit(ImageFit.Cover).borderRadius(8);
          Text(this.relatedVideos[this.recommendedPlaybackIndex].title).fontSize(14)
            .fontColor(Color.White).maxLines(3).textAlign(TextAlign.Start)
            .lineHeight(20).layoutWeight(1);
        }.width('100%').alignItems(VerticalAlign.Center);
        Row({ space: 30 }) {
          Column({ space: 4 }) {
            Image($r('app.media.cb')).width(22).height(22).fillColor(Color.White);
            Text('重播').fontSize(10).fontColor(Color.White);
          }.onClick(() => { this.onReplay(); });
          Column({ space: 4 }) {
            Image($r('app.media.bofang')).width(22).height(22).fillColor(Color.White);
            Text('立即播放').fontSize(10).fontColor(Color.White);
          }.onClick(() => { this.onPlayRecommended(); });
          Column({ space: 4 }) {
            Image($r('app.media.share')).width(22).height(22).fillColor(Color.White);
            Text('分享').fontSize(10).fontColor(Color.White);
          }.onClick(() => { this.onShare(); });
        }.width('100%').justifyContent(FlexAlign.Center);
      }
      .justifyContent(FlexAlign.Center)
      .width('78%')
      .padding(14)
      .backgroundColor('#1C1C1E')
      .borderRadius(12)
      .zIndex(6);
    }
  }

  build() {
    Stack() {
      if (this.currentUrl !== '') {
        this.playbackControls();
      }
      this.playbackFinishedOverlay();
    }.width('100%').height('100%');
  }
}
