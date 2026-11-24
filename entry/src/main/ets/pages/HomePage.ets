import { BOTTOM_PAD_LG, BOTTOM_PAD_PHONE, CHANNEL_STRIP_HEIGHT, PAGE_PADDING } from '../common/DesignSpec';
import { Channel, ChannelRegistry } from '../model/ChannelRegistry';
import { VideoCard, VideoOpenParam } from '../model/BiliModels';
import { RecommendService } from '../services/RecommendService';
import { AppPrefs } from '../services/AppPrefs';
import { VideoCardView } from '../components/VideoCardView';
import { ListFooter, StateView } from '../components/StateView';
import { PlaceholderPanel } from '../components/PlaceholderPanel';
import { ScrollSignal } from '../common/ScrollSignal';
import { uiMaterial } from '@kit.ArkUI';

/** 通道 key：只有推荐通道接入了接口，其余仍为占位 */
const CHANNEL_RECOMMEND: string = 'recommend';
/** 双列时的列间距 */
const CARD_GAP: number = 10;
/** 竖屏混排密度：每 N 条推荐插 1 条竖屏视频 */
const VERTICAL_MIX_STEP: number = 4;

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
  /** 下拉刷新保存前置内容（默认开） */
  @StorageLink('muli_recSaveOnRefresh') recSave: boolean = true;
  /** 下拉刷新数目下标：0 = 10 条，1 = 20 条 */
  @StorageLink('muli_recRefreshCount') @Watch('onFeedPrefChanged') recCountIndex: number = 0;
  /** 竖屏化视频是否混排展示（默认关） */
  @StorageLink('muli_showVertical') @Watch('onFeedPrefChanged') showVertical: boolean = false;
  /** 点击顶部分区 List 是否全量刷新（默认关，实验性） */
  @StorageLink('muli_listTapRefresh') listTapRefresh: boolean = false;
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
  /** 竖屏混排池（来自热门接口，只放真正的竖屏视频）与它的取用游标 */
  private verticalPool: Array<VideoCard> = [];
  private verticalCursor: number = 0;

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

  /** 推荐流相关设置变化（条数 / 竖屏混排）：立刻按新设置重拉第一页 */
  private onFeedPrefChanged(): void {
    if (!this.isRecommend()) {
      return;
    }
    this.verticalPool = [];
    this.verticalCursor = 0;
    this.freshIdx = 0;
    this.loadFirstPage();
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
  private async loadFirstPage(keepPrevious: boolean = false): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      await this.ensureVerticalPool();
      const cards: Array<VideoCard> = this.mixVertical(this.visible(await RecommendService.load(1,
        AppPrefs.recCount(this.recCountIndex))));
      if (keepPrevious && this.items.length > 0) {
        // 「下拉刷新保存前置内容」：新内容插到前面，旧内容继续留在下面可翻
        const merged: Array<VideoCard> = cards.slice();
        for (let i = 0; i < this.items.length; i++) {
          const old: VideoCard = this.items[i];
          const key: string = old.bvid.length > 0 ? old.bvid : `${old.aid}`;
          let existed: boolean = false;
          for (let j = 0; j < merged.length; j++) {
            const fresh: string = merged[j].bvid.length > 0 ? merged[j].bvid : `${merged[j].aid}`;
            if (fresh === key) {
              existed = true;
              break;
            }
          }
          if (!existed) {
            merged.push(old);
          }
        }
        this.items = merged;
      } else {
        this.items = cards;
      }
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

  /** 竖屏化视频展示开关：关闭时把竖屏视频从推荐流里滤掉 */
  private visible(cards: Array<VideoCard>): Array<VideoCard> {
    if (this.showVertical) {
      return cards;
    }
    const result: Array<VideoCard> = [];
    for (let i = 0; i < cards.length; i++) {
      if (!cards[i].vertical) {
        result.push(cards[i]);
      }
    }
    return result;
  }

  /** 竖屏混排池：开关关着就当没有；池子用完了再补一批 */
  private async ensureVerticalPool(): Promise<void> {
    if (!this.showVertical) {
      this.verticalPool = [];
      this.verticalCursor = 0;
      return;
    }
    if (this.verticalCursor < this.verticalPool.length) {
      return;
    }
    try {
      this.verticalPool = await RecommendService.loadVerticalPool();
      this.verticalCursor = 0;
    } catch (err) {
      this.verticalPool = [];
      this.verticalCursor = 0;
    }
  }

  private sameCard(a: VideoCard, b: VideoCard): boolean {
    if (a.bvid.length > 0 && b.bvid.length > 0) {
      return a.bvid === b.bvid;
    }
    return a.aid > 0 && a.aid === b.aid;
  }

  private contains(cards: Array<VideoCard>, card: VideoCard): boolean {
    for (let i = 0; i < cards.length; i++) {
      if (this.sameCard(cards[i], card)) {
        return true;
      }
    }
    return false;
  }

  /**
   * 竖屏混排：每 VERTICAL_MIX_STEP 条正常推荐后面插 1 条竖屏视频（同页去重）。
   * 池子取空就停手，不会为了凑数把同一条重复塞进来。
   */
  private mixVertical(cards: Array<VideoCard>): Array<VideoCard> {
    if (!this.showVertical || this.verticalPool.length === 0) {
      return cards;
    }
    const result: Array<VideoCard> = [];
    for (let i = 0; i < cards.length; i++) {
      result.push(cards[i]);
      if ((i + 1) % VERTICAL_MIX_STEP !== 0) {
        continue;
      }
      while (this.verticalCursor < this.verticalPool.length) {
        const candidate: VideoCard = this.verticalPool[this.verticalCursor];
        this.verticalCursor++;
        if (!this.contains(result, candidate) && !this.contains(cards, candidate)) {
          result.push(candidate);
          break;
        }
      }
    }
    return result;
  }

  /** 上拉加载下一批：fresh_idx 递增，按 bvid 去重后追加 */
  private async loadMore(): Promise<void> {
    if (this.loadingMore || this.loading || !this.hasMore) {
      return;
    }
    this.loadingMore = true;
    try {
      const next: number = this.freshIdx + 1;
      await this.ensureVerticalPool();
      const cards: Array<VideoCard> = this.mixVertical(this.visible(await RecommendService.load(next,
        AppPrefs.recCount(this.recCountIndex))));
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
      // 「点击顶部分区 List 全量刷新」（实验性）：点当前分区即重拉第一页，
      // 关闭时保持原行为（点当前分区不做事，避免误触清空滚动位置）。
      if (this.listTapRefresh && key === CHANNEL_RECOMMEND) {
        this.toast('正在刷新当前分区');
        this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
        this.lastOffset = 0;
        this.loadFirstPage();
      }
      return;
    }
    this.channelKey = key;
    // 切通道视为换列表，滚动位置一并复位
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.lastOffset = 0;
    this.fadeStrip(false);
    if (key === CHANNEL_RECOMMEND && !this.loading) {
      // 全量刷新开关关闭时，已有内容就复用（保持原来的「切回来不重拉」行为）
      if (this.items.length === 0 || this.listTapRefresh) {
        this.loadFirstPage();
      }
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
          const keep: boolean = this.recSave && this.items.length > 0;
          this.hasMore = true;
          this.freshIdx = 0;
          this.stripHidden = false;
          // 关闭「保存前置内容」时先清空，刷新期间列表回到空态（与原行为一致）
          if (!keep) {
            this.items = [];
          }
          this.loadFirstPage(keep);
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
