import { BreakpointObserver } from '../common/BreakpointObserver';
import { common } from '@kit.AbilityKit';
import { MaterialScope } from '../common/Materials';
import { NAV_ID } from '../common/AppNav';
import { TAB_BAR_BOTTOM_MARGIN, TITLE_CTRL_TEXT_SIZE, TITLE_ICON_HIT, TITLE_ICON_SIZE, TITLE_TEXT_SIZE } from '../common/DesignSpec';
import { HomePage } from './HomePage';
import { DynamicPage } from './DynamicPage';
import { HotPage } from './HotPage';
import { LivePage } from './LivePage';
import { PublishPage } from './PublishPage';
import { SearchPage } from './SearchPage';
import { MessagePage } from './MessagePage';
import { MineRoutePage } from './MineRoutePage';
import { LoginPage } from './LoginPage';
import { WebLoginPage } from './WebLoginPage';
import { ChangeLogPage } from './ChangeLogPage';
import { LibraryPage } from './LibraryPage';
import { AboutPage } from './AboutPage';
import { SettingsPage } from './SettingsPage';
import {
  SECTION_APPEARANCE, SECTION_DYNAMIC, SECTION_PLAYER, SECTION_PLAYPAGE, SettingsDetailPage
} from './SettingsDetailPage';
import { UserRoutePage } from './UserRoutePage';
import { VideoPage } from './VideoPage';
import { AuthService } from '../services/AuthService';
import { AppPrefs } from '../services/AppPrefs';
import { ScrollSignal } from '../common/ScrollSignal';
import { UserOpenParam, UserProfile, VideoOpenParam } from '../model/BiliModels';
import {
  HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController, ScrollEffectType, hdsMaterial
} from '@kit.UIDesignKit';
import { LengthMetrics, SymbolGlyphModifier, uiMaterial, window } from '@kit.ArkUI';

/**
 * 页签定义。
 * route 非空表示该页签是「入口型页签」：点击后压入二级页，页签自身不承载内容、也不保留选中态。
 */
class MainTab {
  label: string;
  normalIcon: Resource;
  selectedIcon: Resource;
  route: string;

  constructor(label: string, normalIcon: Resource, selectedIcon: Resource, route: string) {
    this.label = label;
    this.normalIcon = normalIcon;
    this.selectedIcon = selectedIcon;
    this.route = route;
  }
}

const HOME_INDEX: number = 0;
/** 悬浮页签条展开高度（收起时置 0） */
const TAB_BAR_HEIGHT: number = 56;

const MAIN_TABS: Array<MainTab> = [
  new MainTab('首页', $r('sys.symbol.house'), $r('sys.symbol.house_fill'), ''),
  new MainTab('动态', $r('sys.symbol.paperplane'), $r('sys.symbol.paperplane_fill'), ''),
  new MainTab('发布', $r('sys.symbol.plus_circle'), $r('sys.symbol.plus_circle_fill'), 'publish'),
  new MainTab('热门', $r('sys.symbol.flame'), $r('sys.symbol.flame_fill'), ''),
  new MainTab('直播', $r('sys.symbol.dot_radiowaves_left_and_right'),
    $r('sys.symbol.dot_radiowaves_left_and_right'), '')
];

/**
 * 全应用唯一入口页：HdsNavigation 承载路由栈，HdsTabs 承载五大模块。
 * 标题栏由 Index 统一绘制（标题 / 搜索 / 消息 / 头像），页签内容不含标题栏。
 */
@Entry
@Component
struct Index {
  @StorageLink('mainTab') @Watch('onMainTabChanged') currentTab: number = HOME_INDEX;
  @State breakpoint: string = 'sm';
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  @State materialType: hdsMaterial.MaterialType = hdsMaterial.MaterialType.ADAPTIVE;
  @State statusBarH: number = 39;
  @State topInset: number = 95;
  @State scrollersBound: Array<Scroller> = [];
  @State chipMaterialOn: boolean = false;
  @State avatarFace: string = '';
  @StorageLink('loginTick') @Watch('onLoginTick') loginTick: number = 0;
  /** 滚动收起信号（由各页签 List 经 ScrollSignal 写入） */
  @StorageLink('muli_barHidden') @Watch('onBarSignal') barSignal: boolean = false;
  /** 设置里的「底部隐藏」开关 */
  @StorageLink('muli_bottomHide') @Watch('onBottomHidePref') bottomHide: boolean = true;
  @State barHidden: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();
  private tabsController: HdsTabsController = new HdsTabsController();
  private scrollers: Array<Scroller> = [
    new Scroller(), new Scroller(), new Scroller(), new Scroller(), new Scroller()
  ];
  private chipMaterial: uiMaterial.ImmersiveMaterial | undefined = undefined;
  private bpObserver: BreakpointObserver | undefined = undefined;
  /** 最近一次真实页签（入口型页签点击后回退到它） */
  private lastRealTab: number = HOME_INDEX;
  /** 入口型页签拦截期间的选中态回写保护 */
  private intercepting: boolean = false;

  aboutToAppear(): void {
    this.materialLevel = MaterialScope.detectLevel();
    this.materialType = MaterialScope.detectType();
    this.lastRealTab = this.currentTab;
    this.rebindScrollable();
    try {
      this.chipMaterialOn = uiMaterial.isImmersiveMaterialSupported();
      if (this.chipMaterialOn) {
        this.chipMaterial = new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR });
      }
    } catch (err) {
      this.chipMaterialOn = false;
      this.chipMaterial = undefined;
    }
    this.bpObserver = new BreakpointObserver(this.getUIContext().getMediaQuery(), (breakpoint: string) => {
      this.breakpoint = breakpoint;
    });
    this.bpObserver.register();
    this.syncAvoidArea();
    this.refreshAvatar();
    // 应用设置（底部隐藏 / 默认启动页等）先灌进 AppStorage，再按默认启动页切页
    AppPrefs.load(this.getUIContext().getHostContext() as common.UIAbilityContext).then(() => {
      ScrollSignal.enabled = this.bottomHide;
      this.applyStartTab();
    }).catch(() => {
      // 设置读取失败按默认值启动
    });
  }

  /** 按「默认启动页」设置切到对应页签；版块未建立时回退首页 */
  private applyStartTab(): void {
    const startIndex: number = AppStorage.get<number>(AppPrefs.KEY_START_TAB) ?? 0;
    const mainIndex: number = AppPrefs.mainTabOfStart(startIndex);
    this.currentTab = mainIndex;
    this.lastRealTab = mainIndex;
    setTimeout(() => {
      try {
        this.tabsController.changeIndex(mainIndex);
      } catch (err) {
        // lg 布局下控制器可能不可用，忽略
      }
    }, 30);
  }

  private onBarSignal(): void {
    const target: boolean = this.barSignal && this.bottomHide;
    if (target === this.barHidden) {
      return;
    }
    this.barHidden = target;
  }

  private onBottomHidePref(): void {
    ScrollSignal.enabled = this.bottomHide;
    if (!this.bottomHide) {
      this.barHidden = false;
    }
  }

  private onLoginTick(): void {
    this.refreshAvatar();
  }

  /** 标题栏头像：未登录显示占位图标，已登录显示真实头像 */
  private refreshAvatar(): void {
    const profile: UserProfile = AuthService.current();
    if (profile.isLogin && profile.face.length > 0) {
      this.avatarFace = profile.face;
      return;
    }
    if (AuthService.isLogin()) {
      AuthService.loadProfile().then((loaded: UserProfile) => {
        if (loaded.isLogin && loaded.face.length > 0) {
          this.avatarFace = loaded.face;
        }
      }).catch(() => {
        // 资料加载失败时保持占位图标
      });
      return;
    }
    this.avatarFace = '';
  }

  aboutToDisappear(): void {
    if (this.bpObserver !== undefined) {
      this.bpObserver.unregister();
      this.bpObserver = undefined;
    }
  }

  /** 读取系统避让区，换算标题栏所需的顶部留白 */
  private syncAvoidArea(): void {
    const ctx = this.getUIContext().getHostContext();
    window.getLastWindow(ctx).then((win: window.Window) => {
      const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const sb: number = Math.round(this.getUIContext().px2vp(area.topRect.height));
      this.statusBarH = sb;
      this.topInset = sb + 56;
    }).catch(() => {
      // 取不到避让区时保留默认值，标题栏为固定高度
    });
  }

  /** 页签切换后重新绑定可滚动容器，保证标题栏滚动效果对新页签生效 */
  private rebindScrollable(): void {
    this.scrollersBound = this.scrollers.slice();
  }

  private onMainTabChanged(): void {
    if (this.currentTab < 0 || this.currentTab >= MAIN_TABS.length) {
      return;
    }
    if (MAIN_TABS[this.currentTab].route.length > 0) {
      return;
    }
    this.lastRealTab = this.currentTab;
    try {
      this.tabsController.changeIndex(this.currentTab);
    } catch (err) {
      // lg 布局下 TabsController 可能不可用，忽略
    }
  }

  private tabBarStyle(tab: MainTab): BottomTabBarStyle {
    return new BottomTabBarStyle({
      normal: new SymbolGlyphModifier(tab.normalIcon).fontColor([$r('app.color.text_tertiary')]),
      selected: new SymbolGlyphModifier(tab.selectedIcon).fontColor([$r('app.color.brand_primary')])
    }, tab.label)
      .labelStyle({
        selectedColor: $r('app.color.brand_primary'),
        unselectedColor: $r('app.color.text_tertiary')
      });
  }

  private openSearch(): void {
    this.pathStack.pushPathByName('search', '');
  }

  private openMessage(): void {
    this.pathStack.pushPathByName('message', '');
  }

  private openMine(): void {
    this.pathStack.pushPathByName('mine', '');
  }

  /** 把路由参数统一收敛成 VideoOpenParam（兼容未传参的情况） */
  private videoParamOf(param: Object): VideoOpenParam {
    if (param instanceof VideoOpenParam) {
      return param as VideoOpenParam;
    }
    return new VideoOpenParam('', 0, 0);
  }

  /** 我的收藏 / 观看历史 / 稍后再看：参数是 kind 字符串，兜底给收藏 */
  private libraryKindOf(param: Object): string {
    if (param === 'history') {
      return 'history';
    }
    if (param === 'toview') {
      return 'toview';
    }
    return 'fav';
  }

  @Builder
  titleIconButton(icon: Resource, label: string, action: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(TITLE_ICON_SIZE)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(TITLE_ICON_HIT)
    .height(TITLE_ICON_HIT)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.chipMaterialOn ? Color.Transparent : $r('app.color.title_chip_bg'))
    .backgroundBlurStyle(this.chipMaterialOn ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THIN)
    .systemMaterial(this.chipMaterial)
    .borderRadius(20)
    .onClick(() => {
      action();
    })
    .accessibilityText(label)
  }

  @Builder
  searchEntry() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(16)
        .fontColor([$r('app.color.text_tertiary')])
      Text('搜索你感兴趣的内容')
        .fontSize(TITLE_CTRL_TEXT_SIZE - 1)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .height(36)
    .padding({ left: 12, right: 12 })
    .borderRadius(18)
    .backgroundColor(this.chipMaterialOn ? Color.Transparent : $r('app.color.bg_field'))
    .backgroundBlurStyle(this.chipMaterialOn ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THIN)
    .systemMaterial(this.chipMaterial)
    .layoutWeight(1)
    .onClick(() => {
      this.openSearch();
    })
    .accessibilityText('搜索')
  }

  @Builder
  avatarEntry() {
    Row() {
      Stack() {
        if (this.avatarFace.length > 0) {
          Image(this.avatarFace)
            .width(32)
            .height(32)
            .objectFit(ImageFit.Cover)
            .alt($r('app.color.bg_field'))
            .draggable(false)
        } else {
          SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
            .fontSize(22)
            .fontColor([$r('app.color.text_secondary')])
        }
      }
      .width(32)
      .height(32)
      .borderRadius(16)
      .backgroundColor($r('app.color.bg_field'))
      .clip(true)
    }
    .width(TITLE_ICON_HIT)
    .height(TITLE_ICON_HIT)
    .justifyContent(FlexAlign.Center)
    // 与右侧消息 / 搜索图标同款圆形包裹：热区、圆角、底色、材质全部一致，
    // 这样左头像与右图标在标题栏里左右对称、视觉体量相等。
    .backgroundColor(this.chipMaterialOn ? Color.Transparent : $r('app.color.title_chip_bg'))
    .backgroundBlurStyle(this.chipMaterialOn ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THIN)
    .systemMaterial(this.chipMaterial)
    .borderRadius(TITLE_ICON_HIT / 2)
    .onClick(() => {
      this.openMine();
    })
    .accessibilityText('我的')
  }

  @Builder
  titleBarContent() {
    // 左右两侧留白与间距必须恒等，搜索条才会真的居中：
    // 左 = padding 8 + 头像 40 + 间距 8，右 = 间距 8 + 消息 40 + padding 8。
    // 曾经给搜索条单独加 margin 补距离，结果它被推偏了 3vp，这回把间距统一交给 space。
    Row({ space: 8 }) {
      this.avatarEntry()
      if (this.currentTab === HOME_INDEX) {
        this.searchEntry()
      } else {
        Text(MAIN_TABS[this.currentTab].label)
          .fontSize(TITLE_TEXT_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: 2, right: 8 })
        Blank()
        this.titleIconButton($r('sys.symbol.magnifyingglass'), '搜索', () => {
          this.openSearch();
        })
      }
      this.titleIconButton($r('sys.symbol.bell'), '消息', () => {
        this.openMessage();
      })
    }
    .width('100%')
    .height(TITLE_ICON_HIT)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  tabContents() {
    TabContent() {
      HomePage({
        pathStack: this.pathStack,
        scroller: this.scrollers[0],
        topInset: this.topInset,
        breakpoint: this.breakpoint
      })
    }
    .tabBar(this.tabBarStyle(MAIN_TABS[0]))

    TabContent() {
      DynamicPage({
        pathStack: this.pathStack,
        scroller: this.scrollers[1],
        topInset: this.topInset,
        breakpoint: this.breakpoint
      })
    }
    .tabBar(this.tabBarStyle(MAIN_TABS[1]))

    TabContent() {
      // 入口型页签：内容恒为空，点击即压入二级发布页
      Column()
        .width('100%')
        .height('100%')
    }
    .tabBar(this.tabBarStyle(MAIN_TABS[2]))

    TabContent() {
      HotPage({
        pathStack: this.pathStack,
        scroller: this.scrollers[3],
        topInset: this.topInset,
        breakpoint: this.breakpoint
      })
    }
    .tabBar(this.tabBarStyle(MAIN_TABS[3]))

    TabContent() {
      LivePage({
        scroller: this.scrollers[4],
        topInset: this.topInset,
        breakpoint: this.breakpoint
      })
    }
    .tabBar(this.tabBarStyle(MAIN_TABS[4]))
  }

  @Builder
  pageMap(name: string, param: Object) {
    if (name === 'search') {
      SearchPage({
        pathStack: this.pathStack,
        topInset: this.topInset,
        statusBarH: this.statusBarH,
        initialKeyword: this.keywordOf(param)
      })
    } else if (name === 'message') {
      MessagePage({ pathStack: this.pathStack })
    } else if (name === 'mine') {
      MineRoutePage({ pathStack: this.pathStack, topInset: this.topInset, statusBarH: this.statusBarH })
    } else if (name === 'publish') {
      PublishPage({ pathStack: this.pathStack })
    } else if (name === 'login') {
      LoginPage({ pathStack: this.pathStack })
    } else if (name === 'weblogin') {
      WebLoginPage({ pathStack: this.pathStack, mode: param === 'reset' ? 'reset' : '' })
    } else if (name === 'changelog') {
      ChangeLogPage({ pathStack: this.pathStack })
    } else if (name === 'library') {
      LibraryPage({ pathStack: this.pathStack, kind: this.libraryKindOf(param) })
    } else if (name === 'about') {
      AboutPage({ pathStack: this.pathStack })
    } else if (name === 'video') {
      VideoPage({ pathStack: this.pathStack, videoParam: this.videoParamOf(param) })
    } else if (name === 'settings') {
      SettingsPage({ pathStack: this.pathStack })
    } else if (name === 'settings_appearance') {
      SettingsDetailPage({ pathStack: this.pathStack, section: SECTION_APPEARANCE })
    } else if (name === 'settings_player') {
      SettingsDetailPage({ pathStack: this.pathStack, section: SECTION_PLAYER })
    } else if (name === 'settings_playpage') {
      SettingsDetailPage({ pathStack: this.pathStack, section: SECTION_PLAYPAGE })
    } else if (name === 'settings_dynamic') {
      SettingsDetailPage({ pathStack: this.pathStack, section: SECTION_DYNAMIC })
    } else if (name === 'user') {
      UserRoutePage({
        pathStack: this.pathStack, mid: this.midOf(param), topInset: this.topInset, statusBarH: this.statusBarH
      })
    }
  }

  /** 路由参数 → 搜索预置关键词：字符串直传，其余忽略 */
  private keywordOf(param: Object): string {
    if (typeof param === 'string') {
      return param as string;
    }
    return '';
  }

  /** 路由参数 → mid：UserOpenParam 直传，或 number/string 兜底 */
  private midOf(param: Object): number {
    if (param instanceof UserOpenParam) {
      return param.mid;
    }
    if (typeof param === 'number') {
      return param as number;
    }
    if (typeof param === 'string') {
      const value: number = Number(param);
      return Number.isFinite(value) ? value : 0;
    }
    return 0;
  }

  build() {
    Stack() {
      HdsNavigation(this.pathStack) {
        if (this.breakpoint === 'lg') {
          // 平板 / 横屏：页签条立到侧边
          HdsTabs({ controller: this.tabsController }) {
            this.tabContents()
          }
          .vertical(true)
          .barFloatingStyle({
            systemMaterialEffect: {
              materialType: this.materialType,
              materialLevel: this.materialLevel
            }
          })
        } else {
          HdsTabs({ controller: this.tabsController }) {
            this.tabContents()
          }
          .barOverlap(true)
          .vertical(false)
          .barPosition(BarPosition.End)
          // 底部隐藏开启时，上滑把页签条高度收到 0；关闭时恒为常驻高度
          .barHeight(this.barHidden ? 0 : TAB_BAR_HEIGHT)
          .animation({ duration: 180, curve: Curve.Friction })
          .barFloatingStyle({
            barBottomMargin: TAB_BAR_BOTTOM_MARGIN,
            systemMaterialEffect: {
              materialType: this.materialType,
              materialLevel: this.materialLevel
            }
          })
          .onChange((index: number) => {
            this.handleTabChange(index);
          })
        }
      }
      .titleBar({
        content: {
          title: { mainTitle: '' },
          stackBuilder: () => {
            this.titleBarContent();
          }
        },
        style: {
          originalStyle: {
            contentStyle: {
              titleStyle: { mainTitleColor: $r('app.color.text_primary') },
              menuStyle: { iconColor: $r('app.color.text_primary') },
              backIconStyle: { iconColor: $r('app.color.text_primary') }
            }
          },
          scrollEffectStyle: {
            contentStyle: {
              titleStyle: { mainTitleColor: $r('app.color.text_primary') },
              menuStyle: { iconColor: $r('app.color.text_primary') },
              backIconStyle: { iconColor: $r('app.color.text_primary') }
            }
          },
          scrollEffectOpts: {
            enableScrollEffect: true,
            scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
            blurEffectiveStartOffset: LengthMetrics.vp(0),
            blurEffectiveEndOffset: LengthMetrics.vp(64)
          },
          systemMaterialEffect: {
            materialType: this.materialType,
            materialLevel: this.materialLevel
          }
        },
        avoidLayoutSafeArea: false,
        enableComponentSafeArea: false
      })
      .bindToScrollable(this.scrollersBound)
      .id(NAV_ID)
      .hideBackButton(true)
      .titleMode(HdsNavigationTitleMode.MINI)
      .mode(NavigationMode.Stack)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .navDestination(this.pageMap)
      .backgroundColor($r('app.color.bg_page'))
    }
    .alignContent(Alignment.TopStart)
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /** 页签切换总入口：入口型页签压二级页并回退选中态，其余正常切页 */
  private handleTabChange(index: number): void {
    if (this.intercepting) {
      return;
    }
    if (index < 0 || index >= MAIN_TABS.length) {
      return;
    }
    const route: string = MAIN_TABS[index].route;
    if (route.length > 0) {
      const backIndex: number = this.lastRealTab;
      this.intercepting = true;
      this.pathStack.pushPathByName(route, '');
      this.currentTab = backIndex;
      try {
        this.tabsController.changeIndex(backIndex);
      } catch (err) {
        // 忽略：lg 布局下控制器不生效
      }
      setTimeout(() => {
        this.intercepting = false;
      }, 60);
      return;
    }
    this.lastRealTab = index;
    this.currentTab = index;
    ScrollSignal.reset();
    this.rebindScrollable();
  }
}
