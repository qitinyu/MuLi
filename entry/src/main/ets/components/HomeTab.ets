import { VideoItem } from '../models/VideoItem';
import { AuthSession } from '../services/AuthService';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import { FormatUtils } from '../utils/FormatUtils';
import { loadingIndicator } from '../utils/CommonBuilders';
import { HotPage } from '../pages/HotPage';
import { LivePage } from '../pages/LivePage';
import { DynamicPage } from '../pages/DynamicPage';
import { AnimePage } from '../pages/AnimePage';

@Component
export struct HomeTab {
  @Consume activeTab: number;
  @Consume contentTab: number;
  @Consume selectedTopTab: number;
  @Consume topTabsMerged: boolean;
  @Consume floatBallSwapped: boolean;
  @Consume sidebar: number;
  @Consume authSession: AuthSession | null;
  @Consume videos: VideoItem[];
  @Consume loading: boolean;
  @Consume loadingMore: boolean;
  @Consume compactGrid: boolean;
  @Consume portraitBadge: boolean;
  @Consume topInset: number;
  @Consume bottomInset: number;
  @Link refreshing: boolean;
  scroller: Scroller = new Scroller();
  onOpenVideo: (item: VideoItem) => void = (item: VideoItem): void => {};
  onPlayDynamic: (item: VideoItem, showComments: boolean) => void =
    (item: VideoItem, showComments: boolean): void => {};
  onLoadMore: () => void = (): void => {};
  onRefresh: () => void = (): void => {};
  onScrollDelta: (delta: number) => void = (delta: number): void => {};
  onSelectTab: (index: number) => void = (index: number): void => {};

  @Builder
  topBubbleButton(label: string, tabIndex: number, width: number, action: () => void) {
    Row() {
      Text(label)
        .fontSize(this.selectedTopTab === tabIndex ? 15 : 14)
        .fontColor(this.selectedTopTab === tabIndex ? Color.Black : '#3E4854')
        .fontWeight(this.selectedTopTab === tabIndex ? FontWeight.Bold : FontWeight.Normal)
    }
      .justifyContent(FlexAlign.Center)
      .width(width)
      .height(40)
      .backgroundColor(this.topTabsMerged ? Color.Transparent : ImmersiveMaterial.fallbackBackground(0.72))
      .borderRadius(20)
      .shadow({ radius: this.topTabsMerged ? 0 : 5, color: '#22000000', offsetX: 0, offsetY: 2 })
      .onClick(action);
  }

  @Builder
  topTabs() {
    if (this.topTabsMerged) {
      Row({ space: 2 }) {
        this.topBubbleButton('直播', 0, 62, () => { this.onSelectTab(0); });
        this.topBubbleButton('推荐', 1, 66, () => { this.onSelectTab(1); });
        this.topBubbleButton('热门', 2, 62, () => { this.onSelectTab(2); });
      }.height(48).padding({ left: 4, right: 4 })
        .backgroundColor(ImmersiveMaterial.fallbackBackground(0.72))
        .borderRadius(24).systemMaterial(ImmersiveMaterial.thin())
        .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 });
    } else {
      Row({ space: 8 }) {
        this.topBubbleButton('直播', 0, 62, () => { this.onSelectTab(0); });
        this.topBubbleButton('推荐', 1, 66, () => { this.onSelectTab(1); });
        this.topBubbleButton('热门', 2, 62, () => { this.onSelectTab(2); });
      }.height(48);
    }
  }

  @Builder
  topCircleButton(label: string, action: () => void) {
    Button() {
      if (this.authSession !== null && this.authSession.face !== '') {
        Image(this.authSession.face).width(36).height(36).borderRadius(18).objectFit(ImageFit.Cover);
      } else {
        Image($r('app.media.user_me')).width(34).height(34).objectFit(ImageFit.Contain);
      }
    }
      .type(ButtonType.ROUNDED_RECTANGLE)
      .controlSize(ControlSize.NORMAL)
      .width(48)
      .height(48)
      .backgroundColor(ImmersiveMaterial.fallbackBackground(0.72))
      .padding(0)
      .borderRadius(24)
      .systemMaterial(ImmersiveMaterial.thin())
      .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
      .onClick(action);
  }

  @Builder
  homeCard(item: VideoItem) {
    Column({ space: 6 }) {
      Stack() {
        if (item.placeholder) {
          Row().width('100%').aspectRatio(1.62).backgroundColor('#E1E6EE');
        } else if (item.cover !== '') {
          Image(item.cover).width('100%').aspectRatio(1.62).objectFit(ImageFit.Cover);
        } else {
          Row().width('100%').aspectRatio(1.62).backgroundColor('#DCE3EF');
        }
      }
      .borderRadius(10)
      .clip(true)
      if (item.placeholder) {
        Row().width('82%').height(16).backgroundColor('#E1E6EE').borderRadius(4);
        Row().width('58%').height(16).backgroundColor('#E1E6EE').borderRadius(4);
      } else {
        Text(item.title).fontSize(14).maxLines(2).fontWeight(FontWeight.Medium).lineHeight(22);
      }
      Row() {
        if (item.placeholder) {
          Row().width('35%').height(12).backgroundColor('#E1E6EE').borderRadius(4).layoutWeight(1);
          Row().width('25%').height(12).backgroundColor('#E1E6EE').borderRadius(4);
        } else {
          Row({ space: 4 }) {
            Image($r('app.media.bfl')).width(14).height(14);
            Text(FormatUtils.formatCount(item.viewCount)).fontSize(11).fontColor('#8B9199');
          }.layoutWeight(1);
          Row({ space: 4 }) {
            Image($r('app.media.dm')).width(14).height(14);
            Text(FormatUtils.formatCount(item.danmuCount)).fontSize(11).fontColor('#8B9199');
          }.layoutWeight(1);
          if (FormatUtils.isPortraitVideo(item, this.portraitBadge)) {
            Text('竖屏').fontSize(10).fontColor('#E661A0')
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .backgroundColor('#1AE661A0').borderRadius(4);
          }
        }
      }.width('100%');
      Row() {
        if (item.placeholder) {
          Row().width('45%').height(12).backgroundColor('#E1E6EE').borderRadius(4);
        } else if (item.followed) {
          Text('已关注').fontSize(10).fontColor('#1677A8').backgroundColor('#E5F3FA')
            .padding({ left: 5, right: 5, top: 2, bottom: 2 }).borderRadius(4).margin({ right: 4 });
        }
        if (!item.placeholder) {
          Text(`@${item.author}`).fontSize(11).fontColor('#8B9199').layoutWeight(1);
          Text(FormatUtils.formatPublishTime(item.publishTime)).fontSize(11).fontColor('#8B9199');
        }
      }.width('100%');
    }
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor(Color.White)
    .borderRadius(12)
    .height(this.compactGrid ? 320 : 210)
    .onClick(() => {
      if (item.placeholder) {
        return;
      }
      this.onOpenVideo(item);
    });
  }

  build() {
    Column() {
      if (this.activeTab === 1) {
        Row({ space: 8 }) {
          this.topCircleButton('我', () => { this.sidebar = 1; });
          this.topTabs();
          Button() {
            Image($r('app.media.xiaoxi')).width(24).height(24);
          }
          .type(ButtonType.ROUNDED_RECTANGLE)
          .width(48).height(48)
          .backgroundColor(ImmersiveMaterial.fallbackBackground(0.72))
          .borderRadius(24)
          .systemMaterial(ImmersiveMaterial.thin())
          .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
          .onClick(() => { this.sidebar = 2; });
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .justifyContent(FlexAlign.SpaceBetween);
        if (this.contentTab === 1) {
          Refresh({ refreshing: $$this.refreshing, offset: 64, friction: 80 }) {
            Grid(this.scroller) {
              if (this.loading && (this.videos.length === 0 || this.videos[0].placeholder)) {
                GridItem() {
                  loadingIndicator('正在加载推荐', '#1677A8');
                }
                .height(72);
              }
              ForEach(this.videos, (item: VideoItem) => {
                GridItem() { this.homeCard(item); }
              }, (item: VideoItem) => `${item.id}`);
              if (this.loadingMore) {
                GridItem() {
                  loadingIndicator('正在加载', '#1677A8');
                }
                .height(52);
              }
            }
            .columnsTemplate(this.compactGrid ? '1fr' : '1fr 1fr')
            .columnsGap(8)
            .rowsGap(10)
            .padding({ left: 12, right: 12, bottom: 12 })
            .onScrollIndex((_first: number, last: number): void => {
              if (last < Math.max(0, this.videos.length - 4)) return;
              if (this.loadingMore) return;
              this.onLoadMore();
            })
            .onDidScroll((offset: number, _state: ScrollState): void => {
              this.onScrollDelta(offset);
            })
            .width('100%').height('100%').scrollBar(BarState.Off);
          }
          .layoutWeight(1).width('100%')
          .onRefreshing(() => { this.onRefresh(); });
        } else if (this.contentTab === 0) {
          LivePage({ bottomInset: this.bottomInset });
        } else if (this.contentTab === 2) {
          HotPage({ bottomInset: this.bottomInset, showPortraitBadge: this.portraitBadge });
        } else if (this.contentTab === 3) {
          DynamicPage({
            bottomInset: this.bottomInset,
            onPlayVideo: (item: VideoItem, showComments: boolean): void => {
              this.onPlayDynamic(item, showComments);
            }
          });
        } else {
          AnimePage({ bottomInset: this.bottomInset });
        }
      } else if (this.activeTab === 0) {
        DynamicPage({
          bottomInset: this.bottomInset,
          onPlayVideo: (item: VideoItem, showComments: boolean): void => {
            this.onPlayDynamic(item, showComments);
          }
        });
      } else {
        AnimePage({ bottomInset: this.bottomInset });
      }
    }
    .width('100%').height('100%')
    .padding({ top: this.topInset })
    .backgroundColor('#F7F8FA');
  }
}
