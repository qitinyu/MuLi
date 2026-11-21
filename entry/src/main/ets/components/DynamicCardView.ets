import { DynamicCard, emptyDynamicCard, emptyVideoCard, VideoCard } from '../model/BiliModels';
import { PAGE_PADDING } from '../common/DesignSpec';

/** 动态主体里的视频小卡（横向：封面在左，标题/作者在右） */
@Component
struct DynamicVideoBlock {
  @Prop video: VideoCard = emptyVideoCard();

  build() {
    Row({ space: 8 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Image(this.video.cover)
          .width(120)
          .height(76)
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
          .alt($r('app.color.bg_field'))
          .draggable(false)
        if (this.video.cornerText.length > 0) {
          Text(this.video.cornerText)
            .fontSize(10)
            .fontColor($r('app.color.text_on_media'))
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.scrim'))
            .borderRadius(4)
            .margin({ right: 5, bottom: 5 })
        }
      }

      Column({ space: 6 }) {
        Text(this.video.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Start)
        Row({ space: 6 }) {
          if (this.video.viewText.length > 0) {
            Text(this.video.viewText)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          if (this.video.danmuText.length > 0) {
            Text(this.video.danmuText)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .padding(8)
    .backgroundColor($r('app.color.bg_field'))
    .borderRadius(10)
    .margin({ top: 8 })
    .alignItems(VerticalAlign.Top)
  }
}

/**
 * 动态卡片：作者行 → 正文（最多 6 行）→ 内容（视频 / 九宫格图）→ 互动计数。
 * 转发动态额外显示被转发作者名。
 */
@Component
export struct DynamicCardView {
  @Prop card: DynamicCard = emptyDynamicCard();
  onCardTap: (card: DynamicCard) => void = () => {
  };

  build() {
    Column() {
      Row({ space: 8 }) {
        if (this.card.authorFace.length > 0) {
          Image(this.card.authorFace)
            .width(36)
            .height(36)
            .borderRadius(18)
            .objectFit(ImageFit.Cover)
            .alt($r('app.color.bg_field'))
            .draggable(false)
        } else {
          Circle()
            .width(36)
            .height(36)
            .fill($r('app.color.bg_field'))
        }
        Column({ space: 3 }) {
          Text(this.card.authorName)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.card.pubText)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.card.repostName.length > 0) {
        Text(`转发自 ${this.card.repostName}`)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 6 })
      }

      if (this.card.text.length > 0) {
        Text(this.card.text)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .maxLines(6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(20)
          .width('100%')
          .margin({ top: 8 })
          .textAlign(TextAlign.Start)
      }

      if (this.card.kind === 'video' && this.card.video !== null) {
        DynamicVideoBlock({ video: this.card.video })
      } else if (this.card.kind === 'pics' && this.card.pics.length > 0) {
        this.picGrid()
      }

      Row({ space: 18 }) {
        this.statItem($r('sys.symbol.heart'), this.card.likeText)
        this.statItem($r('sys.symbol.ellipsis_message'), this.card.commentText)
        this.statItem($r('sys.symbol.arrowshape_turn_up_right'), this.card.forwardText)
      }
      .width('100%')
      .margin({ top: 10 })
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .padding(12)
    .margin({ left: PAGE_PADDING, right: PAGE_PADDING, bottom: 10 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(14)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.onCardTap(this.card);
    })
  }

  @Builder
  picGrid() {
    if (this.card.pics.length === 1) {
      Image(this.card.pics[0])
        .width('62%')
        .aspectRatio(4 / 3)
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .alt($r('app.color.bg_field'))
        .draggable(false)
        .margin({ top: 8 })
    } else {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.card.pics.slice(0, 9), (url: string) => {
          Image(url)
            .width('31%')
            .aspectRatio(1)
            .objectFit(ImageFit.Cover)
            .borderRadius(8)
            .alt($r('app.color.bg_field'))
            .draggable(false)
            .margin({ right: '3.5%', top: 6 })
        }, (url: string, index: number) => `${index}-${url}`)
      }
      .width('100%')
      .margin({ top: 2 })
    }
  }

  @Builder
  statItem(icon: Resource, text: string) {
    Row({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(14)
        .fontColor([$r('app.color.text_tertiary')])
      Text(text.length > 0 ? text : '0')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
    }
    .alignItems(VerticalAlign.Center)
  }
}