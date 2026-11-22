import { HdsNavDestination, HdsNavDestinationTitleMode, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { bundleManager } from '@kit.AbilityKit';
import { MaterialScope } from '../common/Materials';
import { CARD_RADIUS, PAGE_PADDING } from '../common/DesignSpec';
import { AuthService, AuthDiagLine } from '../services/AuthService';

/**
 * 关于沐哩（二级路由 name = 'about'，入口在「我的 → 关于沐哩」）。
 *
 * 除了版本信息，这里是**登录诊断**的落点：登录态出问题时，
 * 「已登录但一排 0」这句话本身没有信息量，需要把
 * cookie / nav / myinfo / 公开资料 四项的实际返回码摊开看。
 */
@Component
export struct AboutPage {
  pathStack: NavPathStack | undefined = undefined;
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  @State version: string = '2.0.7';
  @State running: boolean = false;
  @State diagnosed: boolean = false;
  @State lines: Array<AuthDiagLine> = [];
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.materialLevel = MaterialScope.detectLevel();
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      if (info.versionName.length > 0) {
        this.version = info.versionName;
      }
    } catch (err) {
      // 取不到就用内置版本号
    }
  }

  private async runDiagnose(): Promise<void> {
    if (this.running) {
      return;
    }
    this.running = true;
    this.lines = [];
    try {
      const result: Array<AuthDiagLine> = await AuthService.diagnose();
      this.lines = result;
      this.diagnosed = true;
    } catch (err) {
      this.lines = [];
      this.diagnosed = true;
    } finally {
      this.running = false;
    }
  }

  @Builder
  headerCard() {
    Row({ space: 12 }) {
      Image($r('app.media.app_logo'))
        .width(56)
        .height(56)
        .borderRadius(14)
        .objectFit(ImageFit.Cover)
        .draggable(false)

      Column({ space: 4 }) {
        Text('沐哩 MuLi')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(`版本 ${this.version}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
        Text('第三方哔哩哔哩客户端 · 仅用于学习与个人体验')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  diagRow(line: AuthDiagLine) {
    Row({ space: 8 }) {
      Row()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(line.ok ? $r('app.color.success') : $r('app.color.danger'))
        .margin({ top: 6 })
      Column({ space: 2 }) {
        Text(line.label)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
        Text(line.value)
          .fontSize(11)
          .lineHeight(17)
          .fontColor($r('app.color.text_tertiary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  diagCard() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .fontColor([$r('app.color.brand_primary')])
        Text('账号诊断')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.running ? '检测中…' : (this.diagnosed ? '重新检测' : '开始检测'))
          .fontSize(12)
          .fontColor($r('app.color.brand_primary'))
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor($r('app.color.brand_tint'))
          .borderRadius(12)
          .onClick(() => {
            this.runDiagnose();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.lines.length > 0) {
        Column({ space: 10 }) {
          ForEach(this.lines, (line: AuthDiagLine) => {
            this.diagRow(line)
          }, (line: AuthDiagLine) => line.label)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        Text('检测 cookie、nav、myinfo 与公开资料四个环节的实际返回码，用于定位「显示已登录却没有数据」。')
          .fontSize(11)
          .lineHeight(17)
          .fontColor($r('app.color.text_tertiary'))
      }

      Text('诊断只读取接口返回码与 cookie 字段名，不会上传或展示凭据内容。')
        .fontSize(10)
        .lineHeight(15)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  infoCard() {
    Column({ space: 10 }) {
      Text('本应用所有内容均来自哔哩哔哩公开接口，版权归原作者与平台所有；' +
        '登录态仅保存在本机，不经过任何第三方服务器。')
        .fontSize(11)
        .lineHeight(17)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 10 }) {
          Row()
            .width('100%')
            .height(12)

          this.headerCard()
          this.diagCard()
          this.infoCard()

          Text('沐哩 MuLi · 非官方客户端')
            .width('100%')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Center)
            .margin({ top: 14, bottom: 40 })
        }
        .width('100%')
        .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .titleBar({
      content: {
        title: { mainTitle: '关于沐哩' }
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
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: this.materialLevel
        }
      }
    })
    .hideBackButton(false)
    // 固定 mini 标题栏：默认的展开态会在内容上方留出一大片空白
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.scroller])
    .backgroundColor($r('app.color.bg_page'))
  }
}
