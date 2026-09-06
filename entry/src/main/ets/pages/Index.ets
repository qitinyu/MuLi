import { VideoItem } from '../models/VideoItem';
import { VideoDetailService } from '../services/VideoDetailService';
import { RecommendationService, RecommendationBatch } from '../services/RecommendationService';
import { ReplyService, VideoComment, CommentBatch } from '../services/ReplyService';
import { PlaybackService, PlaybackResolveResult, QualityOption } from '../services/PlaybackService';
import { BiliHttpClient } from '../services/BiliHttpClient';
import { DanmakuService } from '../services/DanmakuService';
import { WbiService } from '../services/WbiService';
import { AuthService, AuthSession } from '../services/AuthService';
import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import { Want } from '@kit.AbilityKit';
import window from '@ohos.window';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import { AdvancedFeatures } from '../utils/AdvancedFeatures';
import { FilterWords } from '../utils/FilterWords';
import { FormatUtils } from '../utils/FormatUtils';
import { PlaybackMemory } from '../utils/PlaybackMemory';
import { HomeTab } from '../components/HomeTab';
import { HomeBottomBar, HomeActionMenu } from '../components/HomeBottomBar';
import { MineSidebar, MessageSidebar } from '../components/Sidebars';
import { LoginPage, WebLoginPage } from '../components/LoginViews';
import { PlayerScreen } from '../components/PlayerScreen';

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
  @Provide videoWeight: number = 8;
  @Provide pendingResumeMs: number = 0;
  @Provide portraitBadge: boolean = true;
  @Provide currentIndex: number = 0;
  @Provide loading: boolean = false;
  @Provide loadingMore: boolean = false;
  @State refreshing: boolean = false;
  @State keepRefreshContent: boolean = false;
  @Provide compactGrid: boolean = false;
  @Provide actionMenuVisible: boolean = false;
  @Provide floatBallSwapped: boolean = false;
  @Provide topTabsMerged: boolean = false;
  @State bottomBarPinned: boolean = true;
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
  @Provide playbackQualities: QualityOption[] = [];
  @Provide currentQn: number = 0;
  @Provide qualityMenuVisible: boolean = false;
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
  @State showMineCoverSheet: boolean = false;
  @Provide topInset: number = 0;
  @Provide bottomInset: number = 0;
  @Provide detailSection: number = 0;
  @Provide comments: VideoComment[] = [];
  @Provide expandedCommentId: number = -1;
  @Provide subReplies: VideoComment[] = [];
  @Provide subLoading: boolean = false;
  private subPage: number = 1;
  @Provide subHasMore: boolean = false;
  @Provide showCommentInput: boolean = false;
  @Provide commentInputText: string = '';
  @Provide commentLoading: boolean = false;
  @Provide commentError: string = '';
  private commentPage: number = 1;
  @Provide commentTotal: number = 0;
  @Provide commentHasMore: boolean = false;
  @State useAdvancedMaterial: boolean = false;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private playbackRequest: number = 0;
  private detailRequest: number = 0;
  private playbackControlsTimer: number = 0;
  private hasMoreRecommendations: boolean = true;
  @Provide videos: VideoItem[] = Index.placeholderVideos();

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
        statusBarColor: '#F7F8FA',
        navigationBarColor: '#00000000',
        isStatusBarLightIcon: lightIcon,
        isNavigationBarLightIcon: lightIcon
      });
    } catch (error) {
      console.error('Pilihos system bar appearance failed: ' + String(error));
    }
  }

  aboutToAppear(): void {
    this.setSystemBarAppearance(true);
    BiliHttpClient.initDeviceIdentity(this.context);
    WbiService.warmup();
    this.authSession = AuthService.currentSession();
    AdvancedFeatures.loadSettings(this.context);
    this.loadPlayerSettings();
    FilterWords.load(this.context);
    PlaybackMemory.load(this.context);
    this.restoreAuthSession();
    this.loadRecommendations();
    this.updateSystemInsets();
  }

  private async updateSystemInsets(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navigationArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.topInset = px2vp(systemArea.topRect.height);
      this.bottomInset = px2vp(navigationArea.bottomRect.height);
      mainWindow.on('avoidAreaChange', (data): void => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          this.topInset = px2vp(data.area.topRect.height);
        } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          this.bottomInset = px2vp(data.area.bottomRect.height);
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
    }
  }

  onPageShow(): void {
    this.loadPlayerSettings();
    this.consumeSearchPayload();
  }

  private async loadPlayerSettings(): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_player');
      this.keepRefreshContent = store.getSync('keep_refresh_content', false) as boolean;
      this.defaultQuality = store.getSync('default_quality', 0) as number;
      const appearanceStore: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_ui');
      this.floatBallSwapped = appearanceStore.getSync('float_ball_swapped', false) as boolean;
      this.topTabsMerged = appearanceStore.getSync('top_tabs_merged', false) as boolean;
      this.bottomBarPinned = appearanceStore.getSync('bottom_bar_pinned', true) as boolean;
      this.portraitBadge = appearanceStore.getSync('portrait_badge', true) as boolean;
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
      const updated: VideoItem = await VideoDetailService.load(item);
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
        detailed, session === null ? '' : session.cookie, nextPage);
      this.comments = refresh ? batch.items : this.comments.concat(batch.items);
      this.commentPage = nextPage;
      this.commentTotal = batch.total;
      this.commentHasMore = batch.hasMore;
    } catch (error) {
      this.commentError = '评论加载失败，请稍后重试';
      console.error('Pilihos comments failed: ' + String(error));
    } finally {
      this.commentLoading = false;
    }
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

  private submitCommentEntry(): void {
    // 评论发布入口：编辑能力后续接入，先展示占位反馈
    this.showPlaybackToast('评论发布功能开发中，敬请期待');
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
    this.playbackControlsVisible = true;
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
    const index: number = this.videos.indexOf(item);
    if (index < 0 || item.placeholder) return;
    this.savePlaybackProgress();
    this.currentIndex = index;
    this.detailSection = showComments ? 1 : 0;
    this.detailExpanded = false;
    this.detailError = '';
    this.currentUrl = '';
    this.playbackStarting = false;
    this.playbackReady = false;
    this.comments = [];
    this.commentPage = 1;
    this.commentTotal = 0;
    this.commentHasMore = false;
    this.commentError = '';
    this.expandedCommentId = -1;
    this.subReplies = [];
    this.subHasMore = false;
    this.showCommentInput = false;
    this.commentInputText = '';
    this.playbackCurrentMs = 0;
    this.playbackDurationMs = item.duration > 0 ? item.duration * 1000 : 0;
    this.playbackPaused = true;
    this.playbackSpeed = 1.0;
    this.speedMenuVisible = false;
    this.episodeListVisible = false;
    this.qualityMenuVisible = false;
    this.playbackControlsVisible = false;
    this.subtitlesEnabled = false;
    this.danmakuEnabled = true;
    this.verticalExpanded = false;
    this.videoWeight = 8;
    this.currentQn = 0;
    this.playbackQualities = [];
    this.showVertical = true;
    // 播放记忆：恢复上次进度，prepared 后自动 seek（看完的视频从头播放）
    const savedMs: number = PlaybackMemory.progressOf(item.aid);
    if (savedMs > 5000 && (item.duration <= 0 || savedMs < item.duration * 1000 - 5000)) {
      this.pendingResumeMs = savedMs;
      this.showPlaybackToast(`已恢复上次进度 ${FormatUtils.formatPlaybackTime(savedMs)}`);
    }
    this.loadVideoDetail();
    this.prepareCurrentVideo();
    if (showComments) this.loadComments(true);
  }

  private openDynamicVideo(item: VideoItem, showComments: boolean = false): void {
    this.refreshing = false;
    this.actionMenuVisible = false;
    this.videos = [item];
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
    this.videoMounted = true;
    this.playbackReady = false;
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      await mainWindow.setPreferredOrientation(window.Orientation.LANDSCAPE);
    } catch (error) {
      console.error('Pilihos landscape orientation failed: ' + String(error));
    }
  }

  private async closeLandscapePlayback(): Promise<void> {
    this.pendingResumeMs = this.playbackCurrentMs;
    this.landscapePlayback = false;
    this.setSystemBarAppearance(true);
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
    this.currentUrl = '';
    this.playbackUrls = [];
    this.playbackUrlIndex = 0;
    this.videoMounted = false;
    this.playbackStarting = false;
    this.playbackReady = false;
    this.playbackCurrentMs = 0;
    this.playbackDurationMs = 0;
    this.playbackPaused = true;
    this.speedMenuVisible = false;
    this.episodeListVisible = false;
    this.playbackControlsVisible = true;
    this.playbackFinished = false;
    this.recommendedPlaybackIndex = -1;
    let item: VideoItem = this.videos[this.currentIndex];
    try {
      if (item.cid <= 0) {
        item = await VideoDetailService.load(item);
        if (requestId !== this.playbackRequest || !this.showVertical) return;
        this.videos = this.videos.map((candidate: VideoItem): VideoItem =>
          candidate.id === item.id ? item : candidate);
      }
      if (item.cid <= 0) throw new Error('视频 cid 缺失，无法获取播放地址');
      if (item.duration > 0) this.playbackDurationMs = item.duration * 1000;
      // 播放地址带有短期签名，详情页每次进入都重新获取；只有接口失败时才使用旧缓存。
      // targetQn>0 时请求指定清晰度（清晰度切换），否则使用设置中的默认质量。
      const effectiveQn: number = targetQn > 0 ? targetQn : this.defaultQuality;
      let urls: string[] = [];
      try {
        const resolved: PlaybackResolveResult =
          await PlaybackService.resolveWithQuality(item, this.playbackCookie(), effectiveQn);
        urls = resolved.urls;
        this.playbackQualities = resolved.qualities;
        this.currentQn = resolved.grantedQn;
      } catch (resolveError) {
        if (item.playUrl === '') throw new Error(String(resolveError));
        console.warn(`Pilihos live playback URL resolve failed, using cached URL: ${String(resolveError)}`);
        urls = [item.playUrl];
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
    this.detailExpanded = false;
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
      this.showMineCoverSheet = false;
      return true;
    }
    if (!this.showVertical) return false;
    this.savePlaybackProgress();
    this.playbackRequest += 1;
    this.currentUrl = '';
    this.playbackUrls = [];
    this.playbackUrlIndex = 0;
    this.videoMounted = false;
    this.playbackStarting = false;
    this.playbackReady = false;
    this.playerError = '';
    this.showVertical = false;
    this.closeLandscapePlayback();
    return true;
  }

  private playbackCookie(): string {
    const session: AuthSession | null = this.authSession ?? AuthService.currentSession();
    return session === null ? '' : session.cookie;
  }

  build() {
    Stack() {
      if (this.showVertical) {
        PlayerScreen({
          episodeListVisible: $episodeListVisible,
          onOpenVideo: (item: VideoItem, showComments: boolean): void => {
            this.openVideoDetail(item, showComments);
          },
          onLoadComments: (refresh: boolean): void => { this.loadComments(refresh); },
          onToggleReplies: (comment: VideoComment): void => { this.toggleSubReplies(comment); },
          onLoadSubReplies: (rootId: number, refresh: boolean): void => {
            this.loadSubReplies(rootId, refresh);
          },
          onSubmitComment: (): void => { this.submitCommentEntry(); },
          onSendDanmaku: (): void => { this.sendDanmaku(); },
          onRetry: (): void => { this.prepareCurrentVideo(); },
          onQualitySwitch: (qn: number): void => { this.switchPlaybackQuality(qn); },
          onBack: (): void => { this.onBackPress(); },
          onOpenLandscape: (): void => { this.openLandscapePlayback(); }
        });
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
            onScrollDelta: (delta: number): void => { this.handleGridScroll(delta); },
            onSelectTab: (index: number): void => { this.selectContentTab(index); }
          });
          HomeBottomBar({
            refreshing: $refreshing,
            onScrollTop: (): void => {
              this.homeGridScroller.scrollTo({ xOffset: 0, yOffset: 0 });
            },
            onListRefresh: (): void => {
              this.homeGridScroller.scrollTo({ xOffset: 0, yOffset: 0 });
              this.refreshCurrentPage();
            },
            onOpenSearch: (): void => { this.openSearchPanel(); }
          });
          HomeActionMenu({
            onListRefresh: (): void => {
              this.homeGridScroller.scrollTo({ xOffset: 0, yOffset: 0 });
              this.refreshCurrentPage();
            }
          });
        }
        .width('100%').height('100%')
        .backgroundColor('#F7F8FA');
      }
      if (this.loginVisible && !this.showVertical) {
        LoginPage();
      }
      if (this.webLoginVisible && !this.showVertical) {
        WebLoginPage();
      }
      if (this.sidebar !== 0 && !this.showVertical) {
        Column() {
          if (this.sidebar === 1) {
            MineSidebar({ showMineCoverSheet: $showMineCoverSheet });
          } else {
            MessageSidebar();
          }
        }
        .width('100%').height('100%')
        .backgroundColor(ImmersiveMaterial.fallbackBackground())
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
        .transition({ type: TransitionType.Insert, opacity: 0.0 });
      }
    }.width('100%').height('100%')
      .backgroundColor('#F7F8FA')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }
}
