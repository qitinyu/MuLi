import { HdsNavDestination, hdsMaterial } from '@kit.UIDesignKit';
import { MaterialScope } from '../common/Materials';
import { TITLE_BAR_HEIGHT } from '../common/DesignSpec';
import { UserPage } from './UserPage';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';

/** 出场位移（vp）：与他人主页的入场方向相反，从右侧滑入 */
const USER_TRANSITION_OFFSET: number = 480;
const USER_TRANSITION_DURATION: number = 320;
/** 图标视觉尺寸 / 点击热区（与系统标题栏按钮同规格） */
const MENU_ICON_SIZE: number = 21;
const MENU_ICON_HIT: number = 36;

/**
 * 其他用户主页路由壳（V2.1.2）。
 *
 * 与 MineRoutePage 同一套做法：隐藏系统标题栏 + 忽略顶部安全区，让背景图直达状态栏，
 * 标题行自绘 —— 左侧返回键、中间用户昵称（资料到位后由 UserPage 回填）。
 *
 * 与我的页的差别：这里是「进入别人的页面」，所以入场自右向左，并保留返回键。
 *
 * 标题行细节：
 * - 返回键用 sys.symbol.chevron_backward —— 系统符号库里没有 chevron_left，
 *   引用不存在的资源会渲染成空白，看上去就是「纯白底色的方块」。
 * - 右上角两个按钮：搜索该 UP 主的视频、mlist 更多（分享主页 / 加入小黑屋 / 举报）。
 */
@Component
export struct UserRoutePage {
  pathStack: NavPathStack | undefined = undefined;
  @Prop mid: number = 0;
  /** Index 传入：状态栏高度 + 标题栏高度 */
  @Prop topInset: number = 88;
  /** 状态栏高度（vp） */
  @Prop statusBarH: number = 32;
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  @State slideX: number = 0;
  @State scrolled: boolean = false;
  @State userName: string = '';
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.materialLevel = MaterialScope.detectLevel();
  }

  private goBack(): void {
    if (this.pathStack !== undefined) {
      this.pathStack.pop();
    }
  }

  private toast(text: string): void {
    this.getUIContext().getPromptAction().showToast({ message: text, duration: 1600 });
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 搜索该 UP 主的视频：带昵称进搜索页，搜索页首屏直接出结果 */
  private searchThisUser(): void {
    if (this.pathStack === undefined) {
      return;
    }
    if (this.userName.length === 0) {
      this.toast('昵称还没加载好，稍后再试');
      return;
    }
    this.pathStack.pushPathByName('search', this.userName);
  }

  /** 分享 UP 主主页 */
  private async shareSpace(): Promise<void> {
    const url: string = `https://space.bilibili.com/${this.mid}`;
    const title: string = this.userName.length > 0 ? `${this.userName} 的个人主页` : 'UP 主主页';
    try {
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        title: title,
        content: url
      };
      const data: systemShare.SharedData = new systemShare.SharedData(record);
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      await controller.show(this.context(), {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
    } catch (err) {
      try {
        const paste: pasteboard.PasteData =
          pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
        await pasteboard.getSystemPasteboard().setData(paste);
        this.toast('链接已复制，可粘贴分享');
      } catch (nested) {
        this.toast('分享未完成，请手动分享');
      }
    }
  }

  private userTransition() {
    return [
      {
        duration: USER_TRANSITION_DURATION,
        curve: Curve.Friction,
        event: () => {
          this.slideX = 0;
        }
      }
    ] as Array<NavDestinationTransition>;
  }

  @Builder
  glyphButton(icon: Resource, tip: string, tap: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(MENU_ICON_SIZE)
        .fontColor([this.scrolled ? $r('app.color.text_primary') : Color.White])
    }
    .width(MENU_ICON_HIT)
    .height(MENU_ICON_HIT)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.scrolled ? $r('app.color.bg_field') : '#F2FFFFFF')
    .borderRadius(MENU_ICON_HIT / 2)
    .border({ width: 0.5, color: '#1A000000' })
    .onClick(() => {
      tap();
    })
    .accessibilityText(tip)
  }

  @Builder
  backButton(tap: () => void) {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_backward'))
        .fontSize(MENU_ICON_SIZE)
        .fontColor([this.scrolled ? $r('app.color.text_primary') : Color.White])
    }
    .width(MENU_ICON_HIT)
    .height(MENU_ICON_HIT)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.scrolled ? $r('app.color.bg_field') : '#F2FFFFFF')
    .borderRadius(MENU_ICON_HIT / 2)
    .border({ width: 0.5, color: '#1A000000' })
    .onClick(() => {
      tap();
    })
    .accessibilityText('返回')
  }

  @Builder
  titleRow() {
    Row({ space: 8 }) {
      this.backButton(() => {
        this.goBack();
      })

      Text(this.userName.length > 0 ? this.userName : '个人主页')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.scrolled ? $r('app.color.text_primary') : Color.White)
        .textShadow(this.scrolled
          ? { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 }
          : { radius: 6, color: '#66000000', offsetX: 0, offsetY: 1 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      this.glyphButton($r('sys.symbol.magnifyingglass'), '搜索该 UP 主的视频', () => {
        this.searchThisUser();
      })

      // 更多：分享主页 / 加入小黑屋 / 举报（后两项按需求先做占位）
      Row() {
        Image($r('app.media.mlist'))
          .width(MENU_ICON_SIZE)
          .height(MENU_ICON_SIZE)
          .objectFit(ImageFit.Contain)
          .draggable(false)
          .fillColor(this.scrolled ? $r('app.color.text_primary') : Color.White)
      }
      .width(MENU_ICON_HIT)
      .height(MENU_ICON_HIT)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.scrolled ? $r('app.color.bg_field') : '#F2FFFFFF')
      .borderRadius(MENU_ICON_HIT / 2)
      .border({ width: 0.5, color: '#1A000000' })
      .bindMenu([
        {
          value: '分享 UP 主主页',
          action: () => {
            this.shareSpace();
          }
        },
        {
          value: '加入小黑屋',
          action: () => {
            this.toast('加入小黑屋：待接入');
          }
        },
        {
          value: '举报违规 UP',
          action: () => {
            this.toast('举报：待接入');
          }
        }
      ])
      .accessibilityText('更多')
    }
    .width('100%')
    .height(TITLE_BAR_HEIGHT)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        UserPage({
          pathStack: this.pathStack,
          scroller: this.scroller,
          topInset: this.statusBarH,
          breakpoint: 'sm',
          mid: this.mid,
          scrolled: $scrolled,
          onLoaded: (name: string) => {
            this.userName = name;
          }
        })

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
      this.slideX = isEnter ? USER_TRANSITION_OFFSET : 0;
      return isEnter ? this.userTransition() :
        [
          {
            duration: USER_TRANSITION_DURATION,
            curve: Curve.Friction,
            event: () => {
              this.slideX = USER_TRANSITION_OFFSET;
            }
          }
        ] as Array<NavDestinationTransition>;
    })
  }
}