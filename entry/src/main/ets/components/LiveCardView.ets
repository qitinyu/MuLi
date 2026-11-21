import { emptyLiveCard, LiveCard } from '../model/BiliModels';
import { PAGE_PADDING } from '../common/DesignSpec';

/**
 * 直播卡片：封面（16:10）+ 左上角「直播中」标识 + 左下角人气 + 标题 + 主播行。
 * 直播封面比例与视频不同，单独成组件避免视频卡片被条件分支污染。
 */
@Component
export struct LiveCardView {
  @Prop card: LiveCard = emptyLiveCard();
  onCardTap: (card: LiveCard) => void = () => {
  };

  build() {
    Column() {
      // 同 VideoCardView：比例给容器而不是 Image，避免百分比子层把容器压扁
      Stack({ alignContent: Alignment.TopStart }) {
        Image(this.card.cover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(10)
          .alt($r('app.color.bg_field'))
          .draggable(false)

        // 左上角直播中标识
        Row({ space: 3 }) {
          Circle()
            .width(5)
            .height(5)
            .fill($r('app.color.text_on_brand'))
          Text('直播中')
            .fontSize(10)
            .fontColor($r('app.color.text_on_brand'))
        }
        .padding({ left: 6, right: 6, top: 3, bottom: 3 })
        .backgroundColor($r('app.color.brand_primary'))
        .borderRadius(6)
        .margin({ left: 8, top: 8 })

        // 左下角人气
        Column() {
          Blank()
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.flame_fill'))
              .fontSize(11)
              .fontColor([$r('app.color.text_on_media')])
            Text(this.card.onlineText)
              .fontSize(11)
              .fontColor($r('app.color.text_on_media'))
              .maxLines(1)
          }
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor($r('app.color.scrim'))
          .borderRadius(4)
        }
        .width('100%')
        .height('100%')
        .padding(8)
        .alignItems(HorizontalAlign.Start)
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .aspectRatio(16 / 10)
      .clip(true)

      Text(this.card.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(20)
        .width('100%')
        .margin({ top: 8 })

      Row({ space: 6 }) {
        if (this.card.face.length > 0) {
          Image(this.card.face)
            .width(18)
            .height(18)
            .borderRadius(9)
            .objectFit(ImageFit.Cover)
            .alt($r('app.color.bg_field'))
            .draggable(false)
        }
        Text(this.card.uname)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.card.areaName.length > 0) {
          Text(this.card.areaName)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
        }
      }
      .width('100%')
      .margin({ top: 6 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
    .margin({ bottom: 16 })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onCardTap(this.card);
    })
  }
}