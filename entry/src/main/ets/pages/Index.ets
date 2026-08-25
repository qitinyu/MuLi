import { VideoPlayerService } from '../services/VideoPlayerService';
import { VideoItem } from '../models/VideoItem';
import { VideoDetailService } from '../services/VideoDetailService';
import { RecommendationService } from '../services/RecommendationService';
import { PlaybackService } from '../services/PlaybackService';
import { WbiService } from '../services/WbiService';
import { AuthService, AuthSession, AuthPollResult, AuthQrCode } from '../services/AuthService';
import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import web_webview from '@ohos.web.webview';

@Entry
@Component
struct Index {
  @State showVertical: boolean = false;
  @State landscapePlayback: boolean = false;
  @State currentIndex: number = 0;
  @State draggingDown: boolean = false;
  @State loading: boolean = false;
  @State loadingMore: boolean = false;
  private page: number = 0;
  private lastLoadTriggerLength: number = -1;
  @State loadError: string = '';
  @State activeTab: number = 1;
  @State searchExpanded: boolean = false;
  @State searchText: string = '';
  @State loginVisible: boolean = false;
  @State webLoginVisible: boolean = false;
  @State webLoginStatus: string = '';
  @State loginMode: number = 0;
  @State loginAccount: string = '';
  @State loginPassword: string = '';
  @State loginSmsCode: string = '';
  @State loginCookie: string = '';
  @State loginShowPassword: boolean = false;
  @State loginNotice: string = '';
  @State authSession: AuthSession | null = null;
  @State loginQrUrl: string = '';
  @State loginQrStatus: string = '';
  @State loginQrSeconds: number = 0;
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
  @State mineCoverUri: string = '';
  @State showMineCoverSheet: boolean = false;
  @State topInset: number = 24;
  @State bottomInset: number = 8;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private uiPreferences: preferences.Preferences | null = null;
  private playerService: VideoPlayerService = new VideoPlayerService();
  private webController: web_webview.WebviewController = new web_webview.WebviewController();
  private playbackRequest: number = 0;
  private detailRequest: number = 0;
  private qrPolling: boolean = false;
  private qrAuthCode: string = '';
  private surfaceController: XComponentController = new XComponentController();
  private surfaceId: string = '';
  private hasMoreRecommendations: boolean = true;
  private static readonly maxRecommendations: number = 30;
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

  aboutToAppear(): void {
    WbiService.warmup();
    this.authSession = AuthService.currentSession();
    this.restoreAuthSession();
    this.loadMineCover();
    this.loadRecommendations();
    window.getLastWindow(this.context).then((mainWindow: window.Window): void => {
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navigationArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.topInset = px2vp(systemArea.topRect.height);
      this.bottomInset = px2vp(navigationArea.bottomRect.height);
      mainWindow.on('avoidAreaChange', (data): void => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          this.topInset = px2vp(data.area.topRect.height);
        } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          this.bottomInset = px2vp(data.area.bottomRect.height);
        }
      });
    }).catch((error: BusinessError): void => {
      console.error(`Pilihos avoid area failed: ${error.code} ${error.message}`);
    });
  }

  private async loadRecommendations(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    try {
      const result: VideoItem[] = await RecommendationService.load(0);
      if (result.length > 0) {
        this.page = 0;
        this.videos = result;
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

  private async restoreAuthSession(): Promise<void> {
    const current: AuthSession | null = AuthService.currentSession();
    const restored: AuthSession | null = await AuthService.restoreSession(this.context);
    this.authSession = restored ?? current;
    if (restored === null && current !== null) this.refreshAuthData();
  }

  private async loadMoreRecommendations(): Promise<void> {
    if (this.loadingMore || this.loading || !this.hasMoreRecommendations) return;
    if (this.videos.length >= Index.maxRecommendations) {
      this.hasMoreRecommendations = false;
      return;
    }
    this.loadingMore = true;
    try {
      const next: VideoItem[] = await RecommendationService.load(this.page + 1);
      if (next.length > 0) {
        this.page += 1;
        const existing: Set<string> = new Set<string>(this.videos.map((item: VideoItem): string =>
          item.bvid !== '' ? item.bvid : `${item.aid}`));
        const additions: VideoItem[] = next.filter((item: VideoItem): boolean => {
          const key: string = item.bvid !== '' ? item.bvid : `${item.aid}`;
          return !existing.has(key);
        });
        const remaining: number = Index.maxRecommendations - this.videos.length;
        this.videos = this.videos.concat(additions.slice(0, remaining));
        if (this.videos.length >= Index.maxRecommendations || additions.length === 0) {
          this.hasMoreRecommendations = false;
        }
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
    this.playerService.release();
    const item: VideoItem = this.videos[this.currentIndex];
    try {
      const urls: string[] = item.playUrl !== '' ? [item.playUrl] : await PlaybackService.resolveCandidates(item);
      if (requestId !== this.playbackRequest || !this.showVertical) return;
      if (urls.length === 0) throw new Error('没有可用的视频播放地址');
      this.playbackUrls = urls;
      this.playbackUrlIndex = 0;
      this.currentUrl = urls[0];
      if (this.videoMounted && this.surfaceReady) {
        this.startNativePlayback();
      }
    } catch (error) {
      if (requestId !== this.playbackRequest || !this.showVertical) return;
      this.playerError = `播放地址获取失败: ${String(error)}`;
      console.error(`Pilihos playback failed: ${String(error)}`);
    }
  }

  private formatCount(value: number): string {
    if (value >= 100000000) return `${(value / 100000000).toFixed(2).replace(/\.00$/, '')}亿`;
    if (value >= 1000000) return `${(value / 100000).toFixed(2).replace(/\.00$/, '')}万`;
    if (value >= 1000) return `${(value / 1000).toFixed(1).replace(/\.0$/, '')}千`;
    return `${value}`;
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
  private async startQrLogin(): Promise<void> {
    this.qrPolling = false;
    this.loginQrUrl = '';
    this.loginQrStatus = '\u6B63\u5728\u83B7\u53D6\u4E8C\u7EF4\u7801...';
    this.loginQrSeconds = 0;
    try {
      const qrCode: AuthQrCode = await AuthService.requestQrCode();
      if (!this.loginVisible || this.loginMode !== 2) return;
      this.qrAuthCode = qrCode.authCode;
      this.loginQrUrl = qrCode.url;
      this.loginQrSeconds = qrCode.expiresIn;
      this.loginQrStatus = '请使用哔哩哔哩客户端扫码';
      this.pollQrLogin(qrCode.expiresIn);
    } catch (error) {
      this.loginQrStatus = `二维码获取失败：${String(error)}`;
    }
  }

  private async pollQrLogin(expiresIn: number): Promise<void> {
    if (this.qrPolling) return;
    this.qrPolling = true;
    const deadline: number = Date.now() + expiresIn * 1000;
    while (this.qrPolling && this.loginVisible && this.loginMode === 2 && Date.now() < deadline) {
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, 2000);
      });
      if (!this.qrPolling || !this.loginVisible || this.loginMode !== 2) break;
      try {
        const result: AuthPollResult = await AuthService.pollQrCode(this.qrAuthCode, this.context);
        this.loginQrSeconds = Math.max(0, Math.floor((deadline - Date.now()) / 1000));
        if (result.session !== null) {
          this.authSession = result.session;
          this.loginNotice = '\u767B\u5F55\u6210\u529F\uFF0C\u6B22\u8FCE ' + result.session.name;
          this.loginQrStatus = '扫码成功';
          this.loginVisible = false;
          this.sidebar = 0;
          this.qrPolling = false;
          return;
        }
        if (result.code === 86038) {
          this.loginQrStatus = '\u4E8C\u7EF4\u7801\u5DF2\u8FC7\u671F\uFF0C\u8BF7\u5237\u65B0';
          break;
        }
        this.loginQrStatus = '\u7B49\u5F85\u626B\u7801\u6216\u786E\u8BA4...';
      } catch (error) {
        this.loginQrStatus = `二维码轮询失败：${String(error)}`;
        break;
      }
    }
    this.qrPolling = false;
    if (this.loginQrSeconds <= 0 && this.loginQrUrl !== '') this.loginQrStatus = '\u4E8C\u7EF4\u7801\u5DF2\u8FC7\u671F\uFF0C\u8BF7\u5237\u65B0';
  }

  private async loginByCookie(): Promise<void> {
    if (this.loginCookie.trim() === '') {
      this.loginNotice = '\u8BF7\u7C98\u8D34 Cookie';
      return;
    }
    this.loginNotice = '\u6B63\u5728\u9A8C\u8BC1 Cookie...';
    try {
      const session: AuthSession = await AuthService.validateCookie(this.loginCookie, this.context);
      this.authSession = session;
      this.loginNotice = '\u767B\u5F55\u6210\u529F\uFF0C\u6B22\u8FCE ' + session.name;
      this.loginCookie = '';
      this.closeLoginPage();
    } catch (error) {
      this.loginNotice = `Cookie 验证失败??{String(error)}`;
    }
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
      const cookie: string = await web_webview.WebCookieManager.fetchCookie('https://www.bilibili.com');
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
    this.qrPolling = false;
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
    if (this.searchExpanded) {
      this.searchExpanded = false;
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

  private tryNextPlaybackUrl(): boolean {
    const nextIndex: number = this.playbackUrlIndex + 1;
    if (nextIndex >= this.playbackUrls.length) {
      return false;
    }
    this.playbackUrlIndex = nextIndex;
    this.currentUrl = this.playbackUrls[nextIndex];
    this.playbackReady = false;
    this.playbackStarting = false;
    console.info(`Pilihos playback retry url ${nextIndex + 1}/${this.playbackUrls.length}`);
    this.startNativePlayback();
    return true;
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
      await this.playerService.prepare(this.currentUrl, this.surfaceId);
      if (requestId !== this.playbackRequest || !this.showVertical || !this.videoMounted) return;
      await this.playerService.play();
      if (requestId === this.playbackRequest && this.showVertical) {
        this.playbackReady = true;
      }
    } catch (error) {
      if (requestId !== this.playbackRequest || !this.showVertical) return;
      if (this.tryNextPlaybackUrl()) return;
      this.playbackReady = false;
      this.videoMounted = false;
      this.playerError = '\u89C6\u9891\u64AD\u653E\u5931\u8D25: ' + String(error);
      console.error(`Pilihos native playback failed: ${String(error)}`);
      this.playerService.release();
    } finally {
      if (requestId === this.playbackRequest) {
        this.playbackStarting = false;
      }
    }
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
    .height(210)
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
            Text(this.playerError === '' ? '\u6B63\u5728\u52A0\u8F7D\u89C6\u9891...' : this.playerError)
            .fontColor(Color.White).fontSize(15).textAlign(TextAlign.Center);
            Button('\u91CD\u8BD5').onClick(() => { this.prepareCurrentVideo(); });
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
  landscapePlayer() {
    Stack() {
      if (this.currentUrl !== '') {
        XComponent({
          id: 'PilihosLandscapeSurface',
          type: XComponentType.SURFACE,
          controller: this.surfaceController
        }).width('100%').height('100%')
          .onLoad((): void => {
            this.onVideoSurfaceLoad();
          })
          .onDestroy((): void => {
            this.surfaceReady = false;
            this.surfaceId = '';
          });
      } else {
        Column({ space: 12 }) {
            Text(this.playerError === '' ? '\u6B63\u5728\u83B7\u53D6\u89C6\u9891\u64AD\u653E\u5730\u5740...' : this.playerError)
            .fontColor(Color.White).fontSize(15).textAlign(TextAlign.Center);
          if (this.playerError !== '') {
              Button('\u91CD\u8BD5').onClick(() => { this.prepareCurrentVideo(); });
          }
        }.justifyContent(FlexAlign.Center).width('100%').height('100%');
      }
      Button() {
        Image($r('app.media.fanhui_left')).width(24).height(24);
      }
      .type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
      .backgroundColor('#66000000').borderRadius(22)
      .position({ left: 16, top: 16 })
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
          XComponent({
            id: 'PilihosVideoSurface',
            type: XComponentType.SURFACE,
            controller: this.surfaceController
          }).width('100%').height('100%')
            .onLoad((): void => {
              this.onVideoSurfaceLoad();
            })
            .onDestroy((): void => {
              this.surfaceReady = false;
              this.surfaceId = '';
            });
          if (!this.videoMounted) {
            Image(this.videos[this.currentIndex].cover)
              .width('100%').height('100%').objectFit(ImageFit.Cover);
            Button(this.playerError === '' ? '\u64AD\u653E' : '\u91CD\u8BD5').fontSize(16).onClick(() => {
              this.videoMounted = true;
              this.playbackReady = false;
              this.startNativePlayback();
            });
          } else if (this.playbackStarting) {
            Text('\u6B63\u5728\u51C6\u5907\u89C6\u9891...').fontColor(Color.White).fontSize(14)
              .backgroundColor('#99000000').padding(8);
          }
        } else {
          Column({ space: 12 }) {
            Text(this.playerError === '' ? '\u6B63\u5728\u83B7\u53D6\u89C6\u9891\u64AD\u653E\u5730\u5740...' : this.playerError)
              .fontColor(Color.White).fontSize(14).textAlign(TextAlign.Center)
              .backgroundColor('#99000000').padding(8);
            if (this.playerError !== '') {
              Button('\u91CD\u8BD5').onClick(() => { this.prepareCurrentVideo(); });
            }
          }.justifyContent(FlexAlign.Center).width('100%').height('100%');
        }
        Button() {
          Image($r('app.media.left_syb')).width(24).height(24);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(42).height(42)
        .backgroundColor(Color.Transparent)
        .position({ left: 10, top: 10 })
        .onClick(() => { this.onBackPress(); });
      }.width('100%').aspectRatio(16 / 9).backgroundColor(Color.Black);

      Row() {
        Row({ space: 12 }) {
          Text('\u7B80\u4ECB').fontSize(15).fontColor('#1677A8');
          Text('\u8BC4\u8BBA ' + this.formatCount(this.videos[this.currentIndex].commentCount)).fontSize(15);
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
            .onChange((value: string) => { this.danmakuText = value; });
        }
        .layoutWeight(1)
        .padding({ right: 12 })
        .justifyContent(FlexAlign.End)
        .alignItems(VerticalAlign.Center);
      }.width('100%').height(64).backgroundColor(Color.White)
        .border({ width: { bottom: 1 }, color: '#E5E8EC' });      Scroll() {
        Column({ space: 14 }) {
          Row({ space: 12 }) {
            if (this.videos[this.currentIndex].cover !== '') {
              Image(this.videos[this.currentIndex].cover).width(52).height(52).borderRadius(26);
            } else {
              Row().width(52).height(52).borderRadius(26).backgroundColor('#DCE3EF');
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
              Text(this.detailLoading ? '\u6B63\u5728\u52A0\u8F7D\u89C6\u9891\u8BE6\u60C5...' :
                (this.detailError !== '' ? this.detailError :
                  (this.videos[this.currentIndex].description === ''
                    ? '\u6682\u65E0\u7B80\u4ECB' : this.videos[this.currentIndex].description)))
                .fontSize(14).fontColor('#59616B').lineHeight(21)
                .width('100%');
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
                this.currentIndex = this.videos.indexOf(item);
                this.detailExpanded = false;
                this.detailError = '';
                this.currentUrl = '';
                this.loadVideoDetail();
                this.prepareCurrentVideo();
              });
            }
          }, (item: VideoItem) => `related_${item.id}`);
        }.width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: 16, right: 16, top: 14, bottom: this.bottomInset + 30 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off).backgroundColor(Color.White);
    }
    .width('100%').height('100%')
    .padding({ top: this.topInset })
    .backgroundColor(Color.Black);
  }

  @Builder
  topBubbleButton(label: string, selected: boolean, width: number, action: () => void) {
    Button(label)
      .type(ButtonType.ROUNDED_RECTANGLE)
      .controlSize(ControlSize.NORMAL)
      .width(width)
      .height(40)
      .fontSize(selected ? 15 : 14)
      .fontColor(selected ? Color.White : '#3E4854')
      .fontWeight(selected ? FontWeight.Bold : FontWeight.Normal)
      .backgroundColor(selected ? '#1677A8' : '#FFFFFF')
      .borderRadius(20)
      .shadow({ radius: selected ? 8 : 4, color: selected ? '#301677A8' : '#18000000', offsetX: 0, offsetY: 2 })
      .onClick(action);
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
      .backgroundColor('#FFFFFF')
      .padding(0)
      .borderRadius(24)
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
        .backgroundColor('#FFFFFF')
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
        GridItem() { this.mineGridAction('software_settings', '软件设置', false); }
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
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
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
        .backgroundColor(Color.Transparent)
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
        .backgroundColor('#FFFFFF')
        .borderRadius(26)
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
  loginModeButton(label: string, mode: number) {
    Button(label)
      .type(ButtonType.ROUNDED_RECTANGLE)
      .layoutWeight(1).height(52).fontSize(15)
      .fontColor(this.loginMode === mode ? '#1677A8' : '#3E4854')
      .fontWeight(this.loginMode === mode ? FontWeight.Bold : FontWeight.Normal)
      .backgroundColor(Color.Transparent)
      .border({
        width: { bottom: this.loginMode === mode ? 3 : 0 },
        color: '#1677A8'
      })
      .onClick(() => {
        this.loginMode = mode;
        this.loginNotice = '';
        if (mode === 2) {
          this.startQrLogin();
        } else {
          this.qrPolling = false;
        }
      });
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

      Row({ space: 4 }) {
        this.loginModeButton('\u5BC6\u7801', 0);
        this.loginModeButton('\u77ED\u4FE1', 1);
        this.loginModeButton('\u626B\u7801', 2);
        this.loginModeButton('Cookie', 3);
      }
      .width('100%').height(58)
      .padding({ left: 12, right: 12 })
      .border({ width: { bottom: 1 }, color: '#D9DDE2' });

      Scroll() {
        Column({ space: 18 }) {
          if (this.loginMode === 0) {
            Text('使用账号密码登录').fontSize(23).fontWeight(FontWeight.Medium)
              .margin({ top: 28, bottom: 10 });
            Column() {
              TextInput({ placeholder: '\u8D26\u53F7', text: this.loginAccount })
                .width('100%').height(58).fontSize(17)
                .backgroundColor(Color.Transparent)
                .onChange((value: string) => { this.loginAccount = value; });
              Row().width('100%').height(1).backgroundColor('#787D84');
              Row({ space: 8 }) {
                TextInput({ placeholder: '\u5BC6\u7801', text: this.loginPassword })
                  .layoutWeight(1).height(58).fontSize(17)
                  .backgroundColor(Color.Transparent)
                  .type(this.loginShowPassword ? InputType.Normal : InputType.Password)
                  .onChange((value: string) => { this.loginPassword = value; });
                Text(this.loginShowPassword ? '\u9690\u85CF\u5BC6\u7801' : '\u663E\u793A\u5BC6\u7801')
                  .fontSize(13).fontColor('#1677A8')
                  .onClick(() => { this.loginShowPassword = !this.loginShowPassword; });
              }.width('100%');
              Row().width('100%').height(1).backgroundColor('#787D84');
            }.width('100%');

            Row() {
              Text('\u8BB0\u4F4F\u8D26\u53F7').fontSize(14).fontColor('#4C535B');
              Text('\u5FD8\u8BB0\u5BC6\u7801').fontSize(14).fontColor('#1677A8').layoutWeight(1)
                .textAlign(TextAlign.End);
            }.width('100%');

            Button('\u767B\u5F55')
              .type(ButtonType.ROUNDED_RECTANGLE).width(180).height(52)
              .fontSize(18).fontColor('#1677A8').backgroundColor(Color.Transparent)
              .border({ width: 1, color: '#1677A8' }).borderRadius(26)
              .onClick(() => {
                this.loginNotice = this.loginAccount.length === 0 || this.loginPassword.length === 0
                  ? '\u8BF7\u8F93\u5165\u8D26\u53F7\u548C\u5BC6\u7801' : '\u8D26\u53F7\u5BC6\u7801\u767B\u5F55\u9700\u8981 B \u7AD9\u5B98\u65B9\u9A8C\u8BC1\u7801\u548C\u4EBA\u673A\u6821\u9A8C\uFF0C\u8BF7\u4F7F\u7528\u626B\u7801\u6216 Cookie \u767B\u5F55';
              });
          } else if (this.loginMode === 1) {
            Text('\u4F7F\u7528\u77ED\u4FE1\u767B\u5F55').fontSize(23).fontWeight(FontWeight.Medium)
              .margin({ top: 28, bottom: 10 });
            TextInput({ placeholder: '\u624B\u673A\u53F7', text: this.loginAccount })
              .width('100%').height(58).fontSize(17)
              .backgroundColor(Color.Transparent)
              .onChange((value: string) => { this.loginAccount = value; });
            Row().width('100%').height(1).backgroundColor('#787D84');
            Row({ space: 8 }) {
              TextInput({ placeholder: '\u9A8C\u8BC1\u7801', text: this.loginSmsCode })
                .layoutWeight(1).height(58).fontSize(17)
                .backgroundColor(Color.Transparent)
                .onChange((value: string) => { this.loginSmsCode = value; });
              Button('\u83B7\u53D6\u9A8C\u8BC1\u7801')
                .type(ButtonType.ROUNDED_RECTANGLE).height(38)
                .backgroundColor('#E9F4F8').fontColor('#1677A8')
                .onClick(() => {
                  this.loginNotice = '\u77ED\u4FE1\u9A8C\u8BC1\u7801\u9700\u8981 B \u7AD9\u5B98\u65B9\u4EBA\u673A\u6821\u9A8C\uFF0C\u8BF7\u4F7F\u7528\u626B\u7801\u6216 Cookie \u767B\u5F55';
                });
            }.width('100%');
            Row().width('100%').height(1).backgroundColor('#787D84');
            Button('\u767B\u5F55')
              .type(ButtonType.ROUNDED_RECTANGLE).width(180).height(52).fontSize(18)
              .fontColor('#1677A8').backgroundColor(Color.Transparent)
              .border({ width: 1, color: '#1677A8' }).borderRadius(26)
              .onClick(() => {
                this.loginNotice = this.loginAccount.length === 0 || this.loginSmsCode.length === 0
                  ? '\u8BF7\u8F93\u5165\u624B\u673A\u53F7\u548C\u9A8C\u8BC1\u7801' : '\u77ED\u4FE1\u767B\u5F55\u9700\u8981 B \u7AD9\u5B98\u65B9\u4EBA\u673A\u6821\u9A8C\uFF0C\u8BF7\u4F7F\u7528\u626B\u7801\u6216 Cookie \u767B\u5F55';
              });
          } else if (this.loginMode === 2) {
            Text('扫码登录').fontSize(23).fontWeight(FontWeight.Medium)
              .margin({ top: 28, bottom: 10 });
            Column({ space: 14 }) {
              if (this.loginQrUrl === '') {
                Row() {
                  Text(this.loginQrStatus)
                    .fontSize(14).fontColor('#858C94').textAlign(TextAlign.Center);
                }
                .width(210).height(210).padding(14).backgroundColor('#EEF1F4')
                .borderRadius(8).justifyContent(FlexAlign.Center);
              } else {
                QRCode(this.loginQrUrl)
                  .width(210).height(210).color(Color.Black).backgroundColor(Color.White);
              }
              Text(this.loginQrStatus).fontSize(14).fontColor('#1677A8');
              if (this.loginQrSeconds > 0) {
                Text('\u4E8C\u7EF4\u7801\u6709\u6548\u671F ' + this.loginQrSeconds + ' \u79D2').fontSize(12).fontColor('#858C94');
              }
              Button('\u5237\u65B0\u4E8C\u7EF4\u7801').height(40).onClick(() => { this.startQrLogin(); });
            }.alignItems(HorizontalAlign.Center).width('100%');
          } else {
            Text('\u4F7F\u7528 Cookie \u767B\u5F55').fontSize(23).fontWeight(FontWeight.Medium)
              .margin({ top: 28, bottom: 10 });
            TextInput({ placeholder: '\u7C98\u8D34 Cookie', text: this.loginCookie })
              .width('100%').height(110).fontSize(15)
              .backgroundColor('#F1F3F5').borderRadius(10).padding(12)
              .onChange((value: string) => { this.loginCookie = value; });
            Button('\u767B\u5F55')
              .type(ButtonType.ROUNDED_RECTANGLE).width(180).height(52).fontSize(18)
              .fontColor('#1677A8').backgroundColor(Color.Transparent)
              .border({ width: 1, color: '#1677A8' }).borderRadius(26)
              .onClick(() => { this.loginByCookie(); });
          }
          if (this.loginMode === 0 || this.loginMode === 1) {
            Button('\u6253\u5F00\u5B98\u65B9\u767B\u5F55')
              .type(ButtonType.ROUNDED_RECTANGLE).width(220).height(48)
              .fontColor('#1677A8').backgroundColor('#E9F4F8')
              .onClick(() => { this.openWebLogin(); });
          }          if (this.loginNotice !== '') {
            Text(this.loginNotice).fontSize(13).fontColor('#C51D2A')
              .textAlign(TextAlign.Center).width('100%');
          }
          Text('\u767B\u5F55\u51ED\u8BC1\u4EC5\u7528\u4E8E\u5F53\u524D\u5BA2\u6237\u7AEF\u4F1A\u8BDD\uFF0C\u63A5\u5165\u771F\u5B9E\u63A5\u53E3\u524D\u4E0D\u4F1A\u63D0\u4EA4\u6216\u4FDD\u5B58\u3002')
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
              this.topBubbleButton('\u76F4\u64AD', false, 62, () => { this.loadError = '\u76F4\u64AD\u7248\u5757\u8FC1\u79FB\u4E2D'; });
              this.topBubbleButton('\u63A8\u8350', true, 66, () => { this.activeTab = 1; this.loadError = ''; });
              this.topBubbleButton('\u70ED\u95E8', false, 62, () => { this.loadError = '\u70ED\u95E8\u7248\u5757\u8FC1\u79FB\u4E2D'; });
              Button() {
                Image($r('app.media.xiaoxi')).width(24).height(24);
              }
              .type(ButtonType.ROUNDED_RECTANGLE)
              .width(48).height(48)
              .backgroundColor('#FFFFFF')
              .borderRadius(24)
              .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
              .onClick(() => { this.sidebar = 2; });
            }
            .width('100%')
            .padding({ left: 10, right: 10, top: 10, bottom: 8 })
            .justifyContent(FlexAlign.SpaceBetween);
            Scroll() {
              Grid() {
                ForEach(this.videos, (item: VideoItem) => {
                  GridItem() { this.homeCard(item); }
                }, (item: VideoItem) => `${item.id}`);
              }
              .columnsTemplate('1fr 1fr')
              .columnsGap(8)
              .rowsGap(10)
              .padding({ left: 12, right: 12, bottom: 88 })
              .onScrollIndex((_first: number, last: number): void => {
                if (_first <= 0 || last < this.videos.length - 2) return;
                if (this.lastLoadTriggerLength === this.videos.length) return;
                this.lastLoadTriggerLength = this.videos.length;
                this.loadMoreRecommendations();
              });
            }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
          } else if (this.activeTab === 0) {
            Column({ space: 16 }) {
              Text('\u52A8\u6001').fontSize(26).fontWeight(FontWeight.Bold);
              Text('\u5173\u6CE8\u7684\u7528\u6237\u52A8\u6001\u5C06\u5728\u8FD9\u91CC\u663E\u793A').fontSize(15).fontColor('#8B9199');
              Button('\u5237\u65B0\u52A8\u6001').onClick(() => { this.loadError = '\u52A8\u6001\u63A5\u53E3\u8FC1\u79FB\u4E2D'; });
            }.justifyContent(FlexAlign.Center).layoutWeight(1).width('100%');
          } else {
            Column({ space: 16 }) {
              Text('\u756A\u5267').fontSize(26).fontWeight(FontWeight.Bold);
              Text('\u756A\u5267\u5185\u5BB9\u5C06\u5728\u8FD9\u91CC\u663E\u793A').fontSize(15).fontColor('#8B9199');
            }.justifyContent(FlexAlign.Center).layoutWeight(1).width('100%');
          }
          }.width('100%').height('100%').padding({ top: this.topInset }).backgroundColor('#F7F8FA');
          Row({ space: 10 }) {
            Row() {
              Button() {
                Column({ space: 2 }) {
                  Image($r('app.media.dontai')).width(this.activeTab === 0 ? 22 : 20)
                    .height(this.activeTab === 0 ? 22 : 20);
                  Text('\u52A8\u6001').fontSize(11)
                    .fontColor(this.activeTab === 0 ? '#1677A8' : '#3E4854')
                    .fontWeight(this.activeTab === 0 ? FontWeight.Bold : FontWeight.Normal);
                }.alignItems(HorizontalAlign.Center);
              }
              .type(ButtonType.ROUNDED_RECTANGLE).height(52).layoutWeight(1)
              .backgroundColor(Color.Transparent)
              .onClick(() => { this.activeTab = 0; this.loadError = ''; });
              Button() {
                Column({ space: 2 }) {
                  Image($r('app.media.home')).width(this.activeTab === 1 ? 22 : 20)
                    .height(this.activeTab === 1 ? 22 : 20);
                  Text('\u9996\u9875').fontSize(11)
                    .fontColor(this.activeTab === 1 ? '#1677A8' : '#3E4854')
                    .fontWeight(this.activeTab === 1 ? FontWeight.Bold : FontWeight.Normal);
                }.alignItems(HorizontalAlign.Center);
              }
              .type(ButtonType.ROUNDED_RECTANGLE).height(52).layoutWeight(1)
              .backgroundColor(Color.Transparent)
              .onClick(() => { this.activeTab = 1; this.loadError = ''; });
              Button() {
                Column({ space: 2 }) {
                  Image($r('app.media.fanju')).width(this.activeTab === 2 ? 22 : 20)
                    .height(this.activeTab === 2 ? 22 : 20);
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
            .backgroundColor('#FFFFFF').borderRadius(30)
            .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 });

            Row() {
              Button() {
                Image($r('app.media.ic_public_search_filled'))
                  .width(24).height(24);
              }
              .type(ButtonType.ROUNDED_RECTANGLE)
              .width(52).height(52)
              .backgroundColor('#FFFFFF')
              .borderRadius(26)
              .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
              .onClick(() => { this.searchExpanded = true; });
            }
            .width(58).height(58).justifyContent(FlexAlign.Center);
          }
          .width('94%').height(58)
          .position({ left: '3%', bottom: this.bottomInset + 2 })
          .zIndex(10);
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

      if (this.sidebar !== 0 && !this.showVertical && !this.searchExpanded) {
        Column() {
          if (this.sidebar === 1) {
            this.mineSidebar();
          } else {
            this.messageSidebar();
          }
        }
        .width('100%').height('100%')
        .backgroundColor('#F7F8FA')
        .transition({ type: TransitionType.Insert, opacity: 0.0 });
      }
      if (this.searchExpanded && !this.showVertical) {
        Column() {
          Row({ space: 8 }) {
            Button() {
              Image($r('app.media.fanhui_left')).width(24).height(24);
            }
            .type(ButtonType.ROUNDED_RECTANGLE).width(48).height(48)
            .backgroundColor('#FFFFFF')
            .borderRadius(24)
            .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
            .onClick(() => { this.searchExpanded = false; });
            Search({ placeholder: '搜索视频', value: this.searchText })
              .layoutWeight(1).height(48).backgroundColor(Color.White).borderRadius(24)
              .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
              .focusable(true)
              .defaultFocus(true)
              .onChange((value: string) => { this.searchText = value; });
          }
          .width('100%').padding({ left: 10, right: 10, top: this.topInset + 8, bottom: 8 });
        }
        .width('100%').height('100%')
        .alignItems(HorizontalAlign.Start)
        .backgroundColor('#F7F8FA');
      }
    }.width('100%').height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}