import { DynamicCard, emptyDynamicCard, VideoCard } from '../model/BiliModels';
import { shortCount } from '../common/Format';
import { AppPrefs } from '../services/AppPrefs';

/** 封面卡内部压暗高度比例 */
const COVER_SCRIM_HEIGHT: string = '46%';

/**
 * 动态卡片（V2.1.2 改版）。
 *
 * 视频动态改成「大封面卡」：
 *   上部分 —— 封面卡内部底边同一行：时长、播放量、弹幕、点赞数；
 *   下部分 —— 封面卡之外：视频名称一行，再一行点赞（带数）/ 评论 / 转发 / 分享。
 * 图片与纯文字动态保持原排版，只把底部统计换成同一套可点按钮。
 *
 * 整卡不再挂 onClick：按钮需要各自响应，卡片的点击只落在封面与正文上，
 * 避免「点赞同时把视频打开」。
 */
@Component
export struct DynamicCardView {
  @Prop card: DynamicCard = emptyDynamicCard();
  /** 全局 IP 属地开关（我的 → 设置 → 外观 → 全局显示 IP 属地） */
  @StorageLink(AppPrefs.KEY_SHOW_IP) showIpLocation: boolean = true;
  /** 点封面 / 正文：视频动态进播放页，其余进动态详情（暂为提示） */
  onCardTap: (card: DynamicCard) => void = () => {
  };
  /** 点作者头像 / 昵称：进该 UP 的个人主页 */
  onAuthorTap: (mid: number) => void = () => {
  };
  /** 点赞（页面负责乐观更新与失败回滚） */
  onLike: (card: DynamicCard) => void = () => {
  };
  /** 评论：视频动态进播放页评论区并展开输入框 */
  onComment: (card: DynamicCard) => void = () => {
  };
  /** 转发（个人动态发布页未接入，先占位） */
  onForward: (card: DynamicCard) => void = () => {
  };
  /** 分享 */
  onShare: (card: DynamicCard) => void = () => {
  };

  build() {
    Column() {
      this.authorRow()

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
          .maxLines(this.card.kind === 'video' ? 4 : 6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(20)
          .width('100%')
          .margin({ top: 8 })
          .textAlign(TextAlign.Start)
      }

      if (this.card.kind === 'video' && this.card.video !== null) {
        this.videoCard(this.card.video as VideoCard)
      } else if (this.card.kind === 'pics' && this.card.pics.length > 0) {
        // 图片/文字动态没有封面卡，标题区留空，只保留可点的图片网格
        Column() {
          this.picGrid()
        }
        .width('100%')
        .onClick(() => {
          this.onCardTap(this.card);
        })
      }

      this.actionRow()
    }
    .width('100%')
    .padding(12)
    // 不能再设左右 margin：width('100%') 已占满父容器，叠加左右外边距会溢出被裁
    .margin({ bottom: 10 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(14)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  authorRow() {
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
        Row({ space: 6 }) {
          Text(this.card.pubText)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
          if (this.showIpLocation && this.card.pubLocation.length > 0) {
            Text(this.card.pubLocation)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.onAuthorTap(this.card.authorMid);
    })
  }

  /** 放大后的视频封面卡：底边同一行放时长 / 播放 / 弹幕 / 点赞数 */
  @Builder
  videoCard(video: VideoCard) {
    Column() {
      // 封面容器自身定死 16:9：若把比例给 Image、而压暗层又是 height('100%')，
      // Stack 会自动尺寸化并与百分比子层互相等待，实测封面只剩下半、上半空白。
      Stack({ alignContent: Alignment.BottomStart }) {
        Image(video.cover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .alt($r('app.color.bg_field'))
          .draggable(false)

        // 底部压暗：白字压在亮封面上也能看清
        Column()
          .width('100%')
          .height(COVER_SCRIM_HEIGHT)
          .linearGradient({
            angle: 180,
            colors: [['#00000000', 0.0], ['#B3000000', 1.0]]
          })

        Row({ space: 8 }) {
          if (video.cornerText.length > 0) {
            Text(video.cornerText)
              .fontSize(10)
              .fontColor($r('app.color.text_on_media'))
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .backgroundColor('#66000000')
              .borderRadius(4)
          }
          Blank()
          this.metric($r('sys.symbol.play_circle'), video.viewText)
          this.metric($r('sys.symbol.waveform_bubble'), video.danmuText)
          this.metric($r('sys.symbol.hand_thumbsup'), this.likeText())
        }
        .width('100%')
        .padding({ left: 10, right: 10, bottom: 8 })
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .aspectRatio(16 / 9)
      .borderRadius(12)
      .clip(true)
      .onClick(() => {
        this.onCardTap(this.card);
      })

      // 视频名称放在封面卡之外（下部分第一行）
      Text(video.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(21)
        .width('100%')
        .margin({ top: 10 })
        .onClick(() => {
          this.onCardTap(this.card);
        })
    }
    .width('100%')
    .margin({ top: 10 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 封面卡底边的「图标 + 数值」小项 */
  @Builder
  metric(icon: Resource, text: string) {
    Row({ space: 3 }) {
      SymbolGlyph(icon)
        .fontSize(11)
        .fontColor([$r('app.color.text_on_media')])
      Text(text.length > 0 ? text : '0')
        .fontSize(11)
        .fontColor($r('app.color.text_on_media'))
        .maxLines(1)
    }
    .alignItems(VerticalAlign.Center)
  }

  /** 下部分第二行：点赞（带数）/ 评论 / 转发 / 分享 */
  @Builder
  actionRow() {
    Row() {
      this.actionButton(
        $r('sys.symbol.hand_thumbsup'),
        this.likeText(),
        this.card.liked ? $r('app.color.brand_primary') : $r('app.color.text_secondary'),
        () => {
          this.onLike(this.card);
        })
      Blank()
      this.actionButton($r('sys.symbol.ellipsis_message'), this.countText(this.card.commentCount, this.card.commentText),
        $r('app.color.text_secondary'), () => {
          this.onComment(this.card);
        })
      Blank()
      this.actionButton($r('sys.symbol.arrowshape_turn_up_right'), this.countText(this.card.forwardCount,
        this.card.forwardText), $r('app.color.text_secondary'), () => {
        this.onForward(this.card);
      })
      Blank()
      this.actionButton($r('sys.symbol.share'), '分享', $r('app.color.text_secondary'), () => {
        this.onShare(this.card);
      })
    }
    .width('100%')
    .margin({ top: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  actionButton(icon: Resource, text: string, color: Resource, action: () => void) {
    Row({ space: 4 }) {
      SymbolGlyph(icon)
        .fontSize(15)
        .fontColor([color])
      Text(text)
        .fontSize(12)
        .fontColor(color)
        .maxLines(1)
    }
    .height(32)
    .padding({ left: 6, right: 6 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      action();
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

  /**
   * 点赞数：接口给的是格式化字符串（「1.2万」）时直接用，
   * 否则按原始数值换算，保证「点赞需显示点赞数」。
   */
  private likeText(): string {
    if (this.card.likeCount > 0) {
      return shortCount(this.card.likeCount);
    }
    return this.card.likeText;
  }

  private countText(count: number, formatted: string): string {
    if (count > 0) {
      return shortCount(count);
    }
    return formatted;
  }
}