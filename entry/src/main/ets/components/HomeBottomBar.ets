import { curves } from '@kit.ArkUI';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';

@Component
export struct HomeBottomBar {
  @Consume activeTab: number;
  @Consume contentTab: number;
  @Consume selectedTopTab: number;
  @Consume actionMenuVisible: boolean;
  @Consume floatBallSwapped: boolean;
  @Consume bottomBarVisible: boolean;
  @Consume bottomInset: number;
  @Consume loadError: string;
  @Link refreshing: boolean;
  onScrollTop: () => void = (): void => {};
  onListRefresh: () => void = (): void => {};
  onOpenSearch: () => void = (): void => {};

  @Builder
  searchBall() {
    Button() {
      Image($r('app.media.ic_public_search_filled')).width(24).height(24);
    }
    .type(ButtonType.ROUNDED_RECTANGLE).width(52).height(52)
    .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(26)
    .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
    .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
    .onClick(() => { this.onOpenSearch(); });
  }

  @Builder
  actionBall() {
    Button() {
      Image($r('app.media.more')).width(24).height(24);
    }
    .type(ButtonType.ROUNDED_RECTANGLE).width(52).height(52)
    .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(26)
    .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
    .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
    .onClick(() => { this.actionMenuVisible = !this.actionMenuVisible; })
    .gesture(LongPressGesture({ repeat: false }).onAction((): void => {
      this.onScrollTop();
    }));
  }

  build() {
    Row({ space: 10 }) {
      if (this.floatBallSwapped) {
        this.actionBall();
      } else {
        this.searchBall();
      }
      Row() {
        Button() {
          Column({ space: 2 }) {
            Image($r('app.media.dontai')).width(this.activeTab === 0 ? 22 : 20)
              .height(this.activeTab === 0 ? 22 : 20)
              .fillColor(this.activeTab === 0 ? '#1677A8' : '#3E4854');
            Text('动态').fontSize(11)
              .fontColor(this.activeTab === 0 ? '#1677A8' : '#3E4854')
              .fontWeight(this.activeTab === 0 ? FontWeight.Bold : FontWeight.Normal);
          }.alignItems(HorizontalAlign.Center);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).height(52).layoutWeight(1)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.activeTab = 0;
          this.refreshing = false;
          this.actionMenuVisible = false;
          this.loadError = '';
        });
        Button() {
          Column({ space: 2 }) {
            Image($r('app.media.home')).width(this.activeTab === 1 ? 22 : 20)
              .height(this.activeTab === 1 ? 22 : 20)
              .fillColor(this.activeTab === 1 ? '#1677A8' : '#3E4854');
            Text('首页').fontSize(11)
              .fontColor(this.activeTab === 1 ? '#1677A8' : '#3E4854')
              .fontWeight(this.activeTab === 1 ? FontWeight.Bold : FontWeight.Normal);
          }.alignItems(HorizontalAlign.Center);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).height(52).layoutWeight(1)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.activeTab = 1;
          this.contentTab = 1;
          this.selectedTopTab = 1;
          this.refreshing = false;
          this.actionMenuVisible = false;
          this.loadError = '';
        });
        Button() {
          Column({ space: 2 }) {
            Image($r('app.media.fanju')).width(this.activeTab === 2 ? 22 : 20)
              .height(this.activeTab === 2 ? 22 : 20)
              .fillColor(this.activeTab === 2 ? '#1677A8' : '#3E4854');
            Text('番剧').fontSize(11)
              .fontColor(this.activeTab === 2 ? '#1677A8' : '#3E4854')
              .fontWeight(this.activeTab === 2 ? FontWeight.Bold : FontWeight.Normal);
          }.alignItems(HorizontalAlign.Center);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).height(52).layoutWeight(1)
        .backgroundColor(Color.Transparent)
        .onClick(() => { this.activeTab = 2; this.loadError = ''; });
      }
      .layoutWeight(1).height(58).padding({ left: 6, right: 6 })
      .backgroundColor(ImmersiveMaterial.fallbackBackground(0.82))
      .borderRadius(30)
      .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT });

      if (this.floatBallSwapped) {
        this.searchBall();
      } else {
        this.actionBall();
      }
    }
    .width('94%').height(58).padding({ left: 4, right: 4 })
    .justifyContent(FlexAlign.SpaceBetween)
    .position({ left: '3%', bottom: this.bottomInset + 6 })
    .translate({ y: this.bottomBarVisible ? 0 : 220 })
    .animation({ curve: curves.springMotion(0.4, 0.8) })
    .zIndex(10);
  }
}

@Component
export struct HomeActionMenu {
  @Consume actionMenuVisible: boolean;
  @Consume floatBallSwapped: boolean;
  @Consume compactGrid: boolean;
  @Consume bottomInset: number;
  onListRefresh: () => void = (): void => {};

  build() {
    if (this.actionMenuVisible) {
      Column({ space: 8 }) {
        Button() {
          Text('列表刷新').fontSize(13)
            .fontColor(Color.Black).fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)
        }.width(124).height(38)
          .type(ButtonType.ROUNDED_RECTANGLE).borderRadius(18)
          .backgroundColor(ImmersiveMaterial.fallbackBackground())
          .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
          .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
          .onClick(() => {
            this.actionMenuVisible = false;
            this.onListRefresh();
          });
        Button() {
          Text(this.compactGrid ? '改为双列' : '改为单列').fontSize(13)
            .fontColor(Color.Black).fontWeight(FontWeight.Bold)
            .textAlign(TextAlign.Center)
        }.width(124).height(38)
          .type(ButtonType.ROUNDED_RECTANGLE).borderRadius(18)
          .backgroundColor(ImmersiveMaterial.fallbackBackground())
          .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
          .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
          .onClick(() => {
            this.compactGrid = !this.compactGrid;
            this.actionMenuVisible = false;
          });
      }
      .width('100%')
      .alignItems(this.floatBallSwapped ? HorizontalAlign.Start : HorizontalAlign.End)
      .padding({ left: 8, right: 8 })
      .position({ left: 0, right: 0, bottom: this.bottomInset + 64 })
      .transition({ type: TransitionType.Insert, opacity: 0.0 })
      .animation({ duration: 220, curve: Curve.EaseOut })
      .zIndex(11);
    }
  }
}
