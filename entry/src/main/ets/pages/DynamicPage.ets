import { BOTTOM_PAD_LG, BOTTOM_PAD_PHONE, PAGE_PADDING } from '../common/DesignSpec';
import { DynamicCard, DynamicPageData, QuickUp, UserOpenParam, VideoCard, VideoOpenParam } from '../model/BiliModels';
import { AuthService } from '../services/AuthService';
import { AppPrefs } from '../services/AppPrefs';
import { DynamicService } from '../services/DynamicService';
import { DynamicCardView } from '../components/DynamicCardView';
import { ListFooter, StateView } from '../components/StateView';
import { ScrollSignal } from '../common/ScrollSignal';
import { pasteboard } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** 快捷入口头像单元宽度（含昵称） */
const QUICK_CELL_WIDTH: number = 52;
/** 快捷入口头像直径 */
const QUICK_AVATAR_SIZE: number = 44;

/**
 * 动态页（页签二）：关注 UP 主动态流。
 *
 * V2.1.2 改版要点：
 *  1. 顶部新增「快捷 UP 主」行，可左右滑动，一行或两行（设置 → 播放 → 动态 → 快捷入口行数）。
 *     点某个头像即只看该 UP 的动态，再点一次或点首位的「综合」恢复默认混排。
 *  2. 视频动态的封面卡放大，统计数字压进封面底边，操作按钮移到卡外单独一行。
 *
 * 该接口未登录恒返回 -101，因此未登录时不发请求，直接给登录引导；
 * 登录成功后由 AppStorage 的 loginTick 信号触发重载（登录页在别的路由，无法直接回调）。
 */
@Component
export struct DynamicPage {
  pathStack: NavPathStack | undefined = undefined;
  scroller: Scroller = new Scroller();
  @Prop topInset: number = 96;
  @Prop breakpoint: string = 'sm';
  @StorageLink('loginTick') @Watch('onLoginTick') loginTick: number = 0;
  @StorageLink(AppPrefs.KEY_DYN_QUICK_ROWS) @Watch('onQuickRowsChanged') quickRowMode: number = 0;
  @State items: Array<DynamicCard> = [];
  @State quickUps: Array<QuickUp> = [];
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State loadingMore: boolean = false;
  @State errorText: string = '';
  @State needLogin: boolean = false;
  @State hasMore: boolean = true;
  /** 当前只看哪个 UP 的动态；0 表示默认混排 */
  @State activeMid: number = 0;
  /** 翻页游标（接口给的 data.offset；不能叫 offset，会与 CustomComponent 的同名属性冲突） */
  private nextOffset: string = '';
  /** 混排列表与单个 UP 列表各自缓存，来回切换不必重新请求 */
  private mixedItems: Array<DynamicCard> = [];
  private mixedOffset: string = '';
  private mixedHasMore: boolean = true;
  private upItems: Array<DynamicCard> = [];
  private upOffset: string = '';
  private upHasMore: boolean = true;

  aboutToAppear(): void {
    this.loadFirstPage();
  }

  private onLoginTick(): void {
    this.resetAll();
    this.loadFirstPage();
  }

  private onQuickRowsChanged(): void {
    // 行数变多时尽量用现有动态补足头像，避免空位
    this.ensureQuickUps();
  }

  private resetAll(): void {
    this.items = [];
    this.nextOffset = '';
    this.hasMore = true;
    this.activeMid = 0;
    this.mixedItems = [];
    this.mixedOffset = '';
    this.mixedHasMore = true;
    this.upItems = [];
    this.upOffset = '';
    this.upHasMore = true;
  }

  private capacity(): number {
    return AppPrefs.dynQuickCapacity(this.quickRowMode);
  }

  private rows(): number {
    return this.quickRowMode === 1 ? 2 : 1;
  }

  private async loadFirstPage(): Promise<void> {
    if (this.loading) {
      return;
    }
    if (!AuthService.isLogin()) {
      this.needLogin = true;
      this.items = [];
      this.quickUps = [];
      this.refreshing = false;
      return;
    }
    this.needLogin = false;
    this.loading = true;
    this.errorText = '';
    try {
      const page: DynamicPageData = await DynamicService.loadPage('');
      this.items = page.cards;
      this.nextOffset = page.offset;
      this.hasMore = page.hasMore;
      this.mixedItems = page.cards;
      this.mixedOffset = page.offset;
      this.mixedHasMore = page.hasMore;
      await this.loadQuickUps(page.cards);
    } catch (err) {
      const message: string = err instanceof Error ? err.message : '加载失败，请稍后重试';
      if (message.indexOf('未登录') >= 0) {
        this.needLogin = true;
      } else {
        this.errorText = message;
      }
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  /** 快捷 UP 行：优先 /dynamic/uplist，未登录或失败则用已加载动态里的作者去重补足 */
  private async loadQuickUps(cards: Array<DynamicCard>): Promise<void> {
    const want: number = this.capacity();
    let ups: Array<QuickUp> = await DynamicService.quickUps(want);
    if (ups.length < want) {
      const fallback: Array<QuickUp> = DynamicService.quickUpsFromCards(cards, want);
      for (let i = 0; i < fallback.length && ups.length < want; i++) {
        let exists: boolean = false;
        for (let j = 0; j < ups.length; j++) {
          if (ups[j].mid === fallback[i].mid) {
            exists = true;
            break;
          }
        }
        if (!exists) {
          ups.push(fallback[i]);
        }
      }
    }
    this.quickUps = ups;
  }

  private ensureQuickUps(): void {
    if (this.needLogin) {
      return;
    }
    if (this.quickUps.length >= this.capacity()) {
      return;
    }
    this.loadQuickUps(this.mixedItems);
  }

  private async loadMore(): Promise<void> {
    if (this.loadingMore || this.loading || !this.hasMore || this.needLogin || this.nextOffset.length === 0) {
      return;
    }
    this.loadingMore = true;
    const filtering: boolean = this.activeMid > 0;
    try {
      const page: DynamicPageData = filtering
        ? await DynamicService.loadSpacePage(this.activeMid, this.nextOffset)
        : await DynamicService.loadPage(this.nextOffset);
      const appended: Array<DynamicCard> = this.appendUnique(this.items, page.cards);
      this.items = appended;
      if (page.offset.length > 0) {
        this.nextOffset = page.offset;
      }
      this.hasMore = page.hasMore && page.cards.length > 0;
      if (filtering) {
        this.upItems = appended;
        this.upOffset = this.nextOffset;
        this.upHasMore = this.hasMore;
      } else {
        this.mixedItems = appended;
        this.mixedOffset = this.nextOffset;
        this.mixedHasMore = this.hasMore;
      }
    } catch (err) {
      this.hasMore = false;
    } finally {
      this.loadingMore = false;
    }
  }

  private appendUnique(base: Array<DynamicCard>, more: Array<DynamicCard>): Array<DynamicCard> {
    const appended: Array<DynamicCard> = base.slice();
    for (let i = 0; i < more.length; i++) {
      let duplicated: boolean = false;
      for (let j = 0; j < appended.length; j++) {
        if (appended[j].id === more[i].id) {
          duplicated = true;
          break;
        }
      }
      if (!duplicated) {
        appended.push(more[i]);
      }
    }
    return appended;
  }

  /** 点快捷头像：只看该 UP；再点一次恢复混排 */
  private async pickUp(mid: number): Promise<void> {
    const target: number = this.activeMid === mid ? 0 : mid;
    if (target === this.activeMid) {
      return;
    }
    // 先把当前列表存回对应缓存
    if (this.activeMid === 0) {
      this.mixedItems = this.items;
      this.mixedOffset = this.nextOffset;
      this.mixedHasMore = this.hasMore;
    } else {
      this.upItems = this.items;
      this.upOffset = this.nextOffset;
      this.upHasMore = this.hasMore;
    }
    this.activeMid = target;
    this.scroller.scrollEdge(Edge.Top);
    if (target === 0) {
      if (this.mixedItems.length > 0) {
        this.items = this.mixedItems;
        this.nextOffset = this.mixedOffset;
        this.hasMore = this.mixedHasMore;
        this.errorText = '';
        return;
      }
      this.items = [];
      this.nextOffset = '';
      this.hasMore = true;
      await this.loadFirstPage();
      return;
    }
    if (this.upItems.length > 0) {
      this.items = this.upItems;
      this.nextOffset = this.upOffset;
      this.hasMore = this.upHasMore;
      this.errorText = '';
      return;
    }
    await this.loadFiltered(target);
  }

  private async loadFiltered(mid: number): Promise<void> {
    this.items = [];
    this.nextOffset = '';
    this.hasMore = true;
    this.loading = true;
    this.errorText = '';
    try {
      const page: DynamicPageData = await DynamicService.loadSpacePage(mid, '');
      if (this.activeMid !== mid) {
        return;
      }
      this.items = page.cards;
      this.nextOffset = page.offset;
      this.hasMore = page.hasMore;
      this.upItems = page.cards;
      this.upOffset = page.offset;
      this.upHasMore = page.hasMore;
    } catch (err) {
      this.errorText = err instanceof Error ? err.message : '加载该 UP 的动态失败';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private openLogin(): void {
    if (this.pathStack !== undefined) {
      this.pathStack.pushPathByName('login', '');
    }
  }

  private openUser(mid: number): void {
    if (this.pathStack !== undefined && mid > 0) {
      this.pathStack.pushPathByName('user', new UserOpenParam(mid));
    }
  }

  private openVideo(video: VideoCard, focusComment: boolean): void {
    if (this.pathStack === undefined) {
      return;
    }
    const param: VideoOpenParam = new VideoOpenParam(video.bvid, video.aid, video.cid);
    param.focusComment = focusComment;
    this.pathStack.pushPathByName('video', param);
  }

  /** 点赞：先乐观更新，失败回滚并提示（未登录直接引导登录） */
  private async toggleLike(card: DynamicCard): Promise<void> {
    if (!AuthService.isLogin()) {
      this.toast('请先登录后再点赞');
      return;
    }
    const next: boolean = !card.liked;
    this.setLiked(card.id, next);
    try {
      await DynamicService.setLike(card.id, next);
    } catch (err) {
      this.setLiked(card.id, !next);
      this.toast(err instanceof Error ? err.message : '点赞失败');
    }
  }

  /** 就地更新点赞态。ForEach 的键里带了点赞态，因此改完必须换数组引用触发重建 */
  private setLiked(id: string, liked: boolean): void {
    const next: Array<DynamicCard> = this.items.slice();
    for (let i = 0; i < next.length; i++) {
      if (next[i].id === id) {
        next[i].liked = liked;
        break;
      }
    }
    this.items = next;
    if (this.activeMid === 0) {
      this.mixedItems = next;
    } else {
      this.upItems = next;
    }
  }

  private onComment(card: DynamicCard): void {
    if (card.kind === 'video' && card.video !== null) {
      this.openVideo(card.video as VideoCard, true);
      return;
    }
    this.toast('这条动态还没有接入评论区');
  }

  private onForward(card: DynamicCard): void {
    // 个人动态发布页尚未接入，先占位说明，避免误以为没响应
    this.toast('转发到我的动态：发布页尚未接入，先占位');
  }

  private onShare(card: DynamicCard): void {
    if (card.kind === 'video' && card.video !== null) {
      const video: VideoCard = card.video as VideoCard;
      const title: string = video.title.length > 0 ? video.title : `${card.authorName}的投稿`;
      const url: string = video.bvid.length > 0 ? `https://www.bilibili.com/video/${video.bvid}` : '';
      this.share(title, url);
      return;
    }
    this.share(`${card.authorName}的动态`, `https://t.bilibili.com/${card.id}`);
  }

  /** 优先系统分享面板；面板调不起来时退化为「复制链接」，保证按钮总有反馈 */
  private async share(title: string, url: string): Promise<void> {
    const content: string = url.length > 0 ? `${title} ${url}` : title;
    try {
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        title: title,
        content: content
      };
      const data: systemShare.SharedData = new systemShare.SharedData(record);
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
    } catch (err) {
      console.warn(`MuLiDynamic share failed: ${String(err)}`);
      this.copyLink(url.length > 0 ? url : title);
    }
  }

  private copyLink(text: string): void {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.toast('链接已复制，可粘贴分享');
      }).catch(() => {
        this.toast('复制失败，请手动分享');
      });
    } catch (err) {
      this.toast('复制失败，请手动分享');
    }
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text, duration: 1800 });
    } catch (err) {
      // 提示失败不影响主流程
    }
  }

  private activeUpName(): string {
    for (let i = 0; i < this.quickUps.length; i++) {
      if (this.quickUps[i].mid === this.activeMid) {
        return this.quickUps[i].name;
      }
    }
    return '';
  }

  @Builder
  loginGuide() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
        .fontSize(44)
        .fontColor([$r('app.color.text_tertiary')])
      Text('登录后查看动态')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text('关注的人发布了什么，登录沐哩即可同步')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
        .padding({ left: PAGE_PADDING * 2, right: PAGE_PADDING * 2 })
      Row() {
        Text('扫码登录')
          .fontSize(14)
          .fontColor($r('app.color.text_on_brand'))
          .padding({ left: 26, right: 26, top: 9, bottom: 9 })
          .backgroundColor($r('app.color.brand_primary'))
          .borderRadius(19)
      }
      .margin({ top: 6 })
      .onClick(() => {
        this.openLogin();
      })
    }
    .width('100%')
    .padding({ top: 90, bottom: 80 })
    .justifyContent(FlexAlign.Center)
  }

  /** 单个快捷头像：头像 + 昵称，可选未读小圆点 */
  @Builder
  quickCell(up: QuickUp) {
    Column({ space: 5 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        if (up.face.length > 0) {
          Image(up.face)
            .width(QUICK_AVATAR_SIZE)
            .height(QUICK_AVATAR_SIZE)
            .borderRadius(QUICK_AVATAR_SIZE / 2)
            .objectFit(ImageFit.Cover)
            .alt($r('app.color.bg_field'))
            .draggable(false)
            .borderWidth(this.activeMid === up.mid ? 2 : 0)
            .borderColor($r('app.color.brand_primary'))
        } else {
          Circle()
            .width(QUICK_AVATAR_SIZE)
            .height(QUICK_AVATAR_SIZE)
            .fill($r('app.color.bg_field'))
        }
        if (up.hasUpdate) {
          Circle()
            .width(9)
            .height(9)
            .fill($r('app.color.brand_primary'))
            .borderWidth(1.5)
            .borderColor($r('app.color.bg_card'))
        }
      }
      .width(QUICK_AVATAR_SIZE)
      .height(QUICK_AVATAR_SIZE)

      Text(up.name.length > 0 ? up.name : 'UP')
        .fontSize(10)
        .fontColor(this.activeMid === up.mid ? $r('app.color.brand_primary') : $r('app.color.text_tertiary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width(QUICK_CELL_WIDTH)
    }
    .width(QUICK_CELL_WIDTH)
    .onClick(() => {
      this.pickUp(up.mid);
    })
    .gesture(LongPressGesture().onAction(() => {
      this.openUser(up.mid);
    }))
  }

  /** 首位「综合」入口：恢复默认混排 */
  @Builder
  mixedCell() {
    Column({ space: 5 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(QUICK_AVATAR_SIZE)
          .height(QUICK_AVATAR_SIZE)
          .fill(this.activeMid === 0 ? $r('app.color.brand_tint') : $r('app.color.bg_field'))
        SymbolGlyph($r('sys.symbol.square_grid_2x2'))
          .fontSize(20)
          .fontColor([this.activeMid === 0 ? $r('app.color.brand_primary') : $r('app.color.text_tertiary')])
      }
      .width(QUICK_AVATAR_SIZE)
      .height(QUICK_AVATAR_SIZE)

      Text('综合')
        .fontSize(10)
        .fontColor(this.activeMid === 0 ? $r('app.color.brand_primary') : $r('app.color.text_tertiary'))
        .maxLines(1)
        .width(QUICK_CELL_WIDTH)
        .textAlign(TextAlign.Center)
    }
    .width(QUICK_CELL_WIDTH)
    .onClick(() => {
      this.pickUp(0);
    })
  }

  /**
   * 快捷 UP 主行：横向滚动。一行时平铺，两行时每列竖排两个，
   * 因此「左右滑动」在两行模式下依然只沿水平方向。
   */
  @Builder
  quickStrip() {
    Scroll() {
      Row({ space: 12 }) {
        this.mixedCell()
        // 按列分组：每列 rows() 个头像
        ForEach(this.quickColumns(), (column: Array<QuickUp>) => {
          Column({ space: 10 }) {
            ForEach(column, (up: QuickUp) => {
              this.quickCell(up)
            }, (up: QuickUp) => `q-${up.mid}-${this.activeMid}`)
          }
          .alignItems(HorizontalAlign.Center)
        }, (column: Array<QuickUp>, index: number) => `c-${index}-${this.rows()}`)
      }
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Top)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .width('100%')
  }

  /** 把 quickUps 按列切分（每列 rows() 个），两行模式下即左右并列的双行 */
  private quickColumns(): Array<Array<QuickUp>> {
    const columns: Array<Array<QuickUp>> = [];
    const perColumn: number = this.rows();
    const limit: number = Math.min(this.capacity(), this.quickUps.length);
    for (let i = 0; i < limit; i += perColumn) {
      const column: Array<QuickUp> = [];
      for (let j = 0; j < perColumn && i + j < limit; j++) {
        column.push(this.quickUps[i + j]);
      }
      columns.push(column);
    }
    return columns;
  }

  /** 只看某个 UP 时，在列表上方给一条可撤销的说明 */
  @Builder
  filterBar() {
    Row({ space: 6 }) {
      Text(`只看 ${this.activeUpName().length > 0 ? this.activeUpName() : '该 UP'}`)
        .fontSize(12)
        .fontColor($r('app.color.brand_primary'))
      Blank()
      Text('恢复综合')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      SymbolGlyph($r('sys.symbol.xmark'))
        .fontSize(11)
        .fontColor([$r('app.color.text_secondary')])
    }
    .width('100%')
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 2, bottom: 8 })
    .onClick(() => {
      this.pickUp(0);
    })
  }

  @Builder
  dynamicList() {
    List({ scroller: this.scroller }) {
      ListItem() {
        Row()
          .width('100%')
          .height(this.topInset)
      }

      if (this.needLogin) {
        ListItem() {
          this.loginGuide()
        }
      } else {
        if (this.quickUps.length > 0) {
          ListItem() {
            this.quickStrip()
          }
        }

        if (this.activeMid > 0) {
          ListItem() {
            this.filterBar()
          }
        }

        if (this.loading && this.items.length === 0) {
          ListItem() {
            StateView({ kind: 'loading', message: '正在加载动态' })
          }
        } else if (this.errorText.length > 0 && this.items.length === 0) {
          ListItem() {
            StateView({
              kind: 'error',
              message: this.errorText,
              hint: '动态接口偶发限流，稍后重试',
              onRetry: () => {
                if (this.activeMid > 0) {
                  this.loadFiltered(this.activeMid);
                } else {
                  this.loadFirstPage();
                }
              }
            })
          }
        } else if (this.items.length === 0) {
          ListItem() {
            StateView({
              kind: 'empty',
              message: this.activeMid > 0 ? 'TA 还没有发布动态' : '关注的 UP 还没有新动态',
              hint: '去首页逛逛，关注更多人'
            })
          }
        }

        if (this.items.length > 0) {
          ForEach(this.items, (card: DynamicCard) => {
            ListItem() {
              // 左右留白由这里统一提供：卡片自身已是 width('100%')，
              // 若卡片再加左右 margin 会溢出被裁（右半边不可见）。
              Column() {
                DynamicCardView({
                  card: card,
                  onCardTap: (item: DynamicCard) => {
                    if (item.kind === 'video' && item.video !== null) {
                      this.openVideo(item.video as VideoCard, false);
                      return;
                    }
                    this.toast('图片 / 文字动态：详情页待建设');
                  },
                  onAuthorTap: (mid: number) => {
                    this.openUser(mid);
                  },
                  onLike: (item: DynamicCard) => {
                    this.toggleLike(item);
                  },
                  onComment: (item: DynamicCard) => {
                    this.onComment(item);
                  },
                  onForward: (item: DynamicCard) => {
                    this.onForward(item);
                  },
                  onShare: (item: DynamicCard) => {
                    this.onShare(item);
                  }
                })
              }
              .width('100%')
              .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
            }
          }, (card: DynamicCard) => `${card.id}_${card.liked ? 1 : 0}`)

          if (this.loadingMore) {
            ListItem() {
              ListFooter({ text: '正在加载更多' })
            }
          } else if (!this.hasMore) {
            ListItem() {
              ListFooter({ text: '没有更多动态了', showProgress: false })
            }
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
    .onReachEnd(() => {
      this.loadMore();
    })
  }

  build() {
    Refresh({ refreshing: $$this.refreshing }) {
      this.dynamicList()
    }
    .width('100%')
    .height('100%')
    .onRefreshing(() => {
      this.refreshing = true;
      if (this.activeMid > 0) {
        this.upItems = [];
        this.upOffset = '';
        this.upHasMore = true;
        this.loadFiltered(this.activeMid);
      } else {
        this.mixedItems = [];
        this.mixedOffset = '';
        this.mixedHasMore = true;
        this.nextOffset = '';
        this.hasMore = true;
        this.loadFirstPage();
      }
    })
  }
}