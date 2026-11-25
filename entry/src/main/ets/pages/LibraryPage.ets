import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { MaterialScope } from '../common/Materials';
import { PAGE_PADDING } from '../common/DesignSpec';
import { durationText, pubDateText, pubTimeText } from '../common/Format';
import { FavFolder, LibraryItem, VideoOpenParam } from '../model/BiliModels';
import { LibraryService } from '../services/LibraryService';
import { HistoryStore } from '../services/HistoryStore';
import { AuthService } from '../services/AuthService';
import { StateView } from '../components/StateView';

/** 收藏 / 历史 / 稍后再看 三种列表 */
const KIND_FAV: string = 'fav';
const KIND_HISTORY: string = 'history';
const KIND_TOVIEW: string = 'toview';

/** 列表行封面尺寸（16:9） */
const ROW_COVER_W: number = 132;
const ROW_COVER_H: number = 74;
/** 行高（含上下内边距），左滑动作区要跟它对齐 */
const ROW_HEIGHT: number = 94;
/** 左滑动作区单个按钮的宽度（vp）：两个按钮 = 分享 + 移除 */
const SWIPE_ACTION_W: number = 68;

/**
 * 我的收藏 / 观看历史 / 稍后再看（二级路由 name = 'library'）。
 *
 * 一个页面承载三个列表，靠入参 kind 区分，行样式完全共用：
 * - fav：顶部一排收藏夹胶囊，切换即换夹；内容按 mtime 倒序分页；
 * - history：本机记录（HistoryStore）+ 服务端历史（游标翻页）按时间合并去重，
 *   未登录只显示本机记录，服务端失败也不影响本机部分；
 * - toview：服务端稍后再看，左滑可从列表移除。
 *
 * 三个列表都点行进播放页（aid / bvid / cid 都带上，cid 缺失时播放页自己会补）。
 */
@Component
export struct LibraryPage {
  pathStack: NavPathStack | undefined = undefined;
  /** 'fav' | 'history' | 'toview' */
  kind: string = KIND_FAV;
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  @State items: Array<LibraryItem> = [];
  @State folders: Array<FavFolder> = [];
  @State folderId: number = 0;
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State loadingMore: boolean = false;
  @State errorText: string = '';
  /** 非阻塞提示：服务端历史拉取失败但本机记录还在时显示在列表底部 */
  @State noteText: string = '';
  @State hasMore: boolean = false;
  @State loggedIn: boolean = false;
  @StorageLink('loginTick') @Watch('onLoginTick') loginTick: number = 0;
  /** 收藏夹分页页码（从 1 开始） */
  private favPage: number = 1;
  /** 历史的下一页游标 */
  private nextMax: number = 0;
  private nextViewAt: number = 0;
  /** 本机记录被用户移除后本次会话内不再显示（服务端历史里可能还有同一条） */
  private hidden: Array<string> = [];
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.materialLevel = MaterialScope.detectLevel();
    this.loggedIn = AuthService.isLogin();
    this.loadFirst();
  }

  private onLoginTick(): void {
    this.loggedIn = AuthService.isLogin();
    this.loadFirst();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text, duration: 1800 });
    } catch (err) {
      // 无 UI 上下文时忽略
    }
  }

  private titleText(): string {
    if (this.kind === KIND_HISTORY) {
      return '观看历史';
    }
    if (this.kind === KIND_TOVIEW) {
      return '稍后再看';
    }
    return '我的收藏';
  }

  /** 收藏 / 稍后再看需要登录；历史对本机记录开放 */
  private needLogin(): boolean {
    return this.kind !== KIND_HISTORY && !this.loggedIn;
  }

  // ---------------- 数据 ----------------

  private async loadFirst(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    this.noteText = '';
    this.hidden = [];
    try {
      if (this.needLogin()) {
        this.items = [];
        this.folders = [];
        return;
      }
      if (this.kind === KIND_FAV) {
        await this.loadFavFirst();
      } else if (this.kind === KIND_TOVIEW) {
        this.items = await LibraryService.toView();
        this.hasMore = false;
      } else {
        await this.loadHistoryFirst();
      }
    } catch (err) {
      this.items = [];
      this.errorText = err instanceof Error ? err.message : '加载失败，请稍后重试';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private async loadFavFirst(): Promise<void> {
    this.folders = await LibraryService.folders();
    if (this.folders.length === 0) {
      this.items = [];
      this.folderId = 0;
      this.hasMore = false;
      return;
    }
    // 重新载入时尽量停在原夹，夹被删了才回第一个
    let target: number = this.folderId;
    let found: boolean = false;
    for (let i = 0; i < this.folders.length; i++) {
      if (this.folders[i].id === target) {
        found = true;
        break;
      }
    }
    if (!found) {
      target = this.folders[0].id;
    }
    this.folderId = target;
    const page = await LibraryService.favMedias(target, 1);
    this.items = page.items;
    this.favPage = 1;
    this.hasMore = page.hasMore;
  }

  private async loadHistoryFirst(): Promise<void> {
    await HistoryStore.ensure(this.context());
    const local: Array<LibraryItem> = this.visibleLocal();
    this.items = local;
    this.nextMax = 0;
    this.nextViewAt = 0;
    this.hasMore = false;
    if (!this.loggedIn) {
      return;
    }
    try {
      const page = await LibraryService.history(0, 0);
      this.items = LibraryPage.merge(local, page.items, this.hidden);
      this.nextMax = page.max;
      this.nextViewAt = page.viewAt;
      this.hasMore = page.hasMore;
    } catch (err) {
      const message: string = err instanceof Error ? err.message : '观看历史同步失败';
      // 本机记录已经能看了，这里只做一行说明，不把整页打成错误态
      if (this.items.length > 0) {
        this.noteText = `${message}（当前只显示本机记录）`;
      } else {
        this.errorText = message;
      }
    }
  }

  /** 上拉加载下一页：收藏按页码、历史按游标，稍后再看一次给全量所以没有下一页 */
  private async loadMore(): Promise<void> {
    if (!this.hasMore || this.loadingMore || this.loading) {
      return;
    }
    this.loadingMore = true;
    try {
      if (this.kind === KIND_FAV) {
        const page = await LibraryService.favMedias(this.folderId, this.favPage + 1);
        this.favPage = this.favPage + 1;
        const merged: Array<LibraryItem> = this.items.slice();
        const seen: Set<string> = new Set();
        for (let i = 0; i < merged.length; i++) {
          seen.add(LibraryPage.keyOf(merged[i]));
        }
        for (let i = 0; i < page.items.length; i++) {
          const key: string = LibraryPage.keyOf(page.items[i]);
          if (!seen.has(key)) {
            seen.add(key);
            merged.push(page.items[i]);
          }
        }
        this.items = merged;
        this.hasMore = page.hasMore;
      } else if (this.kind === KIND_HISTORY) {
        const page = await LibraryService.history(this.nextMax, this.nextViewAt);
        this.items = LibraryPage.merge(this.items, page.items, this.hidden);
        this.nextMax = page.max;
        this.nextViewAt = page.viewAt;
        this.hasMore = page.hasMore;
      }
    } catch (err) {
      this.toast(err instanceof Error ? err.message : '加载更多失败');
    } finally {
      this.loadingMore = false;
    }
  }

  private async selectFolder(id: number): Promise<void> {
    if (id === this.folderId) {
      return;
    }
    this.folderId = id;
    this.loading = true;
    this.errorText = '';
    try {
      const page = await LibraryService.favMedias(id, 1);
      this.items = page.items;
      this.favPage = 1;
      this.hasMore = page.hasMore;
    } catch (err) {
      this.items = [];
      this.hasMore = false;
      this.errorText = err instanceof Error ? err.message : '收藏内容加载失败';
    } finally {
      this.loading = false;
    }
    this.scroller.scrollEdge(Edge.Top);
  }

  private openVideo(item: LibraryItem): void {
    if (this.pathStack === undefined) {
      this.toast('播放页暂不可用');
      return;
    }
    this.pathStack.pushPathByName('video',
      new VideoOpenParam(item.card.bvid, item.card.aid, item.card.cid));
  }

  /** 是否给这一行挂左滑删除：稍后再看都能删；历史只能删本机记录（服务端那条删不了） */
  private canRemove(item: LibraryItem): boolean {
    if (this.kind === KIND_TOVIEW) {
      return true;
    }
    return this.kind === KIND_HISTORY && item.local;
  }

  /** 分享这一条：系统分享面板，文案与播放页一致（标题 + 播放页链接） */
  private async shareItem(item: LibraryItem): Promise<void> {
    try {
      const title: string = item.card.title.length > 0 ? item.card.title : '沐哩视频';
      const bvid: string = item.card.bvid;
      const content: string = bvid.length > 0
        ? `${title} https://www.bilibili.com/video/${bvid}` : title;
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        title: title,
        content: content
      };
      const data: systemShare.SharedData = new systemShare.SharedData(record);
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      await controller.show(this.context(), {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
    } catch (err) {
      console.warn(`MuLiLibrary share failed: ${String(err)}`);
      this.toast('分享未完成');
    }
  }

  /** 稍后再看 / 本机历史：移除 */
  private async removeFromView(item: LibraryItem): Promise<void> {
    try {
      if (this.kind === KIND_TOVIEW) {
        await LibraryService.removeFromView(item.card.aid);
      } else {
        await HistoryStore.remove(this.context(), item.card.bvid);
      }
      const kept: Array<LibraryItem> = [];
      for (let i = 0; i < this.items.length; i++) {
        if (this.items[i].card.bvid !== item.card.bvid) {
          kept.push(this.items[i]);
        }
      }
      this.items = kept;
      if (this.kind === KIND_HISTORY) {
        this.hidden.push(item.card.bvid);
      }
      this.toast(this.kind === KIND_TOVIEW ? '已从稍后再看移除' : '已从本机记录移除');
    } catch (err) {
      this.toast(err instanceof Error ? err.message : '移除失败');
    }
  }

  private openLogin(): void {
    if (this.pathStack !== undefined) {
      this.pathStack.pushPathByName('login', '');
    }
  }

  private visibleLocal(): Array<LibraryItem> {
    const all: Array<LibraryItem> = HistoryStore.list();
    if (this.hidden.length === 0) {
      return all;
    }
    const result: Array<LibraryItem> = [];
    for (let i = 0; i < all.length; i++) {
      if (this.hidden.indexOf(all[i].card.bvid) < 0) {
        result.push(all[i]);
      }
    }
    return result;
  }

  private static keyOf(item: LibraryItem): string {
    return item.card.bvid.length > 0 ? item.card.bvid : `${item.card.aid}`;
  }

  /** 合并两份列表：按时间倒序、同 bvid 只留一条（先出现的优先，即本机记录优先） */
  private static merge(base: Array<LibraryItem>, extra: Array<LibraryItem>,
    hidden: Array<string>): Array<LibraryItem> {
    const result: Array<LibraryItem> = [];
    const seen: Set<string> = new Set();
    for (let i = 0; i < base.length; i++) {
      const key: string = LibraryPage.keyOf(base[i]);
      if (seen.has(key) || hidden.indexOf(key) >= 0) {
        continue;
      }
      seen.add(key);
      result.push(base[i]);
    }
    for (let i = 0; i < extra.length; i++) {
      const key: string = LibraryPage.keyOf(extra[i]);
      if (seen.has(key) || hidden.indexOf(key) >= 0) {
        continue;
      }
      seen.add(key);
      result.push(extra[i]);
    }
    result.sort((a: LibraryItem, b: LibraryItem) => b.timeTs - a.timeTs);
    return result;
  }

  // ---------------- 行 ----------------

  /** 封面上的进度条：只在看过一段且知道总时长时画 */
  private hasProgress(item: LibraryItem): boolean {
    return item.progress > 0 && item.card.duration > 0;
  }

  private progressPercent(item: LibraryItem): number {
    if (item.card.duration <= 0) {
      return 0;
    }
    const pct: number = Math.floor(item.progress / item.card.duration * 100);
    return Math.max(1, Math.min(100, pct));
  }

  /** 行内第二行：UP 主 + 场景相关的时间 / 播放量 */
  private metaLine(item: LibraryItem): string {
    const author: string = item.card.author.length > 0 ? item.card.author : '未知 UP';
    if (this.kind === KIND_HISTORY) {
      const when: string = pubTimeText(item.timeTs);
      return when.length > 0 ? `${author} · ${when}观看` : author;
    }
    if (this.kind === KIND_TOVIEW) {
      return item.card.viewText.length > 0 ? `${author} · ${item.card.viewText}` : author;
    }
    const when: string = pubDateText(item.timeTs);
    return when.length > 0 ? `${author} · 收藏于 ${when}` : author;
  }

  /** 行内第三行：进度（历史 / 稍后再看）或时长（收藏） */
  private subLine(item: LibraryItem): string {
    if (this.kind === KIND_FAV) {
      return item.card.duration > 0 ? `时长 ${durationText(item.card.duration)}` : '';
    }
    if (this.hasProgress(item)) {
      return `看到 ${durationText(item.progress)} / ${durationText(item.card.duration)}`;
    }
    if (item.card.duration > 0) {
      return `时长 ${durationText(item.card.duration)}`;
    }
    return '';
  }

  @Builder
  itemRow(item: LibraryItem) {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.Bottom }) {
        Image(item.card.cover)
          .width(ROW_COVER_W)
          .height(ROW_COVER_H)
          .objectFit(ImageFit.Cover)
          .borderRadius(7)
          .alt($r('app.color.bg_field'))
          .draggable(false)

        if (this.hasProgress(item)) {
          Row() {
            Row()
              .layoutWeight(this.progressPercent(item))
              .height(2.5)
              .backgroundColor($r('app.color.brand_primary'))
            if (this.progressPercent(item) < 100) {
              Row()
                .layoutWeight(100 - this.progressPercent(item))
                .height(2.5)
            }
          }
          .width('100%')
        }

        // 右下角时长：与卡片列表口径一致
        if (item.card.duration > 0) {
          Row() {
            Blank()
            Text(durationText(item.card.duration))
              .fontSize(10)
              .fontColor($r('app.color.text_on_media'))
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .backgroundColor($r('app.color.scrim'))
              .borderRadius(3)
          }
          .width('100%')
          .padding({ right: 4, bottom: 4 })
        }
      }
      .width(ROW_COVER_W)
      .height(ROW_COVER_H)
      .clip(true)

      Column({ space: 4 }) {
        Text(item.card.title.length > 0 ? item.card.title : '已失效的视频')
          .width('100%')
          .fontSize(14)
          .lineHeight(19)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 4 }) {
          if (item.card.vertical) {
            Text('竖屏')
              .fontSize(9)
              .fontColor($r('app.color.brand_primary'))
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .backgroundColor($r('app.color.brand_tint'))
              .borderRadius(3)
          }
          Text(this.metaLine(item))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.subLine(item).length > 0) {
          Text(this.subLine(item))
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(ROW_HEIGHT)
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openVideo(item);
    })
  }

  /**
   * 左滑动作区：分享（所有行）+ 移除（只有能删的行）。
   *
   * 动作区整块 hitTestBehavior(Block)，避免点击穿透到下面的 ListItem（以前点了只收起左滑，删不掉）。
   */
  @Builder
  rowActions(item: LibraryItem) {
    Row() {
      Row({ space: 4 }) {
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
        Text('分享')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      }
      .width(SWIPE_ACTION_W)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.bg_field'))
      .onClick(() => {
        this.shareItem(item);
      })

      if (this.canRemove(item)) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_on_brand')])
          Text(this.kind === KIND_TOVIEW ? '移除' : '删除')
            .fontSize(12)
            .fontColor($r('app.color.text_on_brand'))
        }
        .width(SWIPE_ACTION_W)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.danger'))
        .onClick(() => {
          this.removeFromView(item);
        })
      }
    }
    .height('100%')
    .alignItems(VerticalAlign.Center)
    // 注意不能用 HitTestMode.Block：它会连子节点的点击一起吞掉（按钮就点不动了），
    // 默认模式即可——动作区浮在 ListItem 之上，子按钮先拿到事件
  }

  // ---------------- 收藏夹胶囊 ----------------

  @Builder
  folderStrip() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.folders, (folder: FavFolder) => {
          Row({ space: 5 }) {
            Text(folder.title)
              .fontSize(13)
              .fontColor(this.folderId === folder.id
                ? $r('app.color.text_on_brand') : $r('app.color.text_secondary'))
              .maxLines(1)
              .constraintSize({ maxWidth: 180 })
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(`${folder.count}`)
              .fontSize(11)
              .fontColor(this.folderId === folder.id
                ? $r('app.color.text_on_brand') : $r('app.color.text_tertiary'))
              .opacity(0.85)
          }
          .height(32)
          .padding({ left: 14, right: 14 })
          .backgroundColor(this.folderId === folder.id
            ? $r('app.color.brand_primary') : $r('app.color.bg_field'))
          .borderRadius(16)
          .onClick(() => {
            this.selectFolder(folder.id);
          })
        }, (folder: FavFolder) => `folder_${folder.id}`)
      }
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
      .height(44)
      .alignItems(VerticalAlign.Center)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  // ---------------- 未登录 ----------------

  @Builder
  loginBlock() {
    Column({ space: 10 }) {
      SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
        .fontSize(34)
        .fontColor([$r('app.color.text_tertiary')])
      Text(this.kind === KIND_FAV ? '登录后查看我的收藏' : '登录后查看稍后再看')
        .fontSize(15)
        .fontColor($r('app.color.text_secondary'))
      Text('收藏夹与稍后再看都存在账号上，登录即可同步')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
      Row() {
        Text('去登录')
          .fontSize(14)
          .fontColor($r('app.color.text_on_brand'))
          .padding({ left: 26, right: 26, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.brand_primary'))
          .borderRadius(18)
      }
      .margin({ top: 4 })
      .onClick(() => {
        this.openLogin();
      })
    }
    .width('100%')
    .padding({ left: PAGE_PADDING * 3, right: PAGE_PADDING * 3, top: 96, bottom: 60 })
    .alignItems(HorizontalAlign.Center)
  }

  // ---------------- 列表 ----------------

  @Builder
  listBody() {
    List({ scroller: this.scroller }) {
      // 标题栏是透明浮层（HdsNavDestination），列表要自己让出这条高度，否则首条内容顶到状态栏
      ListItem() {
        Row()
          .width('100%')
          .height(64)
      }

      if (this.kind === KIND_FAV && this.folders.length > 1) {
        ListItem() {
          this.folderStrip()
        }
      }

      if (this.needLogin()) {
        ListItem() {
          this.loginBlock()
        }
      } else if (this.loading && this.items.length === 0) {
        ListItem() {
          StateView({ kind: 'loading', message: `正在加载${this.titleText()}` })
        }
      } else if (this.errorText.length > 0 && this.items.length === 0) {
        ListItem() {
          StateView({
            kind: 'error',
            message: this.errorText,
            hint: this.loggedIn ? '下拉或点重试再试一次' : '登录后即可查看',
            onRetry: () => {
              this.loadFirst();
            }
          })
        }
      } else if (this.items.length === 0) {
        ListItem() {
          StateView({
            kind: 'empty',
            message: this.emptyText(),
            hint: this.emptyHint()
          })
        }
      } else {
        ForEach(this.items, (item: LibraryItem) => {
          ListItem() {
            this.itemRow(item)
          }
          .swipeAction({
            end: {
              builder: () => {
                this.rowActions(item)
              }
            },
            // 不给 onAction：整条滑到底就触发动作太容易误触（想看看按钮，结果直接分享/删了）
            edgeEffect: SwipeEdgeEffect.Spring
          })
        }, (item: LibraryItem, index: number) => `${index}_${LibraryPage.keyOf(item)}`)

        if (this.noteText.length > 0) {
          ListItem() {
            Text(this.noteText)
              .width('100%')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .textAlign(TextAlign.Center)
              .padding({ left: PAGE_PADDING * 2, right: PAGE_PADDING * 2, top: 16 })
          }
        }

        if (this.loadingMore) {
          ListItem() {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color($r('app.color.text_tertiary'))
              Text('加载中')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            .height(52)
            .justifyContent(FlexAlign.Center)
          }
        } else if (!this.hasMore && this.items.length >= 8) {
          ListItem() {
            Text('没有更多了')
              .width('100%')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .textAlign(TextAlign.Center)
              .padding({ top: 18 })
          }
        }
      }

      ListItem() {
        Row()
          .width('100%')
          .height(48)
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

  private emptyText(): string {
    if (this.kind === KIND_FAV) {
      return '这个收藏夹还是空的';
    }
    if (this.kind === KIND_TOVIEW) {
      return '还没有稍后再看的视频';
    }
    return '还没有观看记录';
  }

  private emptyHint(): string {
    if (this.kind === KIND_FAV) {
      return '在播放页点「收藏」就能把视频放进来';
    }
    if (this.kind === KIND_TOVIEW) {
      return '在播放页点「再看」即可加入';
    }
    return '播放过的视频会出现在这里';
  }

  build() {
    HdsNavDestination() {
      Refresh({ refreshing: $$this.refreshing }) {
        this.listBody()
      }
      .width('100%')
      .height('100%')
      .onRefreshing(() => {
        this.refreshing = true;
        this.loadFirst();
      })
    }
    .titleBar({
      content: {
        title: { mainTitle: this.titleText() }
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
