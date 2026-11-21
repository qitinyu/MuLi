import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { MaterialScope } from '../common/Materials';
import { PlaceholderPanel } from '../components/PlaceholderPanel';

/** 消息页（二级页，全局路由 name = 'message'）：回复/at/点赞/系统通知四类入口。 */
@Component
export struct MessagePage {
  pathStack: NavPathStack | undefined = undefined;
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  private scroller: Scroller = new Scroller();
  private entries: Array<string> = ['回复我的', '@我的', '收到的赞', '系统通知'];

  aboutToAppear(): void {
    this.materialLevel = MaterialScope.detectLevel();
  }

  @Builder
  categoryGrid() {
    Row({ space: 10 }) {
      ForEach(this.entries, (item: string) => {
        Column({ space: 8 }) {
          Row() {
            SymbolGlyph($r('sys.symbol.bell'))
              .fontSize(22)
              .fontColor([$r('app.color.brand_primary')])
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.brand_tint'))

          Text(item)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
      }, (item: string) => item)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(16)
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 12 }) {
          Row()
            .width('100%')
            .height(64)
          this.categoryGrid()
          PlaceholderPanel({
            title: '消息中心',
            note: '私信会话与通知列表待接入 msgfeed 接口',
            icon: $r('sys.symbol.ellipsis_message'),
            panelHeight: 320
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
        title: { mainTitle: '消息' }
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
