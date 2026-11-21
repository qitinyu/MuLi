import { HdsNavDestination, hdsMaterial } from '@kit.UIDesignKit';
import { MaterialScope } from '../common/Materials';
import { TITLE_BAR_HEIGHT } from '../common/DesignSpec';
import { MinePage } from './MinePage';
import { AuthService } from '../services/AuthService';

/** 我的页入场/退场位移（vp）：从左侧屏幕外滑入并向右展开。 */
const MINE_TRANSITION_OFFSET: number = 480;
const MINE_TRANSITION_DURATION: number = 320;
/** 图标视觉尺寸 / 点击热区（与系统标题栏按钮同规格） */
const MENU_ICON_SIZE: number = 21;
const MENU_ICON_HIT: number = 36;

/**
 * 我的页路由壳（V2.0.3）。
 *
 * 版式：与主体页面一致的沉浸标题栏 —— 隐藏系统标题栏与返回键（返回手势/系统返回仍可用），
 * 自绘「我的」标题行，右上角两个图标用系统同款圆形包裹（rotate 更换背景 / off 退出登录）。
 *
 * 背景图要直达系统状态栏，必须让内容区从屏幕顶端开始布局，
 * 因此 hideTitleBar(true) + ignoreLayoutSafeArea(SYSTEM, TOP)（这也正是 HdsNavDestination
 * 下 ignoreLayoutSafeArea 的生效前提）。
 */
@Component
export struct MineRoutePage {
  pathStack: NavPathStack | undefined = undefined;
  /** Index 传入：状态栏高度 + 标题栏高度 */
  @Prop topInset: number = 88;
  /** 状态栏高度（vp）：背景高度按它补齐，标题行按它避让 */
  @Prop statusBarH: number = 32;
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  @State slideX: number = 0;
  @State loggedIn: boolean = false;
  /** 内容是否已滚离顶部：决定标题行用透明还是实底 */
  @State scrolled: boolean = false;
  /** 点「更换背景」图标时自增，MinePage 监听后弹窗 */
  @State coverTick: number = 0;
  /** 点「退出登录」图标时自增，MinePage 监听后登出 */
  @State logoutTick: number = 0;
  @StorageLink('loginTick') @Watch('onLoginTick') loginTick: number = 0;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.materialLevel = MaterialScope.detectLevel();
    this.loggedIn = AuthService.isLogin();
  }

  private onLoginTick(): void {
    this.loggedIn = AuthService.isLogin();
  }

  /** 自定义转场：入场自左向右展开，退场反向收回左侧。 */
  private mineTransition() {
    return [
      {
        duration: MINE_TRANSITION_DURATION,
        curve: Curve.Friction,
        event: () => {
          this.slideX = 0;
        }
      }
    ] as Array<NavDestinationTransition>;
  }

  /** 顶部图标按钮：圆形包裹 + 半透明白底，压在背景图上依然清晰（与系统返回键同规格） */
  @Builder
  iconButton(icon: Resource, tip: string, tap: () => void) {
    Row() {
      // 不设 fillColor：rotate/off 自带黑色描边与填色，
      // fillColor 会把 SVG 里的透明占位 polygon 一起填成实心块。
      Image(icon)
        .width(MENU_ICON_SIZE)
        .height(MENU_ICON_SIZE)
        .objectFit(ImageFit.Contain)
        .draggable(false)
    }
    .width(MENU_ICON_HIT)
    .height(MENU_ICON_HIT)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F2FFFFFF')
    .borderRadius(MENU_ICON_HIT / 2)
    .border({ width: 0.5, color: '#1A000000' })
    .onClick(() => {
      tap();
    })
    .accessibilityText(tip)
  }

  /** 自绘标题行：左侧「我的」，右侧两个图标（不带返回键，避免与标题重叠） */
  @Builder
  titleRow() {
    Row({ space: 8 }) {
      Text('我的')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.scrolled ? $r('app.color.text_primary') : Color.White)
        .textShadow(this.scrolled
          ? { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 }
          : { radius: 6, color: '#66000000', offsetX: 0, offsetY: 1 })
        .maxLines(1)
        .layoutWeight(1)

      this.iconButton($r('app.media.rotate'), '更换背景', () => {
        this.coverTick = Date.now();
      })

      if (this.loggedIn) {
        this.iconButton($r('app.media.off'), '退出登录', () => {
          this.logoutTick = Date.now();
        })
      }
    }
    .width('100%')
    .height(TITLE_BAR_HEIGHT)
    .padding({ left: 16, right: 12 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        MinePage({
          pathStack: this.pathStack,
          scroller: this.scroller,
          topInset: this.statusBarH,
          breakpoint: 'sm',
          scrolled: $scrolled,
          coverTick: $coverTick,
          logoutTick: $logoutTick
        })

        // 标题行浮在背景图之上：
        // - 未滚动时整条透明，只在顶部叠一层很淡的压暗渐变，保证白字可读（背景图直达状态栏）；
        // - 内容滚过封面、标题栏下方已是白色内容区之后才转实底，
        //   此时底色与下方内容同色，视觉上不会出现「浮在图片上的白色卡片」。
        Column()
          .width('100%')
          .height(this.statusBarH + TITLE_BAR_HEIGHT + 24)
          .linearGradient({
            angle: 180,
            colors: [['#4D000000', 0.0], ['#00000000', 1.0]]
          })
          .opacity(this.scrolled ? 0 : 1)
          .animation({ duration: 220, curve: Curve.EaseOut })
          .hitTestBehavior(HitTestMode.None)

        Column() {
          Row()
            .width('100%')
            .height(this.statusBarH)
          this.titleRow()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .backgroundColor(this.scrolled ? $r('app.color.bg_page') : Color.Transparent)
        .animation({ duration: 220, curve: Curve.EaseOut })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP])
    .bindToScrollable([this.scroller])
    .backgroundColor($r('app.color.bg_page'))
    .translate({ x: this.slideX })
    .customTransition((operation: NavigationOperation, isEnter: boolean) => {
      this.slideX = isEnter ? -MINE_TRANSITION_OFFSET : 0;
      return isEnter ? this.mineTransition() :
        [
          {
            duration: MINE_TRANSITION_DURATION,
            curve: Curve.Friction,
            event: () => {
              this.slideX = -MINE_TRANSITION_OFFSET;
            }
          }
        ] as Array<NavDestinationTransition>;
    })
  }
}
