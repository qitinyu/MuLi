import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { MaterialScope } from '../common/Materials';
import { CARD_RADIUS, PAGE_PADDING } from '../common/DesignSpec';

/** 一级总览卡片与二级页的路由名（三个细则页共用 SettingsDetailPage，按 section 区分） */
const ROUTE_APPEARANCE: string = 'settings_appearance';
const ROUTE_PLAYER: string = 'settings_player';
const ROUTE_PLAYPAGE: string = 'settings_playpage';

/**
 * 设置一级总览页（V2.0.5），入口在「我的 → 沐哩设置」。
 *
 * 只做「目录」：竖排三张卡片（外观 · 通用设置 / 播放器 / 播放页 · List 分区），
 * 点进去才是细则页。这样设置项再怎么加，一级页也只有三行，不会越滚越长。
 * 卡片整行左对齐铺满，不做居中排布。
 */
@Component
export struct SettingsPage {
  pathStack: NavPathStack | undefined = undefined;
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.materialLevel = MaterialScope.detectLevel();
  }

  private open(route: string): void {
    if (this.pathStack === undefined) {
      return;
    }
    this.pathStack.pushPathByName(route, '');
  }

  /** 总览卡片：图标 + 标题 + 一句话说明 + 右箭头，整行可点 */
  @Builder
  entryCard(icon: Resource, title: string, summary: string, route: string) {
    Row({ space: 12 }) {
      Row() {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([$r('app.color.brand_primary')])
      }
      .width(38)
      .height(38)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.brand_tint'))
      .borderRadius(12)

      Column({ space: 4 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
        Text(summary)
          .fontSize(11)
          .lineHeight(16)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('app.color.text_tertiary')])
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.open(route);
    })
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 10 }) {
          Row()
            .width('100%')
            .height(64)

          this.entryCard($r('sys.symbol.paintbrush'), '外观 · 通用设置',
            '底部隐藏、默认启动页、UP 主过长名称、播放区顶部沉浸与增量颜色', ROUTE_APPEARANCE)

          this.entryCard($r('sys.symbol.play_circle'), '播放器',
            '默认清晰度、播放行为、过滤词、推荐与推荐页卡片布局', ROUTE_PLAYER)

          this.entryCard($r('sys.symbol.list_bullet'), '播放页 · List 分区',
            '显示 List、跟随界面移动隐藏、首页分区勾选', ROUTE_PLAYPAGE)

          Text('沐哩 MuLi  V2.0.9')
            .width('100%')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Center)
            .margin({ top: 24, bottom: 40 })
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
        title: { mainTitle: '设置' }
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
