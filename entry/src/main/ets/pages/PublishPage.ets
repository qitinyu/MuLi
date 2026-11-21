import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { MaterialScope } from '../common/Materials';
import { PlaceholderPanel } from '../components/PlaceholderPanel';

/**
 * 发布页（二级页，全局路由 name = 'publish'）。
 * 由底部页签「发布」点击后压栈进入，属于入口型页签，不与任何页签内容绑定。
 */
@Component
export struct PublishPage {
  pathStack: NavPathStack | undefined = undefined;
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.materialLevel = MaterialScope.detectLevel();
  }

  @Builder
  entryTile(icon: Resource, label: string, note: string) {
    Column({ space: 10 }) {
      Row() {
        SymbolGlyph(icon)
          .fontSize(26)
          .fontColor([$r('app.color.brand_primary')])
      }
      .width(56)
      .height(56)
      .borderRadius(18)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.brand_tint'))

      Text(label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))

      Text(note)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(2)
        .textAlign(TextAlign.Center)
    }
    .layoutWeight(1)
    .padding({ top: 18, bottom: 18 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.getUIContext().getPromptAction().showToast({ message: `${label}：待建设` });
    })
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Row()
            .width('100%')
            .height(64)
          Row({ space: 10 }) {
            this.entryTile($r('sys.symbol.video'), '投稿视频', '选择稿件上传')
            this.entryTile($r('sys.symbol.square_and_pencil'), '发动态', '图文与视频动态')
          }
          .width('100%')
          Row({ space: 10 }) {
            this.entryTile($r('sys.symbol.film'), '发专栏', '长文编辑器')
            this.entryTile($r('sys.symbol.dot_radiowaves_left_and_right'), '开直播', '推流与开播设置')
          }
          .width('100%')
          PlaceholderPanel({
            title: '发布流程',
            note: '稿件上传、封面裁剪与分区选择待接入创作中心接口',
            icon: $r('sys.symbol.plus_circle'),
            panelHeight: 260
          })
          Row()
            .width('100%')
            .height(40)
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .titleBar({
      content: {
        title: { mainTitle: '发布' }
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
    .bindToScrollable([this.scroller])
    .backgroundColor($r('app.color.bg_page'))
  }
}
