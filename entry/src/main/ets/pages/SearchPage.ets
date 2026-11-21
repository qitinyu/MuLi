import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics, uiMaterial } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { MaterialScope } from '../common/Materials';
import { ListFooter, StateView } from '../components/StateView';
import { LevelBadge } from '../components/LevelBadge';
import { VideoCardView } from '../components/VideoCardView';
import { PAGE_PADDING, TITLE_CTRL_TEXT_SIZE, TITLE_ICON_HIT } from '../common/DesignSpec';
import { shortCount } from '../common/Format';
import { VideoCard, VideoOpenParam } from '../model/BiliModels';
import { SearchBatch, SearchMedia, SearchService, SearchUser } from '../services/SearchService';

/** 结果列表的列间距 */
const CARD_GAP: number = 10;
/** 联想词防抖（ms） */
const SUGGEST_DELAY: number = 260;

/** 类型页签 */
class TypeTab {
  label: string = '';
  value: string = '';

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

/** 排序项 */
class OrderTab {
  label: string = '';
  value: string = '';

  constructor(label: string, value: string) {
    this.label = label;
    this.value = value;
  }
}

/**
 * 搜索页（二级页，全局路由 name = 'search'）。
 *
 * 结构参考前身 Pilihos 的完整搜索：
 *   发现层：输入联想 → 热搜榜 → 搜索历史（长按删单条 / 清空）
 *   结果层：类型页签（视频 / UP主 / 番剧 / 影视）→ 排序（仅视频）→ 结果列表（滚动续页）
 *
 * 顶部搜索栏与首页保持一致：同高（36）、同圆角（18）、内嵌放大镜、同底色 / 材质；
 * 返回键用同规格的圆形胶囊，配合 hideBackButton(true) 避免搜索栏压住系统返回键。
 */
@Component
export struct SearchPage {
  pathStack: NavPathStack | undefined = undefined;
  /** 状态栏 + 标题栏总高度（二级页标题栏是悬浮的，内容必须自己让位） */
  @Prop topInset: number = 95;
  /** 状态栏高度：HdsNavDestination 的内容原点已在状态栏下方，留白要扣掉这一段 */
  @Prop statusBarH: number = 39;
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  @State chipMaterialOn: boolean = false;
  @State keyword: string = '';
  /** 是否已进入结果层（false = 发现层：热搜 + 历史） */
  @State submitted: boolean = false;
  @State searchType: string = SearchService.TYPE_VIDEO;
  @State order: string = SearchService.ORDER_DEFAULT;
  @State videos: Array<VideoCard> = [];
  @State users: Array<SearchUser> = [];
  @State medias: Array<SearchMedia> = [];
  @State searching: boolean = false;
  @State loadingMore: boolean = false;
  @State errorText: string = '';
  @State total: number = 0;
  @State history: Array<string> = [];
  @State hotWords: Array<string> = [];
  @State suggestList: Array<string> = [];
  /** 正在提交关注操作的用户 mid（防连点） */
  @State followBusy: number = 0;

  private page: number = 1;
  private totalPages: number = 0;
  private suggestTimer: number = -1;
  private discoverScroller: Scroller = new Scroller();
  private resultScroller: Scroller = new Scroller();
  private chipMaterial: uiMaterial.ImmersiveMaterial | undefined = undefined;
  private typeTabs: Array<TypeTab> = [
    new TypeTab('视频', SearchService.TYPE_VIDEO),
    new TypeTab('UP主', SearchService.TYPE_USER),
    new TypeTab('番剧', SearchService.TYPE_BANGUMI),
    new TypeTab('影视', SearchService.TYPE_FT)
  ];
  private orderTabs: Array<OrderTab> = [
    new OrderTab('综合排序', SearchService.ORDER_DEFAULT),
    new OrderTab('播放最多', SearchService.ORDER_CLICK),
    new OrderTab('最新发布', SearchService.ORDER_NEW),
    new OrderTab('弹幕最多', SearchService.ORDER_DANMU)
  ];

  aboutToAppear(): void {
    this.materialLevel = MaterialScope.detectLevel();
    try {
      this.chipMaterialOn = uiMaterial.isImmersiveMaterialSupported();
      if (this.chipMaterialOn) {
        this.chipMaterial = new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR });
      }
    } catch (err) {
      this.chipMaterialOn = false;
      this.chipMaterial = undefined;
    }
    const ctx: common.UIAbilityContext | undefined = this.context();
    if (ctx !== undefined) {
      SearchService.loadHistory(ctx).then((list: Array<string>) => {
        this.history = list;
      }).catch(() => {
        // 历史读不到不影响搜索
      });
    }
    SearchService.hotWords().then((words: Array<string>) => {
      this.hotWords = words;
    }).catch(() => {
      // 热搜失败就只展示历史
    });
  }

  aboutToDisappear(): void {
    if (this.suggestTimer !== -1) {
      clearTimeout(this.suggestTimer);
      this.suggestTimer = -1;
    }
  }

  private context(): common.UIAbilityContext | undefined {
    try {
      return this.getUIContext().getHostContext() as common.UIAbilityContext;
    } catch (err) {
      return undefined;
    }
  }

  private back(): void {
    if (this.submitted) {
      // 结果层先退回发现层：比直接退出页面更符合搜索习惯
      this.submitted = false;
      this.suggestList = [];
      this.errorText = '';
      return;
    }
    if (this.pathStack !== undefined) {
      this.pathStack.pop();
    }
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text, duration: 1600 });
    } catch (err) {
      // 忽略
    }
  }

  // ---------------- 搜索 ----------------

  private async doSearch(word: string): Promise<void> {
    const key: string = word.trim();
    if (key.length === 0) {
      this.toast('请输入要搜索的内容');
      return;
    }
    // 提交后收起键盘：结果页要占满屏幕，键盘压着半屏很碍事
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (err) {
      // 焦点控制器不可用时忽略
    }
    this.flushSuggestTimer();
    this.suggestList = [];
    this.keyword = key;
    this.submitted = true;
    this.searching = true;
    this.errorText = '';
    this.videos = [];
    this.users = [];
    this.medias = [];
    this.total = 0;
    this.totalPages = 0;
    this.page = 1;
    this.resultScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    try {
      const batch: SearchBatch = await SearchService.search(this.searchType, key, 1, this.order);
      this.applyBatch(batch, true);
      const ctx: common.UIAbilityContext | undefined = this.context();
      if (ctx !== undefined && this.hasResult(batch)) {
        SearchService.addHistory(ctx, key).then((list: Array<string>) => {
          this.history = list;
        }).catch(() => {
          // 忽略
        });
      }
      if (this.searchType === SearchService.TYPE_USER) {
        this.refreshFollowStates();
      }
    } catch (err) {
      this.errorText = err instanceof Error ? err.message : '搜索失败，请重试';
    } finally {
      this.searching = false;
    }
  }

  /** 把一页结果写入状态；reset = true 覆盖，否则追加 */
  private applyBatch(batch: SearchBatch, reset: boolean): void {
    this.total = batch.total;
    this.totalPages = batch.totalPages;
    this.page = batch.page;
    if (this.searchType === SearchService.TYPE_VIDEO) {
      this.videos = reset ? batch.videos : this.videos.concat(batch.videos);
    } else if (this.searchType === SearchService.TYPE_USER) {
      this.users = reset ? batch.users : this.users.concat(batch.users);
    } else {
      this.medias = reset ? batch.medias : this.medias.concat(batch.medias);
    }
  }

  private hasResult(batch: SearchBatch): boolean {
    return batch.videos.length + batch.users.length + batch.medias.length > 0;
  }

  private async loadMore(): Promise<void> {
    if (this.searching || this.loadingMore || this.page >= this.totalPages) {
      return;
    }
    this.loadingMore = true;
    const nextPage: number = this.page + 1;
    try {
      const batch: SearchBatch = await SearchService.search(this.searchType, this.keyword, nextPage, this.order);
      if (!this.hasResult(batch)) {
        this.totalPages = this.page;
      } else {
        this.applyBatch(batch, false);
        if (this.searchType === SearchService.TYPE_USER) {
          this.refreshFollowStates();
        }
      }
    } catch (err) {
      this.toast('加载下一页失败');
    } finally {
      this.loadingMore = false;
    }
  }

  private switchType(value: string): void {
    if (this.searchType === value || this.searching) {
      return;
    }
    this.searchType = value;
    if (this.submitted) {
      this.doSearch(this.keyword);
    }
  }

  private switchOrder(value: string): void {
    if (this.order === value || this.searching) {
      return;
    }
    this.order = value;
    if (this.submitted) {
      this.doSearch(this.keyword);
    }
  }

  /** 关注态校准：只查前 8 位，避免一次搜索打出几十个请求 */
  private async refreshFollowStates(): Promise<void> {
    for (let i = 0; i < this.users.length && i < 8; i++) {
      const user: SearchUser = this.users[i];
      if (user.mid <= 0) {
        continue;
      }
      const following: boolean = await SearchService.following(user.mid);
      if (following !== user.following) {
        user.following = following;
        this.users = this.users.slice();
      }
    }
  }

  private async toggleFollow(user: SearchUser): Promise<void> {
    if (this.followBusy === user.mid) {
      return;
    }
    this.followBusy = user.mid;
    try {
      const next: boolean = !user.following;
      await SearchService.follow(user.mid, next);
      user.following = next;
      this.users = this.users.slice();
      this.toast(next ? `已关注 ${user.uname}` : '已取消关注');
    } catch (err) {
      this.toast(err instanceof Error ? err.message : '操作失败');
    } finally {
      this.followBusy = 0;
    }
  }

  // ---------------- 输入联想 ----------------

  private flushSuggestTimer(): void {
    if (this.suggestTimer !== -1) {
      clearTimeout(this.suggestTimer);
      this.suggestTimer = -1;
    }
  }

  private onKeywordChanged(value: string): void {
    this.keyword = value;
    this.flushSuggestTimer();
    const term: string = value.trim();
    if (term.length === 0 || this.submitted) {
      this.suggestList = [];
      return;
    }
    this.suggestTimer = setTimeout(() => {
      this.loadSuggest(term);
    }, SUGGEST_DELAY);
  }

  private loadSuggest(term: string): void {
    SearchService.suggest(term).then((words: Array<string>) => {
      // 只接受与当前输入匹配的响应，避免慢响应覆盖新输入
      if (this.keyword.trim() === term && !this.submitted) {
        this.suggestList = words;
      }
    }).catch(() => {
      // 联想失败静默
    });
  }

  private useKeyword(word: string): void {
    this.keyword = word;
    this.suggestList = [];
    this.doSearch(word);
  }

  private removeHistory(word: string): void {
    const ctx: common.UIAbilityContext | undefined = this.context();
    if (ctx === undefined) {
      return;
    }
    SearchService.removeHistory(ctx, word).then((list: Array<string>) => {
      this.history = list;
      this.toast('已删除该条历史');
    }).catch(() => {
      // 忽略
    });
  }

  private clearHistory(): void {
    const ctx: common.UIAbilityContext | undefined = this.context();
    if (ctx === undefined) {
      return;
    }
    SearchService.clearHistory(ctx).then(() => {
      this.history = [];
    }).catch(() => {
      // 忽略
    });
  }

  private openVideo(card: VideoCard): void {
    if (this.pathStack === undefined) {
      return;
    }
    this.pathStack.pushPathByName('video', new VideoOpenParam(card.bvid, card.aid, 0));
  }

  /** 视频结果按两列分组 */
  private videoRows(): Array<Array<VideoCard>> {
    const rows: Array<Array<VideoCard>> = [];
    for (let i = 0; i < this.videos.length; i += 2) {
      const row: Array<VideoCard> = [];
      row.push(this.videos[i]);
      if (i + 1 < this.videos.length) {
        row.push(this.videos[i + 1]);
      }
      rows.push(row);
    }
    return rows;
  }

  private currentCount(): number {
    if (this.searchType === SearchService.TYPE_VIDEO) {
      return this.videos.length;
    }
    if (this.searchType === SearchService.TYPE_USER) {
      return this.users.length;
    }
    return this.medias.length;
  }

  // ---------------- 顶部 ----------------

  /** 返回键：与首页标题栏图标同规格的圆形包裹（40 热区 + 半透明底 + 细描边） */
  @Builder
  backChip() {
    Row() {
      SymbolGlyph($r('sys.symbol.chevron_backward'))
        .fontSize(20)
        .fontColor([$r('app.color.text_primary')])
    }
    .width(40)
    .height(40)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.chipMaterialOn ? Color.Transparent : $r('app.color.title_chip_bg'))
    .backgroundBlurStyle(this.chipMaterialOn ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THIN)
    .systemMaterial(this.chipMaterial)
    .borderRadius(20)
    .margin({ right: 8 })
    .onClick(() => {
      this.back();
    })
    .accessibilityText('返回')
  }

  /** 搜索栏：与首页同款（高 36、圆角 18、放大镜 + 占位文案、同底色 / 材质） */
  @Builder
  searchField() {
    Row({ space: 6 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(16)
        .fontColor([$r('app.color.text_tertiary')])
      TextInput({ text: this.keyword, placeholder: '搜索你感兴趣的内容' })
        .placeholderColor($r('app.color.text_tertiary'))
        .placeholderFont({ size: TITLE_CTRL_TEXT_SIZE - 1 })
        .fontSize(TITLE_CTRL_TEXT_SIZE - 1)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor(Color.Transparent)
        .padding(0)
        .borderRadius(0)
        .height(34)
        .layoutWeight(1)
        .enterKeyType(EnterKeyType.Search)
        .onChange((value: string) => {
          this.onKeywordChanged(value);
        })
        .onSubmit(() => {
          this.doSearch(this.keyword);
        })
      if (this.keyword.length > 0) {
        SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
          .fontSize(15)
          .fontColor([$r('app.color.text_tertiary')])
          .onClick(() => {
            this.onKeywordChanged('');
          })
      }
    }
    .height(36)
    .padding({ left: 12, right: 10 })
    .borderRadius(18)
    .backgroundColor(this.chipMaterialOn ? Color.Transparent : $r('app.color.bg_field'))
    .backgroundBlurStyle(this.chipMaterialOn ? BlurStyle.NONE : BlurStyle.COMPONENT_ULTRA_THIN)
    .systemMaterial(this.chipMaterial)
    .layoutWeight(1)
    .margin({ right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  topRow() {
    Row() {
      this.backChip()
      this.searchField()
      Text('搜索')
        .fontSize(TITLE_CTRL_TEXT_SIZE - 1)
        .fontColor($r('app.color.brand_primary'))
        .onClick(() => {
          this.doSearch(this.keyword);
        })
    }
    .width('100%')
    .height(TITLE_ICON_HIT)
    .padding({ left: 8, right: 12 })
    .alignItems(VerticalAlign.Center)
  }

  // ---------------- 发现层 ----------------

  /** 输入联想（覆盖在发现层顶部） */
  @Builder
  suggestPanel() {
    if (!this.submitted && this.suggestList.length > 0) {
      Column() {
        ForEach(this.suggestList, (word: string, index: number) => {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(14)
              .fontColor([$r('app.color.text_tertiary')])
            Text(word)
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .height(40)
          .padding({ left: 14, right: 14 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.useKeyword(word);
          })
          if (index < this.suggestList.length - 1) {
            Divider()
              .color($r('app.color.divider'))
              .strokeWidth(0.5)
              .margin({ left: 14, right: 14 })
          }
        }, (word: string) => `sg_${word}`)
      }
      .width('100%')
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(14)
      .shadow({ radius: 12, color: $r('app.color.shadow_soft'), offsetY: 2 })
      .margin({ bottom: 12 })
    }
  }

  @Builder
  hotBlock() {
    if (this.hotWords.length > 0) {
      Column({ space: 10 }) {
        Row() {
          Text('哔哩热搜')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text('实时')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          ForEach(this.hotWords, (word: string, index: number) => {
            Row({ space: 5 }) {
              Text(`${index + 1}`)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor(index < 3 ? $r('app.color.brand_primary') : $r('app.color.text_tertiary'))
              Text(word)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('49%')
            .padding({ top: 6, bottom: 6 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.useKeyword(word);
            })
          }, (word: string) => `hot_${word}`)
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(16)
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  historyBlock() {
    Column({ space: 10 }) {
      Row() {
        Text('搜索历史')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.history.length > 0) {
          Text('清空')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .onClick(() => {
              this.clearHistory();
            })
        }
      }
      .width('100%')

      if (this.history.length === 0) {
        Text('暂无搜索历史')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      } else {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.history, (word: string) => {
            Text(word)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .backgroundColor($r('app.color.bg_field'))
              .borderRadius(14)
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.useKeyword(word);
              })
              .gesture(LongPressGesture({ repeat: false }).onAction(() => {
                // 长按删除单条：与点击搜索区分开，不额外弹确认框
                this.removeHistory(word);
              }))
          }, (word: string) => `hist_${word}`)
        }
        .width('100%')

        Text('长按历史词可删除单条')
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  discover() {
    Scroll(this.discoverScroller) {
      Column({ space: 10 }) {
        Row()
          .width('100%')
          .height(8)
        this.suggestPanel()
        this.hotBlock()
        this.historyBlock()
        Row()
          .width('100%')
          .height(24)
      }
      .width('100%')
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
  }

  // ---------------- 结果层 ----------------

  @Builder
  typeTabsBar() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.typeTabs, (tab: TypeTab) => {
          Text(tab.label)
            .fontSize(14)
            .fontWeight(this.searchType === tab.value ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.searchType === tab.value ? $r('app.color.brand_primary') : $r('app.color.text_secondary'))
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .backgroundColor(this.searchType === tab.value ? $r('app.color.brand_tint') : Color.Transparent)
            .borderRadius(16)
            .onClick(() => {
              this.switchType(tab.value);
            })
        }, (tab: TypeTab) => `type_${tab.value}_${this.searchType === tab.value}`)
      }
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
      .alignItems(VerticalAlign.Center)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(44)
  }

  @Builder
  orderBar() {
    if (this.searchType === SearchService.TYPE_VIDEO) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.orderTabs, (tab: OrderTab) => {
            Text(tab.label)
              .fontSize(12)
              .fontColor(this.order === tab.value ? $r('app.color.brand_primary') : $r('app.color.text_tertiary'))
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor(this.order === tab.value ? $r('app.color.brand_tint') : $r('app.color.bg_card'))
              .borderRadius(12)
              .onClick(() => {
                this.switchOrder(tab.value);
              })
          }, (tab: OrderTab) => `order_${tab.value}_${this.order === tab.value}`)
        }
        .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
        .alignItems(VerticalAlign.Center)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(36)
    }
  }

  @Builder
  videoCell(card: VideoCard) {
    Column() {
      VideoCardView({
        card: card,
        compact: true,
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
  videoGrid() {
    ForEach(this.videoRows(), (row: Array<VideoCard>, rowIndex: number) => {
      ListItem() {
        Row({ space: CARD_GAP }) {
          ForEach(row, (card: VideoCard) => {
            this.videoCell(card);
          }, (card: VideoCard) => `sv_${card.bvid}_${card.aid}`)
          if (row.length < 2) {
            Column().layoutWeight(1)
          }
        }
        .width('100%')
        .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
        .alignItems(VerticalAlign.Top)
      }
    }, (row: Array<VideoCard>, rowIndex: number) =>
    `sv_row_${rowIndex}_${row.length > 0 ? row[0].bvid : ''}`)
  }

  /** 等级小标签：直接用素材里的 Lv0~Lv6 矢量图 */
  @Builder
  levelChip(level: number) {
    LevelBadge({ level: level, badgeHeight: 13 })
  }

  @Builder
  followChip(user: SearchUser) {
    Row({ space: 3 }) {
      SymbolGlyph(user.following ? $r('sys.symbol.checkmark') : $r('sys.symbol.plus'))
        .fontSize(11)
        .fontColor([user.following ? $r('app.color.text_tertiary') : $r('app.color.brand_primary')])
      Text(user.following ? '已关注' : '关注')
        .fontSize(11)
        .fontColor(user.following ? $r('app.color.text_tertiary') : $r('app.color.brand_primary'))
    }
    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
    .backgroundColor(user.following ? $r('app.color.bg_field') : $r('app.color.brand_tint'))
    .borderRadius(14)
    .onClick(() => {
      this.toggleFollow(user);
    })
  }

  @Builder
  userRow(user: SearchUser) {
    ListItem() {
      Row({ space: 12 }) {
        if (user.face.length > 0) {
          Image(user.face)
            .width(48)
            .height(48)
            .borderRadius(24)
            .objectFit(ImageFit.Cover)
            .alt($r('app.color.bg_field'))
            .draggable(false)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
              .fontSize(48)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .width(48)
          .height(48)
        }

        Column({ space: 4 }) {
          Row({ space: 5 }) {
            Text(user.uname.length > 0 ? user.uname : '未知用户')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '58%' })
            if (user.level > 0) {
              this.levelChip(user.level)
            }
            Blank()
            this.followChip(user)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(user.sign.length > 0 ? user.sign : '这个人很神秘，什么都没写')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Text(`${shortCount(user.fans)} 粉丝 · ${shortCount(user.videos)} 投稿`)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Top)
      .onClick(() => {
        this.toast(`UP 主主页待建设：${user.uname}`);
      })
    }
  }

  @Builder
  mediaRow(media: SearchMedia) {
    ListItem() {
      Row({ space: 12 }) {
        Image(media.cover)
          .width(74)
          .height(99)
          .objectFit(ImageFit.Cover)
          .borderRadius(8)
          .alt($r('app.color.bg_field'))
          .draggable(false)

        Column({ space: 6 }) {
          Row({ space: 6 }) {
            if (media.typeName.length > 0) {
              Text(media.typeName)
                .fontSize(9)
                .fontColor($r('app.color.brand_primary'))
                .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                .backgroundColor($r('app.color.brand_tint'))
                .borderRadius(3)
            }
            if (media.score > 0) {
              Text(`${media.score.toFixed(1)} 分`)
                .fontSize(10)
                .fontColor($r('app.color.danger'))
            }
            Blank()
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Text(media.title)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .lineHeight(19)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')

          Text(media.subText())
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .width('100%')

          Text(media.styles.length > 0 ? media.styles : media.areas)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Top)
      .onClick(() => {
        this.toast('番剧 / 影视播放待建设');
      })
    }
  }

  @Builder
  resultBody() {
    if (this.searching && this.currentCount() === 0) {
      ListItem() {
        StateView({ kind: 'loading', message: `正在搜索「${this.keyword}」` })
      }
    } else if (this.errorText.length > 0) {
      ListItem() {
        StateView({
          kind: 'error',
          message: this.errorText,
          hint: '检查网络后重试',
          onRetry: () => {
            this.doSearch(this.keyword);
          }
        })
      }
    } else if (this.currentCount() === 0) {
      ListItem() {
        StateView({ kind: 'empty', message: '没有找到相关内容', hint: '换个关键词或切换类型试试' })
      }
    } else {
      if (this.searchType === SearchService.TYPE_VIDEO) {
        this.videoGrid()
      } else if (this.searchType === SearchService.TYPE_USER) {
        ForEach(this.users, (user: SearchUser) => {
          this.userRow(user)
        }, (user: SearchUser) => `su_${user.mid}_${user.following}`)
      } else {
        ForEach(this.medias, (media: SearchMedia) => {
          this.mediaRow(media)
        }, (media: SearchMedia) => `sm_${media.seasonId}`)
      }

      ListItem() {
        if (this.loadingMore) {
          ListFooter({ text: '正在加载更多' })
        } else if (this.page >= this.totalPages && this.totalPages > 0) {
          Row() {
            Text(`已显示全部 ${this.currentCount()} 条结果`)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .height(52)
          .justifyContent(FlexAlign.Center)
        } else {
          ListFooter({ text: '上滑加载更多', showProgress: false })
        }
      }
    }
  }

  @Builder
  resultList() {
    List({ scroller: this.resultScroller }) {
      ListItem() {
        Row() {
          Text(this.summaryText())
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(30)
        .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
        .alignItems(VerticalAlign.Center)
      }

      this.resultBody()

      ListItem() {
        Row()
          .width('100%')
          .height(24)
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onReachEnd(() => {
      this.loadMore();
    })
  }

  private summaryText(): string {
    if (this.searching) {
      return '正在搜索…';
    }
    if (this.total > 0) {
      return `找到约 ${shortCount(this.total)} 个结果`;
    }
    return '';
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.submitted) {
          this.typeTabsBar()
          this.orderBar()
          this.resultList()
        } else {
          this.discover()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: Math.max(56, this.topInset - this.statusBarH) })
      .alignItems(HorizontalAlign.Start)
    }
    .titleBar({
      content: {
        title: { mainTitle: '' },
        stackBuilder: () => {
          this.topRow();
        }
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
    .hideBackButton(true)
    // 系统返回键也遵守「结果层 → 发现层 → 退出」的顺序，避免一格退到底
    .onBackPressed(() => {
      if (this.submitted) {
        this.submitted = false;
        this.suggestList = [];
        this.errorText = '';
        return true;
      }
      return false;
    })
    .bindToScrollable([this.discoverScroller, this.resultScroller])
    .backgroundColor($r('app.color.bg_page'))
  }
}
