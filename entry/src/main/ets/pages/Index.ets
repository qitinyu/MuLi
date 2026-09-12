import { VideoItem } from '../models/VideoItem';
import { DynamicEntry } from '../services/DynamicService';
import { VideoDetailService } from '../services/VideoDetailService';
import { RecommendationService, RecommendationBatch } from '../services/RecommendationService';
import { ReplyService, VideoComment, CommentBatch } from '../services/ReplyService';
import { PlaybackService, PlaybackResolveResult, QualityOption } from '../services/PlaybackService';
import { BiliHttpClient } from '../services/BiliHttpClient';
import { DanmakuService } from '../services/DanmakuService';
import { InteractionService } from '../services/InteractionService';
import { WbiService } from '../services/WbiService';
import { AuthService, AuthSession } from '../services/AuthService';
import { VideoPreloader } from '../services/VideoPreloader';
import { PlayerSettingsService } from '../services/PlayerSettingsService';
import { CommentViewModel, CommentInitDeps } from '../viewmodels/CommentViewModel';
import { InteractionViewModel, InteractionInitDeps } from '../viewmodels/InteractionViewModel';
import { FeedViewModel, FeedInitDeps } from '../viewmodels/FeedViewModel';
import { Logger, LogLevel } from '../utils/Logger';
import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import { Want } from '@kit.AbilityKit';
import window from '@ohos.window';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import { systemShare } from '@kit.ShareKit';
import { AdvancedFeatures } from '../utils/AdvancedFeatures';
import { FilterWords } from '../utils/FilterWords';
import { FormatUtils } from '../utils/FormatUtils';
import { PlaybackMemory } from '../utils/PlaybackMemory';
import { CommentShield } from '../utils/CommentShield';
import { FollowState } from '../utils/FollowState';
import { FavFolder } from '../services/InteractionService';
import { BiliEmoji, EmojiService } from '../services/EmojiService';
import { HomeTab } from '../components/HomeTab';
import { HomeBottomBar } from '../components/HomeBottomBar';
import { MineSidebar } from '../components/Sidebars';
import { LoginPage, WebLoginPage } from '../components/LoginViews';
import { PlayerScreen } from '../components/PlayerScreen';
import { KeyboardAvoidMode } from '@kit.ArkUI';

/**
 * 首页宿主：持有全局状态（@Provide）与全部业务逻辑；
 * 界面区块拆分为 components/ 下的独立组件（信息流/底栏/侧边栏/登录/详情/播放浮层）。
 */
@Entry
@Component
struct Index {
  @Provide showVertical: boolean = false;
  @Provide landscapePlayback: boolean = false;
  @Provide verticalExpanded: boolean = false;
  @Provide videoWeight: number = 6;
  @Provide pendingResumeMs: number = 0;
  @Provide portraitBadge: boolean = true;
  @Provide followStamp: number = 0;
  @Provide currentIndex: number = 0;
  @Provide loading: boolean = false;
  @Provide exitAnimProgress: number = 1; // 1=正常显示, 0=完全透明，用于退出过渡动画
  @Provide loadingMore: boolean = false;
  @State refreshing: boolean = false;
  @State keepRefreshContent: boolean = false;
  @Provide compactGrid: boolean = false;
  @Provide floatBallSwapped: boolean = false;
  @State bottomBarPinned: boolean = true;
  @Provide autoRotateEnabled: boolean = false;
  @Provide bottomBarVisible: boolean = true;
  private bottomBarTimer: number = -1;
  private page: number = 0;
  private recommendationIndex: string = '0';
  private homeGridScroller: Scroller = new Scroller();
  private lastLoadTriggerLength: number = -1;
  private refreshRunning: boolean = false;
  @Provide loadError: string = '';
  @Provide activeTab: number = 1;
  @Provide contentTab: number = 1;
  @Provide selectedTopTab: number = 1;
  @State searchResults: VideoItem[] = [];
  private lastSearchNonce: string = '';
  @Provide loginVisible: boolean = false;
  @Provide webLoginVisible: boolean = false;
  @Provide loginNotice: string = '';
  @Provide authSession: AuthSession | null = null;
  @Provide danmakuText: string = '';
  @Provide detailExpanded: boolean = false;
  @State autoExpandDescription: boolean = false;
  @Provide detailLoading: boolean = false;
  @Provide detailError: string = '';
  @Provide sidebar: number = 0;
  @Provide currentUrl: string = '';
  @Provide videoMounted: boolean = false;
  @Provide playbackStarting: boolean = false;
  @Provide playbackReady: boolean = false;
  @State playbackUrls: string[] = [];
  @State playbackUrlIndex: number = 0;
  @Provide playerError: string = '';
  @Provide defaultQuality: number = 0;
  @Provide videoQuickActionsEnabled: boolean = false;
  @Provide playbackQualities: QualityOption[] = [];
  @Provide currentQn: number = 0;
  @Provide qualityMenuVisible: boolean = false;
  @Provide playMode: number = 0;
  @Provide @Watch('onSequentialChainChange') sequentialChain: boolean = false;
  @Provide @Watch('onDefaultSpeedChange') defaultSpeed: number = 1.0;
  @Provide playbackCurrentMs: number = 0;
  @Provide playbackDurationMs: number = 0;
  @Provide playbackPaused: boolean = true;
  @Provide playbackSpeed: number = 1.0;
  @Provide speedMenuVisible: boolean = false;
  @State episodeListVisible: boolean = false;
  @Provide playbackControlsVisible: boolean = true;
  @Provide playbackFinished: boolean = false;
  @Provide recommendedPlaybackIndex: number = -1;
  @Provide subtitlesEnabled: boolean = false;
  @Provide danmakuEnabled: boolean = true;
  @Provide @Watch('onDanmakuFontSizeChange') danmakuFontSize: number = 40;
  @Provide @Watch('onDanmakuOpacityChange') danmakuOpacity: number = 1;
  @Provide @Watch('onDanmakuSpeedChange') danmakuSpeed: number = 1;
  @Provide @Watch('onDanmakuAreaChange') danmakuArea: number = 100;
  @Provide topInset: number = 0;
  @Provide bottomInset: number = 0;
  @Provide keyboardInset: number = 0;
  @Provide detailSection: number = 0;
  @Provide comments: VideoComment[] = [];
  @Provide expandedCommentId: number = -1;
  @Provide subReplies: VideoComment[] = [];
  @Provide subLoading: boolean = false;
  private subPage: number = 1;
  @Provide subHasMore: boolean = false;
  @Provide showCommentInput: boolean = false;
  @Provide commentInputText: string = '';
  @Provide commentReplyTarget: string = '';
  private commentReplyRootId: number = 0;
  private commentReplyParentId: number = 0;
  @Provide commentLoading: boolean = false;
  @Provide commentError: string = '';
  private commentPage: number = 1;
  @Provide commentTotal: number = 0;
  @Provide commentHasMore: boolean = false;
  @Provide commentSort: string = '0';
  @State useAdvancedMaterial: boolean = false;
  @State favSheetVisible: boolean = false;
  @State playModeSheetVisible: boolean = false;
  @Provide emojiLoading: boolean = false;
  @Provide emojiItems: BiliEmoji[] = [];
  @Provide recentEmojis: string[] = [];
  @Provide emojiPanelVisible: boolean = false;
  @State favFolders: FavFolder[] = [];
  @State favError: string = '';
  @State newFavVisible: boolean = false;
  @State newFavTitle: string = '';
  @State newFavCreating: boolean = false;
  // 收藏夹删除模式：点击 delfiles 进入，勾选文件夹后批量删除
  @State favDeleteMode: boolean = false;
  @State favDeleteIds: number[] = [];
  // 消息跳转上下文：自动展开目标楼层回复（rpid/rootId 由消息页经路由回传）
  private pendingReplyRpid: number = -1;
  private pendingReplyRoot: number = -1;
  private lastMessageNonce: string = '';
  // 消息跳转前快照推荐流，播放退出后恢复（避免整表替换造成的"自动刷新"）
  private savedFeedVideos: VideoItem[] = [];
  private savedFeedIndex: number = 0;
  private feedSnapshotActive: boolean = false;
  // 本轮播放来自消息页：退出后回到消息页
  private jumpFromMessage: boolean = false;
  private savedGridOffset: number = 0;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private playbackRequest: number = 0;
  // 二级播放页的浏览栈：推荐视频进入新层，左上角返回只回退一层。
  private playbackHistory: number[] = [];
  private restoringPlaybackHistory: boolean = false;
  private detailRequest: number = 0;
  private playbackControlsTimer: number = 0;
  private hasMoreRecommendations: boolean = true;
  @Provide videos: VideoItem[] = Index.placeholderVideos();
  @Provide relatedVideos: VideoItem[] = [];
  @Provide relatedLoading: boolean = false;
  private relatedRequest: number = 0;
  @Provide randomPool: VideoItem[] = [];
  private randomPoolIndex: string = '0';
  private randomPoolFetching: boolean = false;

  // ViewModel 实例：封装业务逻辑，减少 Index 代码量
  private commentVM: CommentViewModel = new CommentViewModel();
  private interactionVM: InteractionViewModel = new InteractionViewModel();
  private feedVM: FeedViewModel = new FeedViewModel();

  private static placeholderVideos(): VideoItem[] {
    const result: VideoItem[] = [];
    for (let index: number = 0; index < 10; index++) {
      result.push({
        id: index + 1, aid: 0, bvid: '', cid: 0, title: '', author: '', cover: '',
        viewCount: 0, danmuCount: 0, likeCount: 0, commentCount: 0,
        followed: false, duration: 0, playUrl: '', placeholder: true, publishTime: 0, description: '', tags: [], detailLoaded: false
      });
    }
    return result;
  }

  private async setSystemBarAppearance(lightIcon: boolean): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      await mainWindow.setWindowSystemBarProperties({
        // Keep the system areas opaque so the device wallpaper/system tint
        // cannot bleed into the light home background.
        // Let the fullscreen page background continue under the system bars.
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        isStatusBarLightIcon: lightIcon,
        isNavigationBarLightIcon: lightIcon
      });
    } catch (error) {
      console.error('Pilihos system bar appearance failed: ' + String(error));
    }
  }

  aboutToAppear(): void {
    // 键盘覆盖评论区，由页面按键盘避让区手动抬起编辑器，视频区保持原位。
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.NONE);
    this.setSystemBarAppearance(true);
    BiliHttpClient.initDeviceIdentity(this.context);
    WbiService.warmup();
    this.authSession = AuthService.currentSession();
    AdvancedFeatures.loadSettings(this.context);
    this.loadPlayerSettings();
    FilterWords.load(this.context);
    PlaybackMemory.load(this.context);
    // 初始化 ViewModel
    const commentDeps: CommentInitDeps = { showToast: (msg: string): void => { this.showPlaybackToast(msg); } };
    const interactionDeps: InteractionInitDeps = { showToast: (msg: string): void => { this.showPlaybackToast(msg); } };
    const feedDeps: FeedInitDeps = { showToast: (msg: string): void => { this.showPlaybackToast(msg); }, keepRefreshContent: false };
    this.commentVM.init(commentDeps);
    this.interactionVM.init(interactionDeps);
    this.feedVM.init(feedDeps);
    this.restoreAuthSession();
    this.loadRecommendations();
    this.updateSystemInsets();
    CommentShield.load(this.context);
    EmojiService.loadRecentEmojis(this.context).then((names: string[]): void => {
      this.recentEmojis = names;
    }).catch((): void => {
    });
  }

  private async updateSystemInsets(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navigationArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const keyboardArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
      this.topInset = px2vp(systemArea.topRect.height);
      this.bottomInset = px2vp(navigationArea.bottomRect.height);
      this.keyboardInset = px2vp(keyboardArea.bottomRect.height);
      mainWindow.on('avoidAreaChange', (data): void => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          this.topInset = px2vp(data.area.topRect.height);
        } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          this.bottomInset = px2vp(data.area.bottomRect.height);
        } else if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
          this.keyboardInset = px2vp(data.area.bottomRect.height);
        }
      });
    } catch (error) {
      console.error('Pilihos content inset update failed: ' + String(error));
    }
  }

  private selectContentTab(index: number): void {
    this.selectedTopTab = index;
    this.contentTab = index;
    this.syncTabs();
    this.loadError = '';
  }

  private syncTabs(): void {
    if (this.contentTab === 0) {
      this.activeTab = 1; // 直播
    } else if (this.contentTab === 1) {
      this.activeTab = 1; // 推荐
    } else if (this.contentTab === 2) {
      this.activeTab = 1; // 热门
    } else if (this.contentTab === 3) {
      this.activeTab = 0; // 动态
    } else if (this.contentTab === 4) {
      this.activeTab = 1; // 番剧
    }
  }

  onPageShow(): void {
    this.loadPlayerSettings();
    this.consumeSearchPayload();
    this.consumeMessagePayload();
    this.applyAutoRotate();
  }

  // 消息页回传：直接进入播放（评论区展开），跳转前快照推荐流、退出后恢复
  private consumeMessagePayload(): void {
    const params: Object | undefined = router.getParams() as Object | undefined;
    if (params === undefined) return;
    const payload: Object | undefined =
      (params as Record<string, Object>)['pilihosMessage'] as Object | undefined;
    if (payload === undefined) return;
    const payloadRecord: Record<string, Object> = payload as Record<string, Object>;
    const nonce: string = String(payloadRecord['nonce'] ?? '');
    if (nonce === '' || nonce === this.lastMessageNonce) return;
    const video: VideoItem | undefined = payloadRecord['video'] as VideoItem | undefined;
    if (video === undefined) return;
    this.lastMessageNonce = nonce;
    if (!this.feedSnapshotActive) {
      this.savedFeedVideos = this.videos;
      this.savedFeedIndex = this.currentIndex;
      this.feedSnapshotActive = true;
    }
    this.jumpFromMessage = true;
    this.pendingReplyRpid = Number(payloadRecord['rpid'] ?? -1);
    this.pendingReplyRoot = Number(payloadRecord['rootId'] ?? -1);
    this.openDynamicVideo(video, true);
  }

  private async loadPlayerSettings(): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_player');
      this.keepRefreshContent = store.getSync('keep_refresh_content', false) as boolean;
      this.autoExpandDescription = store.getSync('auto_expand_description', false) as boolean;
      this.defaultQuality = store.getSync('default_quality', 0) as number;
      this.videoQuickActionsEnabled = store.getSync('video_quick_actions', false) as boolean;
      this.playMode = store.getSync('play_mode', 0) as number;
      this.sequentialChain = store.getSync('sequential_chain', false) as boolean;
      const storedSpeed: number = store.getSync('default_speed', 1) as number;
      this.defaultSpeed = storedSpeed >= 0.5 && storedSpeed <= 2 ? storedSpeed : 1.0;
      const storedFontSize: number = store.getSync('danmaku_font_size', 45) as number;
      this.danmakuFontSize = this.normalizeDanmakuFontSize(storedFontSize);
      this.danmakuOpacity = store.getSync('danmaku_opacity', 1) as number;
      this.danmakuSpeed = store.getSync('danmaku_speed', 1) as number;
      this.danmakuArea = this.normalizeDanmakuArea(store.getSync('danmaku_area', 100) as number);
      const appearanceStore: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_ui');
      this.floatBallSwapped = appearanceStore.getSync('float_ball_swapped', false) as boolean;
      this.bottomBarPinned = appearanceStore.getSync('bottom_bar_pinned', true) as boolean;
      this.portraitBadge = appearanceStore.getSync('portrait_badge', true) as boolean;
      this.autoRotateEnabled = appearanceStore.getSync('auto_rotate_enabled', false) as boolean;
      if (this.bottomBarPinned) this.bottomBarVisible = true;

      // 加载高级功能设置状态
      await AdvancedFeatures.loadSettings(this.context);
      this.useAdvancedMaterial = AdvancedFeatures.isImmersiveMaterialEnabled();
    } catch (error) {
      console.error('Pilihos player settings load failed: ' + String(error));
    }
  }

  private async loadRecommendations(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    try {
      const batch: RecommendationBatch = await RecommendationService.loadBatch('0');
      if (batch.items.length > 0) {
        this.page = 0;
        this.recommendationIndex = batch.nextIndex;
        this.videos = batch.items.filter((item: VideoItem): boolean =>
          !FilterWords.isVideoFiltered(item.title));
        this.lastLoadTriggerLength = -1;
        this.hasMoreRecommendations = true;
        // 触发预加载前几个视频的详情
        const cookie: string = this.playbackCookie();
        VideoPreloader.preloadBatch(this.videos, 0, cookie);
      }
    } catch (error) {
      this.loadError = '推荐加载失败，请检查网络';
      console.error(`Pilihos recommendation failed: ${String(error)}`);
    } finally {
      this.loading = false;
    }
  }

  private openSearchPanel(): void {
    router.pushUrl({ url: 'pages/SearchPage' }).catch((error: BusinessError): void => {
      console.error('Pilihos search page failed: ' + String(error));
    });
  }

  private consumeSearchPayload(): void {
    const params: Object | undefined = router.getParams() as Object | undefined;
    if (params === undefined) return;
    const payload: Object | undefined =
      (params as Record<string, Object>)['pilihosPlayback'] as Object | undefined;
    if (payload === undefined) return;
    const payloadRecord: Record<string, Object> = payload as Record<string, Object>;
    const nonce: string = String(payloadRecord['nonce'] ?? '');
    if (nonce === '' || nonce === this.lastSearchNonce) return;
    const results: VideoItem[] = payloadRecord['results'] as VideoItem[];
    const index: number = Number(payloadRecord['index']);
    if (!Array.isArray(results) || Number.isNaN(index) || index < 0 || index >= results.length) return;
    this.lastSearchNonce = nonce;
    this.searchResults = results;
    this.openSearchResult(results[index]);
  }

  private async refreshRecommendations(): Promise<void> {
    if (this.loadingMore) {
      return;
    }
    this.loadError = '';
    try {
      await this.loadPlayerSettings();
      const batch: RecommendationBatch = await RecommendationService.loadBatch('0', true);
      const fresh: VideoItem[] = batch.items;
      if (fresh.length > 0) {
        this.recommendationIndex = batch.nextIndex;
        const existing: Set<string> = new Set<string>(this.videos.map((item: VideoItem): string =>
          item.bvid !== '' ? item.bvid : `${item.aid}`));
        const additions: VideoItem[] = fresh.filter((item: VideoItem): boolean => {
          const key: string = item.bvid !== '' ? item.bvid : `${item.aid}`;
          return !existing.has(key);
        });
        this.videos = this.keepRefreshContent ? additions.concat(this.videos) : fresh;
        this.page = 0;
        this.hasMoreRecommendations = true;
        this.lastLoadTriggerLength = -1;
      }
    } catch (error) {
      this.loadError = '推荐刷新失败，请检查网络';
      console.error(`Pilihos recommendation refresh failed: ${String(error)}`);
    }
  }

  private async loadVideoDetail(): Promise<void> {
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.placeholder || item.detailLoaded) return;
    const requestId: number = this.detailRequest + 1;
    this.detailRequest = requestId;
    this.detailLoading = true;
    this.detailError = '';
    try {
      // 优先使用预加载的数据
      const preloaded: VideoItem | null = VideoPreloader.getPreloadedDetail(item.aid);
      let updated: VideoItem;
      if (preloaded !== null) {
        updated = preloaded;
        console.info(`Pilihos using preloaded detail for aid=${item.aid}`);
      } else {
        updated = await VideoDetailService.load(item);
      }
      if (requestId !== this.detailRequest || this.videos[this.currentIndex] !== item) return;
      this.videos = this.videos.map((candidate: VideoItem): VideoItem =>
        candidate.id === item.id ? updated : candidate);
    } catch (error) {
      if (requestId === this.detailRequest) {
        this.detailError = '视频详情获取失败';
        console.error('Pilihos video detail failed: ' + String(error));
      }
    } finally {
      if (requestId === this.detailRequest) this.detailLoading = false;
    }
  }

  private async loadComments(refresh: boolean = true): Promise<void> {
    if (this.commentLoading) return;
    this.commentLoading = true;
    this.commentError = '';
    const nextPage: number = refresh ? 1 : this.commentPage + 1;
    try {
      const current: VideoItem = this.videos[this.currentIndex];
      const detailed: VideoItem = current.aid > 0 ? current : await VideoDetailService.load(current);
      if (current.aid <= 0) {
        this.videos = this.videos.map((candidate: VideoItem): VideoItem =>
          candidate.id === detailed.id ? detailed : candidate);
      }
      const session: AuthSession | null = this.authSession ?? AuthService.currentSession();
      const batch: CommentBatch = await ReplyService.loadVideoComments(
        detailed, session === null ? '' : session.cookie, nextPage, this.commentSort);
      const visible: VideoComment[] =
        batch.items.filter((entry: VideoComment): boolean => !CommentShield.isHidden(entry.id));
      this.comments = refresh ? visible : this.comments.concat(visible);
      this.commentPage = nextPage;
      this.commentTotal = batch.total;
      this.commentHasMore = batch.hasMore;
      // 消息跳转落地：自动展开目标楼层（对方回复我的那条所在楼）并加载折叠回复
      if (this.pendingReplyRpid > 0) {
        const wanted: number = this.pendingReplyRoot > 0 ? this.pendingReplyRoot : this.pendingReplyRpid;
        const target: VideoComment | undefined =
          this.comments.find((entry: VideoComment): boolean => entry.id === wanted);
        if (target !== undefined && this.expandedCommentId !== target.id) {
          this.toggleSubReplies(target);
        }
        this.pendingReplyRpid = -1;
        this.pendingReplyRoot = -1;
      }
    } catch (error) {
      this.commentError = '评论加载失败，请稍后重试';
      console.error('Pilihos comments failed: ' + String(error));
    } finally {
      this.commentLoading = false;
    }
  }

  private onToggleCommentSort(): void {
    this.commentSort = this.commentSort === '0' ? '2' : '0';
    this.loadComments(true);
  }

  private toggleSubReplies(comment: VideoComment): void {
    if (this.expandedCommentId === comment.id) {
      this.expandedCommentId = -1;
      this.subReplies = [];
      this.subHasMore = false;
      return;
    }
    this.expandedCommentId = comment.id;
    this.loadSubReplies(comment.id, true);
  }

  private async loadSubReplies(rootId: number, refresh: boolean): Promise<void> {
    if (this.subLoading) return;
    this.subLoading = true;
    const nextPage: number = refresh ? 1 : this.subPage + 1;
    try {
      const current: VideoItem = this.videos[this.currentIndex];
      const session: AuthSession | null = this.authSession ?? AuthService.currentSession();
      const batch: CommentBatch = await ReplyService.loadSubReplies(
        current.aid, rootId, session === null ? '' : session.cookie, nextPage);
      this.subReplies = refresh ? batch.items : this.subReplies.concat(batch.items);
      this.subPage = nextPage;
      this.subHasMore = batch.hasMore;
    } catch (error) {
      this.showPlaybackToast('回复加载失败，请稍后重试');
      console.error(`Pilihos sub replies failed: ${String(error)}`);
    } finally {
      this.subLoading = false;
    }
  }

  private requireSession(): AuthSession | null {
    const session: AuthSession | null = this.authSession ?? AuthService.currentSession();
    if (session === null || session.cookie === '' || session.csrf === '') {
      this.showPlaybackToast('请先登录后再互动');
      return null;
    }
    return session;
  }

  private patchCurrentVideo(patch: (item: VideoItem) => void): void {
    this.patchVideoAt(this.currentIndex, patch);
  }

  private patchVideoAt(index: number, patch: (item: VideoItem) => void, expectedAid: number = 0): void {
    const item: VideoItem = this.videos[index];
    if (item === undefined) return;
    if (item.placeholder) return;
    if (expectedAid > 0 && item.aid !== expectedAid) return;
    // 不可变替换：保证状态绑定立即刷新（乐观高亮即时生效）
    const copy: VideoItem = JSON.parse(JSON.stringify(item)) as VideoItem;
    patch(copy);
    this.videos = this.videos.map((candidate: VideoItem, candidateIndex: number): VideoItem =>
      candidateIndex === index ? copy : candidate);
  }

  /**
   * 互动状态与作者信息：openVideoDetail 必经路径（不受 detailLoaded 短路影响），
   * 负责点赞/收藏回显、作者关注态、粉丝数与投稿数。
   */
  private async loadVideoContext(): Promise<void> {
    const session: AuthSession | null = this.authSession ?? AuthService.currentSession();
    const contextIndex: number = this.currentIndex;
    let item: VideoItem = this.videos[contextIndex];
    let contextAid: number = item.aid;
    if (item.placeholder) return;
    // 搜索/推荐条目可能缺 authorMid：补一次详情解析
    if ((item.authorMid ?? 0) <= 0) {
      try {
        const fresh: VideoItem = await VideoDetailService.load(item);
        if (this.currentIndex !== contextIndex || this.videos[contextIndex] !== item) return;
        this.videos = this.videos.map((candidate: VideoItem): VideoItem =>
          candidate.id === item.id ? fresh : candidate);
        item = fresh;
        contextAid = fresh.aid;
      } catch (detailError) {
        console.warn(`Pilihos video context detail failed: ${String(detailError)}`);
      }
    }
    // 互动状态回显
    if (session !== null && session.cookie !== '' && item.aid > 0) {
      try {
        const state = await InteractionService.fetchVideoState(item.aid, session.cookie);
        if (this.currentIndex !== contextIndex || this.videos[contextIndex].aid !== contextAid) return;
        this.patchVideoAt(contextIndex, (target: VideoItem): void => {
          target.liked = state.liked;
          target.disliked = state.disliked;
          target.coined = state.coined;
          target.favored = state.favored;
        });
      } catch (stateError) {
        console.warn(`Pilihos video user state failed: ${String(stateError)}`);
      }
    }
    // 作者关注态 + 粉丝数 + 投稿数；card 为公开接口，未登录也拉取等级/粉丝数
    const authorMid: number = item.authorMid ?? 0;
    if (authorMid > 0) {
      try {
        const cardQuery: Record<string, string> = {};
        cardQuery['mid'] = String(authorMid);
        const cardResult: Record<string, Object> =
          await BiliHttpClient.getJson('/x/web-interface/card', cardQuery,
            session !== null ? session.cookie : '');
        if (Number(cardResult['code'] ?? -1) === 0) {
          if (this.currentIndex !== contextIndex || this.videos[contextIndex].aid !== contextAid) return;
          const cardData: Record<string, Object> = (cardResult['data'] ?? {}) as Record<string, Object>;
          const fans: number = Number(cardData['follower'] ?? 0);
          const cardInfo: Record<string, Object> = (cardData['card'] ?? {}) as Record<string, Object>;
          const levelInfo: Record<string, Object> = (cardInfo['level_info'] ?? {}) as Record<string, Object>;
          const level: number = Number(levelInfo['current_level'] ?? 0);
          this.patchVideoAt(contextIndex, (target: VideoItem): void => {
            target.authorFans = fans;
            target.authorLevel = level;
          });
        }
      } catch (cardError) {
        console.warn(`Pilihos author card failed: ${String(cardError)}`);
      }
    }
    if (session !== null && session.cookie !== '' && authorMid > 0) {
      try {
        const attribute: number = await InteractionService.relationAttribute(authorMid, session.cookie);
        if (this.currentIndex !== contextIndex || this.videos[contextIndex].aid !== contextAid) return;
        const followed: boolean = attribute === 2 || attribute === 6 || attribute === 128;
        this.patchVideoAt(contextIndex, (target: VideoItem): void => {
          target.authorFollowed = followed;
        });
      } catch (relationError) {
        if (this.currentIndex !== contextIndex || this.videos[contextIndex].aid !== contextAid) return;
        const fallbackFollowed: boolean = FollowState.isFollowed(authorMid, item.author);
        this.patchVideoAt(contextIndex, (target: VideoItem): void => {
          target.authorFollowed = fallbackFollowed;
        });
      }
      if ((item.authorVideos ?? 0) <= 0) {
        try {
          const arcSigned: string = await WbiService.sign([
            `mid=${authorMid}`, 'pn=1', 'ps=1', 'order=pubdate'
          ]);
          const arcResult: Record<string, Object> =
            await BiliHttpClient.getJsonQuery('/x/space/wbi/arc/search', arcSigned, session.cookie);
          if (Number(arcResult['code'] ?? -1) === 0) {
            if (this.currentIndex !== contextIndex || this.videos[contextIndex].aid !== contextAid) return;
            const arcData: Record<string, Object> = (arcResult['data'] ?? {}) as Record<string, Object>;
            const arcPage: Record<string, Object> = (arcData['page'] ?? {}) as Record<string, Object>;
            const count: number = Number(arcPage['count'] ?? 0);
        this.patchVideoAt(contextIndex, (target: VideoItem): void => {
              target.authorVideos = count;
            });
          }
        } catch (arcError) {
          console.warn(`Pilihos author arc count failed: ${String(arcError)}`);
        }
      }
    } else if (authorMid > 0 || item.author !== '') {
      const followed: boolean = FollowState.isFollowed(authorMid, item.author);
      this.patchVideoAt(contextIndex, (target: VideoItem): void => {
        target.authorFollowed = followed;
      });
    }
  }

  /**
   * 相关推荐流：详情页底部列表与竖屏化随机连播/播完推荐共用；
   * 排除当前视频、看过的（含未看完，按播放记忆）与过滤词命中的条目。
   */
  private async loadRelatedVideos(): Promise<void> {
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.placeholder || item.aid <= 0) {
      this.relatedVideos = [];
      this.relatedLoading = false;
      return;
    }
    const requestId: number = this.relatedRequest + 1;
    this.relatedRequest = requestId;
    this.relatedLoading = true;
    try {
      const list: VideoItem[] = await VideoDetailService.loadRelated(item);
      const seen: Set<string> = new Set<string>([item.bvid !== '' ? item.bvid : `${item.aid}`]);
      const fresh: VideoItem[] = list.filter((candidate: VideoItem): boolean => {
        const key: string = candidate.bvid !== '' ? candidate.bvid : `${candidate.aid}`;
        if (seen.has(key)) return false;
        seen.add(key);
        return !FilterWords.isVideoFiltered(candidate.title)
          && PlaybackMemory.progressOf(candidate.aid) <= 0;
      });
      if (requestId === this.relatedRequest) this.relatedVideos = fresh;
    } catch (error) {
      console.warn(`Pilihos related videos failed: ${String(error)}`);
      if (requestId === this.relatedRequest) this.relatedVideos = [];
    } finally {
      if (requestId === this.relatedRequest) this.relatedLoading = false;
    }
  }

  /**
   * 竖屏化连播池：走推荐接口拉"全网随机"视频（与首页推荐同源但独立游标），
   * 排除当前/已看过的（含未看完）、过滤词命中与重复条目；存量不足 5 部时补一批。
   */
  private async ensureRandomPool(): Promise<void> {
    if (this.randomPoolFetching || this.randomPool.length >= 5) return;
    this.randomPoolFetching = true;
    try {
      const batch: RecommendationBatch = await RecommendationService.loadBatch(this.randomPoolIndex);
      this.randomPoolIndex = batch.nextIndex;
      const seen: Set<string> = new Set<string>(this.randomPool.map((item: VideoItem): string =>
        item.bvid !== '' ? item.bvid : `${item.aid}`));
      const current: VideoItem = this.videos[this.currentIndex];
      seen.add(current.bvid !== '' ? current.bvid : `${current.aid}`);
      const fresh: VideoItem[] = batch.items.filter((item: VideoItem): boolean => {
        const key: string = item.bvid !== '' ? item.bvid : `${item.aid}`;
        if (item.aid <= 0 || seen.has(key)) return false;
        seen.add(key);
        return !FilterWords.isVideoFiltered(item.title)
          && PlaybackMemory.progressOf(item.aid) <= 0;
      });
      this.randomPool = this.randomPool.concat(fresh);
    } catch (error) {
      console.warn(`Pilihos random pool load failed: ${String(error)}`);
    } finally {
      this.randomPoolFetching = false;
    }
  }

  /**
   * 竖屏化连播（上滑/随机连播/播完推荐）：从全网随机池取一部播放，保持竖屏化状态。
   * 详情页底部的相关推荐不走此路径（仍按当前视频的相似视频展示）。
   */
  private async playRandomGlobalVideo(): Promise<void> {
    this.savePlaybackProgress();
    await this.ensureRandomPool();
    if (this.randomPool.length === 0) {
      this.showPlaybackToast('没有可播放的推荐视频');
      return;
    }
    const item: VideoItem =
      this.randomPool[Math.floor(Math.random() * this.randomPool.length)];
    this.randomPool = this.randomPool.filter((candidate: VideoItem): boolean =>
      candidate !== item);
    this.playbackFinished = false;
    this.videos = this.videos.concat([item]);
    this.currentIndex = this.videos.length - 1;
    this.openVideoDetail(item, false);
    // 播一部补一批，保持池子有货
    this.ensureRandomPool();
  }

  private playSequentialVideo(): void {
    if (this.currentIndex + 1 >= this.videos.length) {
      this.playbackFinished = true;
      this.playbackPaused = true;
      this.recommendedPlaybackIndex = -1;
      this.playbackControlsVisible = true;
      return;
    }
    this.savePlaybackProgress();
    this.currentIndex += 1;
    this.openVideoDetail(this.videos[this.currentIndex], false);
  }

  private shareCurrentVideo(): void {
    const item: VideoItem = this.videos[this.currentIndex];
    this.shareVideoItem(item);
  }

  private shareVideoItem(item: VideoItem): void {
    const uri: string = item.bvid !== '' ? `https://www.bilibili.com/video/${item.bvid}/` :
      `https://www.bilibili.com/video/av${item.aid}/`;
    // 调起系统分享面板：链接形态失败（如 1003702002）时回退文本形态
    try {
      const linkData: systemShare.SharedData = new systemShare.SharedData({
        utd: 'general.url',
        uri: uri
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(linkData);
      controller.show(this.context, { selectionMode: systemShare.SelectionMode.SINGLE })
        .catch((error: BusinessError): void => {
          console.error(`Pilihos share link form failed: ${error.code} ${error.message}`);
          this.showTextShareFallback(uri, error.code);
        });
    } catch (shareError) {
      console.error(`Pilihos share link build failed: ${String(shareError)}`);
      this.showTextShareFallback(uri, -1);
    }
  }

  private showTextShareFallback(uri: string, prevCode: number): void {
    try {
      const textData: systemShare.SharedData = new systemShare.SharedData({
        utd: 'general.plain-text',
        content: uri
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(textData);
      controller.show(this.context, { selectionMode: systemShare.SelectionMode.SINGLE })
        .catch((error: BusinessError): void => {
          console.error(`Pilihos share text form failed: ${error.code} ${error.message}`);
          this.showPlaybackToast(`分享失败 [错误码: ${String(prevCode)}/${String(error.code)}]`);
        });
    } catch (fallbackError) {
      console.error(`Pilihos share text build failed: ${String(fallbackError)}`);
      this.showPlaybackToast(`分享失败 [错误码: ${String(prevCode)}]`);
    }
  }

  private handleVideoQuickAction(item: VideoItem, action: string): void {
    if (action === 'saveCover') {
      this.showPlaybackToast('保存封面正在接入相册权限');
      return;
    }
    if (action === 'hide') {
      this.videos = this.videos.filter((entry: VideoItem): boolean => entry.id !== item.id);
      this.showPlaybackToast('已隐藏该视频');
      return;
    }
    if (action === 'share') {
      this.shareVideoItem(item);
      return;
    }
    if (action === 'report') {
      this.videos = this.videos.filter((entry: VideoItem): boolean => entry.id !== item.id);
      // 应用内网页举报（不再跳系统浏览器）
      const appealUrl: string = item.aid > 0
        ? `https://www.bilibili.com/appeal/?avid=${item.aid}`
        : 'https://www.bilibili.com/appeal/';
      router.pushUrl({
        url: 'pages/WebBrowser',
        params: { url: appealUrl, title: '举报反馈' }
      }).catch((reportError: Object): void => {
        console.error('Pilihos report page failed: ' + String(reportError));
        this.openExternalUrl(appealUrl);
      });
      return;
    }
    if (action === 'block') {
      this.videos = this.videos.filter((entry: VideoItem): boolean =>
        (item.authorMid ?? 0) > 0 ? entry.authorMid !== item.authorMid : entry.author !== item.author);
      this.showPlaybackToast('已隐藏该用户视频');
    }
  }

  private async setPlayMode(mode: number): Promise<void> {
    this.playMode = mode;
    console.info('Pilihos play mode set: ' + String(mode));
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, 'pilihos_player');
      store.putSync('play_mode', mode);
      store.flushSync();
    } catch (error) {
      console.error('Pilihos play mode save failed: ' + String(error));
    }
  }

  private async savePlayerSetting(key: string, value: number | boolean): Promise<void> {
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(this.context, 'pilihos_player');
      store.putSync(key, value);
      store.flushSync();
    } catch (error) {
      console.error(`Pilihos player setting save failed: ${String(error)}`);
    }
  }

  private onSequentialChainChange(): void {
    this.savePlayerSetting('sequential_chain', this.sequentialChain);
  }

  private onDefaultSpeedChange(): void {
    this.savePlayerSetting('default_speed', this.defaultSpeed);
  }


  private async saveDanmakuSetting(key: string, value: number): Promise<void> {
    await this.savePlayerSetting(key, value);
  }

  private onDanmakuFontSizeChange(): void {
    this.saveDanmakuSetting('danmaku_font_size', this.danmakuFontSize);
  }

  private setDanmakuFontSize(size: number): void {
    this.danmakuFontSize = this.normalizeDanmakuFontSize(size);
  }

  private setDanmakuArea(area: number): void {
    const normalized: number = this.normalizeDanmakuArea(area);
    if (this.danmakuArea !== normalized) {
      this.danmakuArea = normalized;
    }
    // 即使重复点击当前值，也明确保存一次，避免设置面板看似无响应。
    this.saveDanmakuSetting('danmaku_area', normalized);
  }

  private normalizeDanmakuFontSize(size: number): number {
    const choices: number[] = [45, 50, 55, 60];
    if (size === 0 || size === 1 || size === 2) return 45;
    let best: number = choices[0];
    choices.forEach((candidate: number): void => {
      if (Math.abs(candidate - size) < Math.abs(best - size)) best = candidate;
    });
    return best;
  }

  private normalizeDanmakuArea(area: number): number {
    const choices: number[] = [25, 50, 75, 100];
    let best: number = choices[0];
    choices.forEach((candidate: number): void => {
      if (Math.abs(candidate - area) < Math.abs(best - area)) best = candidate;
    });
    return best;
  }

  private onDanmakuOpacityChange(): void {
    this.saveDanmakuSetting('danmaku_opacity', this.danmakuOpacity);
  }

  private onDanmakuSpeedChange(): void {
    this.saveDanmakuSetting('danmaku_speed', this.danmakuSpeed);
  }

  private onDanmakuAreaChange(): void {
    this.saveDanmakuSetting('danmaku_area', this.danmakuArea);
  }

  private handleDetailAction(action: string): void {
    if (action === 'like') {
      this.toggleLike();
    } else if (action === 'dislike') {
      this.toggleDislike();
    } else if (action === 'coin') {
      this.showPlaybackToast('投币功能即将接入官方接口');
    } else if (action === 'fav' || action === 'favsheet' || action === 'favdirect'
      || action === 'favtoggle') {
      this.toggleFavEntry();
    } else if (action === 'watchlater') {
      this.addWatchLater();
    } else if (action === 'share') {
      this.shareCurrentVideo();
    } else if (action === 'comments') {
      this.detailSection = 1;
      this.verticalExpanded = false;
    } else if (action === 'commentimage') {
      this.showPlaybackToast('本地图片插入功能即将接入');
    } else if (action === 'commentinsert') {
      this.showPlaybackToast('更多插入功能即将接入');
    } else if (action === 'commentemoji') {
      this.openEmojiPanel();
    } else if (action === 'settings') {
      // 竖屏化内：底部弹出播放模式设置，不跳转子页
      this.playModeSheetVisible = true;
    } else if (action === 'openauthor') {
      this.openAuthorSpace();
    } else if (action === 'videohide') {
      this.handleVideoQuickAction(this.videos[this.currentIndex], 'hide');
    } else if (action === 'videoshare') {
      this.shareCurrentVideo();
    } else if (action === 'videoreport') {
      this.handleVideoQuickAction(this.videos[this.currentIndex], 'report');
    } else if (action === 'videoblock') {
      this.handleVideoQuickAction(this.videos[this.currentIndex], 'block');
    }
  }

  private openAuthorSpace(): void {
    this.openAuthorSpaceItem(this.videos[this.currentIndex]);
  }

  private openAuthorSpaceItem(item: VideoItem): void {
    const mid: number = item.authorMid ?? 0;
    if (mid > 0) {
      this.pushUserSpace(mid, item.author);
      return;
    }
    // 兜底：推荐/热门流缺 mid 时，用视频详情接口水合后再跳转
    if (item.aid > 0 || item.bvid !== '') {
      this.showPlaybackToast('正在获取UP主信息…');
      VideoDetailService.load(item).then((detailed: VideoItem): void => {
        const hydrated: number = detailed.authorMid ?? 0;
        if (hydrated > 0) {
          this.pushUserSpace(hydrated, detailed.author !== '' ? detailed.author : item.author);
          return;
        }
        this.showPlaybackToast('UP主信息缺失');
      }).catch((error: Object): void => {
        console.error('Pilihos author hydrate failed: ' + String(error));
        this.showPlaybackToast('UP主信息加载失败');
      });
      return;
    }
    this.showPlaybackToast('UP主信息加载中');
  }

  private pushUserSpace(mid: number, name: string): void {
    // 轻提示用于真机确认点击链路是否触发（页面打开后即被覆盖）
    this.showPlaybackToast(`正在打开 ${name === '' ? '个人空间' : name} 的主页…`);
    router.pushUrl({
      url: 'pages/UserSpace',
      params: { mid: mid, name: name }
    }).catch((error: BusinessError): void => {
      console.error('Pilihos author space failed: ' + String(error));
      this.showPlaybackToast('打开个人空间失败');
    });
  }

  private async followAuthor(on: boolean): Promise<void> {
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    const item: VideoItem = this.videos[this.currentIndex];
    const mid: number = item.authorMid ?? 0;
    if (mid <= 0) return;
    try {
      await InteractionService.follow(mid, on, session.cookie, session.csrf, '11');
      FollowState.setFollowed(mid, item.author, on);
      this.followStamp += 1;
      this.patchCurrentVideo((target: VideoItem): void => {
        target.authorFollowed = on;
      });
      this.showPlaybackToast(on ? `已关注 ${item.author}` : '已取消关注');
    } catch (error) {
      this.showPlaybackToast(`关注操作失败: ${String(error)}`);
    }
  }

  private async openFavSheet(): Promise<void> {
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.aid <= 0) return;
    // 先弹出面板（立即反馈），收藏夹列表异步填充
    this.favFolders = [];
    this.favError = '';
    this.favSheetVisible = true;
    try {
      const folders: FavFolder[] = await InteractionService.listFavFolders(
        item.aid, session.cookie, session.uid, item.authorMid ?? 0);
      this.favFolders = folders;
      if (folders.length === 0) {
        this.favError = '该账号没有创建过收藏夹';
      }
    } catch (error) {
      this.favError = `收藏夹获取失败：${String(error)}（点此重试）`;
    }
  }

  private async openEmojiPanel(): Promise<void> {
    this.emojiPanelVisible = !this.emojiPanelVisible;
    if (this.emojiPanelVisible) {
      await this.loadEmojiItems();
    }
  }

  private async loadEmojiItems(): Promise<void> {
    if (this.emojiItems.length > 0 || this.emojiLoading) return;
    const session: AuthSession | null = this.authSession ?? AuthService.currentSession();
    if (session === null) return;
    this.emojiLoading = true;
    try {
      this.emojiItems = await EmojiService.loadReplyEmojis(session.cookie);
    } catch (error) {
      this.showPlaybackToast(`表情包获取失败: ${String(error)}`);
    } finally {
      this.emojiLoading = false;
    }
  }

  private selectEmoji(emoji: BiliEmoji): void {
    // 选择表情后保持编辑器和表情面板状态，允许连续点选多个表情。
    this.showCommentInput = true;
    this.emojiPanelVisible = true;
    const name: string = EmojiService.normalizeName(emoji.name);
    this.commentInputText += '[' + name + ']';
    const next: string[] = [name]
      .concat(this.recentEmojis.filter((recent: string): boolean => recent !== name))
      .slice(0, 12);
    this.recentEmojis = next;
    EmojiService.saveRecentEmojis(this.context, next);
  }

  private async toggleFavFolder(folder: FavFolder): Promise<void> {
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    const item: VideoItem = this.videos[this.currentIndex];
    const targetIndex: number = this.currentIndex;
    const targetAid: number = item.aid;
    if (item.aid <= 0) return;
    const on: boolean = !folder.favoured;
    try {
      await InteractionService.addToFolder(item.aid, folder.id, on, session.cookie, session.csrf);
      this.markFavFolder(folder, on, targetIndex, targetAid);
      this.showPlaybackToast(on ? `已收藏到「${folder.title}」` : `已从「${folder.title}」移除`);
    } catch (firstError) {
      // 11010：当前 aid 非有效稿件（番剧/PGC 等场景），水合出正规 aid 后重试一次
      let recovered: boolean = false;
      if (String(firstError).includes('11010')) {
        try {
          const fresh: VideoItem = await VideoDetailService.load(item);
          if (fresh.aid > 0 && fresh.aid !== targetAid) {
            await InteractionService.addToFolder(fresh.aid, folder.id, on, session.cookie, session.csrf);
            this.markFavFolder(folder, on, targetIndex, fresh.aid);
            this.showPlaybackToast(on ? `已收藏到「${folder.title}」` : `已从「${folder.title}」移除`);
            recovered = true;
          }
        } catch (_retryError) {
          recovered = false;
        }
      }
      if (!recovered) {
        this.showPlaybackToast(`收藏操作失败: ${String(firstError)}`);
      }
    }
  }

  // 收藏入口：未收藏 → 打开收藏夹面板选择；已收藏 → 直接取消收藏
  private toggleFavEntry(): void {
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.favored ?? false) {
      this.cancelFavoriteDirect();
      return;
    }
    this.openFavSheet();
  }

  // 直接取消收藏：查询已收藏进的文件夹并逐个移除
  private async cancelFavoriteDirect(): Promise<void> {
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    const item: VideoItem = this.videos[this.currentIndex];
    const targetIndex: number = this.currentIndex;
    const targetAid: number = item.aid;
    if (item.aid <= 0) return;
    try {
      const folders: FavFolder[] = await InteractionService.listFavFolders(
        item.aid, session.cookie, session.uid, item.authorMid ?? 0);
      const favouredFolders: FavFolder[] = folders.filter((entry: FavFolder): boolean => entry.favoured);
      if (favouredFolders.length === 0) {
        this.showPlaybackToast('未找到已收藏的收藏夹');
        this.patchVideoAt(targetIndex, (target: VideoItem): void => { target.favored = false; }, targetAid);
        return;
      }
      for (const folder of favouredFolders) {
        try {
          await InteractionService.addToFolder(item.aid, folder.id, false, session.cookie, session.csrf);
        } catch (removeError) {
          // 11010（非正规稿件 aid）时水合重试
          if (String(removeError).includes('11010')) {
            const fresh: VideoItem = await VideoDetailService.load(item);
            await InteractionService.addToFolder(fresh.aid, folder.id, false, session.cookie, session.csrf);
          } else {
            throw new Error(String(removeError));
          }
        }
      }
      this.patchVideoAt(targetIndex, (target: VideoItem): void => { target.favored = false; }, targetAid);
      this.showPlaybackToast('已取消收藏');
    } catch (error) {
      this.showPlaybackToast(`取消收藏失败: ${String(error)}`);
    }
  }

  private markFavFolder(folder: FavFolder, on: boolean, targetIndex: number, aid: number): void {
    folder.favoured = on;
    this.favFolders = this.favFolders.slice(0);
    this.patchVideoAt(targetIndex, (target: VideoItem): void => {
      target.favored = this.favFolders.some((entry: FavFolder): boolean => entry.favoured);
    }, aid);
  }

  // 删除收藏夹：确认后批量删除（默认收藏夹由服务端拒绝，逐项容错）
  private confirmDeleteFavFolders(): void {
    if (this.favDeleteIds.length === 0) return;
    const ids: number[] = this.favDeleteIds.slice(0);
    AlertDialog.show({
      title: '删除收藏夹',
      message: `确定删除选中的 ${ids.length} 个收藏夹？其中内容将一并移除，默认收藏夹无法删除。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: (): void => { }
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#C51D2A',
        action: (): void => { this.doDeleteFavFolders(ids); }
      }
    });
  }

  private async doDeleteFavFolders(ids: number[]): Promise<void> {
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    try {
      await InteractionService.deleteFavFolders(ids, session.cookie, session.csrf);
      this.showPlaybackToast(`已删除 ${ids.length} 个收藏夹`);
      this.favDeleteMode = false;
      this.favDeleteIds = [];
      await this.openFavSheet();
    } catch (error) {
      this.showPlaybackToast(`删除收藏夹失败: ${String(error)}`);
    }
  }

  private async createFavFolder(): Promise<void> {
    const title: string = this.newFavTitle.trim();
    if (title === '' || this.newFavCreating) return;
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    this.newFavCreating = true;
    try {
      await InteractionService.createFavFolder(title, session.cookie, session.csrf);
      this.showPlaybackToast(`已创建「${title}」`);
      this.newFavVisible = false;
      this.newFavTitle = '';
      // 重新拉取收藏夹列表（保留当前视频上下文）
      const item: VideoItem = this.videos[this.currentIndex];
      const folders: FavFolder[] = await InteractionService.listFavFolders(
        item.aid, session.cookie, session.uid, item.authorMid ?? 0);
      this.favFolders = folders;
    } catch (error) {
      this.showPlaybackToast(`创建收藏夹失败: ${String(error)}`);
    } finally {
      this.newFavCreating = false;
    }
  }

  private async toggleLike(): Promise<void> {
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.aid <= 0) {
      this.showPlaybackToast('视频信息加载中，请稍后');
      return;
    }
    // 先乐观更新 UI，接口失败再回滚
    const on: boolean = !(item.liked ?? false);
    const targetIndex: number = this.currentIndex;
    const targetAid: number = item.aid;
    this.patchVideoAt(targetIndex, (target: VideoItem): void => {
      target.liked = on;
      target.disliked = false;
      target.likeCount = Math.max(0, target.likeCount + (on ? 1 : -1));
    }, targetAid);
    try {
      await InteractionService.rate(item.aid, on ? 1 : 0, session.cookie, session.csrf);
      this.showPlaybackToast(on ? '已点赞' : '已取消点赞');
    } catch (error) {
      this.patchVideoAt(targetIndex, (target: VideoItem): void => {
        target.liked = !on;
        target.likeCount = Math.max(0, target.likeCount + (on ? -1 : 1));
      }, targetAid);
      this.showPlaybackToast(`点赞失败: ${String(error)}`);
    }
  }

  private async toggleDislike(): Promise<void> {
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.aid <= 0) return;
    const on: boolean = !(item.disliked ?? false);
    const targetIndex: number = this.currentIndex;
    const targetAid: number = item.aid;
    const previousLiked: boolean = item.liked ?? false;
    const previousLikeCount: number = item.likeCount;
    this.patchVideoAt(targetIndex, (target: VideoItem): void => {
      target.disliked = on;
      if (on && target.liked) {
        target.liked = false;
        target.likeCount = Math.max(0, target.likeCount - 1);
      }
    }, targetAid);
    try {
      await InteractionService.rate(item.aid, on ? 2 : 0, session.cookie, session.csrf);
      this.showPlaybackToast(on ? '已点踩' : '已取消点踩');
    } catch (error) {
      this.patchVideoAt(targetIndex, (target: VideoItem): void => {
        target.disliked = !on;
        target.liked = previousLiked;
        target.likeCount = previousLikeCount;
      }, targetAid);
      this.showPlaybackToast(`点踩失败: ${String(error)}`);
    }
  }

  private async toggleFavorite(): Promise<void> {
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.aid <= 0) {
      this.showPlaybackToast('视频信息加载中，请稍后');
      return;
    }
    const on: boolean = !(item.favored ?? false);
    try {
      await InteractionService.favorite(item.aid, on, session.cookie, session.csrf);
      this.patchCurrentVideo((target: VideoItem): void => {
        target.favored = on;
      });
      this.showPlaybackToast(on ? '已收藏到默认收藏夹' : '已取消收藏');
    } catch (error) {
      this.showPlaybackToast(`收藏失败: ${String(error)}`);
    }
  }

  private async addWatchLater(): Promise<void> {
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.aid <= 0) {
      return;
    }
    // 静默加入稍后再看，不打扰播放
    try {
      await InteractionService.watchLater(item.aid, session.cookie, session.csrf);
    } catch (error) {
      this.showPlaybackToast(`加入再看失败: ${String(error)}`);
    }
  }

  private async submitComment(): Promise<void> {
    const message: string = this.commentInputText.trim();
    if (message === '') {
      this.showPlaybackToast('先说点什么吧');
      return;
    }
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.aid <= 0) {
      this.showPlaybackToast('视频信息加载中，请稍后');
      return;
    }
    try {
      await InteractionService.addComment(item.aid, message, session.cookie, session.csrf,
        this.commentReplyRootId, this.commentReplyParentId);
      if (this.commentReplyRootId === 0) {
        const localComment: VideoComment = new VideoComment();
        localComment.id = -Date.now();
        localComment.userName = session.name;
        localComment.avatar = session.face;
        localComment.message = message;
        localComment.level = session.level;
        localComment.publishTime = Math.floor(Date.now() / 1000);
        this.comments = [localComment].concat(this.comments);
        this.commentTotal += 1;
      }
      this.commentInputText = '';
      this.commentReplyTarget = '';
      this.commentReplyRootId = 0;
      this.commentReplyParentId = 0;
      this.showCommentInput = false;
      this.showPlaybackToast('评论发布成功');
    } catch (error) {
      this.showPlaybackToast(`评论发布失败: ${String(error)}`);
    }
  }

  // 动态点赞/分享：以动态为对象
  private async likeDynamicEntry(entry: DynamicEntry): Promise<void> {
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    try {
      await InteractionService.likeDynamic(entry.id, session.cookie, session.csrf);
      this.showPlaybackToast('已点赞');
    } catch (error) {
      this.showPlaybackToast(`点赞失败: ${String(error)}`);
    }
  }

  private shareDynamicEntry(entry: DynamicEntry): void {
    try {
      const uri: string = `https://t.bilibili.com/${entry.id}`;
      const sharedData: systemShare.SharedData = new systemShare.SharedData({
        utd: 'general.url',
        uri: uri
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(sharedData);
      controller.show(this.context, { selectionMode: systemShare.SelectionMode.SINGLE })
        .catch((error: BusinessError): void => {
          this.showPlaybackToast(`分享失败 [错误码: ${String(error.code)}]`);
        });
    } catch (shareError) {
      this.showPlaybackToast(`分享失败: ${String(shareError)}`);
    }
  }

  // 动态卡片点赞：直接对稿件点赞（无乐观 UI，结果 toast 反馈）
  private async likeVideoItem(item: VideoItem): Promise<void> {    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    if (item.aid <= 0) {
      this.showPlaybackToast('视频信息缺失');
      return;
    }
    try {
      const on: boolean = !(item.liked ?? false);
      await InteractionService.like(item.aid, on, session.cookie, session.csrf);
      this.showPlaybackToast(on ? '点赞成功' : '已取消点赞');
    } catch (error) {
      this.showPlaybackToast(`点赞失败: ${String(error)}`);
    }
  }

  private replyToComment(comment: VideoComment): void {    this.commentReplyTarget = comment.userName;
    this.commentReplyRootId = comment.id;
    this.commentReplyParentId = comment.id;
    this.showCommentInput = true;
  }

  // 楼中楼回复：root 保持在楼层评论，parent 指向被回复的子评论
  private replyToSubReply(rootId: number, reply: VideoComment): void {
    this.commentReplyTarget = reply.userName;
    this.commentReplyRootId = rootId;
    this.commentReplyParentId = reply.id;
    this.showCommentInput = true;
  }

  private async toggleCommentLike(comment: VideoComment): Promise<void> {
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.aid <= 0) return;
    const on: boolean = !comment.liked;
    const previousLiked: boolean = comment.liked;
    const previousCount: number = comment.likeCount;
    comment.liked = on;
    comment.likeCount = Math.max(0, comment.likeCount + (on ? 1 : -1));
    this.refreshCommentLikeState(comment);
    try {
      await InteractionService.likeComment(comment, item.aid, on, session.cookie, session.csrf);
    } catch (error) {
      comment.liked = previousLiked;
      comment.likeCount = previousCount;
      this.refreshCommentLikeState(comment);
      this.showPlaybackToast(`点赞失败: ${String(error)}`);
    }
  }

  private refreshCommentLikeState(comment: VideoComment): void {
    this.comments = this.comments.map((entry: VideoComment): VideoComment =>
      entry.id === comment.id ? this.cloneComment(comment) : entry);
    this.subReplies = this.subReplies.map((entry: VideoComment): VideoComment =>
      entry.id === comment.id ? this.cloneComment(comment) : entry);
  }

  private cloneComment(comment: VideoComment): VideoComment {
    const copy: VideoComment = new VideoComment();
    copy.id = comment.id;
    copy.mid = comment.mid;
    copy.userName = comment.userName;
    copy.avatar = comment.avatar;
    copy.message = comment.message;
    copy.level = comment.level;
    copy.likeCount = comment.likeCount;
    copy.replyCount = comment.replyCount;
    copy.publishTime = comment.publishTime;
    copy.isUp = comment.isUp;
    copy.liked = comment.liked;
    copy.emotes = comment.emotes;
    return copy;
  }

  private isOwnComment(comment: VideoComment): boolean {
    if (comment.id < 0) return true;
    if (comment.mid <= 0) return false;
    const session: AuthSession | null = this.authSession ?? AuthService.currentSession();
    return session !== null && session.uid !== '' && String(comment.mid) === session.uid;
  }

  private async deleteComment(comment: VideoComment): Promise<void> {
    if (comment.id < 0) {
      this.comments = this.comments.filter((entry: VideoComment): boolean => entry.id !== comment.id);
      this.commentTotal = Math.max(0, this.commentTotal - 1);
      this.showPlaybackToast('评论已删除');
      return;
    }
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.aid <= 0) return;
    try {
      await InteractionService.deleteComment(item.aid, comment.id, session.cookie, session.csrf);
      this.comments = this.comments.filter((entry: VideoComment): boolean => entry.id !== comment.id);
      this.commentTotal = Math.max(0, this.commentTotal - 1);
      this.showPlaybackToast('评论已删除');
    } catch (error) {
      this.showPlaybackToast(`删除失败: ${String(error)}`);
    }
  }

  private hideComment(comment: VideoComment): void {
    CommentShield.hide(this.context, comment.id);
    this.comments = this.comments.filter((entry: VideoComment): boolean => entry.id !== comment.id);
    this.showPlaybackToast('已隐藏该评论');
  }

  private reportComment(comment: VideoComment): void {
    const item: VideoItem = this.videos[this.currentIndex];
    const url: string =
      `https://www.bilibili.com/h5/comment/report?oid=${item.aid}&type=1&rpid=${comment.id}`;
    this.openExternalUrl(url);
  }

  private async blockCommentUser(comment: VideoComment): Promise<void> {
    if (comment.mid <= 0) {
      this.showPlaybackToast('无法获取该用户信息');
      return;
    }
    const session: AuthSession | null = this.requireSession();
    if (session === null) return;
    try {
      await InteractionService.blockUser(comment.mid, session.cookie, session.csrf);
      this.showPlaybackToast('已拉黑该用户');
    } catch (error) {
      this.showPlaybackToast(`拉黑失败: ${String(error)}`);
    }
  }

  private openExternalUrl(url: string): void {
    const want: Want = { action: 'ohos.want.action.viewData', uri: url };
    this.context.startAbility(want).catch((error: BusinessError): void => {
      console.error(`Pilihos open url failed: ${error.code} ${error.message}`);
      this.showPlaybackToast('页面打开失败');
    });
  }

  private async sendDanmaku(): Promise<void> {
    const text: string = this.danmakuText.trim();
    if (text === '') return;
    const session: AuthSession | null = this.authSession ?? AuthService.currentSession();
    if (session === null) {
      this.showPlaybackToast('登录后才能发送弹幕');
      return;
    }
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.cid <= 0) {
      this.showPlaybackToast('弹幕通道未就绪，请稍后重试');
      return;
    }
    try {
      await DanmakuService.send(session.cookie, session.csrf, item.cid, text, this.playbackCurrentMs);
      this.danmakuText = '';
      this.showPlaybackToast('弹幕发送成功，审核通过后显示');
    } catch (error) {
      this.showPlaybackToast(`弹幕发送失败: ${String(error)}`);
      console.error(`Pilihos danmaku send failed: ${String(error)}`);
    }
  }

  private switchPlaybackQuality(qn: number): void {
    if (qn === this.currentQn || this.currentUrl === '') return;
    // 清晰度切换：记录当前进度，新流 prepared 后自动续播
    this.pendingResumeMs = this.playbackCurrentMs;
    this.qualityMenuVisible = false;
    this.prepareCurrentVideo(qn);
  }

  private showPlaybackToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2500,
        bottom: this.bottomInset + 24
      });
    } catch (error) {
      console.error(`Pilihos playback toast failed: ${String(error)}`);
    }
  }

  private showPlaybackControls(): void {
    this.playbackControlsVisible = false;
    if (this.playbackControlsTimer !== 0) {
      clearTimeout(this.playbackControlsTimer);
    }
    this.playbackControlsTimer = setTimeout((): void => {
      if (!this.speedMenuVisible && !this.episodeListVisible && !this.qualityMenuVisible) {
        this.playbackControlsVisible = false;
      }
      this.playbackControlsTimer = 0;
    }, 4000);
  }

  private handleGridScroll(delta: number): void {
    if (this.bottomBarPinned || this.showVertical) {
      this.bottomBarVisible = true;
      return;
    }
    if (delta > 0.5) {
      this.bottomBarVisible = false;
    } else if (delta < -0.5) {
      this.bottomBarVisible = true;
    }
    if (this.bottomBarTimer !== -1) {
      clearTimeout(this.bottomBarTimer);
    }
    this.bottomBarTimer = setTimeout((): void => {
      this.bottomBarVisible = true;
      this.bottomBarTimer = -1;
    }, 700);
  }

  private savePlaybackProgress(): void {
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.placeholder || item.aid <= 0) return;
    if (this.playbackCurrentMs < 5000) return;
    PlaybackMemory.record(this.context, item.aid, this.playbackCurrentMs);
  }

  private openVideoDetail(item: VideoItem, showComments: boolean = false): void {
    if (item.placeholder) return;
    this.savePlaybackProgress();
    // 记忆推荐流位置，返回时恢复（仅在首页 Grid 可见时读取，否则会崩）
    if (!this.showVertical && this.activeTab === 1 && this.contentTab === 1) {
      try {
        const offset: OffsetResult | undefined = this.homeGridScroller.currentOffset();
        if (offset !== undefined) {
          this.savedGridOffset = offset.yOffset;
        } else {
          this.savedGridOffset = 0;
        }
      } catch (offsetError) {
        this.savedGridOffset = 0;
      }
    }
    // 支持从 relatedVideos 列表点击：先尝试在 videos 中查找，找不到则追加到末尾
    let index: number = this.videos.indexOf(item);
    if (index < 0) {
      // 推荐视频不在当前播放序列中：追加进去
      this.videos = this.videos.concat([item]);
      index = this.videos.length - 1;
    }
    if (this.showVertical && !this.restoringPlaybackHistory && index !== this.currentIndex) {
      this.playbackHistory.push(this.currentIndex);
    }
    this.currentIndex = index;

    this.detailSection = showComments ? 1 : 0;
    this.detailExpanded = this.autoExpandDescription;
    this.detailError = '';
    this.currentUrl = '';
    this.playbackStarting = false;
    this.playbackReady = false;
    this.comments = [];
    this.commentPage = 1;
    this.commentTotal = 0;
    this.commentHasMore = false;
    this.commentError = '';
    this.commentSort = '0';
    this.expandedCommentId = -1;
    this.subReplies = [];
    this.subHasMore = false;
    this.showCommentInput = false;
    this.commentInputText = '';
    this.commentReplyTarget = '';
    this.commentReplyRootId = 0;
    this.commentReplyParentId = 0;
    this.playbackCurrentMs = 0;
    this.playbackDurationMs = item.duration > 0 ? item.duration * 1000 : 0;
    this.playbackPaused = true;
     // 默认倍速是“长按视频倍速”，不改变打开视频时的普通播放速度。
     this.playbackSpeed = 1.0;
    this.speedMenuVisible = false;
    this.episodeListVisible = false;
    this.qualityMenuVisible = false;
    this.playbackControlsVisible = false;
    this.subtitlesEnabled = false;
    this.danmakuEnabled = true;
    this.emojiPanelVisible = false;
    this.videoWeight = 6;
    this.currentQn = 0;
    this.playbackQualities = [];
    this.relatedVideos = [];
    this.relatedLoading = false;
    this.showVertical = true;
    // 淡入动画：从透明渐变到正常显示
    this.exitAnimProgress = 0;
    setTimeout((): void => {
      this.exitAnimProgress = 1;
    }, 30);
    // 播放记忆：恢复上次进度，prepared 后自动 seek（看完的视频从头播放）
    // 清掉上一支视频遗留的续播位置，避免新视频从中途"乱跳"
    this.pendingResumeMs = 0;
    const savedMs: number = PlaybackMemory.progressOf(item.aid);
    if (savedMs > 5000 && (item.duration <= 0 || savedMs < item.duration * 1000 - 5000)) {
      this.pendingResumeMs = savedMs;
      this.showPlaybackToast(`已恢复上次进度 ${FormatUtils.formatPlaybackTime(savedMs)}`);
    }
    this.loadVideoDetail();
    this.loadVideoContext();
    this.loadRelatedVideos();
    // 只预加载数据，不自动展开表情面板；面板由输入栏表情按钮控制。
    this.loadEmojiItems();
    // 预热竖屏化连播的全网随机池
    this.ensureRandomPool();
    this.prepareCurrentVideo();
    if (showComments) this.loadComments(true);
  }

  private openDynamicVideo(item: VideoItem, showComments: boolean = false): void {
    this.refreshing = false;
    this.videos = [item];
    // 动态/消息跳转的视频是单条会话，必须归位索引，否则 videos[currentIndex] 越界崩溃
    this.currentIndex = 0;
    this.openVideoDetail(item, showComments);
  }

  private async refreshCurrentPage(): Promise<void> {
    if (this.refreshRunning) return;
    this.refreshRunning = true;
    this.refreshing = true;
    try {
      if (this.contentTab === 1) {
        await this.refreshRecommendations();
      }
    } finally {
      this.refreshRunning = false;
      this.refreshing = false;
    }
  }

  private async restoreAuthSession(): Promise<void> {
    const current: AuthSession | null = AuthService.currentSession();
    const restored: AuthSession | null = await AuthService.restoreSession(this.context);
    this.authSession = restored ?? current;
    if (restored === null && current !== null) this.refreshAuthData();
    const cookie: string = this.authSession === null ? '' : this.authSession.cookie;
    if (cookie !== '') {
      // 关注列表接口需要数字 mid，'self' 会请求失败导致卡片"已关注"永不显示
      const selfMid: string = this.authSession !== null ? this.authSession.uid : '';
      FollowState.refresh(cookie, selfMid).then((): void => {
        // 刷新卡片上的"已关注"标志
        this.followStamp += 1;
      });
    }
  }

  private async loadMoreRecommendations(): Promise<void> {
    if (this.loadingMore || this.loading || !this.hasMoreRecommendations) return;
    this.loadingMore = true;
    try {
      const batch: RecommendationBatch = await RecommendationService.loadBatch(this.recommendationIndex);
      const next: VideoItem[] = batch.items.filter((item: VideoItem): boolean =>
        !FilterWords.isVideoFiltered(item.title));
      if (next.length > 0) {
        this.page += 1;
        const cursorAdvanced: boolean = batch.nextIndex !== this.recommendationIndex;
        if (cursorAdvanced) {
          this.recommendationIndex = batch.nextIndex;
        } else {
          this.hasMoreRecommendations = false;
        }
        const existing: Set<string> = new Set<string>(this.videos.map((item: VideoItem): string =>
          item.bvid !== '' ? item.bvid : `${item.aid}`));
        const additions: VideoItem[] = next.filter((item: VideoItem): boolean => {
          const key: string = item.bvid !== '' ? item.bvid : `${item.aid}`;
          return !existing.has(key);
        });
        this.videos = this.videos.concat(additions);
        // A response may overlap the previous batch. Keep the cursor moving;
        // treating overlap as end-of-feed permanently disables later retries.
        this.hasMoreRecommendations = cursorAdvanced;
        // 触发预加载新加载的视频
        const cookie: string = this.playbackCookie();
        VideoPreloader.preloadBatch(this.videos, this.videos.length - additions.length, cookie);
      } else {
        this.hasMoreRecommendations = false;
      }
    } catch (error) {
      console.error(`Pilihos load more recommendation failed: ${String(error)}`);
    } finally {
      this.loadingMore = false;
    }
  }

  private async openLandscapePlayback(): Promise<void> {
    this.pendingResumeMs = this.playbackCurrentMs;
    this.landscapePlayback = true;
    this.setSystemBarAppearance(true);
    // 保持播放器状态，避免重新初始化导致黑屏
    // this.videoMounted 和 this.playbackReady 保持当前值
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE);
    } catch (error) {
      console.error('Pilihos landscape orientation failed: ' + String(error));
    }
  }

  private backToHome(): void {
    if (!this.showVertical) return;
    this.savePlaybackProgress();
    this.exitPlaybackToHome();
  }

  private async closeLandscapePlayback(): Promise<void> {
    this.pendingResumeMs = this.playbackCurrentMs;
    this.landscapePlayback = false;
    this.setSystemBarAppearance(true);
    // 保持播放器状态，避免重新初始化导致黑屏
    // this.videoMounted 和 this.playbackReady 保持当前值
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT);
    } catch (error) {
      console.error('Pilihos portrait orientation failed: ' + String(error));
    }
  }

  private async prepareCurrentVideo(targetQn: number = -1): Promise<void> {
    const requestId: number = this.playbackRequest + 1;
    this.playbackRequest = requestId;
    this.playerError = '';
    const isNewVideo: boolean = targetQn <= 0;
    // 换新视频才清空续播位置；横竖屏切换重建实例需要保留
    if (isNewVideo) {
      this.pendingResumeMs = 0;
    }
    this.currentUrl = '';
    this.playbackUrls = [];
    this.playbackUrlIndex = 0;
    this.videoMounted = isNewVideo ? false : this.videoMounted;
    this.playbackStarting = isNewVideo ? false : true;
    this.playbackReady = isNewVideo ? false : this.playbackReady;
    this.playbackCurrentMs = isNewVideo ? 0 : this.playbackCurrentMs;
    this.playbackDurationMs = isNewVideo ? 0 : this.playbackDurationMs;
    this.playbackPaused = true;
    this.speedMenuVisible = false;
    this.episodeListVisible = false;
    this.playbackControlsVisible = false;
    this.playbackFinished = false;
    this.recommendedPlaybackIndex = -1;
    let item: VideoItem = this.videos[this.currentIndex];
    try {
      if (item.cid <= 0) {
        // 优先使用预加载的数据
        const preloaded: VideoItem | null = VideoPreloader.getPreloadedDetail(item.aid);
        if (preloaded !== null && preloaded.cid > 0) {
          item = preloaded;
          console.info(`Pilihos using preloaded detail for playback: aid=${item.aid}`);
        } else {
          item = await VideoDetailService.load(item);
        }
        if (requestId !== this.playbackRequest || !this.showVertical) return;
        this.videos = this.videos.map((candidate: VideoItem): VideoItem =>
          candidate.id === item.id ? item : candidate);
      }
      if (item.cid <= 0) throw new Error('视频 cid 缺失，无法获取播放地址');
      if (item.duration > 0) this.playbackDurationMs = item.duration * 1000;
      // 播放地址带有短期签名，详情页每次进入都重新获取；只有接口失败时才使用旧缓存。
      // targetQn>0 时请求指定清晰度（清晰度切换），否则使用设置中的默认质量。
      if (targetQn <= 0) {
        // 设置页与播放器分属两个页面：每次重读默认清晰度，保证设置修改即时生效
        try {
          const store: preferences.Preferences =
            await preferences.getPreferences(this.context, 'pilihos_player');
          this.defaultQuality = store.getSync('default_quality', 0) as number;
        } catch (qualityError) {
          console.warn(`Pilihos default quality reload failed: ${String(qualityError)}`);
        }
      }
      const effectiveQn: number = targetQn > 0 ? targetQn : this.defaultQuality;
      let urls: string[] = [];
      // 优先使用预加载的播放地址（仅首次加载时使用）
      const preloadedUrls: string[] | null = targetQn <= 0 ?
        VideoPreloader.getPreloadedUrls(item.aid) : null;
      if (preloadedUrls !== null && preloadedUrls.length > 0) {
        urls = preloadedUrls;
        console.info(`Pilihos using preloaded URLs for aid=${item.aid}, count=${urls.length}`);
        // 预加载的地址没有清晰度信息，需要补充
        try {
          const resolved: PlaybackResolveResult =
            await PlaybackService.resolveWithQuality(item, this.playbackCookie(), effectiveQn);
          this.playbackQualities = resolved.qualities;
          this.currentQn = resolved.grantedQn;
        } catch (qualityError) {
          console.warn(`Pilihos quality info fetch failed: ${String(qualityError)}`);
        }
      } else {
        try {
          const resolved: PlaybackResolveResult =
            await PlaybackService.resolveWithQuality(item, this.playbackCookie(), effectiveQn);
          urls = resolved.urls;
          this.playbackQualities = resolved.qualities;
          this.currentQn = resolved.grantedQn;
          // 主动切换的清晰度未被授予（如仅大会员可用）时给出降级提示
          if (targetQn > 0 && resolved.grantedQn > 0 && resolved.grantedQn < targetQn) {
            this.showPlaybackToast(`当前仅支持到 ${PlaybackService.qualityLabel(resolved.grantedQn)}`);
          }
        } catch (resolveError) {
          if (item.playUrl === '') throw new Error(String(resolveError));
          console.warn(`Pilihos live playback URL resolve failed, using cached URL: ${String(resolveError)}`);
          urls = [item.playUrl];
        }
      }
      if (requestId !== this.playbackRequest || !this.showVertical) return;
      if (urls.length === 0) throw new Error('没有可用的视频播放地址');
      this.playbackUrls = urls;
      this.playbackUrlIndex = 0;
      this.currentUrl = urls[0];
      console.info(`Pilihos playback URL selected: ${FormatUtils.playbackUrlDescription(this.currentUrl)}, candidates=${urls.length}`);
      this.videoMounted = true;
      this.playbackStarting = false;
    } catch (error) {
      if (requestId !== this.playbackRequest || !this.showVertical) return;
      this.playerError = `播放地址获取失败: ${String(error)}`;
      this.showPlaybackToast('视频播放/加载失败，请重试！');
      console.error(`Pilihos playback failed: ${String(error)}`);
    }
  }

  private openSearchResult(item: VideoItem): void {
    const index: number = this.searchResults.indexOf(item);
    if (index < 0) return;
    this.videos = this.searchResults;
    this.currentIndex = index;
    this.showVertical = true;
    this.detailExpanded = this.autoExpandDescription;
    this.detailError = '';
    this.playbackStarting = false;
    this.playbackReady = false;
    this.loadVideoDetail();
    this.prepareCurrentVideo();
  }

  private async refreshAuthData(): Promise<void> {
    const current: AuthSession | null = AuthService.currentSession();
    if (current === null || current.cookie === '') return;
    try {
      this.authSession = await AuthService.validateCookie(current.cookie, this.context);
    } catch (error) {
      console.error(`Pilihos auth refresh failed: ${String(error)}`);
    }
  }

  onBackPress(): boolean {
    if (this.webLoginVisible) {
      this.webLoginVisible = false;
      return true;
    }
    if (this.loginVisible) {
      this.loginVisible = false;
      this.sidebar = 0;
      return true;
    }
    if (this.episodeListVisible || this.speedMenuVisible || this.qualityMenuVisible) {
      this.episodeListVisible = false;
      this.speedMenuVisible = false;
      this.qualityMenuVisible = false;
      this.showPlaybackControls();
      return true;
    }
    if (this.landscapePlayback) {
      this.closeLandscapePlayback();
      return true;
    }
    if (this.showVertical && this.verticalExpanded) {
      this.verticalExpanded = false;
      return true;
    }
    if (this.sidebar !== 0) {
      this.sidebar = 0;
      return true;
    }
    if (!this.showVertical) return false;
    if (this.playbackHistory.length > 0) {
      const previousIndex: number | undefined = this.playbackHistory.pop();
      if (previousIndex !== undefined && previousIndex >= 0 && previousIndex < this.videos.length) {
        this.savePlaybackProgress();
        this.restoringPlaybackHistory = true;
        this.openVideoDetail(this.videos[previousIndex], false);
        this.restoringPlaybackHistory = false;
        return true;
      }
    }
    this.savePlaybackProgress();
    this.exitPlaybackToHome();
    return true;
  }

  /**
   * 一键退出播放回首页（fanhui_left 逐级返回，home 直接回首页）
   * 带淡出过渡动画，避免瞬间切换的突兀感
   */
  private exitPlaybackToHome(): void {
    this.playbackRequest += 1;
    // 先播放淡出动画
    this.exitAnimProgress = 0;
    setTimeout((): void => {
      this.currentUrl = '';
      this.playbackUrls = [];
      this.playbackUrlIndex = 0;
      this.videoMounted = false;
      this.playbackStarting = false;
      this.playbackReady = false;
      this.playerError = '';
      this.showVertical = false;
      this.playbackHistory = [];
      this.landscapePlayback = false;
      this.verticalExpanded = false;
      this.sidebar = 0;
      // 消息跳转进入播放的：恢复跳转前的完整推荐流（不触发重新加载）
      if (this.feedSnapshotActive) {
        this.videos = this.savedFeedVideos;
        this.currentIndex = this.savedFeedIndex;
        this.feedSnapshotActive = false;
      }
      // 来自消息页的播放：退出后回到消息页
      if (this.jumpFromMessage) {
        this.jumpFromMessage = false;
        router.pushUrl({ url: 'pages/MessagePage' }).catch((error: BusinessError): void => {
          console.error('Pilihos message page restore failed: ' + String(error));
        });
      }
      // 动画结束后恢复透明度，为下次进入做准备
      setTimeout((): void => {
        this.exitAnimProgress = 1;
      }, 50);
      this.setPreferredOrientationPortrait();
      // 推荐流滚动位置恢复（等 Grid 重新挂载后执行）
      const restoreOffset: number = this.savedGridOffset;
      if (restoreOffset > 0) {
        setTimeout((): void => {
          this.homeGridScroller.scrollTo({ xOffset: 0, yOffset: restoreOffset });
        }, 150);
      }
    }, 220);
  }

  private setPreferredOrientationPortrait(): void {
    window.getLastWindow(this.context).then((mainWindow: window.Window): void => {
      mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT);
    }).catch((error: BusinessError): void => {
      console.warn('Pilihos portrait orientation failed: ' + String(error));
    });
  }

  private applyAutoRotate(): void {
    if (this.landscapePlayback) return;
    try {
      window.getLastWindow(this.context).then((mainWindow: window.Window): void => {
        if (this.autoRotateEnabled) {
          // 开启自动横屏：解除方向锁定，跟随系统传感器
          mainWindow.setPreferredOrientation(window.Orientation.UNSPECIFIED);
          console.info('Pilihos auto rotate enabled: sensor-driven');
        } else {
          // 关闭自动横屏：强制锁定竖屏
          mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT);
          console.info('Pilihos auto rotate disabled: locked to portrait');
        }
      }).catch((error: BusinessError): void => {
        console.warn('Pilihos auto rotate apply failed: ' + String(error));
      });
    } catch (error) {
      console.warn('Pilihos auto rotate failed: ' + String(error));
    }
  }

  private playbackCookie(): string {
    const session: AuthSession | null = this.authSession ?? AuthService.currentSession();
    return session === null ? '' : session.cookie;
  }


  @Builder
  playerSettingChip(label: string, selected: boolean, onSelect: () => void) {
    Toggle({ type: ToggleType.Button, isOn: selected }) {
      Text(label)
        .fontSize(13)
        .fontColor(selected ? Color.White : '#1E252D')
        .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
        .textAlign(TextAlign.Center);
    }
    .layoutWeight(1)
    .height(40)
    .selectedColor('#1288FA')
    .onChange((): void => { onSelect(); });
  }

  @Builder
  playModeSheet() {
    Scroll() {
      Column({ space: 10 }) {
        Text('视频播放').fontSize(17).fontWeight(FontWeight.Bold).width('100%');
        Row({ space: 6 }) {
          this.playerSettingChip('单集循环', this.playMode === 1,
            (): void => { this.setPlayMode(1); });
          this.playerSettingChip('随机连播', this.playMode === 2,
            (): void => { this.setPlayMode(2); });
          this.playerSettingChip('停止推荐', this.playMode === 3,
            (): void => { this.setPlayMode(3); });
        }.width('100%');
        Text('单集循环、随机连播或播放结束后停止推荐；合集顺序连播在选集菜单中开启')
          .fontSize(11).fontColor('#858C94').lineHeight(16).width('100%');
        Text('长按倍速').fontSize(15).fontWeight(FontWeight.Bold)
          .width('100%').padding({ top: 6 });
        Row({ space: 6 }) {
          this.playerSettingChip('0.75x', this.defaultSpeed === 0.75,
            (): void => { this.defaultSpeed = 0.75; });
          this.playerSettingChip('1.25x', this.defaultSpeed === 1.25,
            (): void => { this.defaultSpeed = 1.25; });
          this.playerSettingChip('1.50x', this.defaultSpeed === 1.5,
            (): void => { this.defaultSpeed = 1.5; });
          this.playerSettingChip('2.00x', this.defaultSpeed === 2,
            (): void => { this.defaultSpeed = 2; });
        }.width('100%');
        Text('长按视频时使用此倍速，普通播放保持 1.0x').fontSize(11).fontColor('#858C94')
          .lineHeight(16).width('100%');
        Text('偏好设置').fontSize(15).fontWeight(FontWeight.Bold)
          .width('100%').padding({ top: 6 });
        Row({ space: 6 }) {
          this.playerSettingChip('不看视频', false,
            (): void => { this.handleDetailAction('videohide'); });
          this.playerSettingChip('分享视频', false,
            (): void => { this.handleDetailAction('videoshare'); });
          this.playerSettingChip('举报视频', false,
            (): void => { this.handleDetailAction('videoreport'); });
          this.playerSettingChip('进小黑屋', false,
            (): void => { this.handleDetailAction('videoblock'); });
        }.width('100%');
        Text('不看视频/举报会移出当前视频；进小黑屋屏蔽该UP主')
          .fontSize(11).fontColor('#858C94').lineHeight(16).width('100%');
        Divider().strokeWidth(0.5).color('#1A000000');
        Text('弹幕设置').fontSize(17).fontWeight(FontWeight.Bold).width('100%');
        Text('字体大小').fontSize(13).fontColor('#858C94').width('100%');
        Row({ space: 6 }) {
          this.playerSettingChip('45', this.danmakuFontSize === 45,
            (): void => { this.setDanmakuFontSize(45); });
          this.playerSettingChip('50', this.danmakuFontSize === 50,
            (): void => { this.setDanmakuFontSize(50); });
          this.playerSettingChip('55', this.danmakuFontSize === 55,
            (): void => { this.setDanmakuFontSize(55); });
          this.playerSettingChip('60', this.danmakuFontSize === 60,
            (): void => { this.setDanmakuFontSize(60); });
        }.width('100%');
        Text('显示区域').fontSize(13).fontColor('#858C94').width('100%');
        Row({ space: 6 }) {
          this.playerSettingChip('25%', this.danmakuArea === 25,
            (): void => { this.setDanmakuArea(25); });
          this.playerSettingChip('50%', this.danmakuArea === 50,
            (): void => { this.setDanmakuArea(50); });
          this.playerSettingChip('75%', this.danmakuArea === 75,
            (): void => { this.setDanmakuArea(75); });
          this.playerSettingChip('100%', this.danmakuArea === 100,
            (): void => { this.setDanmakuArea(100); });
        }.width('100%');
        Text('不透明度').fontSize(13).fontColor('#858C94').width('100%');
        Row({ space: 6 }) {
          this.playerSettingChip('20%', this.danmakuOpacity === 0.2,
            (): void => { this.danmakuOpacity = 0.2; });
          this.playerSettingChip('50%', this.danmakuOpacity === 0.5,
            (): void => { this.danmakuOpacity = 0.5; });
          this.playerSettingChip('80%', this.danmakuOpacity === 0.8,
            (): void => { this.danmakuOpacity = 0.8; });
          this.playerSettingChip('100%', this.danmakuOpacity === 1,
            (): void => { this.danmakuOpacity = 1; });
        }.width('100%');
        Text('滚动速度').fontSize(13).fontColor('#858C94').width('100%');
        Row({ space: 6 }) {
          this.playerSettingChip('慢', this.danmakuSpeed === 0.5,
            (): void => { this.danmakuSpeed = 0.5; });
          this.playerSettingChip('中', this.danmakuSpeed === 1,
            (): void => { this.danmakuSpeed = 1; });
          this.playerSettingChip('快', this.danmakuSpeed === 1.5,
            (): void => { this.danmakuSpeed = 1.5; });
          this.playerSettingChip('极快', this.danmakuSpeed === 2,
            (): void => { this.danmakuSpeed = 2; });
        }.width('100%');
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: this.bottomInset + 16 });
    }
    .width('100%').height('100%').align(Alignment.Top).scrollBar(BarState.Off);
  }

  @Builder
  favFolderSheet() {
    Column({ space: 12 }) {
      Row() {
        Text('收藏夹').fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1);
        Image($r('app.media.newfiles')).width(22).height(22)
          .margin({ right: 14 })
          .onClick((): void => {
            this.favDeleteMode = false;
            this.favDeleteIds = [];
            this.newFavVisible = !this.newFavVisible;
            this.newFavTitle = '';
          });
        Image($r('app.media.delfiles')).width(22).height(22)
          .fillColor(this.favDeleteMode ? '#C51D2A' : undefined)
          .onClick((): void => {
            this.newFavVisible = false;
            this.favDeleteMode = !this.favDeleteMode;
            this.favDeleteIds = [];
          });
      }.width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ top: 4, right: 8 });
      if (this.favDeleteMode) {
        Row({ space: 12 }) {
          Text(this.favDeleteIds.length > 0 ? `已选 ${this.favDeleteIds.length} 项` : '点击文件夹勾选要删除的收藏夹')
            .fontSize(12).fontColor(this.favDeleteIds.length > 0 ? '#1288FA' : '#858C94')
            .layoutWeight(1);
          Text('取消').fontSize(13).fontColor('#59616B')
            .onClick((): void => {
              this.favDeleteMode = false;
              this.favDeleteIds = [];
            });
          Button(this.favDeleteIds.length > 0 ? `删除(${this.favDeleteIds.length})` : '删除')
            .height(32).fontSize(13)
            .backgroundColor('#C51D2A')
            .enabled(this.favDeleteIds.length > 0)
            .onClick((): void => { this.confirmDeleteFavFolders(); });
        }.width('100%');
      }
      if (this.newFavVisible) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '输入收藏夹标题', text: this.newFavTitle })
            .layoutWeight(1).height(38).fontSize(13)
            .backgroundColor('#F1F3F5').borderRadius(10)
            .onChange((value: string) => { this.newFavTitle = value; })
            .onSubmit((): void => { this.createFavFolder(); });
          Button(this.newFavCreating ? '创建中' : '创建')
            .height(34).fontSize(13)
            .backgroundColor('#1288FA')
            .onClick((): void => { this.createFavFolder(); });
        }.width('100%');
      }
      if (this.favFolders.length === 0) {
        Text(this.favError === '' ? '未获取到收藏夹' : this.favError)
          .fontSize(13).fontColor(this.favError === '' ? '#858C94' : '#C51D2A')
          .width('100%').textAlign(TextAlign.Center)
          .padding({ top: 20, bottom: 20 })
          .onClick((): void => { this.openFavSheet(); });
      }
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.favFolders, (folder: FavFolder) => {
          Column({ space: 5 }) {
            Stack() {
              Image($r('app.media.files')).width(38).height(38).opacity(folder.favoured ? 1 : 0.75);
              if (folder.favoured) {
                Text('已收').fontSize(9).fontColor(Color.White).backgroundColor('#F04B55')
                  .borderRadius(6).padding({ left: 4, right: 4, top: 1, bottom: 1 })
                  .position({ right: -4, top: -4 });
              }
              if (this.favDeleteMode) {
                // 删除模式勾选标记
                Text(this.favDeleteIds.indexOf(folder.id) >= 0 ? '✓' : '')
                  .fontSize(12).fontColor(Color.White).textAlign(TextAlign.Center)
                  .width(18).height(18)
                  .backgroundColor(this.favDeleteIds.indexOf(folder.id) >= 0 ? '#1288FA' : '#FFFFFF')
                  .border({ width: 1, color: this.favDeleteIds.indexOf(folder.id) >= 0 ? '#1288FA' : '#B9C2CC' })
                  .borderRadius(9)
                  .position({ left: -4, top: -4 });
              }
            }.width(44).height(44);
            Text(folder.title).fontSize(12).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              .textAlign(TextAlign.Center);
            Text(`${folder.mediaCount} 条内容`).fontSize(10).fontColor('#858C94');
          }
          .width('31%')
          .margin({ right: '2%', bottom: 10 })
          .padding({ top: 10, bottom: 10 })
          .borderRadius(10)
          .backgroundColor(this.favDeleteIds.indexOf(folder.id) >= 0 ? '#E5F3FA' : '#F7F8FA')
          .onClick((): void => {
            if (this.favDeleteMode) {
              // 删除模式：勾选/取消勾选
              const idx: number = this.favDeleteIds.indexOf(folder.id);
              if (idx >= 0) {
                this.favDeleteIds = this.favDeleteIds.filter((entry: number): boolean => entry !== folder.id);
              } else {
                this.favDeleteIds = this.favDeleteIds.concat([folder.id]);
              }
              return;
            }
            this.toggleFavFolder(folder);
          });
        }, (folder: FavFolder) => `fav_${folder.id}_${folder.favoured}_${this.favDeleteIds.indexOf(folder.id) >= 0}`);
      }.width('100%');
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: this.bottomInset + 16 });
  }


  build() {
    Stack() {
      // 首页背景使用 #F5F7F9 纯色，不再叠加品牌光斑。
      Column()
        .width('100%').height('100%')
        .backgroundColor('#F5F7F9')
        .zIndex(0);
      if (this.showVertical) {
        PlayerScreen({
          episodeListVisible: $episodeListVisible,
          onOpenVideo: (item: VideoItem, showComments: boolean): void => {
            this.openVideoDetail(item, showComments);
          },
          onRandomNext: (): void => { this.playRandomGlobalVideo(); },
          onSequentialNext: (): void => { this.playSequentialVideo(); },
          onLoadComments: (refresh: boolean): void => { this.loadComments(refresh); },
          onToggleReplies: (comment: VideoComment): void => { this.toggleSubReplies(comment); },
          onLoadSubReplies: (rootId: number, refresh: boolean): void => {
            this.loadSubReplies(rootId, refresh);
          },
          onSubmitComment: (): void => { this.submitComment(); },
          onSendDanmaku: (): void => { this.sendDanmaku(); },
          onDetailAction: (action: string): void => { this.handleDetailAction(action); },
          onOpenUser: (mid: number, name: string): void => {
            if (mid > 0) {
              this.pushUserSpace(mid, name);
            } else {
              this.showPlaybackToast('未能获取用户信息');
            }
          },
          onLikeComment: (comment: VideoComment): void => { this.toggleCommentLike(comment); },
          onToggleCommentSort: (): void => { this.onToggleCommentSort(); },
          onReplyComment: (comment: VideoComment): void => { this.replyToComment(comment); },
          onReplySubReply: (rootId: number, reply: VideoComment): void => {
            this.replyToSubReply(rootId, reply);
          },
          onPickEmoji: (emoji: BiliEmoji): void => { this.selectEmoji(emoji); },
          onDeleteComment: (comment: VideoComment): void => { this.deleteComment(comment); },
          onHideComment: (comment: VideoComment): void => { this.hideComment(comment); },
          onReportComment: (comment: VideoComment): void => { this.reportComment(comment); },
          onBlockComment: (comment: VideoComment): void => { this.blockCommentUser(comment); },
          onFollowAuthor: (on: boolean): void => { this.followAuthor(on); },
          onFollowGroup: (): void => { this.showPlaybackToast('分组管理开发中，敬请期待'); },
          onRetry: (): void => { this.prepareCurrentVideo(); },
          onQualitySwitch: (qn: number): void => { this.switchPlaybackQuality(qn); },
          onBack: (): void => { this.onBackPress(); },
          onBackHome: (): void => { this.backToHome(); },
          onSetPlayMode: (mode: number): void => { this.setPlayMode(mode); },
          onSetDanmakuFontSize: (size: number): void => { this.setDanmakuFontSize(size); },
          onSetDanmakuArea: (area: number): void => { this.setDanmakuArea(area); },
          onOpenLandscape: (): void => { this.openLandscapePlayback(); },
          onCloseLandscape: (): void => { this.closeLandscapePlayback(); }
        })
        .opacity(this.exitAnimProgress)
        .animation({ duration: 200, curve: Curve.EaseOut });
      } else {
        Stack({ alignContent: Alignment.Start }) {
          HomeTab({
            scroller: this.homeGridScroller,
            refreshing: $refreshing,
            onOpenVideo: (item: VideoItem): void => { this.openVideoDetail(item, false); },
            onPlayDynamic: (item: VideoItem, showComments: boolean): void => {
              this.openDynamicVideo(item, showComments);
            },
            onLoadMore: (): void => { this.loadMoreRecommendations(); },
            onRefresh: (): void => { this.refreshCurrentPage(); },
            onOpenSearch: (): void => { this.openSearchPanel(); },
            onScrollDelta: (delta: number): void => { this.handleGridScroll(delta); },
            onSelectTab: (index: number): void => { this.selectContentTab(index); },
            onOpenAuthor: (item: VideoItem): void => { this.openAuthorSpaceItem(item); },
            onLikeDynamicVideo: (item: VideoItem): void => { this.likeVideoItem(item); },
            onShareDynamicVideo: (item: VideoItem): void => { this.shareVideoItem(item); },
            onLikeDynamicEntry: (entry: DynamicEntry): void => { this.likeDynamicEntry(entry); },
            onShareDynamicEntry: (entry: DynamicEntry): void => { this.shareDynamicEntry(entry); },
            onVideoQuickAction: (item: VideoItem, action: string): void => {
              this.handleVideoQuickAction(item, action);
            }
          });
          Column() {
            HomeBottomBar({
              refreshing: $refreshing,
              onScrollTop: (): void => {
                this.homeGridScroller.scrollTo({ xOffset: 0, yOffset: 0 });
              },
              onListRefresh: (): void => {
                this.homeGridScroller.scrollTo({ xOffset: 0, yOffset: 0 });
                this.refreshCurrentPage();
              },
              onOpenSearch: (): void => { this.openSearchPanel(); },
              onSelectTab: (index: number): void => { this.selectContentTab(index); }
            });
          }
          .width('100%').height('100%')
          .hitTestBehavior(HitTestMode.Transparent);
        }
        .width('100%').height('100%')
        .backgroundColor(Color.Transparent);
      }
      if (this.loginVisible && !this.showVertical) {
        LoginPage();
      }
      if (this.webLoginVisible && !this.showVertical) {
        WebLoginPage();
      }
      // 侧边栏：遮罩覆盖全屏，面板按类型贴在对应屏幕边缘。
      if (this.sidebar !== 0 && !this.showVertical) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('#66000000')
          .onClick((): void => { this.sidebar = 0; })
          .zIndex(30);
        Column() {
          if (this.sidebar === 1) {
            MineSidebar();
          }
        }
        .width('100%').height('100%')
        .backgroundColor('#F5F7F9')
        .alignItems(HorizontalAlign.Start)
        .position({ left: 0, top: 0 })
        .translate({ x: 0 })
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.translate({ x: this.sidebar === 1 ? -320 : 320 })
            .combine(TransitionEffect.OPACITY),
          TransitionEffect.translate({ x: this.sidebar === 1 ? -320 : 320 })
            .combine(TransitionEffect.OPACITY)
        ).animation({ duration: 300, curve: Curve.EaseInOut }))
        .zIndex(31);
      }
      Row()
        .width(0).height(0)
        .bindSheet($$this.playModeSheetVisible, this.playModeSheet(), {
          height: SheetSize.MEDIUM,
          dragBar: true,
          showClose: false,
          detents: [SheetSize.MEDIUM, SheetSize.LARGE]
        });
      Row()
        .width(0).height(0)
        .bindSheet($$this.favSheetVisible, this.favFolderSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          showClose: false
        });
    }.width('100%').height('100%')
      .backgroundColor('#F5F7F9')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }
}
