import { hdsMaterial, HdsTabs, HdsTabsController, HdsBarStyle } from '@kit.UIDesignKit';

@Component
export struct HomeBottomBar {
  @Consume activeTab: number;
  @Consume contentTab: number;
  @Consume selectedTopTab: number;
  @Consume compactGrid: boolean;
  @Consume bottomBarVisible: boolean;
  @Consume bottomInset: number;
  @Consume loadError: string;
  @Link refreshing: boolean;
  private tabsController: HdsTabsController = new HdsTabsController();
  onScrollTop: () => void = (): void => {};
  onListRefresh: () => void = (): void => {};
  onOpenSearch: () => void = (): void => {};
  onSelectTab: (index: number) => void = (index: number): void => {};

  aboutToAppear(): void {
    this.tabsController.changeIndex(this.currentBarIndex());
  }

  private currentBarIndex(): number {
    if (this.contentTab === 3 || this.activeTab === 0) return 0;
    if (this.contentTab === 2) return 2;
    return 1;
  }

  @Builder
  hdsNavTab(index: number, icon: Resource, label: string) {
    Column({ space: 2 }) {
      Image(icon).width(this.currentBarIndex() === index ? 22 : 20)
        .height(this.currentBarIndex() === index ? 22 : 20)
        .fillColor(this.currentBarIndex() === index ? '#1288FA' : '#3E4854');
      Text(label).fontSize(11)
        .fontColor(this.currentBarIndex() === index ? '#1288FA' : '#3E4854')
        .fontWeight(this.currentBarIndex() === index ? FontWeight.Bold : FontWeight.Normal);
    }
    .width('100%')
    .justifyContent(FlexAlign.Center);
  }

  // 收起态 miniBar 作为搜索入口，展开态显示底部三项页签。
  @Builder
  miniBarContent() {
    Button() {
      Image($r('app.media.ic_public_search_filled'))
        .width(30).height(30)
        .fillColor('#1288FA');
    }
    .type(ButtonType.ROUNDED_RECTANGLE)
    .width(54).height(54)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .onClick((): void => { this.onOpenSearch(); })
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  hdsMainTabs() {
    HdsTabs({ controller: this.tabsController }) {
      TabContent() {}.tabBar(this.hdsNavTab(0, $r('app.media.dontai'), '动态'));
      TabContent() {}.tabBar(this.hdsNavTab(1, $r('app.media.home'), '首页'));
      TabContent() {}.tabBar(this.hdsNavTab(2, $r('app.media.remen'), '热门'));
    }
    .onTabBarClick((index: number): void => {
      if (index === 0) {
        this.activeTab = 0;
        this.contentTab = 3;
        this.selectedTopTab = 3;
        this.loadError = '';
      } else if (index === 1) {
        this.activeTab = 1;
        this.contentTab = 1;
        this.selectedTopTab = 1;
        this.refreshing = false;
        this.loadError = '';
      } else {
        this.activeTab = 1;
        this.contentTab = 2;
        this.selectedTopTab = 2;
        this.loadError = '';
      }
      this.onSelectTab(this.contentTab);
    })
    .scrollable(false)
    .barOverlap(true)
    .barPosition(BarPosition.End)
    .vertical(false)
    .barHeight(56)
    .barFloatingStyle({
      barSideMargin: 28,
      barBottomMargin: this.bottomInset + 10,
      adaptToHandedness: true,
      miniBar: {
        miniBarBuilder: (): void => { this.miniBarContent(); },
        miniBarStyle: HdsBarStyle.COLLAPSE
      },
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.IMMERSIVE,
        materialLevel: hdsMaterial.MaterialLevel.EXQUISITE
      },
      barOpacity: 1
    })
    .width('100%')
    .height('100%');
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.hdsMainTabs();
    }
    .width('100%')
    .height('100%')
    .opacity(this.bottomBarVisible ? 1 : 0)
    .hitTestBehavior(this.bottomBarVisible ? HitTestMode.Default : HitTestMode.Transparent)
    .animation({ duration: 180, curve: Curve.EaseOut });
  }
}
