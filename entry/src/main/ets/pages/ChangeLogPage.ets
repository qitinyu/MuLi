import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { MaterialScope } from '../common/Materials';
import { CARD_RADIUS, PAGE_PADDING } from '../common/DesignSpec';
import { CHANGELOG, ChangeLogEntry } from '../common/Changelog';

/**
 * 更新日志（二级路由 name = 'changelog'，入口在「我的 → 更新日志」）。
 *
 * 形态：小卡片折叠列表 —— 左侧版本号（当前版本带标签）、右侧展开箭头，
 * 点击卡片就地展开该版本的具体内容，默认展开当前版本。
 */
@Component
export struct ChangeLogPage {
  pathStack: NavPathStack | undefined = undefined;
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  /** 当前展开的卡片下标，-1 表示全部收起 */
  @State expanded: number = 0;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.materialLevel = MaterialScope.detectLevel();
  }

  private toggle(index: number): void {
    this.expanded = this.expanded === index ? -1 : index;
  }

  @Builder
  entryCard(entry: ChangeLogEntry, index: number) {
    Column() {
      Row({ space: 8 }) {
        Text(`V${entry.version}`)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.expanded === index
            ? $r('app.color.brand_primary') : $r('app.color.text_primary'))

        if (entry.current) {
          Text('当前版本')
            .fontSize(9)
            .fontColor($r('app.color.brand_primary'))
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.brand_tint'))
            .borderRadius(4)
        }

        Blank()

        Text(entry.date)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))

        SymbolGlyph(this.expanded === index
          ? $r('sys.symbol.chevron_up')
          : $r('sys.symbol.chevron_down'))
          .fontSize(13)
          .fontColor([$r('app.color.text_tertiary')])
          .margin({ left: 2 })
      }
      .width('100%')
      .height(50)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.toggle(index);
      })

      if (this.expanded === index) {
        Column({ space: 8 }) {
          ForEach(entry.items, (item: string) => {
            Row({ space: 7 }) {
              Row()
                .width(4)
                .height(4)
                .borderRadius(2)
                .backgroundColor($r('app.color.brand_soft'))
                .margin({ top: 7 })
              Text(item)
                .fontSize(12)
                .lineHeight(19)
                .fontColor($r('app.color.text_secondary'))
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }, (item: string, i: number) => `${entry.version}_${i}`)
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 14 })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 10 }) {
          Row()
            .width('100%')
            .height(64)

          ForEach(CHANGELOG, (entry: ChangeLogEntry, index: number) => {
            this.entryCard(entry, index)
          }, (entry: ChangeLogEntry) => entry.version)

          Text('沐哩 MuLi · 更新日志按版本倒序排列')
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
        title: { mainTitle: '更新日志' }
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
