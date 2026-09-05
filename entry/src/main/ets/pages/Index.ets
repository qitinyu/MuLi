import { VideoPlayerService } from '../services/VideoPlayerService';
import { VideoItem } from '../models/VideoItem';
import { VideoDetailService } from '../services/VideoDetailService';
import { RecommendationService, RecommendationBatch } from '../services/RecommendationService';
import { DynamicService, DynamicBatch, DynamicAuthor } from '../services/DynamicService';
import { ReplyService, VideoComment, CommentBatch } from '../services/ReplyService';
import { PlaybackService } from '../services/PlaybackService';
import { WbiService } from '../services/WbiService';
import { AuthService, AuthSession } from '../services/AuthService';
import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import { Want } from '@kit.AbilityKit';
import window from '@ohos.window';
import { BusinessError } from '@kit.BasicServicesKit';
import { media } from '@kit.MediaKit';
import { picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import web_webview from '@ohos.web.webview';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import { AdvancedFeatures } from '../utils/AdvancedFeatures';

@Entry
@Component
struct Index {
  @State showVertical: boolean = false;
  @State landscapePlayback: boolean = false;
  @State currentIndex: number = 0;
  @State draggingDown: boolean = false;
  @State loading: boolean = false;
  @State loadingMore: boolean = false;
  @State refreshing: boolean = false;
  @State keepRefreshContent: boolean = false;
  @State compactGrid: boolean = false;
  @State actionMenuVisible: boolean = false;
  @State showDynamicEditor: boolean = false;
  @State floatBallSwapped: boolean = false;
  @State topTabsMerged: boolean = false;
  private page: number = 0;
  private recommendationIndex: string = '0';
  private homeGridScroller: Scroller = new Scroller();
  private lastLoadTriggerLength: number = -1;
  private refreshRunning: boolean = false;
  @State loadError: string = '';
  @State activeTab: number = 1;
  @State contentTab: number = 1;
  @State selectedTopTab: number = 1;
  @State searchResults: VideoItem[] = [];
  private searchPayloadConsumed: boolean = false;
  @State loginVisible: boolean = false;
  @State webLoginVisible: boolean = false;
  @State webLoginStatus: string = '';
  @State loginNotice: string = '';
  @State authSession: AuthSession | null = null;
  @State danmakuText: string = '';
  @State detailExpanded: boolean = false;
  @State detailLoading: boolean = false;
  @State detailError: string = '';
  @State sidebar: number = 0;
  @State currentUrl: string = '';
  @State videoMounted: boolean = false;
  @State surfaceReady: boolean = false;
  @State playbackStarting: boolean = false;
  @State playbackReady: boolean = false;
  @State playbackUrls: string[] = [];
  @State playbackUrlIndex: number = 0;
  @State playerError: string = '';
  @State playbackCurrentMs: number = 0;
  @State playbackDurationMs: number = 0;
  @State playbackPaused: boolean = true;
  @State playbackSpeed: number = 1.0;
  @State speedMenuVisible: boolean = false;
  @State episodeListVisible: boolean = false;
  @State playbackControlsVisible: boolean = true;
  @State playbackFinished: boolean = false;
  @State recommendedPlaybackIndex: number = -1;
  @State subtitlesEnabled: boolean = false;
  @State danmakuEnabled: boolean = true;
  @State mineCoverUri: string = '';
  @State showMineCoverSheet: boolean = false;
  @State topInset: number = 0;
  @State bottomInset: number = 0;
  @State dynamicVideos: VideoItem[] = [];
  @State dynamicAuthors: DynamicAuthor[] = [];
  @State dynamicLoading: boolean = false;
  @State dynamicError: string = '';
  private dynamicOffset: string = '';
  @State detailSection: number = 0;
  @State comments: VideoComment[] = [];
  @State commentLoading: boolean = false;
  @State commentError: string = '';
  @State commentPage: number = 1;
  @State commentTotal: number = 0;
  @State commentHasMore: boolean = false;
  @State useAdvancedMaterial: boolean = false;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private uiPreferences: preferences.Preferences | null = null;
  private playerService: VideoPlayerService = new VideoPlayerService();
  private webController: web_webview.WebviewController = new web_webview.WebviewController();
  private playbackRequest: number = 0;
  private detailRequest: number = 0;
  private playbackControlsTimer: number = 0;
  private surfaceController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private nativeVideoController: VideoController = new VideoController();
  private hasMoreRecommendations: boolean = true;
  @State videos: VideoItem[] = Index.placeholderVideos();

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
    WbiService.warmup();
    this.playerService.onError((message: string): void => {
      this.handleNativePlaybackError(message);
    });
    this.playerService.onTimeUpdate((currentMs: number, durationMs: number): void => {
      if (!this.showVertical) return;
      this.playbackCurrentMs = currentMs;
      if (durationMs > 0) this.playbackDurationMs = durationMs;
      if (!this.playbackFinished && durationMs > 0 && currentMs >= durationMs - 800) {
        this.markPlaybackFinished();
      }
    });
    this.playerService.onStateChange((state: media.AVPlayerState): void => {
      if (!this.showVertical) return;
      this.playbackPaused = state !== 'playing';
      if (state === 'playing') this.playbackReady = true;
      if (state === 'completed') {
        this.markPlaybackFinished();
      }
    });
    this.authSession = AuthService.currentSession();
    AdvancedFeatures.loadSettings(this.context);
    this.loadPlayerSettings();
    this.restoreAuthSession();
    this.loadMineCover();
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

  // 删除重复的setSystemBarAppearance方法定义，保留原有的方法实现

  onPageShow(): void {
    this.loadPlayerSettings();
    this.consumeSearchPayload();
  }

  private async loadPlayerSettings(): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_player');
      this.keepRefreshContent = store.getSync('keep_refresh_content', false) as boolean;
      const appearanceStore: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_ui');
      this.floatBallSwapped = appearanceStore.getSync('float_ball_swapped', false) as boolean;
      this.topTabsMerged = appearanceStore.getSync('top_tabs_merged', false) as boolean;
      
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
        this.videos = batch.items;
        this.lastLoadTriggerLength = -1;
        this.hasMoreRecommendations = true;
      }
    } catch (error) {
      this.loadError = '\u63A8\u8350\u52A0\u8F7D\u5931\u8D25\uFF0C\u8BF7\u68C0\u67E5\u7F51\u7EDC';
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
    if (params === undefined || this.searchPayloadConsumed) return;
    const payload: Object | undefined =
      (params as Record<string, Object>)['pilihosSearch'] as Object | undefined;
    if (payload === undefined) return;
    const results: VideoItem[] = (payload as Record<string, Object>)['results'] as VideoItem[];
    const index: number = Number((payload as Record<string, Object>)['index']);
    if (!Array.isArray(results) || Number.isNaN(index) || index < 0 || index >= results.length) return;
    this.searchPayloadConsumed = true;
    this.searchResults = results;
    this.openSearchResult(results[index]);
  }

  private async loadDynamicVideos(refresh: boolean = false): Promise<void> {
    const session: AuthSession | null = this.authSession ?? AuthService.currentSession();
    if (session === null || session.cookie === '') {
      this.dynamicVideos = [];
      this.dynamicError = '登录后查看关注用户的最新投稿';
      return;
    }
    if (this.dynamicLoading) return;
    this.dynamicLoading = true;
    this.dynamicError = '';
    try {
      const batch: DynamicBatch = await DynamicService.loadVideos(session.cookie, refresh ? '' : this.dynamicOffset);
      this.dynamicOffset = batch.offset;
      this.dynamicVideos = refresh ? batch.items : this.dynamicVideos.concat(batch.items);
      if (refresh) {
        this.dynamicAuthors = batch.authors;
      } else {
        const mergedAuthors: DynamicAuthor[] = this.dynamicAuthors.slice();
        batch.authors.forEach((author: DynamicAuthor): void => {
          if (!mergedAuthors.some((candidate: DynamicAuthor): boolean => candidate.name === author.name)) {
            mergedAuthors.push(author);
          }
        });
        this.dynamicAuthors = mergedAuthors;
      }
    } catch (error) {
      this.dynamicError = '动态加载失败，请检查网络或登录状态';
      console.error('Pilihos dynamic failed: ' + String(error));
    } finally {
      this.dynamicLoading = false;
    }
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
      this.loadError = '\u63A8\u8350\u5237\u65B0\u5931\u8D25\uFF0C\u8BF7\u68C0\u67E5\u7F51\u7EDC';
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

  private openVideoDetail(item: VideoItem, showComments: boolean = false): void {
    const index: number = this.videos.indexOf(item);
    if (index < 0 || item.placeholder) return;
    this.currentIndex = index;
    this.detailSection = showComments ? 1 : 0;
    this.detailExpanded = false;
    this.detailError = '';
    this.currentUrl = '';
    this.surfaceReady = false;
    this.surfaceId = '';
    this.playbackStarting = false;
    this.playbackReady = false;
    this.comments = [];
    this.commentPage = 1;
    this.commentTotal = 0;
    this.commentHasMore = false;
    this.commentError = '';
    this.playbackCurrentMs = 0;
    this.playbackDurationMs = item.duration > 0 ? item.duration * 1000 : 0;
    this.playbackPaused = true;
    this.playbackSpeed = 1.0;
    this.speedMenuVisible = false;
    this.episodeListVisible = false;
    this.playbackControlsVisible = true;
    this.subtitlesEnabled = false;
    this.danmakuEnabled = true;
    this.showVertical = true;
    this.loadVideoDetail();
    this.prepareCurrentVideo();
    if (showComments) this.loadComments(true);
  }

  private openDynamicVideo(item: VideoItem, showComments: boolean = false): void {
    this.refreshing = false;
    this.actionMenuVisible = false;
    this.videos = this.dynamicVideos;
    this.openVideoDetail(item, showComments);
  }

  private async refreshCurrentPage(): Promise<void> {
    if (this.refreshRunning) return;
    this.refreshRunning = true;
    this.refreshing = true;
    try {
      if (this.activeTab === 0 || this.contentTab === 3) {
        await this.loadDynamicVideos(true);
      } else if (this.contentTab === 1) {
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
    if (this.activeTab === 0) this.loadDynamicVideos(true);
    if (restored === null && current !== null) this.refreshAuthData();
  }

  private async loadMoreRecommendations(): Promise<void> {
    if (this.loadingMore || this.loading || !this.hasMoreRecommendations) return;
    this.loadingMore = true;
    try {
      const batch: RecommendationBatch = await RecommendationService.loadBatch(this.recommendationIndex);
      const next: VideoItem[] = batch.items;
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

  private openVertical(): void {
    this.showVertical = true;
    this.currentIndex = 0;
    this.prepareCurrentVideo();
  }

  private async loadMineCover(): Promise<void> {
    try {
      this.uiPreferences = await preferences.getPreferences(this.context, 'pilihos_ui');
      this.mineCoverUri = this.uiPreferences.getSync('mine_cover_uri', '') as string;
    } catch (error) {
      console.error('Pilihos cover preference load failed: ' + String(error));
    }
  }

  private async chooseMineCover(): Promise<void> {
    this.showMineCoverSheet = false;
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({ maxSelectNumber: 1 });
      if (result.photoUris && result.photoUris.length > 0) {
        this.mineCoverUri = result.photoUris[0];
        if (this.uiPreferences === null) {
          this.uiPreferences = await preferences.getPreferences(this.context, 'pilihos_ui');
        }
        this.uiPreferences.putSync('mine_cover_uri', this.mineCoverUri);
        this.uiPreferences.flushSync();
      }
    } catch (error) {
      console.error('Pilihos cover picker failed: ' + String(error));
    }
  }

  private async openLandscapePlayback(): Promise<void> {
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
    this.landscapePlayback = false;
    this.setSystemBarAppearance(true);
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      await mainWindow.setPreferredOrientation(window.Orientation.PORTRAIT);
    } catch (error) {
      console.error('Pilihos portrait orientation failed: ' + String(error));
    }
  }

  private async prepareCurrentVideo(): Promise<void> {
    const requestId: number = this.playbackRequest + 1;
    this.playbackRequest = requestId;
    this.playerError = '';
    this.currentUrl = '';
    this.playbackUrls = [];
    this.playbackUrlIndex = 0;
    this.videoMounted = false;
    this.surfaceReady = false;
    this.surfaceId = '';
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
    await this.playerService.release();
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
      let urls: string[] = [];
      try {
        urls = await PlaybackService.resolveCandidates(item, this.playbackCookie());
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
      console.info(`Pilihos playback URL selected: ${this.playbackUrlDescription(this.currentUrl)}, candidates=${urls.length}`);
      this.videoMounted = true;
      this.playbackStarting = false;
    } catch (error) {
      if (requestId !== this.playbackRequest || !this.showVertical) return;
      this.playerError = `播放地址获取失败: ${String(error)}`;
      this.showPlaybackToast('视频播放/加载失败，请重试！');
      console.error(`Pilihos playback failed: ${String(error)}`);
    }
  }

  private formatCount(value: number): string {
    if (value >= 100000000) return `${(value / 100000000).toFixed(2).replace(/\.00$/, '')}亿`;
    if (value >= 1000000) return `${(value / 100000).toFixed(2).replace(/\.00$/, '')}万`;
    if (value >= 1000) return `${(value / 1000).toFixed(1).replace(/\.0$/, '')}千`;
    return `${value}`;
  }

  private openSearchResult(item: VideoItem): void {
    const index: number = this.searchResults.indexOf(item);
    if (index < 0) return;
    this.videos = this.searchResults;
    this.currentIndex = index;
    this.showVertical = true;
    this.detailExpanded = false;
    this.detailError = '';
    this.surfaceReady = false;
    this.surfaceId = '';
    this.playbackStarting = false;
    this.playbackReady = false;
    this.loadVideoDetail();
    this.prepareCurrentVideo();
  }

  private formatPublishTime(timestamp: number): string {
    if (timestamp <= 0) return '发布时间未知';
    const seconds: number = Math.max(0, Math.floor(Date.now() / 1000) - timestamp);
    if (seconds < 3600) return String(Math.max(1, Math.floor(seconds / 60))) + '\u5206\u949F\u524D';
    if (seconds < 86400) return String(Math.floor(seconds / 3600)) + '\u5C0F\u65F6\u524D';
    if (seconds < 259200) return `${Math.floor(seconds / 86400)}天前`;
    const date: Date = new Date(timestamp * 1000);
    return `${String(date.getFullYear()).substring(2)}/${date.getMonth() + 1}/${date.getDate()}`;
  }


  private formatPublishDate(timestamp: number): string {
    if (timestamp <= 0) return '\u53D1\u5E03\u65F6\u95F4\u672A\u77E5';
    const date: Date = new Date(timestamp * 1000);
    const month: string = String(date.getMonth() + 1).padStart(2, '0');
    const day: string = String(date.getDate()).padStart(2, '0');
    const hour: string = String(date.getHours()).padStart(2, '0');
    const minute: string = String(date.getMinutes()).padStart(2, '0');
    return String(date.getFullYear()) + '-' + month + '-' + day + ' ' + hour + ':' + minute;
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
  private openWebLogin(): void {
    this.loginNotice = '';
    this.webLoginStatus = '请在官方页面完成登录、验证码和人机校验';
    this.webLoginVisible = true;
  }

  private async syncWebLoginCookie(): Promise<void> {
    if (!this.webLoginVisible) return;
    try {
      let cookie: string = '';
      if (AdvancedFeatures.isWebCookieManagerEnabled()) {
        cookie = await web_webview.WebCookieManager.fetchCookie('https://www.bilibili.com');
      } else {
        try {
          cookie = web_webview.WebCookieManager.getCookie('https://www.bilibili.com');
        } catch (e) {
          console.error('Pilihos web cookie fetch fallback failed: ' + String(e));
        }
      }
      if (cookie === '' || !cookie.includes('SESSDATA=')) return;
      const session: AuthSession = await AuthService.validateCookie(cookie, this.context);
      this.authSession = session;
      this.loginNotice = '登录成功，欢迎 ' + session.name;
      this.webLoginStatus = '登录成功';
      this.webLoginVisible = false;
      this.closeLoginPage();
    } catch (error) {
      this.webLoginStatus = '等待官方登录完成';
      console.error('Pilihos web login cookie sync failed: ' + String(error));
    }
  }
  private closeLoginPage(): void {
    this.loginVisible = false;
    this.sidebar = 0;
  }
  private async logout(): Promise<void> {
    await AuthService.logout();
    this.authSession = null;
    this.loginNotice = '\u5DF2\u9000\u51FA\u767B\u5F55';
  }
  private openSoftwareSettings(): void {
    this.sidebar = 0;
    router.pushUrl({ url: 'pages/Settings' }).catch((error: BusinessError): void => {
      console.error('Pilihos settings page failed: ' + String(error));
    });
  }

  onBackPress(): boolean {
    if (this.webLoginVisible) {
      this.webLoginVisible = false;
      return true;
    }
    if (this.loginVisible) {
      this.closeLoginPage();
      return true;
    }
    if (this.episodeListVisible || this.speedMenuVisible) {
      this.episodeListVisible = false;
      this.speedMenuVisible = false;
      this.showPlaybackControls();
      return true;
    }
    if (this.landscapePlayback) {
      this.closeLandscapePlayback();
      return true;
    }
    if (this.sidebar !== 0) {
      this.sidebar = 0;
      this.showMineCoverSheet = false;
      return true;
    }
    if (!this.showVertical) return false;
    this.playbackRequest += 1;
    this.playerService.release();
    this.currentUrl = '';
    this.playbackUrls = [];
    this.playbackUrlIndex = 0;
    this.videoMounted = false;
    this.surfaceReady = false;
    this.surfaceId = '';
    this.playbackStarting = false;
    this.playbackReady = false;
    this.playerError = '';
    this.showVertical = false;
    this.closeLandscapePlayback();
    return true;
  }

  private async tryNextPlaybackUrl(): Promise<boolean> {
    const nextIndex: number = this.playbackUrlIndex + 1;
    if (nextIndex >= this.playbackUrls.length) {
      return false;
    }
    await this.playerService.release();
    this.playbackUrlIndex = nextIndex;
    this.currentUrl = this.playbackUrls[nextIndex];
    this.playbackReady = false;
    this.playbackStarting = false;
    console.info(`Pilihos playback retry url ${nextIndex + 1}/${this.playbackUrls.length}`);
    return true;
  }

  private onNativeVideoPrepared(info: PreparedInfo): void {
    this.playbackDurationMs = Math.max(0, info.duration * 1000);
    this.playbackStarting = false;
    this.playbackReady = true;
    this.playbackPaused = false;
  }

  private onNativeVideoUpdate(info: PlaybackInfo): void {
    this.playbackCurrentMs = Math.max(0, info.time * 1000);
    if (!this.playbackFinished && this.playbackDurationMs > 0 &&
      this.playbackCurrentMs >= this.playbackDurationMs - 800) {
      this.markPlaybackFinished();
    }
  }

  private onNativeVideoError(error: BusinessError): void {
    const message: string = `${error.code} ${error.message}`;
    this.playbackReady = false;
    this.playbackStarting = false;
    this.videoMounted = false;
    this.playerError = '视频播放失败: ' + message;
    this.showPlaybackToast(this.playbackErrorToast(message));
    console.error(`Pilihos native Video error: ${message}`);
  }

  private onVideoSurfaceLoad(): void {
    this.surfaceId = this.surfaceController.getXComponentSurfaceId();
    this.surfaceReady = this.surfaceId !== '';
    if (this.surfaceReady && this.videoMounted && this.currentUrl !== '') {
      this.startNativePlayback();
    }
  }

  private async startNativePlayback(): Promise<void> {
    if (this.currentUrl === '' || !this.surfaceReady || this.surfaceId === '' || this.playbackStarting) {
      return;
    }
    const requestId: number = this.playbackRequest;
    this.playbackStarting = true;
    this.playbackReady = false;
    this.playerError = '';
    try {
      await this.playerService.prepare(this.currentUrl, this.surfaceId, this.playbackReferer(), this.playbackCookie());
      if (requestId !== this.playbackRequest || !this.showVertical || !this.videoMounted) return;
      await this.playerService.play();
      if (requestId === this.playbackRequest && this.showVertical) {
        this.playbackReady = true;
        this.playbackPaused = false;
        this.showPlaybackControls();
      }
    } catch (error) {
      if (requestId !== this.playbackRequest || !this.showVertical) return;
      if (await this.tryNextPlaybackUrl()) return;
      this.playbackReady = false;
      this.videoMounted = false;
      const errorText: string = String(error);
      this.playerError = '视频播放失败: ' + errorText;
      this.showPlaybackToast(this.playbackErrorToast(errorText));
      console.error(`Pilihos native playback failed: ${String(error)}`);
      this.playerService.release();
    } finally {
      if (requestId === this.playbackRequest) {
        this.playbackStarting = false;
      }
    }
  }

  private async handleNativePlaybackError(message: string): Promise<void> {
    if (!this.showVertical || this.currentUrl === '') return;
    if (await this.tryNextPlaybackUrl()) return;
    if (!this.showVertical || this.currentUrl === '') return;
    this.playbackReady = false;
    this.playbackStarting = false;
    this.videoMounted = false;
    this.playerError = '视频播放失败: ' + message;
    this.showPlaybackToast(this.playbackErrorToast(message));
    await this.playerService.release();
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

  private randomRecommendationIndex(): number {
    const candidates: number[] = [];
    this.videos.forEach((item: VideoItem, index: number): void => {
      // 推荐接口的部分条目只有 aid/cid，没有 bvid；只要是可识别的真实视频
      // 就可以进入结束推荐，详情页会按 aid/cid 重新解析播放地址。
      const hasVideoIdentity: boolean = item.aid > 0 || item.cid > 0 || item.bvid !== '' || item.playUrl !== '';
      if (!item.placeholder && index !== this.currentIndex && hasVideoIdentity) candidates.push(index);
    });
    if (candidates.length === 0) return -1;
    return candidates[Math.floor(Math.random() * candidates.length)];
  }

  private markPlaybackFinished(): void {
    if (this.playbackFinished || !this.showVertical) return;
    this.playbackFinished = true;
    this.playbackPaused = true;
    this.recommendedPlaybackIndex = this.randomRecommendationIndex();
    this.showPlaybackControls();
  }

  private replayFinishedVideo(): void {
    this.playbackFinished = false;
    this.prepareCurrentVideo();
  }

  private playRecommendedVideo(): void {
    if (this.recommendedPlaybackIndex < 0) return;
    this.currentIndex = this.recommendedPlaybackIndex;
    this.playbackFinished = false;
    this.openVideoDetail(this.videos[this.currentIndex]);
  }

  private shareCurrentVideo(): void {
    const item: VideoItem = this.videos[this.currentIndex];
    const uri: string = item.bvid !== '' ? `https://www.bilibili.com/video/${item.bvid}/` :
      `https://www.bilibili.com/video/av${item.aid}/`;
    const want: Want = { action: 'ohos.want.action.viewData', uri: uri };
    this.context.startAbility(want).catch((error: BusinessError): void => {
      console.error(`Pilihos share failed: ${error.code} ${error.message}`);
      this.showPlaybackToast('分享失败 [错误码: ' + String(error.code) + ']');
    });
  }

  private playbackErrorToast(errorMessage: string): string {
    const text: string = errorMessage.trim();
    const matched: RegExpMatchArray | null = text.match(/(?:code|错误码)\D*(-?\d+)/i);
    const leadingCode: RegExpMatchArray | null = text.match(/^(-?\d+)/);
    const code: string = matched !== null ? matched[1] :
      (leadingCode !== null ? leadingCode[1] : 'PLAYBACK_ERROR');
    const detail: string = text === '' ? '未知播放器错误' : text;
    return `视频播放/加载失败 [错误码: ${code}] ${detail}`;
  }

  private playbackCookie(): string {
    const session: AuthSession | null = this.authSession ?? AuthService.currentSession();
    return session === null ? '' : session.cookie;
  }

  private playbackReferer(): string {
    const item: VideoItem = this.videos[this.currentIndex];
    if (item.bvid !== '') return `https://www.bilibili.com/video/${item.bvid}/`;
    if (item.aid > 0) return `https://www.bilibili.com/video/av${item.aid}/`;
    return 'https://www.bilibili.com/';
  }

  private playbackUrlDescription(url: string): string {
    const queryIndex: number = url.indexOf('?');
    const withoutQuery: string = queryIndex >= 0 ? url.substring(0, queryIndex) : url;
    return withoutQuery.length > 180 ? withoutQuery.substring(0, 180) : withoutQuery;
  }

  private formatPlaybackTime(valueMs: number): string {
    const totalSeconds: number = Math.max(0, Math.floor(valueMs / 1000));
    const hours: number = Math.floor(totalSeconds / 3600);
    const minutes: number = Math.floor((totalSeconds % 3600) / 60);
    const seconds: number = totalSeconds % 60;
    const minuteText: string = String(minutes).padStart(2, '0');
    const secondText: string = String(seconds).padStart(2, '0');
    if (hours > 0) return String(hours).padStart(2, '0') + ':' + minuteText + ':' + secondText;
    return minuteText + ':' + secondText;
  }

  private async togglePlayback(): Promise<void> {
    if (this.currentUrl === '' || this.playbackStarting) return;
    try {
      if (this.playbackPaused) {
        this.nativeVideoController.start();
        this.playbackPaused = false;
        this.playbackReady = true;
      } else {
        this.nativeVideoController.pause();
        this.playbackPaused = true;
      }
      this.showPlaybackControls();
    } catch (error) {
      this.playerError = '播放控制失败: ' + String(error);
    }
  }

  private showPlaybackControls(): void {
    this.playbackControlsVisible = true;
    if (this.playbackControlsTimer !== 0) {
      clearTimeout(this.playbackControlsTimer);
    }
    this.playbackControlsTimer = setTimeout((): void => {
      if (!this.speedMenuVisible && !this.episodeListVisible) {
        this.playbackControlsVisible = false;
      }
      this.playbackControlsTimer = 0;
    }, 4000);
  }

  private seekPlayback(valueMs: number): void {
    const duration: number = Math.max(0, this.playbackDurationMs);
    const position: number = Math.max(0, Math.min(valueMs, duration > 0 ? duration : valueMs));
    this.playbackCurrentMs = position;
    this.nativeVideoController.setCurrentTime(position / 1000);
  }

  private selectPlaybackSpeed(speed: number): void {
    this.playbackSpeed = speed;
    this.speedMenuVisible = false;
    this.showPlaybackControls();
  }

  private toggleDanmaku(): void {
    this.danmakuEnabled = !this.danmakuEnabled;
    if (!this.danmakuEnabled) this.danmakuText = '';
  }

  @Builder
  commentEntry(item: VideoItem) {
    Row({ space: 3 }) {
      Text('\u8BC4\u8BBA ' + item.commentCount).fontSize(13).fontColor(Color.Grey);
      Text('\u2304').fontSize(22).fontColor(('sys.color.comp_focused_primary'));
    }
    .padding({ left: 8, right: 8, top: 5, bottom: 5 })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => { this.draggingDown = true; })
        .onActionEnd(() => { this.draggingDown = false; })
    )
    .gesture(
      PanGesture()
        .onActionUpdate((event: GestureEvent) => {
          if (this.draggingDown && event.offsetY > 72) this.openVertical();
        })
        .onActionEnd(() => { this.draggingDown = false; })
    );
  }

  @Builder
  homeCard(item: VideoItem) {
    Column({ space: 6 }) {
      Stack() {
        if (item.placeholder) {
          Row().width('100%').aspectRatio(1.62).backgroundColor('#E1E6EE');
        } else if (item.cover !== '') {
          Image(item.cover).width('100%').aspectRatio(1.62).objectFit(ImageFit.Cover);
        } else {
          Row().width('100%').aspectRatio(1.62).backgroundColor('#DCE3EF');
        }
      }
      .borderRadius(10)
      .clip(true)
      if (item.placeholder) {
        Row().width('82%').height(16).backgroundColor('#E1E6EE').borderRadius(4);
        Row().width('58%').height(16).backgroundColor('#E1E6EE').borderRadius(4);
      } else {
        Text(item.title).fontSize(14).maxLines(2).fontWeight(FontWeight.Medium).lineHeight(22);
      }
      Row() {
        if (item.placeholder) {
          Row().width('35%').height(12).backgroundColor('#E1E6EE').borderRadius(4).layoutWeight(1);
          Row().width('25%').height(12).backgroundColor('#E1E6EE').borderRadius(4);
        } else {
          Row({ space: 4 }) {
            Image($r('app.media.bfl')).width(14).height(14);
            Text(this.formatCount(item.viewCount)).fontSize(11).fontColor('#8B9199');
          }.layoutWeight(1);
          Row({ space: 4 }) {
            Image($r('app.media.dm')).width(14).height(14);
            Text(this.formatCount(item.danmuCount)).fontSize(11).fontColor('#8B9199');
          }
        }
      }.width('100%');
      Row() {
        if (item.placeholder) {
          Row().width('45%').height(12).backgroundColor('#E1E6EE').borderRadius(4);
        } else if (item.followed) {
          Text('\u5DF2\u5173\u6CE8').fontSize(10).fontColor('#1677A8').backgroundColor('#E5F3FA')
            .padding({ left: 5, right: 5, top: 2, bottom: 2 }).borderRadius(4).margin({ right: 4 });
        }
        if (!item.placeholder) {
          Text(`@${item.author}`).fontSize(11).fontColor('#8B9199').layoutWeight(1);
          Text(this.formatPublishTime(item.publishTime)).fontSize(11).fontColor('#8B9199');
        }
      }.width('100%');
    }
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor(Color.White)
    .borderRadius(12)
    .height(this.compactGrid ? 320 : 210)
    .onClick(() => {
      if (item.placeholder) {
        return;
      }
      const index: number = this.videos.indexOf(item);
      if (index >= 0) {
        this.currentIndex = index;
        this.showVertical = true;
        this.detailExpanded = false;
        this.detailError = '';
        this.surfaceReady = false;
        this.surfaceId = '';
        this.playbackStarting = false;
        this.playbackReady = false;
        this.loadVideoDetail();
        this.prepareCurrentVideo();
      }
    });
  }

  @Builder
  loadingIndicator(label: string, color: string) {
    Row({ space: 8 }) {
      LoadingProgress().width(26).height(26).color(color);
      Text(label).fontSize(14).fontColor(color).textAlign(TextAlign.Center);
    }
    .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center);
  }

  @Builder
  verticalPlayer() {
    Stack() {
      if (this.currentUrl !== '') {
        Video({ src: this.currentUrl }).width('100%').height('100%').objectFit(ImageFit.Contain).controls(true).autoPlay(false)
          .onError((): void => {
            this.playerError = '\u89C6\u9891\u64AD\u653E\u5931\u8D25\uFF0C\u8BF7\u91CD\u8BD5';
            this.currentUrl = '';
            this.videoMounted = false;
          });
      } else {
        Column({ space: 12 }) {
            if (this.playerError === '') {
              this.loadingIndicator('\u6B63\u5728\u52A0\u8F7D\u89C6\u9891...', '#FFFFFF');
            } else {
              Text(this.playerError).fontColor(Color.White).fontSize(15).textAlign(TextAlign.Center);
            }
            Button() {
              Image($r('app.media.bofang')).width(56).height(56).fillColor(Color.White);
            }
            .type(ButtonType.ROUNDED_RECTANGLE).width(76).height(76)
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.prepareCurrentVideo(); });
        }.justifyContent(FlexAlign.Center).width('100%').height('100%');
      }
      Column() {
        Text('\u89C6\u9891 ' + (this.currentIndex + 1) + '/' + this.videos.length).fontColor(Color.White).fontSize(16);
        Text(this.videos[this.currentIndex].title).fontColor(Color.White).fontSize(17).maxLines(2).margin({ top: 8 });
      }.position({ left: 18, right: 60, bottom: 32 });
      Button('\u8FD4\u56DE').position({ left: 16, top: 20 }).onClick(() => {
        this.playerService.release();
        this.currentUrl = '';
        this.videoMounted = false;
        this.showVertical = false;
      });
      Text('向上滑动切换视频').fontColor(Color.White).fontSize(13).position({ bottom: 30, right: 18 });
    }
    .width('100%').height('100%').backgroundColor(Color.Black)
    .gesture(SwipeGesture({ fingers: 1, direction: SwipeDirection.Vertical })
      .onAction(() => {
        this.playerService.pause();
        this.currentIndex = (this.currentIndex + 1) % this.videos.length;
        this.currentUrl = '';
        this.prepareCurrentVideo();
      }));
  }

  @Builder
  detailAction(label: string, iconName: string) {
    Column({ space: 3 }) {
      if (iconName === 'dianzan') {
        Image($r('app.media.dianzan')).width(24).height(24);
      } else if (iconName === 'diancai') {
        Image($r('app.media.diancai')).width(24).height(24);
      } else if (iconName === 'toubi') {
        Image($r('app.media.toubi')).width(24).height(24);
      } else if (iconName === 'favorites') {
        Image($r('app.media.favorites')).width(24).height(24);
      } else if (iconName === 'watch_later') {
        Image($r('app.media.watch_later')).width(24).height(24);
      } else {
        Image($r('app.media.share')).width(24).height(24);
      }
      Text(label).fontSize(12).fontColor('#3E4854');
    }.layoutWeight(1).alignItems(HorizontalAlign.Center);
  }

  @Builder
  playbackTool(iconName: string, label: string, action: () => void) {
    Column() {
      if (iconName === 'list') {
        Image($r('app.media.list')).width(24).height(24).fillColor(Color.White);
      } else if (iconName === 'speed') {
        Image($r('app.media.speed')).width(24).height(24).fillColor(Color.White);
      } else if (iconName === 'zm') {
        Image($r('app.media.zm')).width(24).height(24).fillColor(Color.White)
          .opacity(this.subtitlesEnabled ? 1 : 0.55);
      } else {
        Image($r('app.media.qp')).width(24).height(24).fillColor(Color.White);
      }
    }.width(42).height(42).justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(action)
      .bindMenu(iconName === 'speed' && this.speedMenuVisible, this.speedMenu(), {
        placement: Placement.Bottom,
        enableArrow: true,
        showInSubWindow: true
      });
  }

  @Builder
  speedMenu() {
    Column({ space: 2 }) {
      Text('倍速').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#20252B')
        .width('100%').height(30).textAlign(TextAlign.Center);
      ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], (speed: number) => {
        Text(speed === 1.0 ? '1.0x（原速度）' : speed.toFixed(2) + 'x').fontSize(12)
          .fontColor(speed === this.playbackSpeed ? '#1677A8' : '#1E252D')
          .fontWeight(speed === this.playbackSpeed ? FontWeight.Bold : FontWeight.Normal)
          .width('100%').height(28).textAlign(TextAlign.Center)
          .onClick(() => { this.selectPlaybackSpeed(speed); });
      }, (speed: number) => `${speed}`);
    }.width(112).padding({ top: 8, bottom: 8 }).backgroundColor('#F7F8FA')
      .borderRadius(10).shadow({ radius: 10, color: '#33000000', offsetX: 0, offsetY: 3 });
  }

  @Builder
  playbackInlineButton() {
    Button() {
      if (this.playbackPaused) {
        Image($r('app.media.bofang')).width(30).height(30).fillColor(Color.White);
      } else {
        Image($r('app.media.stop')).width(30).height(30).fillColor(Color.White);
      }
    }
    .type(ButtonType.ROUNDED_RECTANGLE).width(42).height(32)
    .backgroundColor(Color.Transparent)
    .onClick(() => { this.togglePlayback(); });
  }

  @Builder
  playbackControls() {
    if (this.playbackControlsVisible) {
    Stack() {
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          Text(this.formatPlaybackTime(this.playbackCurrentMs)).fontSize(11).fontColor(Color.White);
          Slider({
            value: this.playbackCurrentMs,
            min: 0,
            max: Math.max(1000, this.playbackDurationMs),
            step: 1000
          })
            .layoutWeight(1).height(24)
            .blockColor('#FFFFFF').selectedColor('#F04B55').trackColor('#66FFFFFF')
            .onChange((value: number): void => { this.seekPlayback(value); });
          Text(this.formatPlaybackTime(this.playbackDurationMs)).fontSize(11).fontColor(Color.White);
        }.width('100%').height(24).alignItems(VerticalAlign.Center);
        Row() {
          this.playbackInlineButton();
          this.playbackTool('list', '选集', () => {
            this.episodeListVisible = !this.episodeListVisible;
            this.speedMenuVisible = false;
            this.showPlaybackControls();
          });
          this.playbackTool('speed', '', () => {
            this.speedMenuVisible = !this.speedMenuVisible;
            this.episodeListVisible = false;
            this.showPlaybackControls();
          });
          this.playbackTool('zm', '', () => {
            this.subtitlesEnabled = !this.subtitlesEnabled;
            this.showPlaybackControls();
          });
          this.playbackTool('qp', '', () => {
            this.openLandscapePlayback();
            this.showPlaybackControls();
          });
        }.width('100%').justifyContent(FlexAlign.SpaceBetween).padding({ left: 4, right: 14 });
      }.width('100%').padding({ left: 10, right: 10, top: 8, bottom: 2 });
    }.width('100%').height(78).alignContent(Alignment.Bottom)
      .position({ left: 0, right: 0, bottom: 0 }).zIndex(3)
      .transition({ type: TransitionType.Insert, translate: { y: 78 }, opacity: 0 })
      .animation({ duration: 260, curve: Curve.EaseOut });
    }
  }

  @Builder
  playbackFinishedOverlay() {
    if (this.playbackFinished && this.recommendedPlaybackIndex >= 0) {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Image(this.videos[this.recommendedPlaybackIndex].cover).width(92).height(52)
            .objectFit(ImageFit.Cover).borderRadius(4);
          Text(this.videos[this.recommendedPlaybackIndex].title).fontSize(12)
            .fontColor(Color.White).maxLines(2).layoutWeight(1);
        }.width('100%');
        Row({ space: 16 }) {
          Column() {
            Image($r('app.media.cb')).width(23).height(23).fillColor(Color.White);
            Text('重播').fontSize(10).fontColor(Color.White);
          }.onClick(() => { this.replayFinishedVideo(); });
          Column() {
            Image($r('app.media.bofang')).width(23).height(23).fillColor(Color.White);
            Text('立即播放').fontSize(10).fontColor(Color.White);
          }.onClick(() => { this.playRecommendedVideo(); });
          Column() {
            Image($r('app.media.share')).width(23).height(23).fillColor(Color.White);
            Text('分享').fontSize(10).fontColor(Color.White);
          }.onClick(() => { this.shareCurrentVideo(); });
        }.width('100%').justifyContent(FlexAlign.End);
      }.width(250).padding(8).backgroundColor('#CC111111').borderRadius(8)
        .position({ right: 8, bottom: 8 }).zIndex(6);
    }
  }

  @Builder
  landscapePlayer() {
    Stack() {
      if (this.currentUrl !== '') {
        Video({ src: this.currentUrl, controller: this.nativeVideoController,
          currentProgressRate: this.playbackSpeed })
          .width('100%').height('100%').objectFit(ImageFit.Contain).controls(false).autoPlay(true)
          .onPrepared((info: PreparedInfo): void => { this.onNativeVideoPrepared(info); })
          .onStart((): void => { this.playbackPaused = false; this.playbackReady = true; })
          .onPause((): void => { this.playbackPaused = true; })
          .onUpdate((info: PlaybackInfo): void => { this.onNativeVideoUpdate(info); })
          .onFinish((): void => { this.markPlaybackFinished(); })
          .onError((error: BusinessError): void => { this.onNativeVideoError(error); });
      } else {
        Column({ space: 12 }) {
            if (this.playerError === '') {
              this.loadingIndicator('\u6B63\u5728\u83B7\u53D6\u89C6\u9891\u64AD\u653E\u5730\u5740...', '#FFFFFF');
            } else {
              Text(this.playerError).fontColor(Color.White).fontSize(15).textAlign(TextAlign.Center);
            }
          if (this.playerError !== '') {
            Button() {
              Image($r('app.media.bofang')).width(56).height(56).fillColor(Color.White);
            }
            .type(ButtonType.ROUNDED_RECTANGLE).width(76).height(76)
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.prepareCurrentVideo(); });
          }
        }.justifyContent(FlexAlign.Center).width('100%').height('100%');
      }
      if (this.currentUrl !== '' && this.playbackControlsVisible) {
        Column() {
          this.playbackControls();
        }.width('100%').height(78).position({ left: 0, right: 0, bottom: 0 }).zIndex(3);
      }
      this.playbackFinishedOverlay();
      Button() {
        Image($r('app.media.fanhui_left')).width(24).height(24);
      }
      .type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
      .backgroundColor('#66000000').borderRadius(22)
      .position({ left: 16, top: 16 })
      .visibility(this.playbackControlsVisible ? Visibility.Visible : Visibility.None)
      .onClick(() => { this.onBackPress(); });
    }
    .width('100%').height('100%').backgroundColor(Color.Black);
  }

  @Builder
  detailPage() {
    Column() {
      Stack() {
        if (this.currentUrl === '' && this.videos[this.currentIndex].cover !== '') {
          Image(this.videos[this.currentIndex].cover)
            .width('100%').height('100%').objectFit(ImageFit.Cover);
        }
        if (this.currentUrl !== '') {
          Video({ src: this.currentUrl, controller: this.nativeVideoController,
            currentProgressRate: this.playbackSpeed })
            .width('100%').height('100%').objectFit(ImageFit.Contain).controls(false).autoPlay(true)
            .onPrepared((info: PreparedInfo): void => { this.onNativeVideoPrepared(info); })
            .onStart((): void => { this.playbackPaused = false; this.playbackReady = true; })
            .onPause((): void => { this.playbackPaused = true; })
            .onUpdate((info: PlaybackInfo): void => { this.onNativeVideoUpdate(info); })
            .onFinish((): void => { this.markPlaybackFinished(); })
            .onError((error: BusinessError): void => { this.onNativeVideoError(error); });
          if (!this.videoMounted) {
            Image(this.videos[this.currentIndex].cover)
              .width('100%').height('100%').objectFit(ImageFit.Cover);
            Button() {
              Image($r('app.media.bofang')).width(56).height(56).fillColor(Color.White);
            }
            .type(ButtonType.ROUNDED_RECTANGLE).width(76).height(76)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.prepareCurrentVideo();
            });
          } else if (this.playbackStarting) {
            Row() {
              this.loadingIndicator('\u6B63\u5728\u51C6\u5907\u89C6\u9891...', '#FFFFFF');
            }
            .backgroundColor('#99000000').padding(8);
          }
        } else {
          Column({ space: 12 }) {
            if (this.playerError === '') {
              this.loadingIndicator('\u6B63\u5728\u83B7\u53D6\u89C6\u9891\u64AD\u653E\u5730\u5740...', '#FFFFFF');
            } else {
              Text(this.playerError).fontColor(Color.White).fontSize(14).textAlign(TextAlign.Center)
                .backgroundColor('#99000000').padding(8);
            }
            if (this.playerError !== '') {
              Button() {
                Image($r('app.media.bofang')).width(56).height(56).fillColor(Color.White);
              }
              .type(ButtonType.ROUNDED_RECTANGLE).width(76).height(76)
              .backgroundColor(Color.Transparent)
              .onClick(() => { this.prepareCurrentVideo(); });
            }
          }.justifyContent(FlexAlign.Center).width('100%').height('100%');
        }
        this.playbackFinishedOverlay();
        Button() {
          Image($r('app.media.left_syb')).width(24).height(24);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(42).height(42)
        .backgroundColor(Color.Transparent)
      .position({ left: 10, top: 10 })
        .visibility(this.playbackControlsVisible ? Visibility.Visible : Visibility.None)
        .onClick(() => { this.onBackPress(); });
        if (this.currentUrl !== '') {
          this.playbackControls();
        }
      }.width('100%').aspectRatio(16 / 9).backgroundColor(Color.Black)
        .onClick((): void => { this.showPlaybackControls(); });

      Row() {
        Row({ space: 12 }) {
          Text('\u7B80\u4ECB').fontSize(15)
            .fontColor(this.detailSection === 0 ? '#1677A8' : '#59616B')
            .fontWeight(this.detailSection === 0 ? FontWeight.Bold : FontWeight.Normal)
            .onClick(() => { this.detailSection = 0; });
          Text('\u8BC4\u8BBA ' + this.formatCount(this.commentTotal > 0
            ? this.commentTotal : this.videos[this.currentIndex].commentCount)).fontSize(15)
            .fontColor(this.detailSection === 1 ? '#1677A8' : '#59616B')
            .fontWeight(this.detailSection === 1 ? FontWeight.Bold : FontWeight.Normal)
            .onClick(() => { this.detailSection = 1; this.loadComments(true); });
        }
        .layoutWeight(1)
        .padding({ left: 16 })
        .alignItems(VerticalAlign.Center);
        Button() {
          Image($r('app.media.down')).width(18).height(18);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(40).height(40)
        .backgroundColor(Color.Transparent)
        .borderRadius(20)
        .onClick(() => { this.openLandscapePlayback(); });
        Row() {
          TextInput({ placeholder: '\u53D1\u4E00\u6761\u5F39\u5E55', text: this.danmakuText })
            .width(122).height(36).fontSize(12).fontColor('#858C94')
            .backgroundColor('#F1F3F5').borderRadius(18)
            .padding({ left: 10, right: 10 })
            .enabled(this.danmakuEnabled)
            .onChange((value: string) => { this.danmakuText = value; });
          Button() {
            Image($r('app.media.dmg')).width(20).height(20)
              .opacity(this.danmakuEnabled ? 1 : 0.38);
          }.type(ButtonType.Capsule).width(36).height(36)
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.toggleDanmaku(); });
        }
        .layoutWeight(1)
        .padding({ right: 8 })
        .justifyContent(FlexAlign.End)
        .alignItems(VerticalAlign.Center);
      }.width('100%').height(64).backgroundColor(Color.White)
        .border({ width: { bottom: 1 }, color: '#E5E8EC' });      Scroll() {
        Column({ space: 14 }) {
          if (this.detailSection === 1) {
            this.commentPanel();
          } else {
          Row({ space: 12 }) {
            if ((this.videos[this.currentIndex].authorFace ?? '') !== '') {
              Image(this.videos[this.currentIndex].authorFace ?? '')
                .width(52).height(52).borderRadius(26).objectFit(ImageFit.Cover);
            } else {
              Image($r('app.media.user_me')).width(52).height(52).borderRadius(26).objectFit(ImageFit.Contain);
            }
            Column({ space: 4 }) {
              Text(`@${this.videos[this.currentIndex].author}`).fontSize(17);
              Text('\u7C89\u4E1D\u6570  \u89C6\u9891\u6570').fontSize(12).fontColor('#858C94');
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            Button(this.videos[this.currentIndex].followed ? '\u5DF2\u5173\u6CE8' : '\u5173\u6CE8').fontSize(13).height(36);
          }.width('100%').height(64);
          Row({ space: 8 }) {
            Text(this.videos[this.currentIndex].title).fontSize(19)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1);
            Button() {
              Image($r('app.media.down')).width(17).height(17);
            }
            .type(ButtonType.ROUNDED_RECTANGLE).width(32).height(32)
            .backgroundColor(Color.Transparent).borderRadius(16)
            .onClick(() => { this.detailExpanded = !this.detailExpanded; });
          }.width('100%').alignItems(VerticalAlign.Center);

          if (this.detailExpanded) {
            Column({ space: 8 }) {
              Text(this.videos[this.currentIndex].title)
                .fontSize(18).fontWeight(FontWeight.Medium).lineHeight(25)
                .width('100%');
              if (this.detailLoading) {
                this.loadingIndicator('\u6B63\u5728\u52A0\u8F7D\u89C6\u9891\u8BE6\u60C5...', '#59616B');
              } else {
                Text(this.detailError !== '' ? this.detailError :
                  (this.videos[this.currentIndex].description === ''
                    ? '\u6682\u65E0\u7B80\u4ECB' : this.videos[this.currentIndex].description))
                  .fontSize(14).fontColor('#59616B').lineHeight(21)
                  .width('100%');
              }
              Text('BV号: ' + (this.videos[this.currentIndex].bvid === ''
                ? '\u6682\u65E0' : this.videos[this.currentIndex].bvid))
                .fontSize(13).fontColor('#858C94').width('100%');
              Text('\u6807\u7B7E ' + (this.videos[this.currentIndex].tags.length === 0
                ? '\u6682\u65E0' : this.videos[this.currentIndex].tags.join(' \u00B7 ')))
                .fontSize(13).fontColor('#858C94').lineHeight(20)
                .width('100%');
            }.width('100%').padding({ top: 2, bottom: 4 })
              .backgroundColor('#F7F8FA').borderRadius(8)
              .padding({ left: 10, right: 10, top: 8, bottom: 8 });
          }
          Row({ space: 18 }) {
            Row({ space: 4 }) {
              Image($r('app.media.bfl')).width(16).height(16);
              Text(this.formatCount(this.videos[this.currentIndex].viewCount))
                .fontSize(13).fontColor('#858C94');
            }
            Row({ space: 4 }) {
              Image($r('app.media.dm')).width(16).height(16);
              Text(this.formatCount(this.videos[this.currentIndex].danmuCount))
                .fontSize(13).fontColor('#858C94');
            }
            Text('\u53D1\u5E03\u4E8E ' + this.formatPublishDate(this.videos[this.currentIndex].publishTime))
              .fontSize(13).fontColor('#858C94');
          }.width('100%').height(28)
            .justifyContent(FlexAlign.Start)
            .alignItems(VerticalAlign.Center);
          Row() {
            this.detailAction('\u70B9\u8D5E', 'dianzan');
            this.detailAction('\u70B9\u8E29', 'diancai');
            this.detailAction('\u6295\u5E01', 'toubi');
            this.detailAction('收藏', 'favorites');
            this.detailAction('\u518D\u770B', 'watch_later');
            this.detailAction('\u5206\u4EAB', 'share');
          }.width('100%').height(64).padding({ top: 12, bottom: 12 })
            .border({ width: { bottom: 1 }, color: '#E5E8EC' });
          ForEach(this.videos, (item: VideoItem) => {
            if (!item.placeholder) {
              Row({ space: 10 }) {
                Image(item.cover).width(132).height(76).borderRadius(8);
                Column({ space: 5 }) {
                  Text(item.title).fontSize(14).maxLines(2).lineHeight(20);
                  Row({ space: 8 }) {
                    Row({ space: 3 }) {
                      Image($r('app.media.bfl')).width(13).height(13);
                      Text(this.formatCount(item.viewCount)).fontSize(11).fontColor('#858C94');
                    }
                    Row({ space: 3 }) {
                      Image($r('app.media.dm')).width(13).height(13);
                      Text(this.formatCount(item.danmuCount)).fontSize(11).fontColor('#858C94');
                    }
                    Text(this.formatPublishTime(item.publishTime))
                      .fontSize(11).fontColor('#858C94').layoutWeight(1);
                  }.width('100%');
                  Text(`@${item.author}`).fontSize(11).fontColor('#858C94');
                }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              }.width('100%').onClick(() => {
                this.openVideoDetail(item, this.detailSection === 1);
              });
            }
          }, (item: VideoItem) => `related_${item.id}`);
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 14, bottom: this.bottomInset + 30 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off).backgroundColor(Color.White);
    }
    .width('100%').height('100%')
    .padding({ top: this.topInset })
    .backgroundColor(Color.Black)
    .bindSheet($$this.episodeListVisible, this.episodeSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true
    });
  }

  @Builder
  episodeSheet() {
    Column() {
      Text(this.videos[this.currentIndex].duration > 0 ? '暂无更多选集' : '当前视频无合集')
        .fontSize(14).fontColor('#30363D').width('100%').textAlign(TextAlign.Center)
        .padding({ top: 18, bottom: 24 });
    }.width('100%').padding({ bottom: this.bottomInset + 8 })
      .backgroundColor('#F7F8FA');
  }

  @Builder
  commentPanel() {
    Column({ space: 12 }) {
      Row() {
        Text('评论 ' + this.formatCount(this.commentTotal > 0
          ? this.commentTotal : this.videos[this.currentIndex].commentCount))
          .fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1);
        Text('按热度').fontSize(13).fontColor('#858C94');
      }.width('100%').padding({ top: 4, bottom: 6 });
      if (this.commentLoading && this.comments.length === 0) {
        this.loadingIndicator('正在加载评论', '#1677A8');
      } else if (this.commentError !== '' && this.comments.length === 0) {
        Column({ space: 10 }) {
          Text(this.commentError).fontSize(14).fontColor('#858C94');
          Button('重新加载').height(36).onClick(() => { this.loadComments(true); });
        }.width('100%').alignItems(HorizontalAlign.Center).padding({ top: 30, bottom: 30 });
      } else if (this.comments.length === 0) {
        Text('还没有评论').fontSize(14).fontColor('#858C94').width('100%')
          .textAlign(TextAlign.Center).padding({ top: 30, bottom: 30 });
      } else {
        ForEach(this.comments, (comment: VideoComment) => {
          this.commentItem(comment);
        }, (comment: VideoComment) => `comment_${comment.id}`);
        if (this.commentHasMore) {
          Button(this.commentLoading ? '正在加载' : '加载更多评论').height(38)
            .width('100%').backgroundColor('#F1F3F5').fontColor('#59616B')
            .onClick(() => { this.loadComments(false); });
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  @Builder
  commentItem(comment: VideoComment) {
    Row({ space: 10 }) {
      if (comment.avatar !== '') {
        Image(comment.avatar).width(38).height(38).borderRadius(19).objectFit(ImageFit.Cover);
      } else {
        Row().width(38).height(38).borderRadius(19).backgroundColor('#DCE3EF');
      }
      Column({ space: 5 }) {
        Row() {
          Text(comment.userName).fontSize(13).fontColor('#59616B').fontWeight(FontWeight.Medium)
            .layoutWeight(1);
          if (comment.isUp) {
            Text('UP主').fontSize(10).fontColor('#1677A8').backgroundColor('#E5F3FA')
              .borderRadius(4).padding({ left: 4, right: 4, top: 2, bottom: 2 });
          }
        }.width('100%');
        Text(comment.message).fontSize(15).fontColor('#1E252D').lineHeight(22).width('100%');
        Row({ space: 14 }) {
          Text(this.formatPublishTime(comment.publishTime)).fontSize(11).fontColor('#A0A6AD');
          Row({ space: 3 }) {
            Image($r('app.media.dianzan')).width(14).height(14);
            Text(this.formatCount(comment.likeCount)).fontSize(11).fontColor('#858C94');
          }
          Row({ space: 3 }) {
            Image($r('app.media.pl')).width(14).height(14);
            Text(this.formatCount(comment.replyCount)).fontSize(11).fontColor('#858C94');
          }
        }.width('100%');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }.width('100%').padding({ top: 10, bottom: 10 })
      .border({ width: { bottom: 1 }, color: '#E9EDF0' });
  }

  @Builder
  topBubbleButton(label: string, tabIndex: number, width: number, action: () => void) {
    Row() {
      Text(label)
        .fontSize(this.selectedTopTab === tabIndex ? 15 : 14)
        .fontColor(this.selectedTopTab === tabIndex ? Color.Black : '#3E4854')
        .fontWeight(this.selectedTopTab === tabIndex ? FontWeight.Bold : FontWeight.Normal)
    }
      .justifyContent(FlexAlign.Center)
      .width(width)
      .height(40)
      .backgroundColor(this.topTabsMerged ? Color.Transparent : ImmersiveMaterial.fallbackBackground(0.72))
      .borderRadius(20)
      .shadow({ radius: this.topTabsMerged ? 0 : 5, color: '#22000000', offsetX: 0, offsetY: 2 })
      .onClick(action);
  }

  @Builder
  topTabs() {
    if (this.topTabsMerged) {
      Row({ space: 2 }) {
        this.topBubbleButton('\u76F4\u64AD', 0, 62, () => { this.selectContentTab(0); });
        this.topBubbleButton('\u63A8\u8350', 1, 66, () => { this.selectContentTab(1); });
        this.topBubbleButton('\u70ED\u95E8', 2, 62, () => { this.selectContentTab(2); });
      }.height(48).padding({ left: 4, right: 4 })
        .backgroundColor(ImmersiveMaterial.fallbackBackground(0.72))
        .borderRadius(24).systemMaterial(ImmersiveMaterial.thin())
        .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 });
    } else {
      Row({ space: 8 }) {
        this.topBubbleButton('\u76F4\u64AD', 0, 62, () => { this.selectContentTab(0); });
        this.topBubbleButton('\u63A8\u8350', 1, 66, () => { this.selectContentTab(1); });
        this.topBubbleButton('\u70ED\u95E8', 2, 62, () => { this.selectContentTab(2); });
      }.height(48);
    }
  }

  @Builder
  topCircleButton(label: string, action: () => void) {
    Button() {
      if (this.authSession !== null && this.authSession.face !== '') {
        Image(this.authSession.face).width(36).height(36).borderRadius(18).objectFit(ImageFit.Cover);
      } else {
        Image($r('app.media.user_me')).width(34).height(34).objectFit(ImageFit.Contain);
      }
    }
      .type(ButtonType.ROUNDED_RECTANGLE)
      .controlSize(ControlSize.NORMAL)
      .width(48)
      .height(48)
               .backgroundColor(ImmersiveMaterial.fallbackBackground(0.72))
      .padding(0)
      .borderRadius(24)
      .systemMaterial(ImmersiveMaterial.thin())
      .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
      .onClick(action);
  }

  @Builder
  mineCoverImage() {
    if (this.mineCoverUri === '') {
      Image($r('app.media.bottom')).width('100%').height(150)
        .objectFit(ImageFit.Cover).borderRadius(14).clip(true);
    } else {
      Image(this.mineCoverUri).width('100%').height(150)
        .objectFit(ImageFit.Cover).borderRadius(14).clip(true);
    }
  }

  @Builder
  mineCoverSheet() {
    Column({ space: 14 }) {
      Text('编辑内容').fontSize(18).fontWeight(FontWeight.Bold);
      Button('更换图片')
        .type(ButtonType.ROUNDED_RECTANGLE)
        .width('100%').height(40).fontSize(16)
        .backgroundColor('#F1F3F5').fontColor('#1E252D')
        .onClick(() => { this.chooseMineCover(); });
    }
    .width('100%').padding({ left: 24, right: 24, top: 20, bottom: this.bottomInset + 15 });
  }

  @Builder
  mineSidebar() {
    Column({ space: 14 }) {
      Stack() {
        this.mineCoverImage();
        Button() {
          Image($r('app.media.jinxin_right')).width(22).height(22);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
        .backgroundColor(ImmersiveMaterial.fallbackBackground())
        .systemMaterial(ImmersiveMaterial.thin())
        .borderRadius(22)
        .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
        .position({ top: 12, right: 12 })
        .zIndex(2)
        .onClick(() => { this.sidebar = 0; });
      }
      .width('100%').height(150)
      .onClick(() => { this.showMineCoverSheet = true; });

      Row({ space: 14 }) {
        if (this.authSession !== null && this.authSession.face !== '') {
          Image(this.authSession.face).width(88).height(88).borderRadius(44).objectFit(ImageFit.Cover);
        } else {
          Image($r('app.media.user_me')).width(88).height(88).borderRadius(44).objectFit(ImageFit.Contain);
        }
        Column({ space: 5 }) {
          Row({ space: 6 }) {
            Text(this.authSession === null ? 'Pilihos \u7528\u6237' : this.authSession.name)
              .fontSize(18).fontWeight(FontWeight.Bold).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Text('LV' + (this.authSession === null ? '0' : String(this.authSession.level)))
              .margin({ left: 6 })
              .fontSize(11).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
              .backgroundColor('#F08A24').borderRadius(5)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 });
          }.width('100%');
          Text(this.authSession === null ? '\u767B\u5F55\u540E\u540C\u6B65\u4E2A\u4EBA\u7B7E\u540D' :
            (this.authSession.sign === '' ? '这个人很懒，什么都没有留下' : this.authSession.sign))
            .fontSize(13).fontColor('#858C94').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
          Text(this.authSession === null ? 'UID -- \u00B7 IP\u5C5E\u5730 --' :
            ('UID ' + this.authSession.uid + ' \u00B7 IP\u5C5E\u5730 ' +
              (this.authSession.ipLocation === '' ? '\u672A\u77E5' : this.authSession.ipLocation)))
            .fontSize(12).fontColor('#858C94').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          .margin({ top: 22 });
      }.width('100%').height(92)
        .margin({ top: -36 })
        .alignItems(VerticalAlign.Top)
        .onClick(() => {
        this.loginVisible = true;
        this.sidebar = 0;
        this.loginNotice = '';
      });

      Row({ space: 8 }) {
        this.mineStat(this.authSession === null ? '0' : this.formatCount(this.authSession.dynamicCount), '\u52A8\u6001');
        this.mineStat(this.authSession === null ? '0' : this.formatCount(this.authSession.followingCount), '\u5173\u6CE8');
        this.mineStat(this.authSession === null ? '0' : this.formatCount(this.authSession.followerCount), '\u7C89\u4E1D');
      }.width('100%');

      Grid() {
        GridItem() { this.mineGridAction('offline_cache', '离线缓存', true); }
        GridItem() { this.mineGridAction('bofang', '观看记录', true); }
        GridItem() { this.mineGridAction('subscriptions', '我的订阅', true); }
        GridItem() { this.mineGridAction('watch_later', '稍后再看', true); }
        GridItem() { this.mineGridAction('favorites', '我的收藏', true); }
        GridItem() { this.mineGridAction('software_settings', '软件设置', true); }
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      .layoutWeight(1);
    }
    .width('100%').height('100%')
    .padding({ top: this.topInset + 12, left: 18, right: 18, bottom: this.bottomInset + 20 })
    .backgroundColor('#F7F8FA')
    .alignItems(HorizontalAlign.Start)
    .bindSheet($$this.showMineCoverSheet, this.mineCoverSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true
    });
  }
  @Builder
  mineStat(value: string, label: string) {
    Column({ space: 4 }) {
      Text(value).fontSize(22).fontWeight(FontWeight.Bold);
      Text(label).fontSize(13).fontColor('#858C94');
    }.layoutWeight(1);
  }

  @Builder
  mineGridAction(iconName: string, label: string, showArrow: boolean) {
    Stack() {
      Column({ space: 8 }) {
        if (iconName === 'offline_cache') {
          Image($r('app.media.offline_cache')).width(24).height(24);
        } else if (iconName === 'bofang') {
          Image($r('app.media.bofang')).width(24).height(24);
        } else if (iconName === 'subscriptions') {
          Image($r('app.media.subscriptions')).width(24).height(24);
        } else if (iconName === 'watch_later') {
          Image($r('app.media.watch_later')).width(24).height(24);
        } else if (iconName === 'favorites') {
          Image($r('app.media.favorites')).width(24).height(24);
        } else {
          Image($r('app.media.software_settings')).width(24).height(24);
        }
        Text(label).fontSize(13).fontColor('#3E4854').textAlign(TextAlign.Center);
      }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center);
      if (showArrow) {
        Image($r('app.media.jinxin_right')).width(16).height(16)
          .position({ right: 10, bottom: 10 });
      }
    }
    .width('100%').aspectRatio(1)
    .backgroundColor(ImmersiveMaterial.fallbackBackground())
    .borderRadius(12)
    .systemMaterial(ImmersiveMaterial.thin())
    .shadow({ radius: 6, color: '#18000000', offsetX: 0, offsetY: 2 })
    .onClick(() => {
      if (iconName === 'software_settings') {
        this.openSoftwareSettings();
      }
    });
  }

  @Builder
  messageSidebar() {
    Column({ space: 18 }) {
      Row() {
        Button() {
          Image($r('app.media.fanhui_left')).width(24).height(24);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(42).height(42)
        .backgroundColor(ImmersiveMaterial.fallbackBackground())
        .systemMaterial(ImmersiveMaterial.thin())
        .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
        .onClick(() => { this.sidebar = 0; });
        Text('\u6D88\u606F').fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.Black).layoutWeight(1);
        Text('\u6E05\u7A7A').fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.Black);
      }.width('100%').alignItems(VerticalAlign.Center);
      Row({ space: 8 }) {
        this.messageBubble('回复我的', '3', 'message_reply');
        this.messageBubble('@\u6211', '', 'at_me');
        this.messageBubble('\u6536\u5230\u7684\u8D5E', '12', 'received_likes');
        this.messageBubble('系统通知', '', 'xiaoxi');
      }.width('100%');
      Column({ space: 0 }) {
        this.messageRow('\u793E\u533A\u4E2D\u5FC3', '\u4E3E\u62A5\u8FDB\u5C55\u53CD\u9988', '08-17', 'message_reply');
        this.messageRow('\u7279\u522B\u5173\u6CE8', '\u65B0\u7684\u5173\u6CE8\u52A8\u6001\u5C06\u5728\u8FD9\u91CC\u663E\u793A', '08-21', 'at_me');
        this.messageRow('\u7CFB\u7EDF\u901A\u77E5', '\u6B22\u8FCE\u4F7F\u7528 Pilihos', '\u4ECA\u5929', 'xiaoxi');
        this.messageRow('\u4E92\u52A8\u6D88\u606F', '\u8BC4\u8BBA\u3001\u70B9\u8D5E\u548C\u56DE\u590D\u5C06\u5728\u8FD9\u91CC\u663E\u793A', '\u66F4\u65E9', 'received_likes');
      }.width('100%');
    }
    .width('100%').height('100%')
    .padding({ top: this.topInset + 12, left: 22, right: 22, bottom: this.bottomInset + 20 })
    .backgroundColor('#F7F8FA')
    .alignItems(HorizontalAlign.Start);
  }

  @Builder
  messageBubble(label: string, count: string, iconName: string) {
    Column({ space: 6 }) {
      Stack() {
        Button() {
          if (iconName === 'message_reply') {
            Image($r('app.media.message_reply')).width(22).height(22);
          } else if (iconName === 'at_me') {
            Image($r('app.media.at_me')).width(22).height(22);
          } else if (iconName === 'received_likes') {
            Image($r('app.media.xiaoxi')).width(22).height(22);
          } else {
            Image($r('app.media.xiaoxi')).width(22).height(22);
          }
        }
        .type(ButtonType.ROUNDED_RECTANGLE)
        .width(52).height(52)
        .backgroundColor(ImmersiveMaterial.fallbackBackground())
        .borderRadius(26)
        .systemMaterial(ImmersiveMaterial.thin())
        .shadow({ radius: 6, color: '#22000000', offsetX: 0, offsetY: 2 });
        if (count !== '') {
          Text(count).fontSize(10).fontColor(Color.White).backgroundColor('#C51D2A')
            .borderRadius(12).padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .position({ right: -4, top: -4 });
        }
      }
      Text(label).fontSize(12).textAlign(TextAlign.Center);
    }.layoutWeight(1).alignItems(HorizontalAlign.Center);
  }
  @Builder
  messageRow(title: string, summary: string, date: string, iconName: string) {
    Row({ space: 12 }) {
      if (iconName === 'message_reply') {
        Image($r('app.media.message_reply')).width(38).height(38).borderRadius(19);
      } else if (iconName === 'at_me') {
        Image($r('app.media.at_me')).width(38).height(38).borderRadius(19);
      } else if (iconName === 'received_likes') {
        Image($r('app.media.xiaoxi')).width(38).height(38).borderRadius(19);
      } else {
        Image($r('app.media.xiaoxi')).width(38).height(38).borderRadius(19);
      }
      Column({ space: 5 }) {
        Row() {
          Text(title).fontSize(14).layoutWeight(1);
          Text(date).fontSize(11).fontColor('#858C94');
        }.width('100%');
        Text(summary).fontSize(13).fontColor('#858C94').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }.width('100%').padding({ top: 14, bottom: 14 })
      .border({ width: { bottom: 1 }, color: '#E9EDF0' });
  }

  @Builder
  liveBasicPage() {
    Scroll() {
      Column({ space: 12 }) {
        Row() {
          Text('正在直播').fontSize(22).fontWeight(FontWeight.Bold).fontColor(Color.Black);
          Text('实时').fontSize(12).fontColor('#1677A8').fontWeight(FontWeight.Bold);
        }.width('100%').justifyContent(FlexAlign.SpaceBetween);
        ForEach(['热门游戏直播', '音乐现场', '生活分享', '知识讲堂'], (title: string, index: number) => {
          Row({ space: 12 }) {
            Stack() {
              Column() { Text('LIVE').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Color.White); }
                .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
                .backgroundColor(['#D86B5D', '#4E9A8A', '#D29B4A', '#6F8CC4'][index]);
            }.width(116).height(76).borderRadius(10);
            Column({ space: 6 }) {
              Text(title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(Color.Black).maxLines(1);
              Text(['主播正在游戏中', '现场音乐演出进行中', '分享今天的生活', '一起了解有趣知识'][index])
                .fontSize(13).fontColor('#626B75').maxLines(1);
              Text(['12.6万', '8.4万', '3.1万', '1.8万'][index] + ' 人观看')
                .fontSize(12).fontColor('#858C94');
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
          }.width('100%').padding(12).backgroundColor(Color.White).borderRadius(12)
            .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 });
        });
      }.width('100%').padding({ left: 14, right: 14, top: 18, bottom: this.bottomInset + 88 })
        .alignItems(HorizontalAlign.Start);
    }.width('100%').height('100%').scrollBar(BarState.Off);
  }

  @Builder
  hotBasicPage() {
    Scroll() {
      Column({ space: 8 }) {
        Text('热门榜单').fontSize(22).fontWeight(FontWeight.Bold).fontColor(Color.Black).width('100%');
        Text('全站热度实时排行').fontSize(13).fontColor('#858C94').width('100%').margin({ bottom: 6 });
        ForEach(['年度最佳番剧推荐', '热门游戏直播回顾', '音乐节精彩瞬间', '科技产品评测', '旅行攻略分享', '美食探店指南'], (title: string, index: number) => {
          Row({ space: 12 }) {
            Text(String(index + 1)).fontSize(index < 3 ? 20 : 15).fontWeight(FontWeight.Bold)
              .fontColor(index === 0 ? '#D28A2E' : index === 1 ? '#7D8791' : index === 2 ? '#A66F4D' : '#858C94')
              .width(30).textAlign(TextAlign.Center);
            Column({ space: 5 }) {
              Text(title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Color.Black).maxLines(1);
              Text(['综合热度 98.6万', '综合热度 87.3万', '综合热度 76.9万', '综合热度 65.2万', '综合热度 54.8万', '综合热度 49.1万'][index])
                .fontSize(12).fontColor('#858C94');
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            Text('查看').fontSize(12).fontColor('#1677A8');
          }.width('100%').padding({ top: 14, bottom: 14, left: 8, right: 8 })
            .backgroundColor(Color.White).borderRadius(10);
        });
      }.width('100%').padding({ left: 14, right: 14, top: 18, bottom: this.bottomInset + 88 })
        .alignItems(HorizontalAlign.Start);
    }.width('100%').height('100%').scrollBar(BarState.Off);
  }

  @Builder
  dynamicBasicPage() {
    Refresh({ refreshing: $$this.refreshing, offset: 56, friction: 80 }) {
    Scroll() {
      Column({ space: 12 }) {
        Row() {
          Text('最近更新').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1E252D')
            .layoutWeight(1);
          Button() {
            Image($r('app.media.edit')).width(20).height(20);
          }.type(ButtonType.ROUNDED_RECTANGLE).width(48).height(48)
            .backgroundColor(ImmersiveMaterial.fallbackBackground(0.72))
            .borderRadius(24)
            .systemMaterial(ImmersiveMaterial.thin())
            .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
            .onClick(() => { this.showDynamicEditor = true; });
        }.width('100%').height(48);
        Scroll() {
          Row({ space: 14 }) {
            ForEach(this.dynamicAuthors, (author: DynamicAuthor) => {
              Column({ space: 4 }) {
                Image(author.face).width(50).height(50).borderRadius(25).objectFit(ImageFit.Cover);
                Text(author.name).fontSize(11).fontColor('#59616B').maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).width(58).textAlign(TextAlign.Center);
              }.width(58);
            }, (author: DynamicAuthor) => `dynamic_author_${author.name}`);
          }.width(Math.max(4, this.dynamicAuthors.length * 72 + 4))
            .padding({ left: 2, right: 2 });
        }.width('100%').height(78)
          .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off);
        if (this.dynamicLoading && this.dynamicVideos.length === 0) {
          this.loadingIndicator('正在加载关注动态', '#1677A8');
        } else if (this.dynamicError !== '') {
          Text(this.dynamicError).fontSize(14).fontColor('#858C94').width('100%').textAlign(TextAlign.Center)
            .margin({ top: 30 });
        } else if (this.dynamicVideos.length === 0) {
          Text('暂时没有新的投稿').fontSize(14).fontColor('#858C94').width('100%').textAlign(TextAlign.Center)
            .margin({ top: 30 });
        } else {
          ForEach(this.dynamicVideos, (item: VideoItem) => {
            this.dynamicVideoCard(item);
          }, (item: VideoItem) => `dynamic_${item.id}`);
        }
      }.width('100%').padding({ left: 14, right: 14, top: 10, bottom: this.bottomInset + 88 })
        .alignItems(HorizontalAlign.Start);
    }.width('100%').height('100%').scrollBar(BarState.Off);
    }
    .layoutWeight(1).width('100%')
    .onRefreshing(() => { this.refreshCurrentPage(); });
  }

  @Builder
  dynamicVideoCard(item: VideoItem) {
    Column({ space: 8 }) {
      if (item.cover !== '') {
        Image(item.cover).width('100%').aspectRatio(1.78).objectFit(ImageFit.Cover).borderRadius(8)
          .onClick(() => { this.openDynamicVideo(item); });
      }
      Text(item.title).fontSize(15).fontWeight(FontWeight.Medium).maxLines(2).lineHeight(22);
      Row() {
        Text('@' + item.author).fontSize(12).fontColor('#1677A8').layoutWeight(1);
        Text(this.formatPublishTime(item.publishTime)).fontSize(12).fontColor('#858C94');
      }.width('100%');
      Row() {
        Row({ space: 4 }) {
          Image($r('app.media.bfl')).width(15).height(15);
          Text(this.formatCount(item.viewCount)).fontSize(11).fontColor('#858C94');
        }.layoutWeight(1);
        Row({ space: 4 }) {
          Image($r('app.media.dm')).width(15).height(15);
          Text(this.formatCount(item.danmuCount)).fontSize(11).fontColor('#858C94');
        }.layoutWeight(1);
        Row({ space: 4 }) {
          Image($r('app.media.dianzan')).width(15).height(15);
          Text(this.formatCount(item.likeCount)).fontSize(11).fontColor('#858C94');
        }.layoutWeight(1);
        Row({ space: 4 }) {
          Image($r('app.media.pl')).width(15).height(15);
          Text(this.formatCount(item.commentCount)).fontSize(11).fontColor('#858C94');
        }.layoutWeight(1).onClick(() => { this.openDynamicVideo(item, true); });
        Row({ space: 4 }) {
          Image($r('app.media.share')).width(15).height(15);
          Text(this.formatCount(item.shareCount ?? 0)).fontSize(11).fontColor('#858C94');
        }.layoutWeight(1);
      }.width('100%');
    }.width('100%').padding(12).backgroundColor(Color.White).borderRadius(10)
      .onClick(() => { this.openDynamicVideo(item); });
  }

  @Builder
  dynamicEditorPage() {
    Column() {
      Row({ space: 10 }) {
        Button() {
          Image($r('app.media.fanhui_left')).width(24).height(24);
        }.type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.showDynamicEditor = false; });
        Text('发布动态').fontSize(20).fontWeight(FontWeight.Bold).layoutWeight(1);
      }.width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 });
      Column() {
        Text('').fontSize(1);
      }.layoutWeight(1).width('100%');
    }.width('100%').height('100%').backgroundColor('#F7F8FA');
  }

  @Builder
  animeBasicPage() {
    Scroll() {
      Column({ space: 12 }) {
        Row() {
          Text('番剧').fontSize(22).fontWeight(FontWeight.Bold).fontColor(Color.Black);
          Text('更新中').fontSize(13).fontColor('#1677A8');
        }.width('100%').justifyContent(FlexAlign.SpaceBetween);
        Grid() {
          ForEach(['进击的巨人', '间谍过家家', '夏日重现', '电锯人', '咒术回战', '我的英雄学院'], (title: string, index: number) => {
            GridItem() {
              Column({ space: 7 }) {
                Stack() {
                  Column() { Text('番剧').fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.White); }
                    .width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
                    .backgroundColor(['#7C9FC4', '#C58A9B', '#8BAE9B', '#D29B69', '#9288B8', '#769EAA'][index]);
                }.width('100%').height(148).borderRadius(10);
                Text(title).fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.Black).maxLines(1);
                Text('更新至第 ' + String(index + 8) + ' 集').fontSize(12).fontColor('#858C94');
              }.width('100%').alignItems(HorizontalAlign.Start);
            }
          });
        }.columnsTemplate('1fr 1fr').columnsGap(12).rowsGap(16).width('100%');
      }.width('100%').padding({ left: 14, right: 14, top: 18, bottom: this.bottomInset + 88 })
        .alignItems(HorizontalAlign.Start);
    }.width('100%').height('100%').scrollBar(BarState.Off);
  }

  @Builder
  webLoginPage() {
    Column() {
      Row({ space: 10 }) {
        Button() {
          Image($r('app.media.fanhui_left')).width(24).height(24);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
        .backgroundColor(Color.Transparent)
        .onClick(() => { this.webLoginVisible = false; });
        Text('\u5B98\u65B9\u767B\u5F55').fontSize(20).fontWeight(FontWeight.Medium)
          .layoutWeight(1);
        Button('\u5B8C\u6210\u767B\u5F55').height(38)
          .onClick(() => { this.syncWebLoginCookie(); });
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: this.topInset + 8, bottom: 6 });
      Text(this.webLoginStatus).fontSize(12).fontColor('#1677A8')
        .width('100%').padding({ left: 18, right: 18, bottom: 6 });
      Web({ src: 'https://passport.bilibili.com/login', controller: this.webController })
        .width('100%').layoutWeight(1)
        .onPageEnd(() => { this.syncWebLoginCookie(); });
    }
    .width('100%').height('100%')
    .backgroundColor('#FAFBFC');
  }
  @Builder
  loginPage() {
    Column() {
      Row({ space: 14 }) {
        Button() {
          Image($r('app.media.fanhui_left')).width(26).height(26);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(46).height(46)
        .backgroundColor(Color.Transparent)
        .onClick(() => { this.closeLoginPage(); });
        Text('\u767B\u5F55').fontSize(26).fontWeight(FontWeight.Medium);
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: this.topInset + 8, bottom: 8 });

      if (this.authSession !== null) {
        Row({ space: 10 }) {
          if (this.authSession.face !== '') {
            Image(this.authSession.face).width(42).height(42).borderRadius(21);
          } else {
            Row().width(42).height(42).borderRadius(21).backgroundColor('#DCE3EF');
          }
          Column({ space: 2 }) {
            Text(this.authSession.name).fontSize(16).fontWeight(FontWeight.Bold);
            Text('UID ' + this.authSession.uid).fontSize(12).fontColor('#858C94');
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
          Button('\u9000\u51FA').height(34).fontSize(13).onClick(() => { this.logout(); });
        }.width('100%').padding({ left: 18, right: 18, bottom: 12 });
      }

      Scroll() {
        Column({ space: 18 }) {
          Text('\u8BF7\u4F7F\u7528\u54D4\u54E9\u54D4\u54E9\u5B98\u65B9\u9875\u9762\u767B\u5F55')
            .fontSize(23).fontWeight(FontWeight.Medium)
            .margin({ top: 28, bottom: 10 });
          Button('\u6253\u5F00\u5B98\u65B9\u767B\u5F55')
            .type(ButtonType.ROUNDED_RECTANGLE).width(220).height(48)
            .fontColor('#1677A8').backgroundColor('#E9F4F8')
            .onClick(() => { this.openWebLogin(); });
          if (this.loginNotice !== '') {
            Text(this.loginNotice).fontSize(13).fontColor('#C51D2A')
              .textAlign(TextAlign.Center).width('100%');
          }
          Text('\u767B\u5F55\u72B6\u6001\u4F1A\u5B89\u5168\u4FDD\u5B58\u5728\u672C\u673A\uFF0C\u91CD\u542F\u5E94\u7528\u540E\u81EA\u52A8\u6062\u590D\u3002')
            .fontSize(12).fontColor('#A4A9AF')
            .textAlign(TextAlign.Center).width('100%')
            .margin({ top: 28, bottom: 24 });
        }
        .width('100%')
        .padding({ left: 30, right: 30, bottom: this.bottomInset + 20 })
        .alignItems(HorizontalAlign.Center);
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }
    .width('100%').height('100%').backgroundColor('#FAFBFC');
  }

  @Builder
  searchFloatingButton() {
    Button() {
      Image($r('app.media.ic_public_search_filled')).width(24).height(24);
    }
    .type(ButtonType.ROUNDED_RECTANGLE).width(52).height(52)
    .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(26)
    .systemMaterial(ImmersiveMaterial.ultraThin())
    .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
    .onClick(() => { this.openSearchPanel(); });
  }

  @Builder
  actionFloatingButton() {
    Button() {
      Image($r('app.media.more')).width(24).height(24);
    }
    .type(ButtonType.ROUNDED_RECTANGLE).width(52).height(52)
    .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(26)
    .systemMaterial(ImmersiveMaterial.ultraThin())
    .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
    .onClick(() => { this.actionMenuVisible = !this.actionMenuVisible; })
    .gesture(LongPressGesture({ repeat: false }).onAction((): void => {
      this.homeGridScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    }));
  }

  build() {
    Stack() {
      if (this.showVertical) {
        if (this.landscapePlayback) {
          this.landscapePlayer();
        } else {
          this.detailPage();
        }
      } else {
        Stack({ alignContent: Alignment.Start }) {
          Column() {
          if (this.activeTab === 1) {
            Row({ space: 8 }) {
              this.topCircleButton('\u6211', () => { this.sidebar = 1; });
              this.topTabs();
              Button() {
                Image($r('app.media.xiaoxi')).width(24).height(24);
              }
              .type(ButtonType.ROUNDED_RECTANGLE)
              .width(48).height(48)
      .backgroundColor(ImmersiveMaterial.fallbackBackground(0.72))
              .borderRadius(24)
              .systemMaterial(ImmersiveMaterial.thin())
              .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
              .onClick(() => { this.sidebar = 2; });
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .justifyContent(FlexAlign.SpaceBetween);
            if (this.contentTab === 1) {
            Refresh({ refreshing: $$this.refreshing, offset: 64, friction: 80 }) {
              Grid(this.homeGridScroller) {
                if (this.loading && (this.videos.length === 0 || this.videos[0].placeholder)) {
                  GridItem() {
                    this.loadingIndicator('\u6B63\u5728\u52A0\u8F7D\u63A8\u8350', '#1677A8');
                  }
                  .height(72);
                }
                ForEach(this.videos, (item: VideoItem) => {
                  GridItem() { this.homeCard(item); }
                }, (item: VideoItem) => `${item.id}`);
                if (this.loadingMore) {
                  GridItem() {
                    this.loadingIndicator('\u6B63\u5728\u52A0\u8F7D', '#1677A8');
                  }
                  .height(52);
                }
              }
              .columnsTemplate(this.compactGrid ? '1fr' : '1fr 1fr')
              .columnsGap(8)
              .rowsGap(10)
              .padding({ left: 12, right: 12, bottom: 12 })
              .onScrollIndex((_first: number, last: number): void => {
                if (last < Math.max(0, this.videos.length - 4)) return;
                if (this.loadingMore) return;
                this.loadMoreRecommendations();
              })
              .width('100%').height('100%').scrollBar(BarState.Off);
            }
            .layoutWeight(1).width('100%')
            .onRefreshing(() => { this.refreshCurrentPage(); });
} else if (this.contentTab === 0) {
              this.liveBasicPage();
	            } else if (this.contentTab === 2) {
              this.hotBasicPage();
	            } else if (this.contentTab === 3) {
              this.dynamicBasicPage();
	            } else {
              this.animeBasicPage();
	            }
          } else if (this.activeTab === 0) {
            this.dynamicBasicPage();
          } else {
            this.animeBasicPage();
          }
          }.width('100%').height('100%').padding({ top: this.topInset }).backgroundColor('#F7F8FA');
          Row({ space: 10 }) {
if (this.floatBallSwapped) {
	              this.actionFloatingButton();
	            } else {
	              this.searchFloatingButton();
	            }
	            Row() {
	              Button() {
	                Column({ space: 2 }) {
                  Image($r('app.media.dontai')).width(this.activeTab === 0 ? 22 : 20)
                    .height(this.activeTab === 0 ? 22 : 20)
                    .fillColor(this.activeTab === 0 ? '#1677A8' : '#3E4854');
	                  Text('\u52A8\u6001').fontSize(11)
	                    .fontColor(this.activeTab === 0 ? '#1677A8' : '#3E4854')
	                    .fontWeight(this.activeTab === 0 ? FontWeight.Bold : FontWeight.Normal);
	                }.alignItems(HorizontalAlign.Center);
	              }
.type(ButtonType.ROUNDED_RECTANGLE).height(52).layoutWeight(1)
		              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.activeTab = 0;
                this.refreshing = false;
                this.actionMenuVisible = false;
                this.loadError = '';
                this.loadDynamicVideos(true);
              });
	              Button() {
	                Column({ space: 2 }) {
                  Image($r('app.media.home')).width(this.activeTab === 1 ? 22 : 20)
                    .height(this.activeTab === 1 ? 22 : 20)
                    .fillColor(this.activeTab === 1 ? '#1677A8' : '#3E4854');
	                  Text('\u9996\u9875').fontSize(11)
	                    .fontColor(this.activeTab === 1 ? '#1677A8' : '#3E4854')
	                    .fontWeight(this.activeTab === 1 ? FontWeight.Bold : FontWeight.Normal);
	                }.alignItems(HorizontalAlign.Center);
	              }
.type(ButtonType.ROUNDED_RECTANGLE).height(52).layoutWeight(1)
		              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.activeTab = 1;
                this.contentTab = 1;
                this.selectedTopTab = 1;
                this.refreshing = false;
                this.actionMenuVisible = false;
                this.loadError = '';
              });
	              Button() {
	                Column({ space: 2 }) {
                  Image($r('app.media.fanju')).width(this.activeTab === 2 ? 22 : 20)
                    .height(this.activeTab === 2 ? 22 : 20)
                    .fillColor(this.activeTab === 2 ? '#1677A8' : '#3E4854');
	                  Text('\u756A\u5267').fontSize(11)
	                    .fontColor(this.activeTab === 2 ? '#1677A8' : '#3E4854')
	                    .fontWeight(this.activeTab === 2 ? FontWeight.Bold : FontWeight.Normal);
	                }.alignItems(HorizontalAlign.Center);
	              }
.type(ButtonType.ROUNDED_RECTANGLE).height(52).layoutWeight(1)
		              .backgroundColor(Color.Transparent)
		              .onClick(() => { this.activeTab = 2; this.loadError = ''; });
		            }
            .layoutWeight(1).height(58).padding({ left: 6, right: 6 })
            .backgroundColor(ImmersiveMaterial.fallbackBackground(0.82))
            .borderRadius(30)
            .systemMaterial(ImmersiveMaterial.ultraThin());

            if (this.floatBallSwapped) {
              this.searchFloatingButton();
            } else {
              this.actionFloatingButton();
            }
          }
          .width('94%').height(58).padding({ left: 4, right: 4 })
          .justifyContent(FlexAlign.SpaceBetween)
          .position({ left: '3%', bottom: this.bottomInset + 6 })
          .zIndex(10);
          if (this.actionMenuVisible) {
            Column({ space: 8 }) {
              Button() {
                Text('列表刷新').fontSize(13)
                  .fontColor(Color.Black).fontWeight(FontWeight.Bold)
                  .textAlign(TextAlign.Center)
              }.width(124).height(38)
                .type(ButtonType.ROUNDED_RECTANGLE).borderRadius(18)
                .backgroundColor(ImmersiveMaterial.fallbackBackground())
                .systemMaterial(ImmersiveMaterial.thin())
                .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
                .onClick(() => {
                  this.actionMenuVisible = false;
                  this.homeGridScroller.scrollTo({ xOffset: 0, yOffset: 0 });
                  this.refreshCurrentPage();
                });
              Button() {
                Text(this.compactGrid ? '改为双列' : '改为单列').fontSize(13)
                  .fontColor(Color.Black).fontWeight(FontWeight.Bold)
                  .textAlign(TextAlign.Center)
              }.width(124).height(38)
                .type(ButtonType.ROUNDED_RECTANGLE).borderRadius(18)
                .backgroundColor(ImmersiveMaterial.fallbackBackground())
                .systemMaterial(ImmersiveMaterial.thin())
                .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
                .onClick(() => {
                  this.compactGrid = !this.compactGrid;
                  this.actionMenuVisible = false;
                });
            }
            .width('100%')
            .alignItems(this.floatBallSwapped ? HorizontalAlign.Start : HorizontalAlign.End)
            .padding({ left: 8, right: 8 })
            .position({ left: 0, right: 0, bottom: this.bottomInset + 64 })
            .transition({ type: TransitionType.Insert, opacity: 0.0 })
            .animation({ duration: 220, curve: Curve.EaseOut })
            .zIndex(11);
          }
        }
        .width('100%').height('100%')
        .backgroundColor('#F7F8FA');
      }
      if (this.loginVisible && !this.showVertical) {
        this.loginPage();
      }
      if (this.webLoginVisible && !this.showVertical) {
        this.webLoginPage();
      }

      if (this.sidebar !== 0 && !this.showVertical) {
        Column() {
          if (this.sidebar === 1) {
            this.mineSidebar();
          } else {
            this.messageSidebar();
          }
        }
        .width('100%').height('100%')
        .backgroundColor(ImmersiveMaterial.fallbackBackground())
        .systemMaterial(ImmersiveMaterial.thin())
        .transition({ type: TransitionType.Insert, opacity: 0.0 });
      }
      if (this.showDynamicEditor && !this.showVertical) {
        this.dynamicEditorPage();
      }
    }.width('100%').height('100%')
      .backgroundColor('#F7F8FA')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }
}
