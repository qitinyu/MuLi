import { BOTTOM_PAD_LG, BOTTOM_PAD_PHONE, CHANNEL_STRIP_HEIGHT, PAGE_PADDING } from '../common/DesignSpec';
import { Channel, ChannelRegistry } from '../model/ChannelRegistry';
import { VideoCard, VideoOpenParam } from '../model/BiliModels';
import { RecommendService } from '../services/RecommendService';
import { VideoCardView } from '../components/VideoCardView';
import { ListFooter, StateView } from '../components/StateView';
import { PlaceholderPanel } from '../components/PlaceholderPanel';
import { ScrollSignal } from '../common/ScrollSignal';
import { uiMaterial } from '@kit.ArkUI';

/** 通道 key：只有推荐通道接入了接口，其余仍为占位 */
const CHANNEL_RECOMMEND: string = 'recommend';
/** 双列时的列间距 */
const CARD_GAP: number = 10;

/**
 * 首页（推荐页）＝启动默认页。
 *
 * 顶部 List（分区条）由「我的-设置-播放页-List 分区」控制：
 * - 显示 List（默认开）：关闭后整条不渲染；
 * - 跟随界面移动隐藏（默认开）：上滑时分区条随内容一起收起，下滑/回顶立即出现。
 * 分区内容来自设置里的 4 列勾选网格，最多 16 个，顺序恒按注册表顺序。
 *
 * 信息流卡片布局来自「设置-播放器-推荐页-卡片布局」：1×N / 2×N / 自适应，
 * 2 列及以上使用 VideoCardView 的紧凑模式，按行分组塞进 List 保证翻页与刷新行为不变。
 */
@Component
export struct HomePage {
  pathStack: NavPathStack | undefined = undefined;
  scroller: Scroller = new Scroller();
  @Prop topInset: number = 96;
  @Prop breakpoint: string = 'sm';
  @StorageLink('muli_listVisible') listVisible: boolean = true;
  @StorageLink('muli_listFollow') listFollow: boolean = true;
  @StorageLink('muli_partitions') @Watch('onPartitionsChanged') partitionKeys: string = '';
  @StorageLink('muli_cardLayout') cardLayout: number = 1;
  @State channels: Array<Channel> = ChannelRegistry.selected(ChannelRegistry.defaultKeys());
  /** 当前通道 key（不用下标，分区集变化时下标会错位） */
  @State channelKey: string = CHANNEL_RECOMMEND;
  @State stripHidden: boolean = false;
  @State stripMaterialOn: boolean = false;
  @State items: Array<VideoCard> = [];
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State loadingMore: boolean = false;
  @State errorText: string = '';
  @State hasMore: boolean = true;
  /** 下一次请求使用的 fresh_idx */
  private freshIdx: number = 0;
  private lastOffset: number = 0;
  private stripMaterial: uiMaterial.ImmersiveMaterial | undefined = undefined;

  aboutToAppear(): void {
    try {
      this.stripMaterialOn = uiMaterial.isImmersiveMaterialSupported();
      if (this.stripMaterialOn) {
        this.stripMaterial = new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR });
      }
    } catch (err) {
      this.stripMaterialOn = false;
    }
    this.refreshChannels();
    this.loadFirstPage();
  }

  /** 分区选择变化：重建通道列表，并把当前通道收敛到仍然存在的项 */
  private onPartitionsChanged(): void {
    this.refreshChannels();
  }

  private refreshChannels(): void {
    this.channels = ChannelRegistry.selected(this.partitionKeys);
    let exists: boolean = false;
    for (let i = 0; i < this.channels.length; i++) {
      if (this.channels[i].key === this.channelKey) {
        exists = true;
        break;
      }
    }
    if (!exists) {
      this.channelKey = this.channels.length > 0 ? this.channels[0].key : CHANNEL_RECOMMEND;
    }
  }

  private isRecommend(): boolean {
    return this.channelKey === CHANNEL_RECOMMEND;
  }

  private currentChannel(): Channel {
    for (let i = 0; i < this.channels.length; i++) {
      if (this.channels[i].key === this.channelKey) {
        return this.channels[i];
      }
    }
    return ChannelRegistry.at(0);
  }

  /** 拉第一页（下拉刷新与首次进入共用） */
  private async loadFirstPage(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      const cards: Array<VideoCard> = await RecommendService.load(1);
      this.items = cards;
      this.freshIdx = 1;
      this.hasMore = cards.length > 0;
    } catch (err) {
      this.errorText = err instanceof Error ? err.message : '加载失败，请稍后重试';
      if (this.items.length === 0) {
        this.items = [];
      }
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  /** 上拉加载下一批：fresh_idx 递增，按 bvid 去重后追加 */
  private async loadMore(): Promise<void> {
    if (this.loadingMore || this.loading || !this.hasMore) {
      return;
    }
    this.loadingMore = true;
    try {
      const next: number = this.freshIdx + 1;
      const cards: Array<VideoCard> = await RecommendService.load(next);
      if (cards.length === 0) {
        this.hasMore = false;
      } else {
        const appended: Array<VideoCard> = this.items.slice();
        for (let i = 0; i < cards.length; i++) {
          const key: string = cards[i].bvid.length > 0 ? cards[i].bvid : `${cards[i].aid}`;
          let duplicated: boolean = false;
          for (let j = 0; j < appended.length; j++) {
            const exist: string = appended[j].bvid.length > 0 ? appended[j].bvid : `${appended[j].aid}`;
            if (exist === key) {
              duplicated = true;
              break;
            }
          }
          if (!duplicated) {
            appended.push(cards[i]);
          }
        }
        this.items = appended;
        this.freshIdx = next;
      }
    } catch (err) {
      this.hasMore = false;
    } finally {
      this.loadingMore = false;
    }
  }

  private switchChannel(key: string): void {
    if (key === this.channelKey) {
      return;
    }
    this.channelKey = key;
    // 切通道视为换列表，滚动位置一并复位
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.lastOffset = 0;
    this.fadeStrip(false);
    if (key === CHANNEL_RECOMMEND && this.items.length === 0 && !this.loading) {
      this.loadFirstPage();
    }
  }

  // ---------- 分区条收起 / 展开 ----------

  private fadeStrip(hidden: boolean): void {
    if (this.stripHidden === hidden) {
      return;
    }
    this.getUIContext().animateTo({ duration: 180, curve: Curve.Friction }, () => {
      this.stripHidden = hidden;
    });
  }

  private onListScroll(): void {
    ScrollSignal.report(this.scroller);
    let offset: number = 0;
    try {
      offset = this.scroller.currentOffset().yOffset;
    } catch (err) {
      return;
    }
    if (!this.listVisible || !this.listFollow) {
      this.fadeStrip(false);
      this.lastOffset = offset;
      return;
    }
    const movingUp: boolean = offset > this.lastOffset;
    this.lastOffset = offset;
    if (offset <= 8) {
      this.fadeStrip(false);
      return;
    }
    if (movingUp && offset > CHANNEL_STRIP_HEIGHT) {
      this.fadeStrip(true);
    } else if (!movingUp) {
      this.fadeStrip(false);
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

  // ---------- 卡片布局 ----------

  /** 当前列数：1×N = 1 列，2×N = 2 列，自适应在宽屏给 4 列、窄屏按 2 列 */
  private columns(): number {
    if (this.cardLayout === 0) {
      return 1;
    }
    if (this.cardLayout === 2) {
      return this.breakpoint === 'lg' ? 4 : 2;
    }
    return 2;
  }

  /** 按列数分组，List 里一行渲染一条 ListItem */
  private rows(): Array<Array<VideoCard>> {
    const cols: number = this.columns();
    const result: Array<Array<VideoCard>> = [];
    for (let i = 0; i < this.items.length; i += cols) {
      const row: Array<VideoCard> = [];
      const end: number = Math.min(i + cols, this.items.length);
      for (let j = i; j < end; j++) {
        row.push(this.items[j]);
      }
      result.push(row);
    }
    return result;
  }

  /** 末行补位：保证最后一行卡片宽度与上面一致，不被 layoutWeight 拉满 */
  private fillers(count: number): Array<number> {
    const result: Array<number> = [];
    for (let i = 0; i < count; i++) {
      result.push(i);
    }
    return result;
  }

  @Builder
  channelChip(item: Channel) {
    Text(item.label)
      .fontSize(15)
      .fontWeight(this.channelKey === item.key ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.channelKey === item.key ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .backgroundColor(this.channelKey === item.key ? $r('app.color.brand_tint') : Color.Transparent)
      .borderRadius(16)
      .onClick(() => {
        this.switchChannel(item.key);
      })
  }

  @Builder
  channelStrip() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.channels, (item: Channel) => {
          this.channelChip(item);
        }, (item: Channel) => item.key)
      }
      .height(CHANNEL_STRIP_HEIGHT)
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
      .alignItems(VerticalAlign.Center)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(CHANNEL_STRIP_HEIGHT)
  }

  /** 顶部留白：让首条内容从分区条下方开始滚动 */
  @Builder
  listHeader() {
    Row()
      .width('100%')
      .height(this.topInset + (this.listVisible ? CHANNEL_STRIP_HEIGHT : 0))
  }

  @Builder
  cardCell(card: VideoCard) {
    Column() {
      VideoCardView({
        card: card,
        compact: this.columns() > 1,
        onCardTap: (item: VideoCard) => {
          this.openVideo(item);
        },
        onMoreTap: (item: VideoCard) => {
          this.toast(`《${item.title}》更多操作待建设`);
        }
      })
    }
    .layoutWeight(1)
  }

  @Builder
  feedRows() {
    ForEach(this.rows(), (row: Array<VideoCard>, rowIndex: number) => {
      ListItem() {
        Row({ space: CARD_GAP }) {
          ForEach(row, (card: VideoCard, colIndex: number) => {
            this.cardCell(card);
          }, (card: VideoCard, colIndex: number) => `${rowIndex}-${colIndex}-${card.bvid}-${card.aid}`)

          if (row.length < this.columns()) {
            ForEach(this.fillers(this.columns() - row.length), (item: number) => {
              Column().layoutWeight(1)
            }, (item: number) => `fill-${rowIndex}-${item}`)
          }
        }
        .width('100%')
        .padding(this.columns() > 1
          ? { left: PAGE_PADDING, right: PAGE_PADDING }
          : { left: 0, right: 0 })
        .alignItems(VerticalAlign.Top)
      }
    }, (row: Array<VideoCard>, rowIndex: number) =>
    `row-${rowIndex}-${row.length}-${row.length > 0 ? row[0].bvid : ''}`)
  }

  @Builder
  recommendList() {
    List({ scroller: this.scroller }) {
      ListItem() {
        this.listHeader()
      }

      if (this.loading && this.items.length === 0) {
        ListItem() {
          StateView({ kind: 'loading', message: '正在为你推荐' })
        }
      } else if (this.errorText.length > 0 && this.items.length === 0) {
        ListItem() {
          StateView({
            kind: 'error',
            message: this.errorText,
            hint: '检查网络后重试，或稍后再来',
            onRetry: () => {
              this.loadFirstPage();
            }
          })
        }
      } else if (this.items.length === 0) {
        ListItem() {
          StateView({ kind: 'empty', message: '暂时没有推荐内容', hint: '下拉刷新试试' })
        }
      } else {
        this.feedRows()

        if (this.loadingMore) {
          ListItem() {
            ListFooter({ text: '正在加载更多' })
          }
        } else if (!this.hasMore) {
          ListItem() {
            ListFooter({ text: '没有更多了', showProgress: false })
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
      this.onListScroll();
    })
    .onReachEnd(() => {
      this.loadMore();
    })
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.isRecommend()) {
        Refresh({ refreshing: $$this.refreshing }) {
          this.recommendList()
        }
        .width('100%')
        .height('100%')
        .onRefreshing(() => {
          this.refreshing = true;
          this.items = [];
          this.hasMore = true;
          this.freshIdx = 0;
          this.stripHidden = false;
          this.loadFirstPage();
        })
      } else {
        Scroll(this.scroller) {
          Column() {
            this.listHeader()
            PlaceholderPanel({
              title: `${this.currentChannel().label} · 内容区`,
              note: this.currentChannel().note,
              icon: $r('sys.symbol.house'),
              panelHeight: 460
            })
            Row()
              .width('100%')
              .height(this.breakpoint === 'lg' ? BOTTOM_PAD_LG : BOTTOM_PAD_PHONE)
          }
          .width('100%')
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onScroll(() => {
          this.onListScroll();
        })
      }

      // 分区条：贴在标题栏下沿，材质与标题栏同源；上滑时整条淡出上移
      if (this.listVisible) {
        Column() {
          this.channelStrip()
        }
        .width('100%')
        .margin({ top: this.topInset })
        .translate({ y: this.stripHidden ? -CHANNEL_STRIP_HEIGHT : 0 })
        .opacity(this.stripHidden ? 0 : 1)
        .backgroundColor(this.stripMaterialOn ? Color.Transparent : $r('app.color.bg_page'))
        .backgroundBlurStyle(this.stripMaterialOn ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THIN)
        .systemMaterial(this.stripMaterial)
      }
    }
    .width('100%')
    .height('100%')
  }
}
