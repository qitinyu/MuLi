import { HdsNavDestination } from '@kit.UIDesignKit';
import { display, window, KeyboardAvoidMode } from '@kit.ArkUI';
import { audio } from '@kit.AudioKit';
import { common } from '@kit.AbilityKit';
import { BOTTOM_PAD_PHONE, PAGE_PADDING } from '../common/DesignSpec';
import { durationText, plainCount, pubTimeText } from '../common/Format';
import { AuthorStat, VideoCard, VideoDetail, VideoOpenParam, emptyVideoCard } from '../model/BiliModels';
import { VideoService } from '../services/VideoService';
import { VideoPlayer } from '../services/VideoPlayer';
import { RecommendService } from '../services/RecommendService';
import { PlayerPrefs } from '../services/PlayerPrefs';
import { CommentFeed, CommentService, SubReplyFeed, VideoComment } from '../services/CommentService';
import { ListFooter, StateView } from '../components/StateView';
import { LevelBadge } from '../components/LevelBadge';
import { PlayerSettingsPanel } from '../components/PlayerSettingsPanel';

const PLAYER_BAR_HEIGHT: number = 44;
const PLAYER_CTRL_HEIGHT: number = 46;
/** 工具行高度（紧接画布，配色与画布一致） */
const ACTION_BAR_HEIGHT: number = 50;
/** 控制条无操作后自动隐藏的时长 */
const CONTROL_HIDE_MS: number = 4000;
/** HUD 停留时长 */
const HUD_HIDE_MS: number = 900;
/** 左右滑动每一档对应的像素距离与毫秒数（每档 5s） */
const SEEK_STEP_VP: number = 60;
const SEEK_STEP_MS: number = 5000;
/** 滑动区域判定：左 35% 亮度 / 右 35% 音量，中间为盲区 */
const SIDE_ZONE_RATIO: number = 0.35;
/** 信息区三个版块：与 Tabs 下标一一对应（支持左右滑动切换） */
const TAB_KEYS: Array<string> = ['brief', 'comments', 'settings'];
/** 评论输入框的组件 id：打开浮层后按 id 申请焦点，弹出键盘 */
const COMPOSER_INPUT_ID: string = 'muli_composer_input';
/** 评论输入的表情面板：b 站是纯文本表情，插入后按 [名称] 显示 */
const COMPOSER_EMOJIS: Array<string> = [
  'doge', '妙啊', '支持', '微笑', '笑哭', '鼓掌', '点赞', '吃瓜',
  '惊讶', '委屈', '思考', '大笑', '大哭', '喜欢', '害羞', '生气',
  'ok', '爱心', '难过', '调皮'
];

/**
 * 视频二级播放页（V2.0.3），路由 name = 'video'。
 *
 * 结构要点：
 * - 画布 XComponent 只有一个实例，全屏 / 竖屏摆放都只改外层容器高度，绝不切 if 分支，
 *   否则 surface 重建会让播放进度归零（历史回归）。
 * - 控制条 4s 无操作自动隐藏；双击播放暂停、左右滑快进快退、左亮度右音量、长按倍速。
 * - 信息区去掉卡片，简介 / 评论 / 设置走底部工具行；中间按钮切「竖屏摆放模式」（视频铺满+信息浮层）。
 * - 右侧设置面板承载播放器偏好；弹幕相关仅占位，弹幕轨道未接入。
 */
@Component
export struct VideoPage {
  pathStack: NavPathStack | undefined = undefined;
  videoParam: VideoOpenParam = new VideoOpenParam('', 0, 0);
  @State detail: VideoDetail = new VideoDetail();
  @State loading: boolean = true;
  @State errorText: string = '';
  @State playError: string = '';
  @State playing: boolean = false;
  @State started: boolean = false;
  @State positionMs: number = 0;
  @State durationMs: number = 0;
  @State fullscreen: boolean = false;
  @State canvasHeight: number = 211;
  /** 竖屏摆放模式：视频铺满竖屏 + 信息浮层 */
  @State portraitMode: boolean = false;
  /** 控制条（返回 / 中央播放键 / 进度条）是否可见 */
  @State controlsVisible: boolean = true;
  /** 工具行当前选中的信息页：brief / comments / settings */
  @State infoTab: string = 'brief';
  /** 当前 Tabs 下标：与 infoTab 同步，支持左右滑动切换 */
  @State infoTabIndex: number = 0;
  /** 简介是否展开（参考图标题右侧箭头） */
  @State briefExpanded: boolean = false;
  /** 评论：按时间 / 按热度（2 = 时间，3 = 热度） */
  @State commentSort: number = CommentService.MODE_TIME;
  @State comments: Array<VideoComment> = [];
  @State commentsLoading: boolean = false;
  @State commentsError: string = '';
  @State commentTotal: number = 0;
  @State commentEnd: boolean = false;
  @State commentLoaded: boolean = false;
  /** 当前展开楼中楼的顶层评论 rpid（空 = 全部收起，一次只展开一条） */
  @State expandedRpid: string = '';
  /** 当前楼中楼已加载的子回复 */
  @State subComments: Array<VideoComment> = [];
  @State subLoading: boolean = false;
  @State subEnd: boolean = true;
  @State subTotal: number = 0;
  /** 评论输入浮层 */
  @State composerVisible: boolean = false;
  @State composerText: string = '';
  @State composerSending: boolean = false;
  /** 正在回复的目标昵称（空 = 发顶层评论） */
  @State composerTarget: string = '';
  /** 键盘实际高度（vp），仅用于判断键盘是否弹出 */
  @State keyboardH: number = 0;
  /** 输入卡需要自己上移的距离：扣掉系统已经让出的高度，避免「页面被顶一次 + 卡片再抬一次」 */
  @State kbOffset: number = 0;
  /** 底部手势条高度（vp）：键盘收起时卡片内容要让开 */
  @State bottomInset: number = 0;
  /** 状态栏高度（vp）：本页铺满全屏（画布压到状态栏下面），顶部控件要自己让开 */
  @State topInset: number = 0;
  /** 输入卡下方的工具面板：'' = 收起，'emoji' = 表情，'mention' = @ */
  @State composerPanel: string = '';
  /** TextArea 当前选区，插入表情 / @ 时按光标位置拼接 */
  @State selStart: number = -1;
  @State selEnd: number = -1;
  /** 播放页下方推荐列表 */
  @State recommendList: Array<VideoCard> = [];
  @State recommendLoading: boolean = false;
  /** 玩家偏好（设置面板通过 $prefs 双向绑定） */
  @State prefs: PlayerPrefs = new PlayerPrefs();
  /** 手势 HUD 文案 */
  @State hudText: string = '';
  @State hudVisible: boolean = false;
  /** 播完「停止推荐」时悬浮的推荐视频 */
  @State recommendCard: VideoCard = emptyVideoCard();
  @State showRecommendCard: boolean = false;

  /** 拖动进度条期间暂停跟随播放进度 */
  private dragging: boolean = false;
  private player: VideoPlayer = new VideoPlayer();
  private xController: XComponentController = new XComponentController();
  private scroller: Scroller = new Scroller();
  private commentScroller: Scroller = new Scroller();
  private settingsScroller: Scroller = new Scroller();
  private tabsController: TabsController = new TabsController();
  /** 评论游标（接口的 cursor.next，原样回传） */
  private commentCursor: string = '';
  /** 楼中楼：正在展开的 root 与页码 */
  private subRoot: string = '';
  private subPage: number = 1;
  /** 评论输入的目标：root 为空 = 顶层评论，否则回复楼中楼 */
  private composerRoot: string = '';
  private composerParent: string = '';
  private mainWin: window.Window | undefined = undefined;
  private keyboardWatcher: ((height: number) => void) | undefined = undefined;
  /** 页面根容器当前高度 / 键盘弹出前的基准高度（vp）：两者之差 = 系统已让出的高度 */
  private pageH: number = 0;
  private basePageH: number = 0;
  /** 当前是否已开启屏幕常亮（避免重复下发） */
  private keepOn: boolean = false;
  /** 播放失败是否已经自动重取过一次地址（避免无限重试） */
  private playRetried: boolean = false;
  private surfaceWatch: number = 0;
  private controlTimer: number = -1;
  private hudTimer: number = -1;
  /** 续播目标位置（prepared 后 seek 才有效） */
  private resumeMs: number = 0;
  /** 画布宽度 vp，用于判定左 / 右滑动区域 */
  private surfaceWidth: number = 360;

  // 手势状态
  private gestureMode: string = '';
  private seekBaseMs: number = 0;
  private seekPreviewMs: number = 0;
  private seekSteps: number = 0;
  private startBrightness: number = -1;
  private originalBrightness: number = -1;
  private startVolume: number = 8;
  private holdSpeedActive: boolean = false;

  aboutToAppear(): void {
    this.player.onStateChange = (state: string) => {
      this.playing = state === 'playing';
      // 播放中常亮，暂停 / 播完 / 出错立刻还系统默认，避免用户放着不动就永远不息屏
      this.setKeepScreenOn(state === 'playing');
      if (state === 'prepared') {
        this.started = true;
        if (this.resumeMs > 0) {
          this.player.seek(this.resumeMs);
          this.resumeMs = 0;
        }
      }
    };
    this.player.onProgress = (positionMs: number, durationMs: number) => {
      if (this.dragging) {
        return;
      }
      this.positionMs = positionMs;
      if (durationMs > 0) {
        this.durationMs = durationMs;
      }
    };
    this.player.onError = (message: string) => {
      this.playError = message;
      // CDN 直链带时效签名，偶尔首次拉到的地址已过期：自动重取一次，不必用户手点重试
      if (!this.playRetried && this.videoParam.cid > 0) {
        this.playRetried = true;
        setTimeout(() => {
          this.playError = '';
          this.loadPlayUrl();
        }, 400);
      }
    };
    this.player.onCompleted = () => {
      this.onPlayCompleted();
    };
    this.bindKeyboard();
    this.bootstrap();
  }

  /**
   * 监听键盘高度：输入卡要在键盘正上方。
   *
   * 这里不再「无条件上移键盘高度」——系统默认的 OFFSET 避让已经把整页顶上去一次，
   * 再叠一层 margin 就会把卡片顶到屏幕中间（中间空出一大块）。
   * 做法：先把本页切成 RESIZE 避让（页面被压矮，卡片自然贴住键盘），
   * 同时用「键盘高度 − 页面实际被压矮的高度」兜底——万一页面没被压矮，也能自己补足差额。
   */
  private bindKeyboard(): void {
    try {
      window.getLastWindow(this.context()).then((win: window.Window) => {
        this.mainWin = win;
        this.applyAvoidMode(KeyboardAvoidMode.RESIZE);
        this.readBottomInset(win);
        // 画布压到状态栏下面了，状态栏文字得用浅色
        this.applyStatusBarContent(win, true);
        this.keyboardWatcher = (height: number) => {
          this.keyboardH = height > 0 ? this.getUIContext().px2vp(height) : 0;
          this.syncKbOffset();
        };
        win.on('keyboardHeightChange', this.keyboardWatcher);
      }).catch(() => {
        // 拿不到窗口就保持原位，浮层仍在页面内
      });
    } catch (err) {
      console.warn(`MuLiVideo keyboard watch failed: ${String(err)}`);
    }
  }

  private applyAvoidMode(mode: KeyboardAvoidMode): void {
    try {
      this.getUIContext().setKeyboardAvoidMode(mode);
    } catch (err) {
      console.warn(`MuLiVideo setKeyboardAvoidMode failed: ${String(err)}`);
    }
  }

  /**
   * 状态栏文字 / 图标的明暗：本页画布压在状态栏下面，只有浅色图标看得清；
   * 退出页面还原成深色，别把其它浅色页面的状态栏弄成白字。
   */
  private applyStatusBarContent(win: window.Window, light: boolean): void {
    win.setWindowSystemBarProperties({ statusBarContentColor: light ? '#FFFFFF' : '#000000' })
      .catch((err: Error) => {
        console.warn(`MuLiVideo statusBarContent failed: ${err.message}`);
      });
  }

  /**
   * 播放期间保持屏幕常亮。
   * 之前只看视频不点屏幕，系统的休眠计时照样走，看到一半就黑屏；
   * 这里跟随播放状态开关，暂停与退出页面都会立即关闭，不会白耗电。
   */
  private setKeepScreenOn(on: boolean): void {
    if (this.keepOn === on) {
      return;
    }
    this.keepOn = on;
    const apply = (win: window.Window): void => {
      win.setWindowKeepScreenOn(on).catch((err: Error) => {
        console.warn(`MuLiVideo keepScreenOn=${on} failed: ${err.message}`);
      });
    };
    if (this.mainWin !== undefined) {
      apply(this.mainWin);
      return;
    }
    window.getLastWindow(this.context()).then(apply).catch(() => {
      // 拿不到窗口时忽略
    });
  }

  /**
   * 读底部手势条高度，键盘收起时输入卡内容要让开这一条；
   * 顺带读状态栏高度——本页已经铺到屏幕最上沿（画布压在状态栏下面），顶部控件得自己让开。
   */
  private readBottomInset(win: window.Window): void {
    try {
      const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.bottomInset = this.getUIContext().px2vp(area.bottomRect.height);
    } catch (err) {
      this.bottomInset = 0;
    }
    try {
      const sys: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = this.getUIContext().px2vp(sys.topRect.height);
    } catch (err) {
      this.topInset = 0;
    }
  }

  /** 页面根容器尺寸变化：键盘弹出（RESIZE）时会变小，用它算系统已经让出了多少 */
  private onPageResize(height: number): void {
    if (height > 0) {
      this.pageH = height;
    }
    this.syncKbOffset();
  }

  private syncKbOffset(): void {
    if (this.keyboardH <= 0) {
      // 键盘收起时的高度就是基准高度
      if (this.pageH > 0) {
        this.basePageH = this.pageH;
      }
      this.kbOffset = 0;
      return;
    }
    const shrunk: number = this.basePageH > 0 ? Math.max(0, this.basePageH - this.pageH) : 0;
    this.kbOffset = Math.max(0, this.keyboardH - shrunk);
  }

  private async bootstrap(): Promise<void> {
    this.syncCanvasSize();
    try {
      const ctx = this.context();
      this.prefs = await PlayerPrefs.load(ctx);
    } catch (err) {
      console.warn(`MuLiVideo prefs load ignored: ${String(err)}`);
    }
    await this.loadDetail();
    this.showControls();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 按屏幕宽度算出 16:9 的内嵌画布高度 */
  private syncCanvasSize(): void {
    try {
      const widthPx: number = display.getDefaultDisplaySync().width;
      const widthVp: number = this.getUIContext().px2vp(widthPx);
      this.canvasHeight = Math.round(widthVp * 9 / 16);
    } catch (err) {
      console.warn(`MuLiVideo sync canvas size failed: ${String(err)}`);
    }
  }

  aboutToDisappear(): void {
    if (this.controlTimer !== -1) {
      clearTimeout(this.controlTimer);
      this.controlTimer = -1;
    }
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
      this.hudTimer = -1;
    }
    if (this.prefs.continuePlay && this.videoParam.bvid.length > 0 && this.positionMs > 0) {
      PlayerPrefs.saveProgress(this.context(), this.videoParam.bvid, this.positionMs);
    }
    this.restoreBrightness();
    this.setKeepScreenOn(false);
    this.player.release();
    this.restorePortrait();
    // 退出本页把避让模式还原，避免影响其它页面（搜索页等）的默认弹起行为
    this.applyAvoidMode(KeyboardAvoidMode.OFFSET);
    if (this.mainWin !== undefined) {
      this.applyStatusBarContent(this.mainWin, false);
    }
    if (this.mainWin !== undefined && this.keyboardWatcher !== undefined) {
      try {
        this.mainWin.off('keyboardHeightChange', this.keyboardWatcher);
      } catch (err) {
        // 窗口已销毁时忽略
      }
    }
  }

  private async loadDetail(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    this.showRecommendCard = false;
    this.started = false;
    this.positionMs = 0;
    this.playError = '';
    this.playRetried = false;
    this.resetComments();
    try {
      const info: VideoDetail = await VideoService.detail(this.videoParam.bvid, this.videoParam.aid);
      this.detail = info;
      this.videoParam.bvid = info.bvid;
      this.videoParam.aid = info.aid;
      if (info.cid > 0) {
        this.videoParam.cid = info.cid;
      }
      if (this.prefs.continuePlay) {
        this.resumeMs = await PlayerPrefs.loadProgress(this.context(), this.videoParam.bvid);
      }
      this.loading = false;
      await this.loadPlayUrl();
      // 作者粉丝/投稿与推荐列表都是「补充信息」，异步加载、失败静默，不能拖慢起播
      this.loadAuthorStat(info.authorMid);
      this.loadRecommendList(info.bvid);
      // 连播 / 换集时若正停在评论版块，评论已随 resetComments 清空，这里补一次首屏
      if (this.infoTabIndex === 1 && !this.commentLoaded) {
        this.loadComments(true);
      }
    } catch (err) {
      this.loading = false;
      this.errorText = err instanceof Error ? err.message : '视频信息加载失败';
    }
  }

  private async loadPlayUrl(): Promise<void> {
    try {
      const url: string = await VideoService.playUrl(
        this.videoParam.bvid, this.videoParam.cid, this.videoParam.aid, this.prefs.quality);
      await this.player.setSource(url);
      // XComponent 的 onLoad 在部分机型/时序下不触发，这里补一个兜底轮询
      this.waitForSurface();
    } catch (err) {
      this.playError = err instanceof Error ? err.message : '播放地址获取失败';
    }
  }

  /** 作者粉丝 / 投稿：拉取失败只留空，不影响页面其它内容 */
  private async loadAuthorStat(mid: number): Promise<void> {
    try {
      const stat: AuthorStat = await VideoService.authorStat(mid);
      if (stat.followerText.length === 0 && stat.archiveText.length === 0) {
        return;
      }
      const next: VideoDetail = this.detail.clone();
      next.followerText = stat.followerText;
      next.archiveText = stat.archiveText;
      this.detail = next;
    } catch (err) {
      console.warn(`MuLiVideo author stat ignored: ${String(err)}`);
    }
  }

  /** 播放页下方推荐列表：过滤当前视频，最多 8 条 */
  private async loadRecommendList(bvid: string): Promise<void> {
    this.recommendLoading = true;
    try {
      const cards: Array<VideoCard> = await RecommendService.load(Math.floor(Math.random() * 50) + 2);
      const list: Array<VideoCard> = [];
      for (let i = 0; i < cards.length; i++) {
        if (cards[i].bvid.length > 0 && cards[i].bvid !== bvid) {
          list.push(cards[i]);
        }
        if (list.length >= 8) {
          break;
        }
      }
      this.recommendList = list;
    } catch (err) {
      this.recommendList = [];
      console.warn(`MuLiVideo recommend list failed: ${String(err)}`);
    }
    this.recommendLoading = false;
  }

  // ---------------- 评论 ----------------

  /** 换视频时清空评论，回到第一页 */
  private resetComments(): void {
    this.comments = [];
    this.commentCursor = '';
    this.commentEnd = false;
    this.commentLoaded = false;
    this.commentTotal = 0;
    this.commentsError = '';
    this.collapseSub();
    this.closeComposer();
  }

  // ---------------- 楼中楼 ----------------

  /** 收起楼中楼 */
  private collapseSub(): void {
    this.expandedRpid = '';
    this.subRoot = '';
    this.subComments = [];
    this.subTotal = 0;
    this.subPage = 1;
    this.subEnd = true;
    this.subLoading = false;
  }

  /**
   * 展开 / 收起某条评论的楼中楼。
   * 展开时先用 reply/main 自带的预览顶上（避免空白等待），再拉第一页完整数据覆盖。
   */
  private toggleSub(item: VideoComment): void {
    if (this.expandedRpid === item.rpid) {
      this.collapseSub();
      return;
    }
    this.expandedRpid = item.rpid;
    this.subRoot = item.rpid;
    this.subPage = 1;
    this.subTotal = item.rcount;
    this.subEnd = false;
    this.subLoading = false;
    // 预览先上，接口回来再覆盖；预览里父级昵称同样需要解析
    const preview: Array<VideoComment> = item.preview.slice();
    CommentService.resolveReplyTargets(preview, item);
    this.subComments = preview;
    this.loadSub(true);
  }

  /** 载入楼中楼：reset = true 回到第 1 页，否则续接下一页 */
  private async loadSub(reset: boolean): Promise<void> {
    if (this.subLoading || this.subRoot.length === 0) {
      return;
    }
    if (!reset && this.subEnd) {
      return;
    }
    const rootRpid: string = this.subRoot;
    const nextPage: number = reset ? 1 : this.subPage + 1;
    this.subLoading = true;
    try {
      const feed: SubReplyFeed = await CommentService.subList(this.detail.aid, rootRpid, nextPage);
      // 请求期间用户可能已切到别的楼层：丢弃过期响应
      if (this.subRoot !== rootRpid) {
        return;
      }
      const items: Array<VideoComment> = CommentService.markUpper(feed.items, this.detail.authorMid);
      // 父评论可能在上一条楼层或更后面，这里把本楼层已知的 rpid -> 昵称补全
      const root: VideoComment | undefined = this.comments.find((c: VideoComment) => c.rpid === rootRpid);
      if (root !== undefined) {
        CommentService.resolveReplyTargets(items, root);
      }
      if (reset) {
        this.subComments = items;
      } else {
        const merged: Array<VideoComment> = this.subComments.slice();
        for (let i = 0; i < items.length; i++) {
          merged.push(items[i]);
        }
        this.subComments = merged;
      }
      if (feed.total > 0) {
        this.subTotal = feed.total;
      }
      this.subPage = nextPage;
      this.subEnd = !feed.hasMore;
    } catch (err) {
      if (reset && this.subComments.length === 0) {
        this.toast(err instanceof Error ? err.message : '回复加载失败');
      }
      this.subEnd = true;
    } finally {
      this.subLoading = false;
    }
  }

  /** 刷新当前楼中楼（回复成功后用） */
  private refreshSub(): void {
    if (this.subRoot.length === 0) {
      return;
    }
    this.subPage = 1;
    this.subEnd = false;
    this.loadSub(true);
  }

  // ---------------- 评论输入 ----------------

  /** 打开输入浮层：target 为空 = 发顶层评论 */
  private openComposer(root: string, parent: string, target: string): void {
    this.composerRoot = root;
    this.composerParent = parent;
    this.composerTarget = target;
    this.composerText = '';
    this.composerPanel = '';
    this.composerVisible = true;
    // 卡片是这一帧才创建的，等挂载后把焦点送进去，键盘才会随之弹出（defaultFocus 在动态浮层里不生效）
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(COMPOSER_INPUT_ID);
      } catch (err) {
        // 焦点申请失败不影响手动点输入框
      }
    }, 120);
  }

  private closeComposer(): void {
    this.composerVisible = false;
    this.composerText = '';
    this.composerTarget = '';
    this.composerRoot = '';
    this.composerParent = '';
    this.composerPanel = '';
    this.selStart = -1;
    this.selEnd = -1;
  }

  /** 打开 / 收起输入框下方的工具面板（表情、@）；打开面板时先收键盘，面板才不会和键盘抢位置 */
  private toggleComposerPanel(panel: string): void {
    if (this.composerPanel === panel) {
      this.composerPanel = '';
      return;
    }
    this.composerPanel = panel;
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (err) {
      // 取不到焦点控制器时忽略，面板照样展示
    }
  }

  /** 按光标位置插入片段（表情 / @），没有光标就追加到末尾 */
  private insertChunk(chunk: string): void {
    const text: string = this.composerText;
    const hasSel: boolean = this.selStart >= 0 && this.selStart <= text.length;
    const from: number = hasSel ? this.selStart : text.length;
    const to: number = hasSel && this.selEnd >= this.selStart ? Math.min(this.selEnd, text.length) : from;
    this.composerText = text.substring(0, from) + chunk + text.substring(to);
    this.selStart = from + chunk.length;
    this.selEnd = this.selStart;
  }

  /** @ 面板候选：UP 主 + 当前已加载评论的作者，去重后取前 12 个 */
  private mentionNames(): Array<string> {
    const out: Array<string> = [];
    const push = (name: string): void => {
      if (name.length > 0 && out.indexOf(name) < 0 && out.length < 12) {
        out.push(name);
      }
    };
    push(this.detail.authorName);
    for (let i = 0; i < this.comments.length; i++) {
      push(this.comments[i].name);
    }
    return out;
  }

  private async sendComment(): Promise<void> {
    const text: string = this.composerText.trim();
    if (text.length === 0) {
      this.toast('先说点什么吧');
      return;
    }
    if (this.composerSending) {
      return;
    }
    this.composerSending = true;
    try {
      await CommentService.post(this.detail.aid, text, this.composerRoot, this.composerParent);
      const isReply: boolean = this.composerRoot.length > 0;
      this.closeComposer();
      this.toast(isReply ? '回复已发布' : '评论已发布');
      if (isReply) {
        const rpid: string = this.composerRoot;
        this.refreshSub();
        // 回复数 +1，让「共 N 条回复」立刻变化
        for (let i = 0; i < this.comments.length; i++) {
          if (this.comments[i].rpid === rpid) {
            this.comments[i].rcount = this.comments[i].rcount + 1;
          }
        }
        this.comments = this.comments.slice();
      } else {
        this.resetComments();
        this.loadComments(true);
      }
    } catch (err) {
      this.toast(err instanceof Error ? err.message : '发布失败');
    } finally {
      this.composerSending = false;
    }
  }

  /** 载入评论：reset = true 从第一页重来，否则续接游标 */
  private async loadComments(reset: boolean): Promise<void> {
    if (this.commentsLoading) {
      return;
    }
    if (!reset && this.commentEnd) {
      return;
    }
    this.commentsLoading = true;
    this.commentsError = '';
    try {
      const feed: CommentFeed = await CommentService.list(
        this.detail.aid, this.commentSort, reset ? '' : this.commentCursor);
      const items: Array<VideoComment> = CommentService.markUpper(feed.items, this.detail.authorMid);
      if (feed.total > 0) {
        this.commentTotal = feed.total;
      }
      this.commentCursor = feed.cursor;
      this.commentEnd = feed.isEnd || feed.items.length === 0;
      if (reset) {
        this.comments = items;
      } else {
        const merged: Array<VideoComment> = this.comments.slice();
        for (let i = 0; i < items.length; i++) {
          merged.push(items[i]);
        }
        this.comments = merged;
      }
    } catch (err) {
      this.commentsError = err instanceof Error ? err.message : '评论加载失败';
    } finally {
      this.commentsLoading = false;
      this.commentLoaded = true;
    }
  }

  /** 切换排序方式：换到新排序时重新从第一页拉取 */
  private switchSort(sort: number): void {
    if (this.commentSort === sort) {
      return;
    }
    this.commentSort = sort;
    this.resetComments();
    this.loadComments(true);
  }

  /** 工具行 / 滑动切换三版块：两者都改 tabIndex，保证文字高亮与 Tabs 同步 */
  private switchTab(index: number): void {
    const clamped: number = index < 0 ? 0 : (index > 2 ? 2 : index);
    if (this.infoTabIndex === clamped) {
      return;
    }
    this.infoTabIndex = clamped;
    this.infoTab = TAB_KEYS[clamped];
    try {
      this.tabsController.changeIndex(clamped);
    } catch (err) {
      // Tabs 尚未挂载时忽略
    }
    if (clamped === 1 && !this.commentLoaded) {
      this.loadComments(true);
    }
  }

  private onTabChanged(index: number): void {
    if (index === this.infoTabIndex && this.infoTab === TAB_KEYS[index]) {
      return;
    }
    this.infoTabIndex = index;
    this.infoTab = TAB_KEYS[index];
    if (index === 1 && !this.commentLoaded) {
      this.loadComments(true);
    }
  }

  /** 换视频后回到「简介」版块 */
  private resetTab(): void {
    this.infoTabIndex = 0;
    this.infoTab = TAB_KEYS[0];
    try {
      this.tabsController.changeIndex(0);
    } catch (err) {
      // Tabs 未挂载（加载中）时忽略
    }
  }

  /** 评论数：接口拿到总数用它，否则退回视频详情里的文案 */
  private commentCountText(): string {
    if (this.commentTotal > 0) {
      return plainCount(this.commentTotal);
    }
    const text: string = this.detail.replyText;
    return text.length > 0 ? text : '0';
  }

  private onSurfaceReady(): void {
    const surfaceId: string = this.xController.getXComponentSurfaceId();
    if (surfaceId.length === 0) {
      this.waitForSurface();
      return;
    }
    this.player.attachSurface(surfaceId);
  }

  /** 兜底：每 100ms 试取一次 surfaceId，最多 30 次（约 3 秒） */
  private waitForSurface(): void {
    if (this.surfaceWatch >= 30) {
      return;
    }
    this.surfaceWatch += 1;
    setTimeout(() => {
      const surfaceId: string = this.xController.getXComponentSurfaceId();
      if (surfaceId.length > 0) {
        this.player.attachSurface(surfaceId);
      } else {
        this.waitForSurface();
      }
    }, 100);
  }

  private async togglePlay(): Promise<void> {
    if (this.playError.length === 0) {
      await this.player.toggle();
      this.showControls();
    }
  }

  private formatMs(ms: number): string {
    const total: number = Math.floor(ms / 1000);
    return durationText(total);
  }

  /** 控制条：显示并重置自动隐藏计时。手势 / 点按都会调用 */
  private showControls(): void {
    this.controlsVisible = true;
    if (this.controlTimer !== -1) {
      clearTimeout(this.controlTimer);
    }
    this.controlTimer = setTimeout(() => {
      // 拖动 / 长按 / 滑动中不隐藏
      if (!this.dragging && this.gestureMode.length === 0 && !this.holdSpeedActive) {
        this.controlsVisible = false;
      }
      this.controlTimer = -1;
    }, CONTROL_HIDE_MS);
  }

  private toggleControls(): void {
    if (this.controlsVisible) {
      if (this.controlTimer !== -1) {
        clearTimeout(this.controlTimer);
        this.controlTimer = -1;
      }
      this.controlsVisible = false;
    } else {
      this.showControls();
    }
  }

  private showHud(text: string): void {
    this.hudText = text;
    this.hudVisible = true;
    if (this.hudTimer !== -1) {
      clearTimeout(this.hudTimer);
    }
    this.hudTimer = setTimeout(() => {
      this.hudVisible = false;
      this.hudTimer = -1;
    }, HUD_HIDE_MS);
  }

  private async enterFullscreen(): Promise<void> {
    this.fullscreen = true;
    try {
      const win: window.Window = await window.getLastWindow(this.context());
      await win.setPreferredOrientation(window.Orientation.LANDSCAPE);
      await win.setWindowSystemBarEnable([]);
    } catch (err) {
      console.warn(`MuLiVideo fullscreen failed: ${String(err)}`);
    }
  }

  private async restorePortrait(): Promise<void> {
    if (!this.fullscreen) {
      return;
    }
    this.fullscreen = false;
    try {
      const win: window.Window = await window.getLastWindow(this.context());
      await win.setWindowSystemBarEnable(['status']);
      await win.setPreferredOrientation(window.Orientation.PORTRAIT);
    } catch (err) {
      console.warn(`MuLiVideo restore failed: ${String(err)}`);
    }
    setTimeout(() => {
      this.syncCanvasSize();
    }, 320);
  }

  private onBack(): void {
    if (this.fullscreen) {
      this.restorePortrait();
      return;
    }
    if (this.portraitMode) {
      this.portraitMode = false;
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

  // ---------------- 手势：亮度 / 音量 / 快进快退 / 长按倍速 ----------------

  private gestureZone(event: GestureEvent): string {
    const localX: number = event.fingerList.length > 0 ? event.fingerList[0].localX : this.surfaceWidth / 2;
    const bound: number = this.surfaceWidth * SIDE_ZONE_RATIO;
    if (localX < bound) {
      return 'brightness';
    }
    if (localX > this.surfaceWidth - bound) {
      return 'volume';
    }
    return 'center';
  }

  private async onVerticalStart(event: GestureEvent): Promise<void> {
    if (!this.prefs.quickGestures) {
      return;
    }
    this.gestureMode = this.gestureZone(event);
    try {
      const manager: audio.AudioManager = audio.getAudioManager();
      this.startVolume = await manager.getVolume(audio.AudioVolumeType.MEDIA);
    } catch (err) {
      this.startVolume = 8;
    }
    try {
      const win: window.Window = await window.getLastWindow(this.context());
      const brightness: number = win.getWindowProperties().brightness;
      if (brightness > 0) {
        this.startBrightness = brightness;
        if (this.originalBrightness < 0) {
          this.originalBrightness = brightness;
        }
      }
    } catch (err) {
      this.startBrightness = 0.5;
    }
    this.showControls();
  }

  private async onVerticalUpdate(event: GestureEvent): Promise<void> {
    if (!this.prefs.quickGestures || this.gestureMode.length === 0 || this.gestureMode === 'center') {
      return;
    }
    const dy: number = event.offsetY;
    if (this.gestureMode === 'brightness') {
      const brightness: number = Math.max(0.05, Math.min(1, this.startBrightness - dy / 500));
      try {
        const win: window.Window = await window.getLastWindow(this.context());
        await win.setWindowBrightness(brightness);
      } catch (err) {
        // 部分设备不允许改窗口亮度
      }
      this.showHud(`亮度 ${Math.round(brightness * 100)}%`);
    } else if (this.gestureMode === 'volume') {
      const manager: audio.AudioManager = audio.getAudioManager();
      const maxVolume: number = await manager.getMaxVolume(audio.AudioVolumeType.MEDIA);
      const ceiling: number = maxVolume > 0 ? maxVolume : 15;
      const volume: number = Math.max(0, Math.min(ceiling,
        Math.round(this.startVolume - dy / 500 * ceiling)));
      try {
        await manager.setVolume(audio.AudioVolumeType.MEDIA, volume);
      } catch (err) {
        // 忽略
      }
      this.showHud(`音量 ${volume}/${ceiling}`);
    }
  }

  private onVerticalEnd(): void {
    this.gestureMode = '';
    this.showControls();
  }

  private restoreBrightness(): void {
    if (this.originalBrightness < 0) {
      return;
    }
    const brightness: number = this.originalBrightness;
    this.originalBrightness = -1;
    window.getLastWindow(this.context()).then((win: window.Window): void => {
      win.setWindowBrightness(brightness).catch((): void => {
        // 忽略
      });
    }).catch((): void => {
      // 忽略
    });
  }

  /** 左右滑动：每 60vp 一档 5s，松手（离开屏幕）才真正跳转 */
  private onSeekStart(): void {
    if (!this.prefs.quickGestures) {
      return;
    }
    this.gestureMode = 'seek';
    this.seekBaseMs = this.positionMs;
    this.seekPreviewMs = this.positionMs;
    this.seekSteps = 0;
    this.showControls();
  }

  private onSeekUpdate(event: GestureEvent): void {
    if (!this.prefs.quickGestures || this.gestureMode !== 'seek') {
      return;
    }
    const steps: number = Math.trunc(event.offsetX / SEEK_STEP_VP);
    if (steps === this.seekSteps) {
      return;
    }
    this.seekSteps = steps;
    const duration: number = this.durationMs;
    this.seekPreviewMs = Math.max(0, Math.min(
      this.seekBaseMs + steps * SEEK_STEP_MS, duration > 0 ? duration : this.seekBaseMs + steps * SEEK_STEP_MS));
    const forward: boolean = steps > 0;
    this.showHud(`${forward ? '快进' : '快退'} ${this.formatMs(Math.abs(steps * SEEK_STEP_MS))}`);
  }

  private onSeekEnd(): void {
    if (this.gestureMode === 'seek') {
      if (this.seekSteps !== 0) {
        this.player.seek(this.seekPreviewMs);
        this.positionMs = this.seekPreviewMs;
      }
      this.showControls();
    }
    this.gestureMode = '';
  }

  /** 长按：用设置里的默认倍速播放，松手恢复原倍速 */
  private onHoldSpeed(): void {
    if (!this.prefs.quickGestures || !this.started) {
      return;
    }
    if (!this.holdSpeedActive) {
      this.holdSpeedActive = true;
      this.player.setSpeed(this.prefs.longPressSpeed);
      this.showHud(`${this.prefs.longPressSpeed.toFixed(2)}x 倍速播放`);
    }
  }

  private onHoldSpeedEnd(): void {
    if (this.holdSpeedActive) {
      this.holdSpeedActive = false;
      this.player.setSpeed(1);
    }
  }

  // ---------------- 播放模式：循环 / 随机连播 / 停止推荐 ----------------

  private onPlayCompleted(): void {
    const mode: number = this.prefs.playMode;
    if (mode === 0) {
      this.player.seek(0);
      this.player.play();
      this.showHud('单集循环');
    } else if (mode === 1) {
      this.playRandomNext();
    } else {
      this.showRecommendCard = true;
      this.loadRecommendCard();
    }
  }

  private async loadRecommendCard(): Promise<void> {
    try {
      const cards: Array<VideoCard> = await RecommendService.load(Math.floor(Math.random() * 50) + 2);
      let picked: VideoCard | null = null;
      for (let i = 0; i < cards.length; i++) {
        if (cards[i].bvid.length > 0 && cards[i].bvid !== this.videoParam.bvid) {
          picked = cards[i];
          break;
        }
      }
      if (picked !== null) {
        this.recommendCard = picked;
      }
    } catch (err) {
      console.warn(`MuLiVideo recommend card failed: ${String(err)}`);
    }
  }

  private async playRandomNext(): Promise<void> {
    try {
      const cards: Array<VideoCard> = await RecommendService.load(Math.floor(Math.random() * 50) + 2);
      const picked: VideoCard | null = cards.length > 0 ? cards[Math.floor(Math.random() * cards.length)] : null;
      if (picked === null || picked.bvid.length === 0) {
        this.toast('暂无可连播的推荐视频');
        return;
      }
      this.videoParam = new VideoOpenParam(picked.bvid, picked.aid, picked.cid);
      this.holdSpeedActive = false;
      await this.loadDetail();
    } catch (err) {
      this.toast('连播加载失败，请重试');
    }
  }

  /** 点击推荐卡：换源重载并回到内容顶部 */
  private openCard(card: VideoCard): void {
    if (card.bvid.length === 0) {
      return;
    }
    this.briefExpanded = false;
    this.resetTab();
    this.holdSpeedActive = false;
    this.videoParam = new VideoOpenParam(card.bvid, card.aid, card.cid);
    this.loadDetail();
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  private async onSettingsChanged(key: string, value: number | boolean): Promise<void> {
    if (key === 'quality') {
      this.showHud('清晰度已切换，正在重载');
      await this.loadPlayUrl();
    } else if (key === 'longPressSpeed' && typeof value === 'number') {
      this.showHud(`长按倍速 ${value.toFixed(2)}x`);
    }
    this.showControls();
  }

  // ---------------- UI ----------------

  @Builder
  topBar() {
    Row() {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_backward'))
          .fontSize(20)
          .fontColor([$r('app.color.text_on_media')])
      }
      .width(34)
      .height(34)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.scrim'))
      .borderRadius(17)
      .onClick(() => {
        this.onBack();
      })

      Text(this.detail.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_on_media'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ left: 8 })
    }
    .width('100%')
    .height(PLAYER_BAR_HEIGHT + this.topSafe())
    // 画布压到状态栏下面了，返回键与标题要让开状态栏，否则会和时间 / 电量挤在一行
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 4 + this.topSafe() })
    .alignItems(VerticalAlign.Center)
  }

  /** 状态栏占位：全屏时系统栏已隐藏，不需要再让 */
  private topSafe(): number {
    return this.fullscreen ? 0 : this.topInset;
  }

  @Builder
  bottomBar() {
    Row({ space: 8 }) {
      Text(this.formatMs(this.positionMs))
        .fontSize(11)
        .fontColor($r('app.color.text_on_media'))
      Slider({
        value: this.positionMs,
        min: 0,
        max: this.durationMs > 0 ? this.durationMs : 1,
        style: SliderStyle.OutSet
      })
        .selectedColor($r('app.color.brand_primary'))
        .trackColor($r('app.color.overlay'))
        .blockColor($r('app.color.text_on_media'))
        .trackThickness(2)
        .layoutWeight(1)
        .onChange((value: number, mode: SliderChangeMode) => {
          this.dragging = mode !== SliderChangeMode.End;
          this.positionMs = value;
          if (mode === SliderChangeMode.End) {
            this.player.seek(value);
            this.showControls();
          }
        })
      Text(this.formatMs(this.durationMs))
        .fontSize(11)
        .fontColor($r('app.color.text_on_media'))
      SymbolGlyph(this.fullscreen || this.portraitMode
        ? $r('sys.symbol.arrow_down_right_and_arrow_up_left')
        : $r('sys.symbol.arrow_up_left_and_arrow_down_right'))
        .fontSize(17)
        .fontColor([$r('app.color.text_on_media')])
        .onClick(() => {
          if (this.fullscreen) {
            this.restorePortrait();
          } else if (this.portraitMode) {
            this.portraitMode = false;
            this.syncCanvasSize();
          } else {
            this.enterFullscreen();
          }
        })
    }
    .width('100%')
    .height(PLAYER_CTRL_HEIGHT)
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
    .alignItems(VerticalAlign.Center)
  }

  /** 画布 + 叠层控制（尺寸由外层决定，竖屏 16:9 / 竖屏摆放铺满 / 全屏铺满） */
  @Builder
  playerLayer() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({
        id: 'muli_video_canvas',
        type: XComponentType.SURFACE,
        controller: this.xController
      })
        .width('100%')
        .height('100%')
        .onLoad(() => {
          this.onSurfaceReady();
        })

      // 画布首帧之前用封面占位，避免黑屏。
      // 这里用 Contain 而不是 Cover：b 站封面多是 16:10，Cover 会上下裁掉一截，
      // 叠在底部工具行上方时看起来就像「视频被白条盖住了」。
      if (!this.started || this.playError.length > 0) {
        Image(this.detail.cover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .alt($r('app.color.bg_field'))
          .draggable(false)
      }

      if (this.playError.length > 0) {
        Column({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(26)
            .fontColor([$r('app.color.text_on_media')])
          Text(this.playError)
            .fontSize(12)
            .fontColor($r('app.color.text_on_media'))
          Text('点击重试')
            .fontSize(12)
            .fontColor($r('app.color.brand_primary'))
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.scrim'))
            .borderRadius(14)
            .onClick(() => {
              this.playError = '';
              this.loadPlayUrl();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.scrim'))
      }

      // 控制层：4s 无操作自动隐藏
      if (this.controlsVisible) {
        Column() {
          this.topBar()

          Column() {
            if (!this.playing && this.playError.length === 0 && !this.loading) {
              SymbolGlyph($r('sys.symbol.play_circle_fill'))
                .fontSize(54)
                .fontColor([$r('app.color.text_on_media')])
            }
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.togglePlay();
          })

          if (this.started) {
            this.bottomBar()
          } else {
            Row()
              .width('100%')
              .height(PLAYER_CTRL_HEIGHT)
          }
        }
        .width('100%')
        .height('100%')
        .transition({ type: TransitionType.Insert, opacity: 0 })
        .transition({ type: TransitionType.Delete, opacity: 0 })
      }

      // 迷你进度条：控制条隐藏时仍保留一条细线
      if (!this.controlsVisible && this.prefs.miniProgress && this.started) {
        Progress({
          value: this.positionMs,
          total: this.durationMs > 0 ? this.durationMs : 1,
          type: ProgressType.Linear
        })
          .width('100%')
          .height(2)
          .color($r('app.color.brand_primary'))
          .backgroundColor($r('app.color.overlay'))
          .align(Alignment.Bottom)
      }

      // 手势 HUD
      if (this.hudVisible) {
        Row() {
          Text(this.hudText)
            .fontSize(13)
            .fontColor($r('app.color.text_on_media'))
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        }
        .backgroundColor($r('app.color.scrim'))
        .borderRadius(16)
      }

      // 播完「停止推荐」悬浮卡
      if (this.showRecommendCard && this.recommendCard.bvid.length > 0) {
        Column({ space: 10 }) {
          Text('为你推荐')
            .fontSize(12)
            .fontColor($r('app.color.text_on_media'))
          Row({ space: 10 }) {
            Image(this.recommendCard.cover)
              .width(104)
              .height(60)
              .objectFit(ImageFit.Cover)
              .borderRadius(6)
              .alt($r('app.color.bg_field'))
            Text(this.recommendCard.title)
              .fontSize(13)
              .fontColor($r('app.color.text_on_media'))
              .maxLines(3)
              .layoutWeight(1)
          }
          .width('100%')
          Text('点击播放')
            .fontSize(12)
            .fontColor($r('app.color.text_on_media'))
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.brand_primary'))
            .borderRadius(14)
            .onClick(() => {
              this.videoParam = new VideoOpenParam(
                this.recommendCard.bvid, this.recommendCard.aid, this.recommendCard.cid);
              this.playRandomNext();
            })
        }
        .width('72%')
        .padding(14)
        .backgroundColor($r('app.color.scrim'))
        .borderRadius(12)
      }
    }
    .width('100%')
    .height('100%')
    // 手势组：单击显示/隐藏控制条，双击播放暂停（Exclusive 避免互相抢占）
    .gesture(GestureGroup(GestureMode.Exclusive,
      TapGesture({ count: 2 }).onAction(() => {
        this.togglePlay();
      }),
      TapGesture().onAction(() => {
        this.toggleControls();
      })
    ))
    // 水平：快进快退（每档 5s，松手跳转）
    .gesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 20 })
      .onActionStart(() => {
        this.onSeekStart();
      })
      .onActionUpdate((event: GestureEvent) => {
        this.onSeekUpdate(event);
      })
      .onActionEnd(() => {
        this.onSeekEnd();
      }))
    // 垂直：左侧亮度 / 右侧音量
    .gesture(PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 20 })
      .onActionStart((event: GestureEvent) => {
        this.onVerticalStart(event);
      })
      .onActionUpdate((event: GestureEvent) => {
        this.onVerticalUpdate(event);
      })
      .onActionEnd(() => {
        this.onVerticalEnd();
      }))
    // 长按：加速播放
    .gesture(LongPressGesture({ repeat: true, duration: 500 })
      .onAction(() => {
        this.onHoldSpeed();
      })
      .onActionEnd(() => {
        this.onHoldSpeedEnd();
      }))
  }

  /** 工具行的页签文字：选中态用品牌色 + 加粗，与参考图一致 */
  @Builder
  infoTabText(label: string, key: string, index: number) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.infoTab === key ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.infoTab === key ? $r('app.color.brand_primary') : $r('app.color.text_secondary'))
      .onClick(() => {
        this.switchTab(index);
      })
  }

  /** 工具行：简介 / 评论 / 设置靠左 · 中间竖屏摆放切换 · 右侧弹幕输入与开关占位 */
  @Builder
  actionBar() {
    Row() {
      Row({ space: 18 }) {
        this.infoTabText('简介', 'brief', 0)
        this.infoTabText('评论', 'comments', 1)
        this.infoTabText('设置', 'settings', 2)
      }

      Blank().layoutWeight(1)

      // 中间的竖屏摆放模式切换（参考图里的「≡」按钮）
      Row() {
        SymbolGlyph($r('sys.symbol.line_3_horizontal'))
          .fontSize(16)
          .fontColor([$r('app.color.text_secondary')])
      }
      .width(30)
      .height(30)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.bg_field'))
      .borderRadius(15)
      .margin({ right: 10 })
      .onClick(() => {
        this.portraitMode = !this.portraitMode;
        setTimeout(() => {
          this.syncCanvasSize();
        }, 60);
      })

      // 右侧：弹幕输入占位 + 弹幕开关
      Row({ space: 6 }) {
        Row() {
          Text('发一条弹幕')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .height(30)
        .layoutWeight(1)
        .padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.bg_field'))
        .borderRadius(15)
        .onClick(() => {
          this.toast('弹幕发送待接入');
        })

        SymbolGlyph($r('sys.symbol.waveform_bubble'))
          .fontSize(16)
          .fontColor([this.prefs.danmakuOn
            ? $r('app.color.brand_primary') : $r('app.color.text_tertiary')])
          .onClick(() => {
            this.prefs.danmakuOn = !this.prefs.danmakuOn;
            this.prefs.save(this.context(), 'danmakuOn', this.prefs.danmakuOn);
            this.toast(this.prefs.danmakuOn ? '弹幕显示已开启（占位）' : '弹幕显示已关闭（占位）');
          })
      }
      .width(170)
    }
    .width('100%')
    .height(ACTION_BAR_HEIGHT)
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
    .alignItems(VerticalAlign.Center)
    // 用页面底色而不是纯白：纯白条紧贴视频下沿时，看起来像一层白膜盖住了画面
    .backgroundColor($r('app.color.bg_page'))
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  /** service 层的计数带「播放 / 弹幕」后缀，参考图只要数字 */
  private bareCount(text: string): string {
    return text.replace('播放', '').replace('弹幕', '');
  }

  private two(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }

  /** 参考图的绝对发布时间：2026-11-21 11:47 */
  private publishAbsolute(ts: number): string {
    if (!Number.isFinite(ts) || ts <= 0) {
      return '';
    }
    const date: Date = new Date(Math.floor(ts) * 1000);
    return `${date.getFullYear()}-${this.two(date.getMonth() + 1)}-${this.two(date.getDate())}`
      + ` ${this.two(date.getHours())}:${this.two(date.getMinutes())}`;
  }

  /** 作者副标题：粉丝 / 投稿（接口没拿到就退回评论数，避免出现空行） */
  private authorSubText(): string {
    const parts: Array<string> = [];
    if (this.detail.followerText.length > 0) {
      parts.push(`${this.detail.followerText} 粉丝`);
    }
    if (this.detail.archiveText.length > 0) {
      parts.push(`${this.detail.archiveText} 投稿`);
    }
    if (parts.length === 0) {
      const reply: string = this.detail.replyText.length > 0 ? this.detail.replyText : '0';
      return `${reply} 条评论`;
    }
    return parts.join(' · ');
  }

  /** 作者行：头像 + 昵称 + 粉丝/投稿 + 关注（参考图） */
  @Builder
  authorBlock() {
    Row({ space: 10 }) {
      if (this.detail.authorFace.length > 0) {
        Image(this.detail.authorFace)
          .width(42)
          .height(42)
          .borderRadius(21)
          .objectFit(ImageFit.Cover)
          .alt($r('app.color.bg_field'))
          .draggable(false)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
            .fontSize(42)
            .fontColor([$r('app.color.text_tertiary')])
        }
        .width(42)
        .height(42)
      }

      Column({ space: 3 }) {
        Text(this.detail.authorName.length > 0 ? `@${this.detail.authorName}` : 'UP 主')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.authorSubText())
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 3 }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(12)
          .fontColor([$r('app.color.brand_primary')])
        Text('关注')
          .fontSize(13)
          .fontColor($r('app.color.brand_primary'))
      }
      .padding({ left: 10, right: 14, top: 6, bottom: 6 })
      .backgroundColor($r('app.color.brand_tint'))
      .borderRadius(15)
      .onClick(() => {
        this.toast('关注功能待建设');
      })
    }
    .width('100%')
    .padding({ top: 12, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  /** 标题行：右侧箭头控制简介展开 */
  @Builder
  titleRow() {
    Row({ space: 8 }) {
      Text(this.detail.title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .lineHeight(24)
        .fontColor($r('app.color.text_primary'))
        .maxLines(this.briefExpanded ? 8 : 2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      SymbolGlyph(this.briefExpanded
        ? $r('sys.symbol.chevron_up')
        : $r('sys.symbol.chevron_down'))
        .fontSize(16)
        .fontColor([$r('app.color.text_tertiary')])
        .onClick(() => {
          this.briefExpanded = !this.briefExpanded;
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ bottom: 8 })
  }

  /** 元信息：播放量 · 弹幕数 · 发布时间（参考图顺序） */
  @Builder
  metaRow() {
    Row() {
      SymbolGlyph($r('sys.symbol.play_square'))
        .fontSize(13)
        .fontColor([$r('app.color.text_tertiary')])
      Text(this.bareCount(this.detail.viewText))
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ left: 3 })
      Text('·')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ left: 7, right: 7 })
      SymbolGlyph($r('sys.symbol.waveform_bubble'))
        .fontSize(13)
        .fontColor([$r('app.color.text_tertiary')])
      Text(this.detail.danmuText)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ left: 3 })
      Text(`发布于 ${this.publishAbsolute(this.detail.pubTs)}`)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ left: 12 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ bottom: 12 })
  }

  /** 单个互动项：图标在上、数字或动作名在下 */
  @Builder
  actionItem(icon: Resource, label: string) {
    Column({ space: 5 }) {
      SymbolGlyph(icon)
        .fontSize(23)
        .fontColor([$r('app.color.text_secondary')])
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.toast(`${label} 功能待接入`);
    })
  }

  /** 六项互动：点赞 / 点踩 / 投币 / 收藏 / 再看 / 分享（参考图） */
  @Builder
  actionRow() {
    Row() {
      this.actionItem($r('sys.symbol.hand_thumbsup'),
        this.detail.likeText.length > 0 ? this.detail.likeText : '点赞')
      this.actionItem($r('sys.symbol.hand_thumbsdown'), '点踩')
      this.actionItem($r('sys.symbol.medal'),
        this.detail.coinText.length > 0 ? this.detail.coinText : '投币')
      this.actionItem($r('sys.symbol.star'),
        this.detail.favText.length > 0 ? this.detail.favText : '收藏')
      this.actionItem($r('sys.symbol.arrow_clockwise'), '再看')
      this.actionItem($r('sys.symbol.share'),
        this.detail.shareText.length > 0 ? this.detail.shareText : '分享')
    }
    .width('100%')
    .padding({ top: 4, bottom: 10 })
  }

  /** 简介：标题右侧箭头展开后，在互动行下方直接向下铺开 */
  @Builder
  briefBlock() {
    Column({ space: 6 }) {
      Text(this.detail.desc.length > 0 ? this.detail.desc : '该视频没有简介')
        .width('100%')
        .fontSize(13)
        .lineHeight(20)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(10)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`BV号 ${this.detail.bvid}`)
        .width('100%')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 4, bottom: 12 })
  }

  /** 设置页签：内联向下列表，不占用侧边栏 */
  @Builder
  settingsBlock() {
    Column() {
      Text('播放设置')
        .width('100%')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .padding({ top: 14 })
      PlayerSettingsPanel({
        prefs: $prefs,
        onChanged: (key: string, value: number | boolean): void => {
          this.onSettingsChanged(key, value);
        }
      })
    }
    .width('100%')
  }

  /** 推荐列表项：左封面右文案（参考图） */
  @Builder
  recommendRow(card: VideoCard) {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Image(card.cover)
          .width(132)
          .height(74)
          .objectFit(ImageFit.Cover)
          .borderRadius(6)
          .alt($r('app.color.bg_field'))
          .draggable(false)
        if (card.duration > 0) {
          Text(durationText(card.duration))
            .fontSize(10)
            .fontColor($r('app.color.text_on_media'))
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.overlay'))
            .borderRadius(3)
            .margin({ right: 4, bottom: 4 })
        }
      }
      .width(132)
      .height(74)

      Column({ space: 4 }) {
        Text(card.title)
          .fontSize(14)
          .lineHeight(19)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${this.bareCount(card.viewText)} · ${card.danmuText} ${pubTimeText(card.pubTs)}`)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
        Text(`@${card.author}`)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Top)
    .onClick(() => {
      this.openCard(card);
    })
  }

  @Builder
  recommendBlock() {
    Column() {
      Divider().color($r('app.color.divider'))
      Row() {
        Text('相关推荐')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.recommendLoading) {
          Text('加载中…')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
      }
      .width('100%')
      .padding({ top: 12, bottom: 4 })

      if (this.recommendList.length === 0 && !this.recommendLoading) {
        Text('暂无推荐内容')
          .width('100%')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .padding({ top: 8, bottom: 16 })
      } else {
        ForEach(this.recommendList, (card: VideoCard) => {
          this.recommendRow(card)
        }, (card: VideoCard) => `rcmd_${card.bvid}`)
      }
    }
    .width('100%')
  }

  /** 评论头部：总数 + 排序（按时间 / 按热度，用系统菜单切换） */
  @Builder
  commentHeader() {
    Row() {
      Text(`评论 ${this.commentCountText()}`)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Blank()
      Row({ space: 3 }) {
        Text(this.commentSort === CommentService.MODE_TIME ? '按时间' : '按热度')
          .fontSize(12)
          .fontColor($r('app.color.brand_primary'))
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(11)
          .fontColor([$r('app.color.brand_primary')])
      }
      .padding({ left: 8, right: 4, top: 4, bottom: 4 })
      .onClick(() => {
        // 点击整体在「时间 / 热度」之间来回切，保持交互一步到位
        this.switchSort(this.commentSort === CommentService.MODE_TIME
          ? CommentService.MODE_HOT : CommentService.MODE_TIME);
      })
    }
    .width('100%')
    .height(46)
    .alignItems(VerticalAlign.Center)
  }

  /** 单条评论：头像 + 昵称 / 等级 + 正文 + 时间与互动 */
  @Builder
  commentRow(item: VideoComment) {
    Column() {
      Row({ space: 10 }) {
        if (item.face.length > 0) {
          Image(item.face)
            .width(38)
            .height(38)
            .borderRadius(19)
            .objectFit(ImageFit.Cover)
            .alt($r('app.color.bg_field'))
            .draggable(false)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
              .fontSize(38)
              .fontColor([$r('app.color.text_tertiary')])
          }
          .width(38)
          .height(38)
        }

        Column({ space: 5 }) {
          Row({ space: 5 }) {
            Text(item.name.length > 0 ? item.name : '匿名用户')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '62%' })
            if (item.level > 0) {
              LevelBadge({ level: item.level, badgeHeight: 13 })
            }
            if (item.fromUp) {
              Text('UP')
                .fontSize(9)
                .fontColor($r('app.color.text_on_brand'))
                .padding({ left: 3, right: 3, top: 1, bottom: 1 })
                .backgroundColor($r('app.color.brand_primary'))
                .borderRadius(3)
            }
          }
          .alignItems(VerticalAlign.Center)

          Text(item.message)
            .width('100%')
            .fontSize(14)
            .lineHeight(21)
            .fontColor($r('app.color.text_primary'))
            .maxLines(8)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row({ space: 16 }) {
            Text(item.timeText())
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
            Row({ space: 3 }) {
              SymbolGlyph($r('sys.symbol.hand_thumbsup'))
                .fontSize(14)
                .fontColor([item.liked ? $r('app.color.brand_primary') : $r('app.color.text_tertiary')])
              if (item.like > 0) {
                Text(`${item.like}`)
                  .fontSize(11)
                  .fontColor(item.liked ? $r('app.color.brand_primary') : $r('app.color.text_tertiary'))
              }
            }
            .alignItems(VerticalAlign.Center)
            Text('回复')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .onClick(() => {
                this.openComposer(item.rpid, '', item.name);
              })
            Blank()
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 1 })

          if (item.rcount > 0) {
            Row({ space: 3 }) {
              Text(this.expandedRpid === item.rpid ? '收起回复' : `共 ${item.rcount} 条回复`)
                .fontSize(11)
                .fontColor($r('app.color.brand_primary'))
              SymbolGlyph($r('sys.symbol.chevron_down'))
                .fontSize(10)
                .fontColor([$r('app.color.brand_primary')])
                .rotate({ angle: this.expandedRpid === item.rpid ? 180 : 0 })
            }
            .padding({ top: 2, bottom: 2 })
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.toggleSub(item);
            })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 12, bottom: 12 })

      // 楼中楼：缩进展示，从属于当前楼层
      if (this.expandedRpid === item.rpid) {
        this.subReplyArea(item)
      }

      Divider()
        .color($r('app.color.divider'))
        .strokeWidth(0.5)
    }
    .width('100%')
  }

  /** 楼中楼区域：缩进 + 子回复列表 + 展开更多 */
  @Builder
  subReplyArea(root: VideoComment) {
    Column({ space: 0 }) {
      if (this.subComments.length === 0) {
        Row() {
          if (this.subLoading) {
            Text('正在加载回复…')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          } else {
            Text('暂无回复')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
        }
        .width('100%')
        .height(32)
        .alignItems(VerticalAlign.Center)
      } else {
        ForEach(this.subComments, (sub: VideoComment) => {
          this.subCommentRow(sub, root)
        }, (sub: VideoComment) => `sub_${sub.rpid}`)

        if (this.subLoading) {
          Row() {
            Text('正在加载…')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .height(32)
          .alignItems(VerticalAlign.Center)
        } else if (!this.subEnd) {
          Text(`展开更多回复（${this.subTotal}）`)
            .fontSize(11)
            .fontColor($r('app.color.brand_primary'))
            .padding({ top: 8, bottom: 8 })
            .onClick(() => {
              this.loadSub(false);
            })
        }
      }

      Text(root.name.length > 0 ? `回复 @${root.name}` : '回复')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .padding({ top: 6, bottom: 2 })
        .onClick(() => {
          this.openComposer(root.rpid, '', root.name);
        })
    }
    .width('100%')
    .padding({ left: 48, top: 2, bottom: 6 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 单条子回复：头像 + 昵称 + 等级 / 「回复 @某人」+ 正文 + 时间与互动 */
  @Builder
  subCommentRow(sub: VideoComment, root: VideoComment) {
    Row({ space: 8 }) {
      if (sub.face.length > 0) {
        Image(sub.face)
          .width(26)
          .height(26)
          .borderRadius(13)
          .objectFit(ImageFit.Cover)
          .alt($r('app.color.bg_field'))
          .draggable(false)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
            .fontSize(26)
            .fontColor([$r('app.color.text_tertiary')])
        }
        .width(26)
        .height(26)
      }

      Column({ space: 3 }) {
        Row({ space: 5 }) {
          Text(sub.name.length > 0 ? sub.name : '匿名用户')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '50%' })
          if (sub.fromUp) {
            Text('UP')
              .fontSize(8)
              .fontColor($r('app.color.text_on_brand'))
              .padding({ left: 3, right: 3, top: 1, bottom: 1 })
              .backgroundColor($r('app.color.brand_primary'))
              .borderRadius(3)
          }
          if (sub.replyToName.length > 0) {
            Text(`回复 @${sub.replyToName}`)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          } else if (sub.level > 0) {
            LevelBadge({ level: sub.level, badgeHeight: 12 })
          }
          Blank()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(sub.message)
          .width('100%')
          .fontSize(13)
          .lineHeight(19)
          .fontColor($r('app.color.text_primary'))
          .maxLines(6)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 14 }) {
          Text(sub.timeText())
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
          Row({ space: 2 }) {
            SymbolGlyph($r('sys.symbol.hand_thumbsup'))
              .fontSize(11)
              .fontColor([$r('app.color.text_tertiary')])
            if (sub.like > 0) {
              Text(`${sub.like}`)
                .fontSize(10)
                .fontColor($r('app.color.text_tertiary'))
            }
          }
          .alignItems(VerticalAlign.Center)
          Text('回复')
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => {
              this.openComposer(root.rpid, sub.rpid, sub.name);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Top)
  }

  /** 评论版块：头部 + 列表（滚到底自动续页）+ 右下角发评论悬浮键 */
  @Builder
  commentsBlock() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      List({ scroller: this.commentScroller }) {
        ListItem() {
          this.commentHeader()
        }

        if (this.commentsLoading && this.comments.length === 0) {
          ListItem() {
            StateView({ kind: 'loading', message: '正在加载评论' })
          }
        } else if (this.commentsError.length > 0 && this.comments.length === 0) {
          ListItem() {
            StateView({
              kind: 'error',
              message: this.commentsError,
              hint: '评论接口偶发风控，稍后重试',
              onRetry: () => {
                this.loadComments(true);
              }
            })
          }
        } else if (this.comments.length === 0) {
          ListItem() {
            StateView({ kind: 'empty', message: '还没有评论', hint: '来抢个沙发吧' })
          }
        } else {
          ForEach(this.comments, (item: VideoComment) => {
            ListItem() {
              this.commentRow(item)
            }
          }, (item: VideoComment) => `cmt_${item.rpid}`)

          ListItem() {
            if (this.commentsLoading) {
              ListFooter({ text: '正在加载更多评论' })
            } else if (this.commentEnd) {
              Row() {
                Text(`已显示全部 ${this.comments.length} 条评论`)
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

        ListItem() {
          Row()
            .width('100%')
            .height(BOTTOM_PAD_PHONE)
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .onReachEnd(() => {
        this.loadComments(false);
      })

      // 发评论：打开输入浮层（顶层评论）
      Row() {
        SymbolGlyph($r('sys.symbol.square_and_pencil'))
          .fontSize(20)
          .fontColor([$r('app.color.brand_primary')])
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(22)
      .shadow({ radius: 10, color: $r('app.color.shadow_soft'), offsetY: 2 })
      .margin({ right: 16, bottom: 96 })
      .onClick(() => {
        this.openComposer('', '', '');
      })
    }
    .width('100%')
    .height('100%')
  }

  /** 输入卡工具条上的圆形图标入口（表情 / 图片 / @ / 插入） */
  @Builder
  composerToolIcon(symbol: Resource, active: boolean, action: () => void) {
    Row() {
      SymbolGlyph(symbol)
        .fontSize(19)
        .fontColor([active ? $r('app.color.brand_primary') : $r('app.color.text_secondary')])
    }
    .width(34)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .borderRadius(17)
    .backgroundColor(active ? $r('app.color.brand_tint') : Color.Transparent)
    .onClick(action)
  }

  /** 输入卡下方的面板：表情 / @ 二选一，点选后按光标插入文本 */
  @Builder
  composerPanelArea() {
    Scroll() {
      Flex({ wrap: FlexWrap.Wrap }) {
        if (this.composerPanel === 'emoji') {
          ForEach(COMPOSER_EMOJIS, (item: string) => {
            Text(`[${item}]`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.bg_field'))
              .borderRadius(8)
              .margin({ right: 6, bottom: 6 })
              .onClick(() => {
                this.insertChunk(`[${item}]`);
              })
          }, (item: string) => `emoji_${item}`)
        } else {
          ForEach(this.mentionNames(), (name: string) => {
            Text(`@${name}`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.bg_field'))
              .borderRadius(8)
              .margin({ right: 6, bottom: 6 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '60%' })
              .onClick(() => {
                this.insertChunk(`@${name} `);
              })
          }, (name: string) => `mention_${name}`)
        }
      }
      .width('100%')
    }
    .width('100%')
    .height(126)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }

  /** 评论输入浮层：遮罩 + 底部输入卡（顶层评论与楼中楼回复共用） */
  @Builder
  commentComposer() {
    if (this.composerVisible) {
      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.scrim'))
          .onClick(() => {
            this.closeComposer();
          })

        Column({ space: 8 }) {
          Row() {
            Text(this.composerTarget.length > 0 ? `回复 @${this.composerTarget}` : '发一条评论')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Blank()
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(18)
              .fontColor([$r('app.color.text_tertiary')])
              .onClick(() => {
                this.closeComposer();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          TextArea({ text: this.composerText, placeholder: '善语结善缘，恶言伤人心' })
            .id(COMPOSER_INPUT_ID)
            .placeholderColor($r('app.color.text_tertiary'))
            .placeholderFont({ size: 14 })
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.bg_field'))
            .borderRadius(10)
            .height(84)
            .padding(10)
            .onFocus(() => {
              // 键盘起来时面板必须让位，否则两者叠在一起
              this.composerPanel = '';
            })
            .onTextSelectionChange((start: number, end: number) => {
              this.selStart = start;
              this.selEnd = end;
            })
            .onChange((value: string) => {
              this.composerText = value;
            })

          if (this.composerPanel.length > 0) {
            this.composerPanelArea()
          }

          // 工具条：左侧四个入口（表情 / 图片 / @ / 插入内容），右侧发送
          Row({ space: 2 }) {
            this.composerToolIcon($r('sys.symbol.face_smiling'), this.composerPanel === 'emoji', () => {
              this.toggleComposerPanel('emoji');
            })
            this.composerToolIcon($r('sys.symbol.picture'), false, () => {
              this.toast('图片评论待接入');
            })
            this.composerToolIcon($r('sys.symbol.at'), this.composerPanel === 'mention', () => {
              this.toggleComposerPanel('mention');
            })
            this.composerToolIcon($r('sys.symbol.plus'), false, () => {
              this.toast('插入内容待接入');
            })
            Blank()
            Text(this.composerSending ? '发送中…' : '发送')
              .fontSize(14)
              .fontColor($r('app.color.text_on_brand'))
              .padding({ left: 20, right: 20, top: 8, bottom: 8 })
              .backgroundColor(this.composerText.trim().length === 0 || this.composerSending
                ? $r('app.color.text_tertiary') : $r('app.color.brand_primary'))
              .borderRadius(17)
              .onClick(() => {
                this.sendComment();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({
          left: 14,
          right: 14,
          top: 10,
          bottom: this.keyboardH > 0 ? 8 : 10 + this.bottomInset
        })
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius({ topLeft: 18, topRight: 18 })
        .shadow({ radius: 16, color: $r('app.color.shadow_strong'), offsetY: -2 })
        .margin({ bottom: this.kbOffset })
      }
      .width('100%')
      .height('100%')
    }
  }

  /** 简介版块：作者 → 标题 → 元信息 → 六项互动 → 简介 / 推荐 */
  @Builder
  briefTab() {
    Scroll(this.scroller) {
      Column({ space: 0 }) {
        this.authorBlock()
        this.titleRow()
        this.metaRow()
        this.actionRow()
        Divider().color($r('app.color.divider'))
        if (this.briefExpanded) {
          this.briefBlock()
        }
        this.recommendBlock()
        Row()
          .width('100%')
          .height(BOTTOM_PAD_PHONE)
      }
      .width('100%')
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
  }

  /** 设置版块：播放器偏好内联列表 */
  @Builder
  settingsTab() {
    Scroll(this.settingsScroller) {
      Column() {
        this.settingsBlock()
        Row()
          .width('100%')
          .height(BOTTOM_PAD_PHONE)
      }
      .width('100%')
      .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
  }

  @Builder
  infoArea() {
    Column() {
      this.actionBar()
      if (this.loading) {
        Column() {
          StateView({ kind: 'loading', message: '正在获取视频信息' })
        }
        .layoutWeight(1)
        .width('100%')
      } else if (this.errorText.length > 0) {
        Column() {
          StateView({
            kind: 'error',
            message: this.errorText,
            hint: '检查网络后重试',
            onRetry: () => {
              this.loadDetail();
            }
          })
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        // 三个版块装在 Tabs 里，barHeight 0 隐藏自带页签条（页签由工具行自绘）：
        // 这样既能点文字切换，也能在内容区左右滑动随时切换，且各版块各自保留滚动位置。
        Tabs({ barPosition: BarPosition.Start, controller: this.tabsController }) {
          TabContent() {
            this.briefTab()
          }
          .tabBar('简介')

          TabContent() {
            this.commentsBlock()
          }
          .tabBar('评论')

          TabContent() {
            this.settingsTab()
          }
          .tabBar('设置')
        }
        .barHeight(0)
        .scrollable(true)
        .animationDuration(220)
        .layoutWeight(1)
        .width('100%')
        .onChange((index: number) => {
          this.onTabChanged(index);
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
    // 本页根容器铺了黑底（状态栏那一条要留黑），信息区必须自己铺回页面底色，
    // 否则列表是透明的，浅色模式下会看见黑底
    .backgroundColor($r('app.color.bg_page'))
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        // 单一结构：画布始终是 Column 的第一个子节点，全屏/竖屏摆放只改高度、不切分支。
        // 若用 if/else 两套分支，XComponent 会被销毁重建 → 重新 prepare → 播放回到 0 秒。
        Column() {
          Stack({ alignContent: Alignment.Center }) {
            this.playerLayer()
          }
          .width('100%')
          .height(this.fullscreen || this.portraitMode ? '100%' : this.canvasHeight)
          .backgroundColor(Color.Black)
          .clip(true)
          .onAreaChange((oldValue: Area, newValue: Area) => {
            const width: number = Number(newValue.width);
            if (width > 0) {
              this.surfaceWidth = width;
              // 按真实宽度重算 16:9：display 宽度在折叠屏 / 分屏下可能与内容区不一致，
              // 差几 vp 就会让画面上下被裁掉一小条，看起来像被底部白条压住。
              if (!this.fullscreen && !this.portraitMode) {
                const target: number = Math.round(width * 9 / 16);
                if (target > 0 && Math.abs(target - this.canvasHeight) > 1) {
                  this.canvasHeight = target;
                }
              }
            }
          })

          if (!this.fullscreen && !this.portraitMode) {
            this.infoArea()
          }
        }
        .width('100%')
        .height('100%')

        // 竖屏摆放模式：信息以浮层叠在铺满的视频下方
        if (this.portraitMode && !this.fullscreen) {
          Column() {
            this.infoArea()
          }
          .width('100%')
          .height('58%')
          .align(Alignment.Bottom)
          .backgroundColor($r('app.color.bg_page'))
          .borderRadius({ topLeft: 16, topRight: 16 })
          .shadow({ radius: 12, color: $r('app.color.shadow_strong'), offsetY: -3 })
        }

        // 评论输入浮层：盖住整页，含标题栏区域（本页 hideTitleBar）
        this.commentComposer()
      }
      .width('100%')
      .height('100%')
      // 状态栏那一条铺黑：NavDestination 只放开了底部安全区（列表能铺到屏幕下沿），
      // 顶部仍是窗口底色（#F5F6F7），不铺黑就会留一条白边。用 expandSafeArea 把绘制区域顶到屏幕最上沿，
      // 布局仍从状态栏下方开始，所以黑色只出现在状态栏这一条上。
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .backgroundColor(Color.Black)
      // 键盘避让用 RESIZE：页面被压矮时能在这里量到，输入卡据此判断还要不要自己上移
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.onPageResize(Number(newValue.height));
      })
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    // 整页铺到屏幕上下沿：NavDestination 默认把状态栏和手势条两条让出来，
    // 露出的是窗口底色（#F5F6F7），上下各一条「白边」。这里让布局忽略安全区，
    // 画布压到状态栏下面（顶部留黑），评论列表铺到屏幕最下沿。
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor($r('app.color.bg_page'))
  }
}
