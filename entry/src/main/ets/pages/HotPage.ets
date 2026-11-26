import { BOTTOM_PAD_LG, BOTTOM_PAD_PHONE, CARD_RADIUS, PAGE_PADDING } from '../common/DesignSpec';
import { VideoCard, VideoOpenParam } from '../model/BiliModels';
import { HOT_CAROUSEL_COUNT, HOT_CATEGORIES, HotCategory, HotService } from '../services/HotService';
import { StateView } from '../components/StateView';
import { ScrollSignal } from '../common/ScrollSignal';
import { durationText, shortCount } from '../common/Format';

/** 轮播区高度：手机端固定，平板稍高一点 */
const CAROUSEL_HEIGHT_SM: number = 196;
const CAROUSEL_HEIGHT_LG: number = 260;
/** 分类中等卡片尺寸 */
const CATEGORY_CARD_WIDTH: number = 118;
const CATEGORY_CARD_HEIGHT: number = 74;
/** 小卡封面尺寸（左侧视频封面 + 右侧信息） */
const ROW_COVER_WIDTH: number = 138;
const ROW_COVER_HEIGHT: number = 84;

/**
 * 热门页（页签四，V2.1.2 重做）。
 *
 * 版式参考官方热门并微改，自上而下三段：
 * 1. 轮播：前五名大卡片，信息集中在右下 —— 视频名称，以及「UP 头像 + UP 名 + 播放量」同一行；
 * 2. 分类：中等卡片横向滑动，点选切换分区榜（rid）；
 * 3. 其余名次：小卡片，左侧视频封面 + 右侧信息。
 *
 * 排行榜接口一次返回约 100 条且无分页，因此只做下拉刷新，展开更多只是把余下名次铺出来。
 */
@Component
export struct HotPage {
  pathStack: NavPathStack | undefined = undefined;
  scroller: Scroller = new Scroller();
  @Prop topInset: number = 96;
  @Prop breakpoint: string = 'sm';
  @State items: Array<VideoCard> = [];
  /** 当前选中的分类下标（HOT_CATEGORIES 的下标） */
  @State categoryIndex: number = 0;
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State errorText: string = '';
  /** 小卡片首屏只铺 20 条，其余按需展开，避免一次渲染上百个卡片 */
  @State visibleCount: number = 20;
  private swiperController: SwiperController = new SwiperController();

  aboutToAppear(): void {
    this.loadData();
  }

  private async loadData(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      this.items = await HotService.load(HOT_CATEGORIES[this.categoryIndex].rid);
      this.visibleCount = 20;
    } catch (err) {
      this.errorText = err instanceof Error ? err.message : '加载失败，请稍后重试';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text, duration: 1800 });
    } catch (err) {
      // 提示失败不影响主流程
    }
  }

  /** 打开视频二级播放页 */
  private openVideo(item: VideoCard): void {
    if (this.pathStack === undefined) {
      this.toast('播放页暂不可用');
      return;
    }
    this.pathStack.pushPathByName('video', new VideoOpenParam(item.bvid, item.aid, item.cid));
  }

  /** 切换分类：立即重载该分区榜，并把轮播与列表都滚回顶部 */
  private pickCategory(index: number): void {
    if (this.categoryIndex === index) {
      return;
    }
    this.categoryIndex = index;
    this.items = [];
    this.scroller.scrollEdge(Edge.Top);
    this.loadData();
  }

  private carouselCards(): Array<VideoCard> {
    return this.items.slice(0, HOT_CAROUSEL_COUNT);
  }

  /** 轮播之后剩余的条目（轮播已展示前五名） */
  private rankedCards(): Array<VideoCard> {
    return this.items.slice(HOT_CAROUSEL_COUNT);
  }

  private carouselHeight(): number {
    return this.breakpoint === 'lg' ? CAROUSEL_HEIGHT_LG : CAROUSEL_HEIGHT_SM;
  }

  // ---------- 轮播大卡片 ----------

  @Builder
  carouselCard(card: VideoCard, index: number) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Image(card.cover)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .alt($r('app.color.bg_field'))
        .draggable(false)

      // 底部压暗：右下信息压在图上时保持可读
      Column()
        .width('100%')
        .height('62%')
        .linearGradient({
          angle: 180,
          colors: [['#00000000', 0.0], ['#CC000000', 1.0]]
        })

      // 顶部角标行：左名次 / 右时长
      Row() {
        Text(`TOP ${index + 1}`)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_on_brand'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor($r('app.color.brand_primary'))
          .borderRadius(9)
        Blank()
        if (card.duration > 0) {
          Text(durationText(card.duration))
            .fontSize(11)
            .fontColor($r('app.color.text_on_media'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#66000000')
            .borderRadius(6)
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 12 })
      .alignItems(VerticalAlign.Top)
      .position({ x: 0, y: 0 })

      // 右下信息块：视频名称 + （UP 头像 + UP 名 + 播放量 同一行）
      Column({ space: 6 }) {
        Text(card.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_on_media'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.End)
          .width('100%')

        Row({ space: 6 }) {
          if (card.authorFace.length > 0) {
            Image(card.authorFace)
              .width(18)
              .height(18)
              .borderRadius(9)
              .objectFit(ImageFit.Cover)
              .alt($r('app.color.bg_field'))
              .draggable(false)
          } else {
            SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
              .fontSize(14)
              .fontColor([$r('app.color.text_on_media')])
          }
          Text(card.author)
            .fontSize(11)
            .fontColor($r('app.color.text_on_media'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '34%' })
          Text('·')
            .fontSize(11)
            .fontColor('#B3FFFFFF')
          Text(card.viewText)
            .fontSize(11)
            .fontColor('#E6FFFFFF')
            .maxLines(1)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .padding({ left: 16, right: 12, bottom: 14 })
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .height('100%')
    .borderRadius(CARD_RADIUS)
    .clip(true)
    .onClick(() => {
      this.openVideo(card);
    })
  }

  @Builder
  carousel() {
    Swiper(this.swiperController) {
      ForEach(this.carouselCards(), (card: VideoCard, index: number) => {
        this.carouselCard(card, index)
      }, (card: VideoCard, index: number) => `c-${index}-${card.bvid}`)
    }
    .width('100%')
    .height(this.carouselHeight())
    .autoPlay(true)
    .interval(4200)
    .loop(true)
    .indicator(true)
    .itemSpace(8)
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
  }

  // ---------- 分类中等卡片 ----------

  @Builder
  categoryCard(cat: HotCategory, index: number) {
    Column({ space: 3 }) {
      Row() {
        Text(cat.label)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.categoryIndex === index
            ? $r('app.color.brand_primary') : $r('app.color.text_primary'))
        Blank()
        if (this.categoryIndex === index) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(12)
            .fontColor([$r('app.color.brand_primary')])
        }
      }
      .width('100%')

      Text(cat.note)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width(CATEGORY_CARD_WIDTH)
    .height(CATEGORY_CARD_HEIGHT)
    .padding({ left: 12, right: 12, top: 11, bottom: 11 })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.categoryIndex === index
      ? $r('app.color.brand_tint') : $r('app.color.bg_card'))
    .borderRadius(14)
    .border({
      width: this.categoryIndex === index ? 1 : 0,
      color: this.categoryIndex === index ? $r('app.color.brand_line') : Color.Transparent
    })
    .onClick(() => {
      this.pickCategory(index);
    })
  }

  @Builder
  categoryStrip() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(HOT_CATEGORIES, (cat: HotCategory, index: number) => {
          this.categoryCard(cat, index)
        }, (cat: HotCategory) => cat.rid)
      }
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
    }
    .width('100%')
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
  }

  // ---------- 小卡片（左封面 + 右信息） ----------

  private rankText(card: VideoCard): string {
    return card.cornerText.length > 0 ? card.cornerText : '';
  }

  @Builder
  listCard(card: VideoCard) {
    Row({ space: 10 }) {
      // 左：视频封面
      Stack({ alignContent: Alignment.BottomEnd }) {
        Image(card.cover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .alt($r('app.color.bg_field'))
          .draggable(false)

        if (this.rankText(card).length > 0) {
          Text(this.rankText(card))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_on_brand'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor($r('app.color.brand_primary'))
            .borderRadius(6)
            .position({ x: 6, y: 6 })
        }

        if (card.duration > 0) {
          Text(durationText(card.duration))
            .fontSize(11)
            .fontColor($r('app.color.text_on_media'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor('#66000000')
            .borderRadius(6)
            .margin({ right: 6, bottom: 6 })
        }
      }
      .width(ROW_COVER_WIDTH)
      .height(ROW_COVER_HEIGHT)
      .borderRadius(10)
      .clip(true)

      // 右：信息
      Column({ space: 5 }) {
        Text(card.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row({ space: 6 }) {
          if (card.authorFace.length > 0) {
            Image(card.authorFace)
              .width(18)
              .height(18)
              .borderRadius(9)
              .objectFit(ImageFit.Cover)
              .alt($r('app.color.bg_field'))
              .draggable(false)
          } else {
            SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
              .fontSize(14)
              .fontColor([$r('app.color.text_tertiary')])
          }
          Text(card.author)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '46%' })
          Text(card.viewText)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row({ space: 8 }) {
          Text(card.danmuText)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
          if (card.likeText.length > 0) {
            Text(`${card.likeText}点赞`)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          Blank()
          if (card.tname !== undefined && card.tname.length > 0) {
            Text(card.tname)
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor($r('app.color.bg_field'))
              .borderRadius(6)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .height(ROW_COVER_HEIGHT)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 6, bottom: 6 })
    .onClick(() => {
      this.openVideo(card);
    })
  }

  @Builder
  hotList() {
    List({ scroller: this.scroller }) {
      ListItem() {
        Row()
          .width('100%')
          .height(this.topInset)
      }

      if (this.loading && this.items.length === 0) {
        ListItem() {
          StateView({ kind: 'loading', message: '正在加载热门' })
        }
      } else if (this.errorText.length > 0 && this.items.length === 0) {
        ListItem() {
          StateView({
            kind: 'error',
            message: this.errorText,
            hint: '排行榜接口偶发限流，稍后重试',
            onRetry: () => {
              this.loadData();
            }
          })
        }
      } else if (this.items.length === 0) {
        ListItem() {
          StateView({ kind: 'empty', message: '暂时没有热门内容' })
        }
      } else {
        // 1. 顶部轮播：前五名大卡片
        if (this.carouselCards().length > 0) {
          ListItem() {
            this.carousel()
          }
        }

        // 2. 分类中等卡片
        ListItem() {
          Column({ space: 8 }) {
            Row() {
              Text('分类')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text(`${HOT_CATEGORIES[this.categoryIndex].label}榜`)
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            .padding({ left: PAGE_PADDING, right: PAGE_PADDING })

            this.categoryStrip()
          }
          .width('100%')
          .padding({ top: 14, bottom: 4 })
        }

        // 3. 其余名次：左封面 + 右信息
        if (this.rankedCards().length > 0) {
          ListItem() {
            Row() {
              Text('热榜')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
            .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 14, bottom: 4 })
          }
        }

        ForEach(this.rankedCards().slice(0, this.visibleCount), (card: VideoCard) => {
          ListItem() {
            this.listCard(card)
          }
        }, (card: VideoCard, index: number) => `r-${index}-${card.bvid}-${card.aid}`)

        if (this.visibleCount < this.rankedCards().length) {
          ListItem() {
            Row() {
              Text(`展开全部 ${this.rankedCards().length} 条`)
                .fontSize(13)
                .fontColor($r('app.color.brand_primary'))
            }
            .width('100%')
            .height(52)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.visibleCount = this.rankedCards().length;
            })
          }
        }
      }

      ListItem() {
        Row()
          .width('100%')
          .height(this.breakpoint === 'lg' ? BOTTOM_PAD_LG : BOTTOM_PAD_PHONE)
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onScroll(() => {
      ScrollSignal.report(this.scroller);
    })
  }

  build() {
    Refresh({ refreshing: $$this.refreshing }) {
      this.hotList()
    }
    .width('100%')
    .height('100%')
    .onRefreshing(() => {
      this.refreshing = true;
      this.loadData();
    })
  }
}