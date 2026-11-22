import { emptyVideoCard, VideoCard } from '../model/BiliModels';
import { PAGE_PADDING } from '../common/DesignSpec';
import { durationText, pubDateText } from '../common/Format';
import { AppPrefs } from '../services/AppPrefs';

/**
 * 视频卡片（推荐流 / 排行榜共用）。
 *
 * 统一的「三行信息」结构（V2.0.3）：
 *   a. 标题（单行，超出省略）
 *   b. 竖屏标记（仅竖屏视频）+ 播放量 + 弹幕数
 *   c. 已关注标记 + UP 主名 + 发布日期 yy/MM/dd + 更多三点（占位）
 * 封面保留角标（排行榜名次 / 推荐理由）与右下角时长。
 *
 * V2.0.5：UP 名可能很长，「已关注」标记挪到名字前面，免得被长名挤到右边界之外；
 * 长名处理方式跟随「外观 · 通用设置 → UP 主过长名称」（省略号 / 循环滚动）。
 *
 * compact = true 用于 2×N / 自适应多列布局：去掉左右内边距、整体字号降一级，
 * 由外层 Row 统一给列间距，避免双列时留白过大。
 */
@Component
export struct VideoCardView {
  @Prop card: VideoCard = emptyVideoCard();
  /** 多列紧凑模式 */
  @Prop compact: boolean = false;
  /** 0 = 过长隐藏，1 = 循环滚动（设置页写入，这里订阅即时生效） */
  @StorageLink(AppPrefs.KEY_AUTHOR_NAME_MODE) authorNameMode: number = 0;
  /** 点击卡片：进入播放页 */
  onCardTap: (card: VideoCard) => void = () => {
  };
  /** 点击「更多」：多操作菜单占位 */
  onMoreTap: (card: VideoCard) => void = () => {
  };

  private titleSize(): number {
    return this.compact ? 13 : 14;
  }

  private subSize(): number {
    return this.compact ? 10 : 11;
  }

  private authorText(): string {
    return this.card.author.length > 0 ? this.card.author : '未知 UP';
  }

  build() {
    Column() {
      // 封面容器自身定死 16:9：若把比例给 Image、而角标层又是 height('100%')，
      // Stack 会自动尺寸化并与百分比子层互相等待，实测会把封面压成 5.5:1 的扁条。
      Stack({ alignContent: Alignment.Bottom }) {
        Image(this.card.cover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(this.compact ? 8 : 10)
          .alt($r('app.color.bg_field'))
          .draggable(false)

        // 角标（排行榜名次 / 推荐理由）：左上角
        Column() {
          if (this.card.cornerText.length > 0) {
            Text(this.card.cornerText)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_on_brand'))
              .padding({ left: 7, right: 7, top: 2, bottom: 2 })
              .backgroundColor(this.isRankCorner() ? $r('app.color.brand_primary') : $r('app.color.scrim'))
              .borderRadius(6)
              .maxLines(1)
          }
          Blank()
        }
        .width('100%')
        .height('100%')
        .padding(8)
        .alignItems(HorizontalAlign.Start)
        .hitTestBehavior(HitTestMode.Transparent)

        // 右下角时长：播放量已挪到第二行，这里只留时长避免重复
        Row() {
          Blank()
          if (this.card.duration > 0) {
            Text(durationText(this.card.duration))
              .fontSize(11)
              .fontColor($r('app.color.text_on_media'))
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .backgroundColor($r('app.color.scrim'))
              .borderRadius(4)
          }
        }
        .width('100%')
        .padding({ left: 8, right: 8, bottom: 7 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .aspectRatio(16 / 9)
      .clip(true)
      .onClick(() => {
        this.onCardTap(this.card);
      })

      // a. 标题
      Text(this.card.title)
        .fontSize(this.titleSize())
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(this.compact ? 19 : 20)
        .width('100%')
        .margin({ top: this.compact ? 6 : 8 })
        .onClick(() => {
          this.onCardTap(this.card);
        })

      // b. 竖屏提示 + 播放量 + 弹幕数
      Row({ space: 5 }) {
        if (this.card.vertical) {
          Text('竖屏')
            .fontSize(9)
            .fontColor($r('app.color.brand_primary'))
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.brand_tint'))
            .borderRadius(3)
        }
        if (this.card.viewText.length > 0) {
          Text(this.card.viewText)
            .fontSize(this.subSize())
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
        }
        if (this.card.danmuText.length > 0) {
          Text('·')
            .fontSize(this.subSize())
            .fontColor($r('app.color.text_tertiary'))
          Text(this.card.danmuText)
            .fontSize(this.subSize())
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .layoutWeight(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .margin({ top: 3 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.onCardTap(this.card);
      })

      // c. 已关注标记 + UP 主 + 发布日期 + 更多
      Row() {
        Row({ space: this.compact ? 3 : 4 }) {
          // 标记放最前：UP 名再长也挤不掉它
          if (this.card.followed) {
            Text('已关注')
              .fontSize(9)
              .fontColor($r('app.color.brand_primary'))
              .padding({ left: 3, right: 3, top: 1, bottom: 1 })
              .border({ width: 0.5, color: $r('app.color.brand_line') })
              .borderRadius(3)
              .flexShrink(0)
          }

          if (this.authorNameMode === 1) {
            // 循环滚动：只要名字比可用宽度长就自己滚，「已关注」不会跟着动
            Marquee({
              start: true,
              step: 4,
              loop: -1,
              fromStart: true,
              src: this.authorText()
            })
              .fontSize(this.subSize())
              .fontColor($r('app.color.text_tertiary'))
              .height(this.compact ? 15 : 16)
              .layoutWeight(1)
              .margin({ right: 2 })
          } else {
            Text(this.authorText())
              .fontSize(this.subSize())
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }

          if (this.card.pubTs > 0) {
            Text(pubDateText(this.card.pubTs))
              .fontSize(this.subSize())
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .flexShrink(0)
          }
        }
        .layoutWeight(1)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onCardTap(this.card);
        })

        // 三点是独立热区：只弹更多操作，不进播放页（父级不再整体挂 click，靠分区点击）
        Row() {
          Image($r('app.media.mlist'))
            .width(this.compact ? 15 : 16)
            .height(this.compact ? 15 : 16)
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.text_tertiary'))
            .draggable(false)
        }
        .width(this.compact ? 20 : 22)
        .height(this.compact ? 20 : 22)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.onMoreTap(this.card);
        })
      }
      .width('100%')
      .margin({ top: 4 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(this.compact
      ? { left: 0, right: 0 }
      : { left: PAGE_PADDING, right: PAGE_PADDING })
    .margin({ bottom: this.compact ? 14 : 16 })
    .alignItems(HorizontalAlign.Start)
  }

  private isRankCorner(): boolean {
    const text: string = this.card.cornerText;
    if (text.length === 0 || text.length > 3) {
      return false;
    }
    for (let i = 0; i < text.length; i++) {
      const code: number = text.charCodeAt(i);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    return true;
  }
}
