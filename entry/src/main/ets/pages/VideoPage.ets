import { HdsNavDestination } from '@kit.UIDesignKit';
import { display, window, KeyboardAvoidMode } from '@kit.ArkUI';
import { audio } from '@kit.AudioKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { BOTTOM_PAD_PHONE, PAGE_PADDING } from '../common/DesignSpec';
import { durationText, plainCount, pubTimeText, shortCount } from '../common/Format';
import { AuthorStat, VideoCard, VideoDetail, VideoOpenParam, emptyVideoCard } from '../model/BiliModels';
import { VideoService } from '../services/VideoService';
import { VideoPlayer } from '../services/VideoPlayer';
import { RecommendService } from '../services/RecommendService';
import { PlayerPrefs } from '../services/PlayerPrefs';
import { CommentEmote, CommentFeed, CommentService, SubReplyFeed, VideoComment } from '../services/CommentService';
import { DanmakuItem, DanmakuService } from '../services/DanmakuService';
import { InteractiveService, VideoRelation } from '../services/InteractiveService';
import { HiddenCommentStore } from '../services/HiddenCommentStore';
import { BiliCookie } from '../services/BiliHttp';
import { ListFooter, StateView } from '../components/StateView';
import { LevelBadge } from '../components/LevelBadge';
import { PlayerSettingsPanel } from '../components/PlayerSettingsPanel';
import { AppPrefs } from '../services/AppPrefs';

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
/** 普通 / 全屏滑动区域判定：左 35% 亮度 / 右 35% 音量，中间为盲区 */
const SIDE_ZONE_RATIO: number = 0.35;
/** 竖屏连播滑动区域判定：视频竖直上半 50% 内，左 20% 亮度 / 右 20% 音量，中间为盲区 */
const PORTRAIT_SIDE_ZONE_RATIO: number = 0.20;
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
/** 竖屏连播：跟手拖拽的切换阈值上限（vp）；实际取画面盒高度的 22%，夹在 30~这个值之间 */
const PORTRAIT_SWITCH_TRIGGER_VP: number = 60;
/** 竖屏连播：轻扫判定（vp/s）。位移不够但甩得快也算切换，跟抖音/B 站一样 */
const PORTRAIT_SWITCH_VELOCITY: number = 780;
/** 竖屏连播：画面与顶栏之间留的呼吸空间（vp）。贴太紧看起来像顶到了返回图标 */
const PORTRAIT_TOP_GAP: number = 32;
/** 竖屏连播：底部给 UP 信息 / 进度条 / 操作行预留的高度（vp），画面不压到它们 */
const PORTRAIT_BOTTOM_RESERVE: number = 224;
/** 竖屏连播：滑出 / 滑入动画时长 */
const PORTRAIT_SLIDE_OUT_MS: number = 200;
const PORTRAIT_SLIDE_IN_MS: number = 240;
/** 弹幕画布重绘间隔（ms）：约 30fps，足够跟手，也不会把主线程画满 */
const DANMAKU_FRAME_MS: number = 33;
/** 弹幕横穿一屏的基准时长（ms，1.0x 速度）；乘速度倍率后变快变慢 */
const DANMAKU_TRAVEL_MS: number = 9000;
/** 顶部 / 底部固定弹幕停留时长 */
const DANMAKU_FIXED_MS: number = 4200;
/** 同屏最多渲染多少条，超出直接丢弃（弹幕海也不至于把帧率拖垮） */
const DANMAKU_MAX_ACTIVE: number = 90;
/** 弹幕输入框 id：打开浮层后按 id 申请焦点 */
const DANMAKU_INPUT_ID: string = 'muli_danmaku_input';
/**
 * 视频区顶栏图标是否带半透明圆底。
 * V2.1.0 按要求「去除图标阴影」：圆底本质是一块 scrim 色块，在亮画面上很像一圈阴影，
 * 置 false 后只保留图标本体。若在亮背景下看不清，改回 true 即可恢复。
 */
const TOP_ICON_CHIP_BG: boolean = false;
/** 竖屏化视频（9:16）在横屏区可拉伸到的最大高度：占整屏比例，留一截给下方推荐 */
const VERTICAL_MAX_STAGE_RATIO: number = 0.80;
/** 拉伸到该比例（含）即松手进入竖屏模式 */
const VERTICAL_ENTER_RATIO: number = 0.76;

/** 评论正文的富文本片段：url 非空 = 表情图片，mention = 命中 @某人（上品牌色） */
class CommentSegment {
  text: string = '';
  url: string = '';
  mention: boolean = false;

  constructor(text: string, url: string, mention: boolean = false) {
    this.text = text;
    this.url = url;
    this.mention = mention;
  }
}

/** 楼中楼的一行：item 是回复本身，depth 是嵌套层级（0 = 直接回复楼主） */
class SubRow {
  item: VideoComment = new VideoComment();
  depth: number = 0;

  constructor(item: VideoComment, depth: number) {
    this.item = item;
    this.depth = depth;
  }
}

/** 竖屏连播的上下切换历史：下滑时回到上一条，只需记住它从哪来、封面长什么样 */
class PortraitEntry {
  param: VideoOpenParam = new VideoOpenParam('', 0, 0);
  cover: string = '';

  constructor(param: VideoOpenParam, cover: string) {
    this.param = param;
    this.cover = cover;
  }
}

/**
 * 竖屏连播的「下一支」预取结果。
 *
 * 上滑切换之所以会黑屏 3~5s，是因为播放地址是松手后才去请求的（详情 + 取流 + prepare）。
 * 提前把这三步做完放在这里，松手时只要 setSource 就能出画。
 */
class PortraitPrefetch {
  param: VideoOpenParam = new VideoOpenParam('', 0, 0);
  detail: VideoDetail = new VideoDetail();
  url: string = '';

  constructor(param: VideoOpenParam, detail: VideoDetail, url: string) {
    this.param = param;
    this.detail = detail;
    this.url = url;
  }
}

/** 竖屏连播画面盒的位置与高度（vp）：画面层与切换垫层共用同一套几何，切起来才不会跳 */
class PortraitFrame {
  top: number = 0;
  height: number = 0;

  constructor(top: number, height: number) {
    this.top = top;
    this.height = height;
  }
}

/**
 * 正在画布上的一条弹幕。
 *
 * 时间一律用「视频时间轴」（毫秒）而不是墙钟：暂停时进度不走，弹幕就停在原地；
 * 拖动进度条跳回去时，靠这个判断哪些要清掉、哪些要补出来。
 */
class ActiveDanmaku {
  text: string = '';
  color: string = '#FFFFFF';
  /** 落在第几条轨道（0 在最上） */
  lane: number = 0;
  /** 从底部往上数的轨道（mode 4 用） */
  fromBottom: boolean = false;
  /** 顶部 / 底部固定弹幕：不横向移动，停留几秒后淡出 */
  fixed: boolean = false;
  /** 进入时间轴的时刻（ms） */
  bornMs: number = 0;
  /** 存活时长（ms） */
  durationMs: number = 0;
  /** 文本宽度（vp），画布量过一次就存下来，避免每帧 measureText */
  width: number = 0;
}

/** 一条弹幕轨道的占用情况：freeAt 之前不再往这条轨道塞新弹幕，避免叠字 */
class DanmakuLane {
  freeAt: number = 0;
}

/**
 * 视频二级播放页（V2.0.3），路由 name = 'video'。
 *
 * 结构要点：
 * - 画布 XComponent 只有一个实例，全屏 / 竖屏摆放都只改外层容器高度，绝不切 if 分支，
 *   否则 surface 重建会让播放进度归零（历史回归）。
 * - 控制条 4s 无操作自动隐藏；双击播放暂停、左右滑快进快退、左亮度右音量、长按倍速。
 * - 信息区去掉卡片，简介 / 评论 / 设置走底部工具行；中间按钮切「竖屏摆放模式」（视频铺满+信息浮层）。
 * - 右侧设置面板承载播放器偏好；弹幕用一块 Canvas 按播放时间轴逐帧绘制，参数在设置面板里即时生效。
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
  /** 竖屏连播模式：视频铺满整屏 + 右侧竖排互动 + 底部浮层（参考 B 站竖屏沉浸） */
  @State portraitMode: boolean = false;
  /** 竖屏模式下底部信息浮层是否展开（展开简介时浮层拉高） */
  @State portraitDescExpanded: boolean = false;
  /** 竖屏顶部「设置」唤起的底部弹窗（内容与播放区设置面板一致） */
  @State portraitSettingsVisible: boolean = false;
  /** 竖屏连播：底部 up 信息 + 视频名称是否显示（点击屏幕切换，进度条与操作行固定显示） */
  @State portraitInfoVisible: boolean = true;
  /** 竖屏连播：上下拖拽切换时，视频与浮层跟随手指的实时位移（vp，负值=向上滑出） */
  @State portraitDragY: number = 0;
  /** 竖屏连播：正在执行「滑出→切换→滑入」动画，动画期间忽略新手势 */
  private portraitSwitching: boolean = false;
  /** 视频真实比例（高 / 宽）：竖屏连播按它摆画面容器，避免画面居中后上方留一大片黑 */
  @State videoAspect: number = 0;
  /** 整屏高度（vp）：竖屏切换的滑出滑入距离基准 */
  @State stageH: number = 0;
  /** 竖屏连播：预取到的下一条封面（上滑时从底部露出，避免切换过程纯黑） */
  @State portraitNextCover: string = '';
  /** 竖屏连播：下滑时要回到的上一条封面 */
  @State portraitPrevCover: string = '';
  /** 从竖屏连播进的全屏：退出全屏要回到连播而不是普通播放页 */
  @State fullscreenFromPortrait: boolean = false;
  /** 评论长按弹窗 */
  @State sheetCommentVisible: boolean = false;
  @State sheetComment: VideoComment = new VideoComment();
  @State sheetCommentIsSub: boolean = false;
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
  /** 评论下拉刷新中（Refresh 容器的绑定值，松手后由加载逻辑置回 false） */
  @State commentRefreshing: boolean = false;
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
  /** 表情面板数据（`[doge]` → 图片），首次打开表情面板时拉一次 */
  @State composerEmotes: Array<CommentEmote> = [];
  @State composerEmotesLoading: boolean = false;
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
  /** 播放结束态（停止推荐）：视频区黑屏只留推荐内容 + 重播入口 */
  @State playEnded: boolean = false;
  /** 竖屏化视频在横屏区被用户拉高的额外高度（vp，0 = 按 16:9 原尺寸） */
  @State displayExtra: number = 0;
  /** 播放区顶部是否沉浸到系统状态栏（设置页可关；关了就用增量色块补那一条） */
  @StorageLink(AppPrefs.KEY_TOP_IMMERSIVE) @Watch('onTopStyleChanged') topImmersive: boolean = true;
  /** 关闭沉浸时增量条颜色：0 = 黑色，1 = 白色 */
  @StorageLink(AppPrefs.KEY_TOP_INSET_COLOR) @Watch('onTopStyleChanged') topInsetColor: number = 0;
  /** 本地点赞态：relation 接口返回，未登录恒 false */
  @State liked: boolean = false;
  /** 点赞文案（直接存展示值，避免「方法里算出来的字符串」不触发界面刷新） */
  @State likeTextUi: string = '';
  /** 点赞数原值（本地点赞 / 取消后 ±1，再交给 shortCount 格式化） */
  private likeCount: number = 0;
  /** 点赞请求进行中，避免连点重复提交 */
  private likeBusy: boolean = false;
  /** 弹幕输入浮层 */
  @State danmakuComposerVisible: boolean = false;
  @State danmakuDraft: string = '';
  @State danmakuSending: boolean = false;

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
  /** 切后台前是否在播 + 中断时的进度：回前台按「中断继续播放」决定要不要自动接上 */
  private interrupted: boolean = false;
  private interruptMs: number = 0;
  private appBgHandler: (() => void) | undefined = undefined;
  private appFgHandler: (() => void) | undefined = undefined;
  /** 播放失败是否已经自动重取过一次地址（避免无限重试） */
  private playRetried: boolean = false;
  private surfaceWatch: number = 0;
  private controlTimer: number = -1;
  private hudTimer: number = -1;
  /** 续播目标位置（prepared 后 seek 才有效） */
  private resumeMs: number = 0;
  /** 画布宽度 vp，用于判定左 / 右滑动区域 */
  private surfaceWidth: number = 360;
  /** 画布高度 vp，竖屏连播下用于判定上半（亮度/音量）与下半（切换视频） */
  private surfaceHeight: number = 211;
  /** 竖屏连播：下滑可回到的历史（进连播时开始记） */
  private portraitHistory: Array<PortraitEntry> = [];
  /** 竖屏连播：预取好的下一条（null = 还没有） */
  private portraitPrefetch: PortraitPrefetch | null = null;
  private portraitPrefetching: boolean = false;
  /** 预取目标 bvid：避免同一条被重复预取 */
  private portraitPrefetchBvid: string = '';
  /** 打开弹幕输入框前是否在播：发送 / 关闭后自动续播 */
  private danmakuResume: boolean = false;
  /** 因为「压栈打开下一个视频」而临时暂停：返回本页时自动接上 */
  private pausedForPush: boolean = false;
  /** 竖屏化视频拖动时的起始额外高度 */
  private displayDragBase: number = 0;
  /** 工具行那颗箭头这次按下是否已经变成「拖动」（true 时松手走拉伸收尾，不再当点击） */
  private arrowDragging: boolean = false;

  // 弹幕
  /** 弹幕画布上下文（全局只有一块，画在画面盒里，跟着画面一起平移） */
  private danmakuCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private danmakuReady: boolean = false;
  private danmakuWidth: number = 0;
  private danmakuHeight: number = 0;
  /** 当前视频的全部弹幕（按时间升序） */
  private danmakuList: Array<DanmakuItem> = [];
  /** 屏幕上正在动的弹幕 */
  private danmakuActive: Array<ActiveDanmaku> = [];
  /** 下一条待上屏的弹幕下标（时间升序游标） */
  private danmakuEmit: number = 0;
  /** 当前弹幕对应的 cid，切换视频后用于丢弃过期响应 */
  private danmakuCid: number = 0;
  /** 加载请求序号：连播快速切换时只认最后一次 */
  private danmakuToken: number = 0;
  private danmakuTimer: number = -1;
  /** 轨道占用（每条轨道下一次可塞弹幕的时间轴时刻） */
  private danmakuLanes: Array<DanmakuLane> = [];
  /** 播放时钟锚点：position = pos + (now - at)，暂停时只取 pos */
  private danmakuClockPos: number = 0;
  private danmakuClockAt: number = 0;
  private danmakuClockPlaying: boolean = false;
  /** 上一帧的时间轴位置：用来识别「大跨度跳转」（拖进度 / 切集）并重置游标 */
  private danmakuLastPos: number = -1;
  /** 上一帧弹幕是否开着：从关到开时把游标对齐到当前位置，避免一次性补出几百条 */
  private danmakuWasOn: boolean = true;
  /** 1vp 等于多少物理像素：Canvas 的 font 用 px，坐标用 vp，字号必须换算 */
  private danmakuRatio: number = 0;

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
      // 弹幕时钟：开播重新锚定，暂停时把已走过的那段折成静态位置（弹幕停在原地）
      if (state === 'playing') {
        const current: number = this.player.positionMs;
        this.danmakuClockPos = current > 0 ? current : this.danmakuNow();
        this.danmakuClockAt = Date.now();
        this.danmakuClockPlaying = true;
      } else if (state === 'paused' || state === 'stopped' || state === 'completed') {
        this.danmakuClockPos = this.danmakuNow();
        this.danmakuClockAt = Date.now();
        this.danmakuClockPlaying = false;
      }
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
      // 以播放器上报的进度为准重新锚定，弹幕不会随时间漂走
      this.danmakuClockPos = positionMs;
      this.danmakuClockAt = Date.now();
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
    this.player.onVideoSize = (width: number, height: number) => {
      // 只在竖屏连播用得上：按真实比例给画面容器定高，画面才能贴着顶部排，不再居中留黑
      const aspect: number = height > 0 ? height / width : 0;
      if (aspect > 0 && Math.abs(aspect - this.videoAspect) > 0.001) {
        this.videoAspect = aspect;
      }
    };
    this.bindKeyboard();
    this.bindAppLifecycle();
    this.startDanmakuLoop();
    this.bootstrap();
  }

  /**
   * 应用前后台：后台记下进度并暂停，回前台按「中断继续播放」自动接上。
   * 用 eventHub（EntryAbility 的 onForeground / onBackground 发事件）而不是 window 事件，
   * 各机型表现一致，也不会和全屏 / 键盘的窗口监听抢。
   */
  private bindAppLifecycle(): void {
    try {
      const hub = this.context().eventHub;
      this.appBgHandler = () => {
        this.onAppBackground();
      };
      this.appFgHandler = () => {
        this.onAppForeground();
      };
      hub.on('muli_app_background', this.appBgHandler);
      hub.on('muli_app_foreground', this.appFgHandler);
    } catch (err) {
      console.warn(`MuLiVideo app lifecycle bind failed: ${String(err)}`);
    }
  }

  private unbindAppLifecycle(): void {
    try {
      const hub = this.context().eventHub;
      if (this.appBgHandler !== undefined) {
        hub.off('muli_app_background', this.appBgHandler);
      }
      if (this.appFgHandler !== undefined) {
        hub.off('muli_app_foreground', this.appFgHandler);
      }
    } catch (err) {
      // context 已销毁时忽略
    }
    this.appBgHandler = undefined;
    this.appFgHandler = undefined;
  }

  private onAppBackground(): void {
    // 只有「正在播」才算中断：本来就是暂停状态，回来也不该自己动起来
    if (!this.player.isPlaying) {
      return;
    }
    this.interrupted = true;
    this.interruptMs = this.positionMs;
    this.player.pause();
  }

  private async onAppForeground(): Promise<void> {
    if (!this.interrupted) {
      return;
    }
    this.interrupted = false;
    if (!this.prefs.continuePlay) {
      return;
    }
    const target: number = this.interruptMs > 0 ? this.interruptMs : this.positionMs;
    if (target > 0) {
      this.player.seek(target);
    }
    await this.player.play();
    this.showControls();
    this.showHud('已从中断处继续播放');
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
        // 画布压到状态栏下面了，状态栏文字得用浅色（关闭沉浸 / 白色增量条时反过来）
        this.applyStatusBarContent(win, this.lightStatusBar());
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
      // 竖屏连播的滑出/滑入位移与画面高度都按整屏算
      if (this.stageH !== height) {
        this.stageH = height;
      }
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
      // 删隐名单先读出来：首屏评论落地时才能直接把隐掉的过滤掉
      await HiddenCommentStore.load(ctx);
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

  /**
   * 竖屏连播入口（工具行正中那颗向下箭头）。
   * 进入后画面向下铺满整屏、信息区变成贴底的浮层，退出即回到 16:9 常规排版。
   */
  private togglePortraitMode(): void {
    this.portraitMode = !this.portraitMode;
    // 进出连播都要把切换临时态（位移 / 预热 / 历史）清干净，避免上一条的封面串进来
    this.resetPortraitSwitchState();
    // 画布高度依赖模式，等布局落定再算一次，避免 16:9 的旧高度残留
    setTimeout(() => {
      this.syncCanvasSize();
    }, 60);
    if (this.portraitMode) {
      this.portraitInfoVisible = true;
      this.showControls();
      // 一进来就把下一条备好
      this.prefetchNextPortrait();
    }
  }

  /** 竖屏连播点「评论」：退出连播回到普通播放页，并直接把信息区切到评论区 */
  private exitPortraitToComments(): void {
    this.portraitMode = false;
    this.resetPortraitSwitchState();
    // 退出连播后画布回到 16:9，布局落定再校一次高度
    setTimeout(() => {
      this.syncCanvasSize();
    }, 60);
    // 强制切到评论 tab（即使当前下标已是 1，也要保证 Tabs controller 与高亮同步）
    this.infoTabIndex = 1;
    this.infoTab = TAB_KEYS[1];
    try {
      this.tabsController.changeIndex(1);
    } catch (err) {
      // Tabs 尚未挂载时忽略
    }
    if (!this.commentLoaded) {
      this.loadComments(true);
    }
    this.showControls();
  }

  aboutToDisappear(): void {
    this.stopDanmakuLoop();
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
    this.unbindAppLifecycle();
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

  /**
   * 载入视频详情 + 播放地址。
   *
   * prefetched 非空且 bvid 对得上时走「预热命中」分支：详情与播放地址都已经在手里，
   * 只做一次 setSource —— 竖屏连播上滑能立刻出画，靠的就是这条路径。
   */
  private async loadDetail(prefetched?: PortraitPrefetch | null): Promise<void> {
    this.loading = true;
    this.errorText = '';
    this.showRecommendCard = false;
    this.playEnded = false;
    this.displayExtra = 0;
    this.started = false;
    this.positionMs = 0;
    this.playError = '';
    this.playRetried = false;
    this.resetComments();
    // 换视频：弹幕列表 / 时钟 / 点赞态都属于上一条，先全部清掉再按新视频拉
    this.resetDanmaku();
    this.liked = false;
    this.likeCount = 0;
    this.likeTextUi = '';
    try {
      const warm: PortraitPrefetch | null = prefetched !== undefined ? prefetched : null;
      if (warm !== null && warm.param.bvid === this.videoParam.bvid && warm.url.length > 0) {
        const ready: VideoDetail = warm.detail;
        this.detail = ready;
        this.videoParam.bvid = ready.bvid;
        this.videoParam.aid = ready.aid;
        if (ready.cid > 0) {
          this.videoParam.cid = ready.cid;
        }
        this.likeCount = ready.likeCount;
        this.syncLikeText();
        this.loading = false;
        await this.player.setSource(warm.url);
        this.waitForSurface();
        this.loadAuthorStat(ready.authorMid);
        this.loadRecommendList(ready.bvid);
        this.loadLikeState();
        this.loadDanmaku();
        if (this.infoTabIndex === 1 && !this.commentLoaded) {
          this.loadComments(true);
        }
        this.prefetchNextPortrait();
        return;
      }
      const info: VideoDetail = await VideoService.detail(this.videoParam.bvid, this.videoParam.aid);
      this.detail = info;
      this.videoParam.bvid = info.bvid;
      this.videoParam.aid = info.aid;
      if (info.cid > 0) {
        this.videoParam.cid = info.cid;
      }
      this.likeCount = info.likeCount;
      this.syncLikeText();
      if (this.prefs.continuePlay) {
        this.resumeMs = await PlayerPrefs.loadProgress(this.context(), this.videoParam.bvid);
      }
      this.loading = false;
      await this.loadPlayUrl();
      // 作者粉丝/投稿与推荐列表都是「补充信息」，异步加载、失败静默，不能拖慢起播
      this.loadAuthorStat(info.authorMid);
      this.loadRecommendList(info.bvid);
      this.loadLikeState();
      this.loadDanmaku();
      // 连播 / 换集时若正停在评论版块，评论已随 resetComments 清空，这里补一次首屏
      if (this.infoTabIndex === 1 && !this.commentLoaded) {
        this.loadComments(true);
      }
      // 竖屏连播：这条刚开始播就把下一条备好
      this.prefetchNextPortrait();
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

  /** 播放页下方推荐列表：过滤当前视频与命中推荐过滤词的条目，最多 8 条 */
  private async loadRecommendList(bvid: string): Promise<void> {
    this.recommendLoading = true;
    try {
      const cards: Array<VideoCard> = await RecommendService.load(Math.floor(Math.random() * 50) + 2);
      const blocked: Array<string> = PlayerPrefs.keywords(this.prefs.filterRecommend);
      const list: Array<VideoCard> = [];
      for (let i = 0; i < cards.length; i++) {
        if (cards[i].bvid.length > 0 && cards[i].bvid !== bvid &&
          !PlayerPrefs.hitKeyword(cards[i].title, blocked)) {
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

  // ---------------- 点赞 ----------------

  /**
   * 读取当前账号对这条视频的点赞态。
   * 未登录 / 接口风控都按「未点赞」渲染，不弹错，也不影响播放。
   */
  private async loadLikeState(): Promise<void> {
    const aid: number = this.detail.aid;
    if (aid <= 0 || !BiliCookie.isLogin()) {
      this.liked = false;
      return;
    }
    try {
      const relation: VideoRelation = await InteractiveService.relation(aid);
      if (this.detail.aid === aid) {
        this.liked = relation.liked;
      }
    } catch (err) {
      console.warn(`MuLiVideo like state failed: ${String(err)}`);
    }
  }

  /**
   * 点赞 / 取消点赞。
   * 先乐观更新（点赞数字立刻 +1 或 -1、图标当场变色），失败再整体回滚并提示服务端原因。
   */
  private async toggleLike(): Promise<void> {
    if (this.likeBusy) {
      return;
    }
    if (!BiliCookie.isLogin()) {
      this.toast('请先登录后再点赞');
      return;
    }
    const aid: number = this.detail.aid;
    if (aid <= 0) {
      this.toast('视频信息还没就绪');
      return;
    }
    const target: boolean = !this.liked;
    const beforeLiked: boolean = this.liked;
    const beforeCount: number = this.likeCount;
    this.likeBusy = true;
    this.liked = target;
    this.likeCount = Math.max(0, beforeCount + (target ? 1 : -1));
    this.syncLikeText();
    try {
      await InteractiveService.setLike(aid, target);
      this.toast(target ? '已点赞' : '已取消点赞');
    } catch (err) {
      if (this.detail.aid === aid) {
        this.liked = beforeLiked;
        this.likeCount = beforeCount;
        this.syncLikeText();
      }
      this.toast(err instanceof Error ? err.message : '点赞失败');
    } finally {
      this.likeBusy = false;
    }
  }

  /** 把点赞数同步成展示文案；@State 直接参与 UI，改动必定触发刷新 */
  private syncLikeText(): void {
    if (this.likeCount > 0) {
      this.likeTextUi = shortCount(this.likeCount);
      return;
    }
    this.likeTextUi = this.detail.likeText.length > 0 ? this.detail.likeText : '';
  }

  // ---------------- 弹幕 ----------------

  private startDanmakuLoop(): void {
    if (this.danmakuTimer !== -1) {
      return;
    }
    this.danmakuTimer = setInterval(() => {
      this.drawDanmakuFrame();
    }, DANMAKU_FRAME_MS);
  }

  private stopDanmakuLoop(): void {
    if (this.danmakuTimer === -1) {
      return;
    }
    clearInterval(this.danmakuTimer);
    this.danmakuTimer = -1;
  }

  /** 弹幕时钟：播放中按墙钟外推，暂停时停住；拖动进度条由界面直接改锚点 */
  private danmakuNow(): number {
    const base: number = this.danmakuClockPlaying
      ? this.danmakuClockPos + Math.max(0, Date.now() - this.danmakuClockAt)
      : this.danmakuClockPos;
    if (this.durationMs > 0) {
      return Math.min(base, this.durationMs);
    }
    return base;
  }

  private danmakuSetClock(positionMs: number): void {
    this.danmakuClockPos = Math.max(0, positionMs);
    this.danmakuClockAt = Date.now();
  }

  /** 换视频 / 离页：弹幕列表、轨道、时钟一起清掉，避免上一条的弹幕串到新视频上 */
  private resetDanmaku(): void {
    this.danmakuToken += 1;
    this.danmakuList = [];
    this.danmakuActive = [];
    this.danmakuEmit = 0;
    this.danmakuCid = 0;
    this.danmakuLanes = [];
    this.danmakuLastPos = -1;
    this.danmakuWasOn = this.prefs.danmakuOn;
    this.danmakuSetClock(0);
    this.danmakuClockPlaying = false;
  }

  /**
   * 拉当前视频的弹幕。
   * token 用于丢弃过期响应：竖屏连播快速上滑时，上一条的弹幕不能落到新视频上。
   */
  private async loadDanmaku(): Promise<void> {
    const cid: number = this.videoParam.cid;
    const token: number = this.danmakuToken + 1;
    this.danmakuToken = token;
    this.danmakuList = [];
    this.danmakuActive = [];
    this.danmakuEmit = 0;
    this.danmakuLanes = [];
    this.danmakuLastPos = -1;
    this.danmakuCid = cid;
    if (cid <= 0 || !this.prefs.danmakuOn) {
      return;
    }
    try {
      const list: Array<DanmakuItem> = await DanmakuService.list(cid);
      if (token !== this.danmakuToken) {
        return;
      }
      this.danmakuList = list;
      // 列表回来时进度可能已经走了几秒：游标直接对齐当前位置，不要把开头几百条一次性倒出来
      this.danmakuEmit = this.danmakuLowerBound(this.danmakuNow());
      this.danmakuLastPos = this.danmakuNow();
    } catch (err) {
      console.warn(`MuLiVideo danmaku load failed: ${String(err)}`);
    }
  }

  /** 二分找第一条「时间严格大于 timeMs」的弹幕下标 */
  private danmakuLowerBound(timeMs: number): number {
    let low: number = 0;
    let high: number = this.danmakuList.length;
    while (low < high) {
      const mid: number = (low + high) >> 1;
      if (this.danmakuList[mid].timeMs <= timeMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /**
   * 把时间轴走到 now 的弹幕放进轨道。
   * 识别「大跨度跳转」（拖进度 / 切集）：超过 1.2s 回退或 2.5s 前进就重建游标并清空屏幕。
   */
  private pumpDanmaku(now: number): void {
    if (this.danmakuList.length === 0) {
      return;
    }
    if (this.danmakuLastPos >= 0 &&
      (now < this.danmakuLastPos - 1200 || now > this.danmakuLastPos + 2500)) {
      this.danmakuEmit = this.danmakuLowerBound(now);
      this.danmakuActive = [];
      this.danmakuLanes = [];
    }
    this.danmakuLastPos = now;
    while (this.danmakuEmit < this.danmakuList.length) {
      const item: DanmakuItem = this.danmakuList[this.danmakuEmit];
      if (item.timeMs > now) {
        break;
      }
      this.danmakuEmit += 1;
      this.spawnDanmaku(item, now);
    }
  }

  /** 弹幕可绘制的顶部安全边：常规播放时画布压在状态栏下面，弹幕要避开状态栏图标 */
  private danmakuTopPad(): number {
    if (this.fullscreen) {
      return 0;
    }
    if (this.portraitMode) {
      // 竖屏连播的画面盒本身已经从状态栏 + 顶栏下方开始，不再重复让位
      return 0;
    }
    return Math.max(0, this.topInset);
  }

  /**
   * 画布坐标是 vp，但 `ctx.font` 的 px 是物理像素（实测 26px 只画出 7vp 高），
   * 所以字号要乘屏幕密度；measureText 返回的也是物理像素，量到宽度后要除回去。
   */
  private danmakuPixelRatio(): number {
    if (this.danmakuRatio > 0) {
      return this.danmakuRatio;
    }
    try {
      this.danmakuRatio = this.getUIContext().vp2px(1);
    } catch (err) {
      this.danmakuRatio = 3;
    }
    if (!(this.danmakuRatio > 0)) {
      this.danmakuRatio = 3;
    }
    return this.danmakuRatio;
  }

  /** 按轨道分配位置；轨道全被占就丢弃这一条（弹幕海的正常处理方式） */
  private spawnDanmaku(item: DanmakuItem, now: number): void {
    if (this.danmakuActive.length >= DANMAKU_MAX_ACTIVE) {
      return;
    }
    if (this.danmakuWidth <= 1 || this.danmakuHeight <= 1) {
      return;
    }
    // 弹幕过滤词：命中任一词的弹幕直接不上屏
    if (PlayerPrefs.hitKeyword(item.text, PlayerPrefs.keywords(this.prefs.filterDanmaku))) {
      return;
    }
    const size: number = this.prefs.danmakuSize > 0 ? this.prefs.danmakuSize : 18;
    const laneHeight: number = Math.max(18, Math.round(size * 1.6));
    const ratio: number = this.prefs.danmakuArea > 0 ? this.prefs.danmakuArea : 1;
    const topPad: number = this.danmakuTopPad();
    const usable: number = Math.max(laneHeight, this.danmakuHeight - topPad);
    const lanes: number = Math.max(1, Math.floor(usable * ratio / laneHeight));
    this.ensureDanmakuLanes(lanes);
    const fixed: boolean = item.mode === 4 || item.mode === 5;
    const pixelRatio: number = this.danmakuPixelRatio();
    this.danmakuCtx.font = `${Math.round(size * pixelRatio)}px sans-serif`;
    const width: number = Math.max(16, this.danmakuCtx.measureText(item.text).width / pixelRatio);
    let lane: number = -1;
    if (fixed && item.mode === 4) {
      for (let i = lanes - 1; i >= 0; i--) {
        if (this.danmakuLanes[i].freeAt <= now) {
          lane = i;
          break;
        }
      }
    } else {
      for (let i = 0; i < lanes; i++) {
        if (this.danmakuLanes[i].freeAt <= now) {
          lane = i;
          break;
        }
      }
    }
    if (lane < 0) {
      return;
    }
    const speed: number = this.prefs.danmakuSpeed > 0 ? this.prefs.danmakuSpeed : 1;
    const duration: number = fixed ? DANMAKU_FIXED_MS : Math.round(DANMAKU_TRAVEL_MS / speed);
    const bullet: ActiveDanmaku = new ActiveDanmaku();
    bullet.text = item.text;
    bullet.color = item.color;
    bullet.lane = lane;
    bullet.fromBottom = fixed && item.mode === 4;
    bullet.fixed = fixed;
    bullet.bornMs = now;
    bullet.durationMs = duration;
    bullet.width = width;
    this.danmakuActive.push(bullet);
    // 轨道什么时候能再塞一条：滚动弹幕等到它整条进入画面（再留一点间距），固定弹幕等它整段停留结束
    const hold: number = fixed
      ? duration + 400
      : Math.round(duration * width / Math.max(1, this.danmakuWidth + width)) + 140;
    this.danmakuLanes[lane].freeAt = now + hold;
  }

  private ensureDanmakuLanes(lanes: number): void {
    if (this.danmakuLanes.length === lanes) {
      return;
    }
    const next: Array<DanmakuLane> = [];
    for (let i = 0; i < lanes; i++) {
      next.push(i < this.danmakuLanes.length ? this.danmakuLanes[i] : new DanmakuLane());
    }
    this.danmakuLanes = next;
  }

  /**
   * 每帧重绘。
   *
   * 用一块 Canvas 而不是几十个 Text 组件：位置全部按视频时间轴算，
   * 暂停、拖动、切集都能精确对上；30fps 重绘一次也比频繁增删组件便宜。
   */
  private drawDanmakuFrame(): void {
    if (!this.danmakuReady || this.danmakuWidth <= 1 || this.danmakuHeight <= 1) {
      return;
    }
    const ctx: CanvasRenderingContext2D = this.danmakuCtx;
    ctx.clearRect(0, 0, this.danmakuWidth, this.danmakuHeight);
    const now: number = this.danmakuNow();
    if (!this.prefs.danmakuOn) {
      if (this.danmakuWasOn) {
        this.danmakuWasOn = false;
        this.danmakuActive = [];
        this.danmakuLanes = [];
      }
      this.danmakuLastPos = now;
      return;
    }
    if (!this.danmakuWasOn) {
      this.danmakuWasOn = true;
      this.danmakuEmit = this.danmakuLowerBound(now);
      this.danmakuLastPos = now;
      if (this.danmakuList.length === 0 && this.danmakuCid > 0) {
        this.loadDanmaku();
      }
    }
    this.pumpDanmaku(now);
    if (this.danmakuActive.length === 0) {
      return;
    }
    const size: number = this.prefs.danmakuSize > 0 ? this.prefs.danmakuSize : 18;
    const laneHeight: number = Math.max(18, Math.round(size * 1.6));
    const opacity: number = this.prefs.danmakuOpacity > 0 ? this.prefs.danmakuOpacity : 1;
    const topPad: number = this.danmakuTopPad();
    const ratio: number = this.danmakuPixelRatio();
    ctx.font = `${Math.round(size * ratio)}px sans-serif`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.lineWidth = Math.max(1.2, size / 10);
    ctx.strokeStyle = 'rgba(0,0,0,0.55)';
    const alive: Array<ActiveDanmaku> = [];
    for (let i = 0; i < this.danmakuActive.length; i++) {
      const bullet: ActiveDanmaku = this.danmakuActive[i];
      if (bullet.durationMs <= 0) {
        continue;
      }
      const progress: number = (now - bullet.bornMs) / bullet.durationMs;
      if (progress >= 1.02 || progress < -0.5) {
        continue;
      }
      const p: number = Math.max(0, Math.min(1, progress));
      const x: number = bullet.fixed
        ? (this.danmakuWidth - bullet.width) / 2
        : this.danmakuWidth - (this.danmakuWidth + bullet.width) * p;
      const y: number = bullet.fromBottom
        ? this.danmakuHeight - (bullet.lane + 1) * laneHeight + 3
        : topPad + bullet.lane * laneHeight + 3;
      let fade: number = 1;
      if (bullet.fixed && p > 0.82) {
        fade = Math.max(0, (1 - p) / 0.18);
      }
      ctx.globalAlpha = Math.max(0, Math.min(1, opacity * fade));
      // 先描边再填充：浅色弹幕压在亮画面上也能看清
      ctx.strokeText(bullet.text, x, y);
      ctx.fillStyle = bullet.color;
      ctx.fillText(bullet.text, x, y);
      alive.push(bullet);
    }
    this.danmakuActive = alive;
    ctx.globalAlpha = 1;
  }

  /** 总开关（工具行 / 竖屏操作行 / 设置面板三处共用） */
  private toggleDanmaku(): void {
    this.prefs.danmakuOn = !this.prefs.danmakuOn;
    this.prefs.save(this.context(), 'danmakuOn', this.prefs.danmakuOn);
    if (this.prefs.danmakuOn && this.danmakuList.length === 0) {
      this.loadDanmaku();
    }
    this.toast(this.prefs.danmakuOn ? '弹幕已开启' : '弹幕已关闭');
  }

  private openDanmakuComposer(): void {
    if (!BiliCookie.isLogin()) {
      this.toast('请先登录后再发弹幕');
      return;
    }
    if (this.detail.cid <= 0) {
      this.toast('视频信息还没就绪');
      return;
    }
    this.danmakuDraft = '';
    // 发弹幕时自动暂停：输入 / 选表情期间画面不动，方便对时间点；发送或关闭后自动续播
    this.danmakuResume = this.playing;
    if (this.danmakuResume) {
      this.player.pause();
    }
    this.danmakuComposerVisible = true;
    setTimeout(() => {
      try {
        this.getUIContext().getFocusController().requestFocus(DANMAKU_INPUT_ID);
      } catch (err) {
        // 申请不到焦点也能手点输入框
      }
    }, 120);
  }

  private closeDanmakuComposer(): void {
    this.danmakuComposerVisible = false;
    this.danmakuDraft = '';
    this.resumeAfterDanmaku();
  }

  /** 关掉弹幕浮层后接着播（原本就是暂停态的不动） */
  private resumeAfterDanmaku(): void {
    if (!this.danmakuResume) {
      return;
    }
    this.danmakuResume = false;
    this.player.play();
  }

  private async sendDanmaku(): Promise<void> {
    const text: string = this.danmakuDraft.trim();
    if (text.length === 0) {
      this.toast('说点什么吧');
      return;
    }
    if (this.danmakuSending) {
      return;
    }
    this.danmakuSending = true;
    try {
      const now: number = this.danmakuNow();
      await DanmakuService.send(this.detail.cid, this.detail.bvid, text, now);
      // 自己发的弹幕立刻上屏（b 站同款体验），不必等服务端回刷
      this.spawnDanmaku(new DanmakuItem(now, 1, '#FFFFFF', text), now);
      this.closeDanmakuComposer();
      this.toast('弹幕已发送');
    } catch (err) {
      this.toast(err instanceof Error ? err.message : '弹幕发送失败');
    } finally {
      this.danmakuSending = false;
    }
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

  // ---------------- 评论长按操作 ----------------

  /** 长按某条评论：弹出底部操作面板（复制 / 分享 / 举报 / 删除或删隐） */
  private openCommentSheet(item: VideoComment, isSub: boolean): void {
    this.sheetComment = item;
    this.sheetCommentIsSub = isSub;
    this.sheetCommentVisible = true;
  }

  /** 自己的评论是「删除」，别人的是「删隐」（只对自己隐藏，本地记名单） */
  private sheetDeleteLabel(): string {
    return this.isMyComment() ? '删除回复' : '删隐回复';
  }

  private isMyComment(): boolean {
    const myMid: number = BiliCookie.mid();
    return myMid > 0 && this.sheetComment.mid === myMid;
  }

  /** 复制评论正文（表情在 clipboard 里就是原始 `[doge]` 标记，和 b 站一致） */
  private async copyComment(): Promise<void> {
    const text: string = this.sheetComment.message;
    if (text.length === 0) {
      this.toast('这条评论没有正文');
      return;
    }
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      await pasteboard.getSystemPasteboard().setData(data);
      this.toast('已复制');
    } catch (err) {
      console.warn(`MuLiVideo copy failed: ${String(err)}`);
      this.toast('复制失败');
    }
  }

  /** 删除自己的评论 / 把别人的评论删隐（仅自己不可见） */
  private async deleteOrHideComment(): Promise<void> {
    const item: VideoComment = this.sheetComment;
    if (item.rpid.length === 0) {
      return;
    }
    if (this.isMyComment()) {
      try {
        await CommentService.remove(this.detail.aid, item.rpid);
        this.dropCommentLocally(item.rpid, this.sheetCommentIsSub);
        this.toast('已删除');
      } catch (err) {
        this.toast(err instanceof Error ? err.message : '删除失败');
      }
      return;
    }
    await HiddenCommentStore.hide(this.context(), item.rpid);
    this.dropCommentLocally(item.rpid, this.sheetCommentIsSub);
    this.toast('已删隐，仅自己不可见');
  }

  /** 过滤掉被「删隐」的评论（本地黑名单，只影响自己） */
  private filterHidden(items: Array<VideoComment>): Array<VideoComment> {
    const out: Array<VideoComment> = [];
    for (let i = 0; i < items.length; i++) {
      if (!HiddenCommentStore.isHidden(items[i].rpid)) {
        out.push(items[i]);
      }
    }
    return out;
  }

  /** 从当前列表里摘掉一条（删除 / 删隐之后立刻生效，不必等刷新） */
  private dropCommentLocally(rpid: string, isSub: boolean): void {
    if (isSub) {
      this.subComments = this.subComments.filter((c: VideoComment) => c.rpid !== rpid);
      if (this.subTotal > 0) {
        this.subTotal -= 1;
      }
      return;
    }
    this.comments = this.comments.filter((c: VideoComment) => c.rpid !== rpid);
    if (this.commentTotal > 0) {
      this.commentTotal -= 1;
    }
    if (this.expandedRpid === rpid) {
      this.collapseSub();
    }
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
      const items: Array<VideoComment> = this.filterHidden(
        CommentService.markUpper(feed.items, this.detail.authorMid));
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
    if (panel === 'emoji') {
      this.loadComposerEmotes();
    }
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (err) {
      // 取不到焦点控制器时忽略，面板照样展示
    }
  }

  /** 拉一次表情面板数据（图片版）；拿到空列表就保持 `[文字]` 兜底 */
  private async loadComposerEmotes(): Promise<void> {
    if (this.composerEmotesLoading || this.composerEmotes.length > 0) {
      return;
    }
    this.composerEmotesLoading = true;
    try {
      const list: Array<CommentEmote> = await CommentService.emotePanel();
      if (list.length > 0) {
        this.composerEmotes = list;
      }
    } catch (err) {
      // 面板接口偶发失败无妨，保留文字兜底
    } finally {
      this.composerEmotesLoading = false;
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
      const items: Array<VideoComment> = this.filterHidden(
        CommentService.markUpper(feed.items, this.detail.authorMid));
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

  /** 下拉刷新：忽略已翻页状态，从第一页重拉（排序不变），方便看到最新评论 */
  private async refreshComments(): Promise<void> {
    if (this.commentsLoading) {
      // 已有请求在跑：别再叠一个，直接收起转圈，避免两份响应互相覆盖
      this.commentRefreshing = false;
      return;
    }
    this.commentCursor = '';
    this.commentEnd = false;
    this.commentLoaded = true;
    await this.loadComments(true);
    this.commentRefreshing = false;
    if (this.commentsError.length > 0) {
      this.toast(this.commentsError);
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

  /** 竖屏连播里点「全屏」：切成横屏全屏播放，退出时回到连播（而不是普通播放页） */
  private async enterFullscreenFromPortrait(): Promise<void> {
    if (this.fullscreen) {
      return;
    }
    this.fullscreenFromPortrait = true;
    // 全屏沿用普通播放页那套控制条，连播的浮层与拖动位移先收掉
    this.portraitMode = false;
    this.resetPortraitSwitchState();
    this.controlsVisible = true;
    await this.enterFullscreen();
    this.showControls();
  }

  private async restorePortrait(): Promise<void> {
    if (!this.fullscreen) {
      return;
    }
    this.fullscreen = false;
    const backToPortrait: boolean = this.fullscreenFromPortrait;
    this.fullscreenFromPortrait = false;
    try {
      const win: window.Window = await window.getLastWindow(this.context());
      await win.setWindowSystemBarEnable(['status']);
      await win.setPreferredOrientation(window.Orientation.PORTRAIT);
    } catch (err) {
      console.warn(`MuLiVideo restore failed: ${String(err)}`);
    }
    if (backToPortrait) {
      // 从连播进来的全屏：退出来要回到连播
      this.portraitMode = true;
      this.resetPortraitSwitchState();
      this.showControls();
      this.prefetchNextPortrait();
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

  /** 竖屏顶部「分享」：调起系统分享面板，把标题 + b 站链接作为纯文本分享出去 */
  private async shareVideo(): Promise<void> {
    try {
      const title: string = this.detail.title.length > 0 ? this.detail.title : '沐哩视频';
      const bvid: string = this.detail.bvid;
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
      console.warn(`MuLiVideo share failed: ${String(err)}`);
      this.toast('分享未完成');
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
    const localY: number = event.fingerList.length > 0 ? event.fingerList[0].localY : this.surfaceHeight / 2;
    // 竖屏连播：视频区固定铺满，按上下半分区。
    // 下半 50%（全宽）：上下切换视频；上半 50%：左 20% 亮度 / 右 20% 音量，中间盲区。
    if (this.portraitMode && !this.fullscreen) {
      if (localY >= this.surfaceHeight / 2) {
        return 'portraitSwitch';
      }
      const portraitBound: number = this.surfaceWidth * PORTRAIT_SIDE_ZONE_RATIO;
      if (localX < portraitBound) {
        return 'brightness';
      }
      if (localX > this.surfaceWidth - portraitBound) {
        return 'volume';
      }
      return 'center';
    }
    // 其它模式（普通竖屏 / 全屏）保持原判定：左 35% 亮度 / 右 35% 音量，中间盲区。
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
    // 切换动画进行中忽略新手势，避免动画未完又叠加位移
    if (!this.prefs.quickGestures || this.portraitSwitching) {
      return;
    }
    const zone: string = this.gestureZone(event);
    // 竖屏连播下半屏由 gestureZone 直接判为 portraitSwitch（上下拖动切换视频），
    // 不初始化亮度/音量；上半屏左右两侧仍走原亮度/音量，中间盲区空处理。
    // 与水平快进、单击双击、长按都互不干扰。
    if (zone === 'portraitSwitch') {
      this.gestureMode = 'portraitSwitch';
      this.portraitDragY = 0;
      // 预取没备好就现场补一次：多数情况下换完上一条就已经备好了
      if (this.portraitPrefetch === null) {
        this.prefetchNextPortrait();
      }
      return;
    }
    this.gestureMode = zone;
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
    // 竖屏下半屏：视频与浮层跟随手指上下移动（跟手），松手再决定切换或回弹。
    // 向下拖动只给 0.35 阻尼并限制在较小范围，作为「取消切换」的反馈。
    if (this.gestureMode === 'portraitSwitch') {
      const limit: number = this.switchShift();
      // 上滑：全程跟手（下一支）；下滑：有历史记录才能跟手回上一条，
      // 已经到头了就只给 0.35 阻尼，手感上是「拉不动」而不是完全没反应。
      if (dy > 0 && this.portraitHistory.length === 0) {
        this.portraitDragY = Math.min(limit * 0.35, dy * 0.35);
      } else {
        this.portraitDragY = Math.max(-limit, Math.min(limit, dy));
      }
      return;
    }
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

  private onVerticalEnd(event?: GestureEvent): void {
    // 竖屏下半屏：松手按「位移 + 甩动速度」决定——向上滑到下一个、向下滑回上一个，
    // 都不够就回弹。位移基准是画面盒高度（≈210~470vp），取 22%、夹在 30~60vp，
    // 短滑几十 vp 就能切换；位移不够但甩得快（≥780 vp/s）同样算数。
    if (this.gestureMode === 'portraitSwitch') {
      const dy: number = event !== undefined ? event.offsetY : 0;
      const velocity: number = event !== undefined ? event.velocityY : 0;
      this.gestureMode = '';
      this.hudVisible = false;
      const limit: number = this.switchShift();
      const trigger: number = Math.max(30, Math.min(PORTRAIT_SWITCH_TRIGGER_VP, limit * 0.22));
      const flick: boolean = Math.abs(velocity) >= PORTRAIT_SWITCH_VELOCITY;
      const goUp: boolean = dy < 0 && (dy <= -trigger || flick);
      const goDown: boolean = dy > 0 && this.portraitHistory.length > 0 && (dy >= trigger || flick);
      if (goUp) {
        this.runPortraitSwitch(-1);
      } else if (goDown) {
        this.runPortraitSwitch(1);
      } else {
        this.animatePortraitY(0, PORTRAIT_SLIDE_OUT_MS);
      }
      return;
    }
    this.gestureMode = '';
    this.showControls();
  }

  /** 竖屏连播：把视频/浮层位移动画到目标值，返回 Promise 便于串联滑出 → 切换 → 滑入 */
  private animatePortraitY(target: number, duration: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      try {
        this.getUIContext().animateTo({
          duration: duration,
          curve: Curve.EaseOut,
          onFinish: () => {
            resolve();
          }
        }, () => {
          this.portraitDragY = target;
        });
      } catch (err) {
        this.portraitDragY = target;
        resolve();
      }
    });
  }

  /**
   * 竖屏连播：画面盒里的内容滑出去 → 换源 → 新画面就地接上。
   *
   * direction = -1 上滑（下一个），+1 下滑（上一个）。
   * 换源前先把旧视频暂停：否则旧视频的音频会跟着漂在新画面上（用户反馈的「音频还是上一个视频的」）。
   * 换源优先用预热好的结果，正常情况松手后几百毫秒就能出画。
   *
   * 位移基准是「画面盒高度」而不是整屏：滑到底时目标封面正好落进画面盒，
   * 这时把位移归零、换成新视频就行，不需要再反向滑一遍，也不会整屏闪一张封面。
   */
  private async runPortraitSwitch(direction: number): Promise<void> {
    if (this.portraitSwitching) {
      return;
    }
    this.portraitSwitching = true;
    const h: number = this.switchShift();
    const before: PortraitEntry = new PortraitEntry(
      new VideoOpenParam(this.videoParam.bvid, this.videoParam.aid, this.videoParam.cid),
      this.detail.cover);
    const beforeBvid: string = this.videoParam.bvid;

    // 1) 先停掉旧视频：静音比画面晚一步会让人以为切错片
    this.player.pause();

    // 2) 当前画面滑出画面盒（目标封面正好滑进来）
    await this.animatePortraitY(direction < 0 ? -h : h, PORTRAIT_SLIDE_OUT_MS);

    // 3) 换源（画面盒里此刻露的是目标视频的封面，不是黑屏）
    let switched: boolean = false;
    if (direction < 0) {
      switched = await this.applyNextPortrait(before);
    } else {
      switched = await this.applyPrevPortrait();
    }

    // 4) 失败：把原视频拉回画面盒
    if (!switched) {
      if (this.videoParam.bvid !== beforeBvid) {
        this.videoParam = before.param;
        await this.loadDetail();
      } else {
        this.player.play();
      }
      await this.animatePortraitY(0, PORTRAIT_SLIDE_IN_MS);
      this.toast('切换失败，已返回');
      this.portraitSwitching = false;
      return;
    }
    // 5) 新视频就地接上：位移归零，画面盒里换成的正是刚才那张封面（detail.cover），像素级无缝
    this.portraitDragY = 0;
    this.portraitNextCover = '';
    this.portraitPrevCover = this.portraitHistory.length > 0
      ? this.portraitHistory[this.portraitHistory.length - 1].cover : '';
    this.portraitSwitching = false;
    // 换完立刻预热下一条，下一次上滑才不会又等几秒
    this.prefetchNextPortrait();
  }

  /** 上滑切到下一条：优先用预取结果，没有就现场随机取一条 */
  private async applyNextPortrait(before: PortraitEntry): Promise<boolean> {
    const prefetched: PortraitPrefetch | null = this.portraitPrefetch;
    this.portraitPrefetch = null;
    this.portraitPrefetchBvid = '';
    // 注意：这里不清 portraitNextCover —— 换源期间画面盒里正显示着这张封面，清了会闪黑
    if (prefetched !== null) {
      this.portraitHistory.push(before);
      this.portraitPrevCover = before.cover;
      this.videoParam = prefetched.param;
      await this.loadDetail(prefetched);
      return this.videoParam.bvid === prefetched.param.bvid && this.detail.bvid.length > 0 &&
        this.playError.length === 0;
    }
    const beforeBvid: string = this.videoParam.bvid;
    await this.playRandomNext();
    if (this.videoParam.bvid === beforeBvid) {
      return false;
    }
    this.portraitHistory.push(before);
    this.portraitPrevCover = before.cover;
    return this.playError.length === 0;
  }

  /** 下滑回到上一条 */
  private async applyPrevPortrait(): Promise<boolean> {
    if (this.portraitHistory.length === 0) {
      return false;
    }
    const entry: PortraitEntry | undefined = this.portraitHistory.pop();
    if (entry === undefined || entry.param.bvid.length === 0) {
      return false;
    }
    // 预热的是「随机下一条」，回退后已经不成立了，直接作废
    this.portraitPrefetch = null;
    this.portraitPrefetchBvid = '';
    this.portraitNextCover = '';
    // portraitPrevCover 留给切换动画当预览，切完由 runPortraitSwitch 重置为新的历史栈顶
    this.videoParam = entry.param;
    await this.loadDetail();
    return this.videoParam.bvid === entry.param.bvid && this.playError.length === 0;
  }

  /**
   * 竖屏连播：后台预热下一条（详情 + 取流）。
   *
   * 上滑黑屏的根因是「松手之后才去请求详情和播放地址」，网络 + prepare 三五秒就过去了。
   * 这里在当前视频开始播之后就先把下一条备好，松手时只剩一次 setSource。
   */
  private async prefetchNextPortrait(): Promise<void> {
    if (!this.portraitMode || this.fullscreen) {
      return;
    }
    if (this.portraitPrefetching || this.portraitPrefetch !== null) {
      return;
    }
    this.portraitPrefetching = true;
    try {
      const cards: Array<VideoCard> = await RecommendService.load(Math.floor(Math.random() * 50) + 2);
      let picked: VideoCard | null = null;
      for (let i = 0; i < cards.length; i++) {
        if (cards[i].bvid.length > 0 && cards[i].bvid !== this.videoParam.bvid) {
          picked = cards[i];
          break;
        }
      }
      if (picked === null) {
        return;
      }
      const info: VideoDetail = await VideoService.detail(picked.bvid, picked.aid);
      if (info.bvid.length === 0) {
        return;
      }
      const cid: number = info.cid > 0 ? info.cid : picked.cid;
      const url: string = await VideoService.playUrl(info.bvid, cid, info.aid, this.prefs.quality);
      if (url.length === 0) {
        return;
      }
      // 期间可能已经退出连播 / 已经切走：目标还成立才收下
      if (!this.portraitMode || this.fullscreen || this.portraitPrefetch !== null) {
        return;
      }
      this.portraitPrefetch = new PortraitPrefetch(new VideoOpenParam(info.bvid, info.aid, cid), info, url);
      this.portraitPrefetchBvid = info.bvid;
      this.portraitNextCover = info.cover;
    } catch (err) {
      console.warn(`MuLiVideo prefetch ignored: ${String(err)}`);
    } finally {
      this.portraitPrefetching = false;
    }
  }

  /** 退出连播 / 换片时把预热与切换相关的临时状态清干净 */
  private resetPortraitSwitchState(): void {
    this.portraitDragY = 0;
    this.portraitPrefetch = null;
    this.portraitPrefetchBvid = '';
    this.portraitPrefetching = false;
    this.portraitHistory = [];
    this.portraitNextCover = '';
    this.portraitPrevCover = '';
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
    // 三种播放模式在竖屏 / 横屏下行为一致（V2.1.0）：
    // 0 单集循环 → 从头再放；1 随机连播 → 横屏压栈下一条 / 竖屏滑下一条；2 停止推荐 → 黑屏只留推荐。
    const mode: number = this.prefs.playMode;
    if (mode === 0) {
      this.playEnded = false;
      // 用串行的「从头重播」而不是 seek(0)+play()：completed 终态下两者会抢时序，进度回不到 0
      this.player.replay();
      this.showHud('单集循环');
      return;
    }
    if (mode === 1) {
      this.playEnded = false;
      if (this.portraitMode) {
        this.runPortraitSwitch(-1);
      } else {
        this.playRandomNext();
      }
      return;
    }
    // 停止推荐：视频区黑屏，只展示推荐内容与「重播视频」
    this.playEnded = true;
    this.showRecommendCard = true;
    this.controlsVisible = true;
    this.loadRecommendCard();
    this.loadRecommendList(this.videoParam.bvid);
  }

  /** 重播刚刚播完的这条：清掉结束态，从头开始 */
  private replayVideo(): void {
    this.playEnded = false;
    this.showRecommendCard = false;
    this.positionMs = 0;
    this.danmakuSetClock(0);
    this.player.replay();
    this.showControls();
  }

  private async loadRecommendCard(): Promise<void> {
    try {
      const cards: Array<VideoCard> = await RecommendService.load(Math.floor(Math.random() * 50) + 2);
      const blocked: Array<string> = PlayerPrefs.keywords(this.prefs.filterRecommend);
      let picked: VideoCard | null = null;
      for (let i = 0; i < cards.length; i++) {
        if (cards[i].bvid.length > 0 && cards[i].bvid !== this.videoParam.bvid &&
          !PlayerPrefs.hitKeyword(cards[i].title, blocked)) {
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
      const blocked: Array<string> = PlayerPrefs.keywords(this.prefs.filterRecommend);
      const picked: VideoCard | null = cards.length > 0 ? cards[Math.floor(Math.random() * cards.length)] : null;
      if (picked === null || picked.bvid.length === 0) {
        this.toast('暂无可连播的推荐视频');
        return;
      }
      if (PlayerPrefs.hitKeyword(picked.title, blocked)) {
        this.toast('随机到的视频命中了推荐过滤词，已跳过');
        return;
      }
      // 竖屏连播：先在盒子里滑出再换源，无法压栈（要保持跟手连续），仍走原地换源
      if (!this.portraitMode && this.pathStack !== undefined) {
        // 横屏：压一个新播放页，覆盖在当前视频上——返回就能回到上一条，不会直接退到首页
        this.holdSpeedActive = false;
        this.pathStack.pushPathByName('video', new VideoOpenParam(picked.bvid, picked.aid, picked.cid));
        return;
      }
      // 竖屏连播：先把目标封面挂到切换垫层上，即使取流慢也不会是一屏纯黑
      if (this.portraitMode && picked.cover.length > 0) {
        this.portraitNextCover = picked.cover;
      }
      this.videoParam = new VideoOpenParam(picked.bvid, picked.aid, picked.cid);
      this.holdSpeedActive = false;
      await this.loadDetail();
    } catch (err) {
      this.toast('连播加载失败，请重试');
    }
  }

  /** 点击推荐卡：横屏压栈打开新视频（返回回到当前这条），竖屏连播内原地换源 */
  private openCard(card: VideoCard): void {
    if (card.bvid.length === 0) {
      return;
    }
    this.holdSpeedActive = false;
    if (!this.portraitMode && this.pathStack !== undefined) {
      this.pathStack.pushPathByName('video', new VideoOpenParam(card.bvid, card.aid, card.cid));
      return;
    }
    this.briefExpanded = false;
    this.resetTab();
    this.videoParam = new VideoOpenParam(card.bvid, card.aid, card.cid);
    this.loadDetail();
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }

  private async onSettingsChanged(key: string, value: number | boolean | string): Promise<void> {
    if (key === 'quality') {
      this.showHud('清晰度已切换，正在重载');
      await this.loadPlayUrl();
    } else if (key === 'longPressSpeed' && typeof value === 'number') {
      this.showHud(`长按倍速 ${value.toFixed(2)}x`);
    } else if (key === 'danmakuOn') {
      // 设置面板里重新打开：之前关着时没拉列表，这里补一次
      if (value === true && this.danmakuList.length === 0 && this.videoParam.cid > 0) {
        this.loadDanmaku();
      }
    } else if (key === 'filterRecommend') {
      // 过滤词改了：下方推荐与结束态推荐卡都按新词重拉
      this.loadRecommendList(this.videoParam.bvid);
      if (this.showRecommendCard) {
        this.loadRecommendCard();
      }
      this.showHud('推荐过滤已更新');
    } else if (key === 'filterDanmaku') {
      // 弹幕过滤词是逐帧读取的，清一下屏上已存在的即可立即见效
      this.danmakuActive = [];
      this.showHud('弹幕过滤已更新');
    }
    this.showControls();
  }

  // ---------------- UI ----------------

  @Builder
  topBar() {
    Row({ space: 8 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_backward'))
          .fontSize(20)
          .fontColor([$r('app.color.text_on_media')])
      }
      .width(34)
      .height(34)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(TOP_ICON_CHIP_BG ? $r('app.color.scrim') : Color.Transparent)
      .borderRadius(17)
      .onClick(() => {
        this.onBack();
      })

      // 一键回首页：推荐视频层层压栈后，不必一层层返回
      Row() {
        SymbolGlyph($r('sys.symbol.house'))
          .fontSize(17)
          .fontColor([$r('app.color.text_on_media')])
      }
      .width(34)
      .height(34)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(TOP_ICON_CHIP_BG ? $r('app.color.scrim') : Color.Transparent)
      .borderRadius(17)
      .onClick(() => {
        this.goHome();
      })

      Blank()

      // 分享（调起系统分享面板）
      Row() {
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(17)
          .fontColor([$r('app.color.text_on_media')])
      }
      .width(34)
      .height(34)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(TOP_ICON_CHIP_BG ? $r('app.color.scrim') : Color.Transparent)
      .borderRadius(17)
      .onClick(() => {
        this.shareVideo();
      })

      // 悬浮窗（xfcb 白色填充，与其他按钮同用 scrim 半透明圆底）
      Row() {
        Image($r('app.media.xfcb'))
          .width(18)
          .height(18)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      }
      .width(34)
      .height(34)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(TOP_ICON_CHIP_BG ? $r('app.color.scrim') : Color.Transparent)
      .borderRadius(17)
      .onClick(() => {
        this.toast('悬浮窗播放待接入');
      })
    }
    .width('100%')
    .height(PLAYER_BAR_HEIGHT + this.topSafe())
    // 画布压到状态栏下面了，返回键与标题要让开状态栏，否则会和时间 / 电量挤在一行
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING, top: 4 + this.topSafe() })
    .alignItems(VerticalAlign.Center)
  }

  /** 状态栏占位：全屏时系统栏已隐藏；不沉浸时那一条由增量色块本身占住，控件不用再让 */
  private topSafe(): number {
    if (this.fullscreen) {
      return 0;
    }
    return this.topImmersive ? this.topInset : 0;
  }

  /** 关闭沉浸时顶部增量条的颜色 */
  private insetColor(): ResourceColor {
    return this.topInsetColor === 1 ? Color.White : Color.Black;
  }

  /** 状态栏文字 / 图标的明暗：压在黑底上用浅色，白色增量条上用深色 */
  private lightStatusBar(): boolean {
    return this.topImmersive || this.topInsetColor === 0;
  }

  /** 设置页改了沉浸 / 增量颜色：立刻同步状态栏图标明暗（窗口属性只在下发时生效） */
  private onTopStyleChanged(): void {
    if (this.fullscreen || this.mainWin === undefined) {
      return;
    }
    this.applyStatusBarContent(this.mainWin, this.lightStatusBar());
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
          // 弹幕跟着进度条走：拖动时立刻按新位置重排，松手 seek 后不用再等一次同步
          this.danmakuSetClock(value);
          if (mode === SliderChangeMode.End) {
            this.player.seek(value);
            this.showControls();
          }
        })
      Text(this.formatMs(this.durationMs))
        .fontSize(11)
        .fontColor($r('app.color.text_on_media'))
      // 播完后（停止推荐模式）控制条右侧出现「重播视频」，不必回到顶部再点一次播放
      if (this.playEnded) {
        Text('重播视频')
          .fontSize(11)
          .fontColor($r('app.color.text_on_media'))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor($r('app.color.scrim'))
          .borderRadius(12)
          .margin({ right: 4 })
          .onClick(() => {
            this.replayVideo();
          })
      }
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

  /**
   * 竖屏连播的画面盒几何。
   *
   * - 竖屏视频（高 > 宽）：宽度直接铺满屏幕，高度按真实比例算（`width * aspect`），从顶栏下方起排。
   *   不再按「顶栏下方 ~ 信息区上方」那段空间去压缩 —— 一压缩，9:16 的画面只剩约七成宽，
   *   两侧留出黑边，看起来像视频被缩小了；超出底部的那截由底部浮层（渐变转黑）盖住，与常见竖屏流的观感一致。
   * - 横屏视频：仍按 16:9 自然高度算，再把「顶栏下方 ~ 信息区上方」的剩余空间上下平分，避免贴在顶部晾一大片黑。
   */
  private portraitFrame(): PortraitFrame {
    const stage: number = this.stageH > 0 ? this.stageH : 780;
    const width: number = this.surfaceWidth > 0 ? this.surfaceWidth : 360;
    const aspect: number = this.videoAspect > 0 ? this.videoAspect : 9 / 16;
    const topLimit: number = this.topInset + PLAYER_BAR_HEIGHT + PORTRAIT_TOP_GAP;
    const natural: number = Math.round(width * aspect);

    if (aspect > 1.02) {
      // 屏宽定宽、等比定高：9:16 的片子高度会接近整屏，底部那一截自然落到浮层（渐变转黑）下面，
      // 顶部仍从顶栏下方起算，状态栏 / 返回图标不会压在亮画面上。
      const height: number = Math.min(natural, Math.round(stage));
      return new PortraitFrame(topLimit, height);
    }

    const room: number = Math.max(160, stage - PORTRAIT_BOTTOM_RESERVE - topLimit);
    const height: number = Math.min(Math.max(natural, 120), room);
    const top: number = topLimit + Math.max(0, Math.round((room - height) / 2));
    return new PortraitFrame(top, height);
  }

  /** 竖屏连播的画面盒高度；其它模式仍然铺满父容器 */
  private videoBoxHeight(): Length {
    if (!this.portraitMode || this.fullscreen) {
      return '100%';
    }
    return this.portraitFrame().height;
  }

  /** 竖屏连播画面盒距屏幕顶部的距离；其它模式不偏移 */
  private portraitVideoTop(): number {
    if (!this.portraitMode || this.fullscreen) {
      return 0;
    }
    return this.portraitFrame().top;
  }

  /** 画布 + 叠层控制（尺寸由外层决定，竖屏 16:9 / 竖屏摆放铺满 / 全屏铺满） */
  @Builder
  playerLayer() {
    Stack({ alignContent: this.portraitMode && !this.fullscreen ? Alignment.Top : Alignment.Center }) {
      // 画面视口：竖屏连播时它就是一个「画面盒」，上下切换的当前画面与上/下一条封面
      // 都在盒子里滑动，并被裁在盒内——不会再整屏铺一张封面，也不会冲进顶栏/底栏。
      // 其它模式视口就是整块画布，行为与原来一致。
      Stack({ alignContent: Alignment.Top }) {
        // 上一条的封面：下滑时从盒子上方滑进来
        if (this.portraitMode && !this.fullscreen && this.portraitDragY > 0 &&
          this.portraitPrevCover.length > 0) {
          Image(this.portraitPrevCover)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .draggable(false)
            .translate({ y: this.portraitDragY - this.switchShift() })
        }

        Column() {
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

            // 弹幕层：叠在画面之上、控制层之下，跟着画面盒一起平移；不拦截手势。
            // 用单块 Canvas 逐帧绘制，位置按视频时间轴算，暂停 / 拖动 / 切集都能精确对上。
            Canvas(this.danmakuCtx)
              .width('100%')
              .height('100%')
              .onReady(() => {
                this.danmakuReady = true;
              })
              .onAreaChange((oldValue: Area, newValue: Area) => {
                const width: number = Number(newValue.width);
                const height: number = Number(newValue.height);
                if (width > 0 && height > 0) {
                  this.danmakuWidth = width;
                  this.danmakuHeight = height;
                  this.danmakuReady = true;
                }
              })
              .hitTestBehavior(HitTestMode.None)

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
          }
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .height('100%')
        // 竖屏连播：当前画面跟随手指上下移动（其它模式恒为 0）
        .translate({ y: this.portraitMode && !this.fullscreen ? this.portraitDragY : 0 })

        // 下一条的封面：上滑时从盒子下方滑进来
        if (this.portraitMode && !this.fullscreen && this.portraitDragY < 0 &&
          this.portraitNextCover.length > 0) {
          Image(this.portraitNextCover)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .draggable(false)
            .translate({ y: this.portraitDragY + this.switchShift() })
        }
      }
      .width('100%')
      .height(this.videoBoxHeight())
      .margin({ top: this.portraitVideoTop() })
      .backgroundColor(Color.Black)
      .clip(true)

      // 控制层：4s 无操作自动隐藏。竖屏连播模式不再复用这套控制条，
      // 顶栏 / 进度条 / 操作行改由独立的底部浮层承载，避免两套进度条和顶栏重复。
      if (this.controlsVisible && !this.portraitMode) {
        Column() {
          this.topBar()

          // 中央播放图标只作暂停态视觉提示，不绑 onClick：
          // 暂停/继续统一交给 GestureGroup 的双击分支，单击只切换控制条（隐藏/显示 UP 区），
          // 否则单击空白想收起 UP 区时会被这里的 onClick 判成暂停（手势冲突）。
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
          .hitTestBehavior(HitTestMode.None)

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

      // 迷你进度条：无操作把界面收干净后，只在视频区域最低边留这一条。
      // 竖屏连播模式由独立底部浮层的固定进度条承载，不需要这条迷你进度条。
      if (!this.controlsVisible && this.prefs.miniProgress && this.started && !this.portraitMode) {
        Column() {
          Blank()
          Progress({
            value: this.positionMs,
            total: this.durationMs > 0 ? this.durationMs : 1,
            type: ProgressType.Linear
          })
            .width('100%')
            .height(2)
            .color($r('app.color.brand_primary'))
            .backgroundColor($r('app.color.overlay'))
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
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
        // 竖屏连播里 Stack 是顶对齐，HUD 原本会顶到状态栏；下移到画面盒上沿附近
        .margin({ top: this.portraitMode && !this.fullscreen ? this.portraitFrame().top + 12 : 0 })
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
        // 竖屏连播：控制条已移除，单击只切换 up 信息 + 视频名称的显隐；
        // 顶栏、固定进度条、操作行不受影响。其余模式仍切控制条。
        if (this.portraitMode && !this.fullscreen) {
          this.portraitInfoVisible = !this.portraitInfoVisible;
        } else {
          this.toggleControls();
        }
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
    // 垂直：左侧亮度 / 右侧音量 / 竖屏连播下半屏上下切换视频
    // distance 调到 10：原来 20vp 的起手阈值会让手指先「空走」一段，切换显得迟钝
    .gesture(PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 10 })
      .onActionStart((event: GestureEvent) => {
        this.onVerticalStart(event);
      })
      .onActionUpdate((event: GestureEvent) => {
        this.onVerticalUpdate(event);
      })
      .onActionEnd((event: GestureEvent) => {
        this.onVerticalEnd(event);
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

  /**
   * 竖屏连播切换的位移距离：就是画面盒的高度。
   *
   * 切换时只有画面盒里的内容上下滑一屏，上一条正好滑出盒子、下一条正好滑进来；
   * 原来用整屏高度，等于让整页（含底栏）一起飞出屏幕，才会出现「一拖动就整屏黑/闪封面」。
   */
  private switchShift(): number {
    if (this.portraitMode && !this.fullscreen) {
      return Math.max(60, this.portraitFrame().height);
    }
    return this.stageH > 0 ? this.stageH : (this.pageH > 0 ? this.pageH : 1000);
  }

  // ---------------- 竖屏化视频（9:16）在横屏区的展示 ----------------

  /** 当前这条是不是竖屏视频（高 > 宽） */
  private isVerticalVideo(): boolean {
    return this.videoAspect > 1.02;
  }

  /**
   * 是否允许把画面往下拉、撑高后进竖屏。
   *
   * V2.1.0 修正：这里不再看「竖屏视频展示」开关。那个开关只负责推荐流里要不要混排竖屏视频，
   * 和「这条视频能不能拉进竖屏」无关；之前挂在开关上，关着开关时任何竖屏视频都拖不动
   * 工具行那颗箭头，从搜索进来看竖屏视频就永远进不了竖屏模式。
   */
  private canExpandVertical(): boolean {
    return !this.fullscreen && !this.portraitMode && this.isVerticalVideo();
  }

  /** 拉伸上限：整屏的 80%，把下方推荐压下去但不吃掉 */
  private displayMax(): number {
    const stage: number = this.stageH > 0 ? this.stageH : 780;
    return Math.max(this.canvasHeight, Math.round(stage * VERTICAL_MAX_STAGE_RATIO));
  }

  /** 横屏区画布高度：16:9 基准 + 用户拉高的量，夹在基准与上限之间 */
  private normalCanvasHeight(): number {
    if (!this.canExpandVertical()) {
      return this.canvasHeight;
    }
    const target: number = this.canvasHeight + Math.max(0, this.displayExtra);
    return Math.min(Math.max(target, this.canvasHeight), this.displayMax());
  }

  private onDisplayDragUpdate(dy: number): void {
    const max: number = this.displayMax();
    this.displayExtra = Math.min(Math.max(0, this.displayDragBase + dy), max - this.canvasHeight);
  }

  /** 松手：拉到底直接进竖屏模式，否则停手位置就地保留（最小回落到 16:9） */
  private onDisplayDragEnd(): void {
    const height: number = this.normalCanvasHeight();
    const stage: number = this.stageH > 0 ? this.stageH : 780;
    if (height >= stage * VERTICAL_ENTER_RATIO) {
      this.displayExtra = 0;
      this.toast('已进入竖屏模式');
      this.togglePortraitMode();
      return;
    }
    if (height < this.canvasHeight + 24) {
      this.displayExtra = 0;
      return;
    }
    this.showHud(`画面已放大到 ${Math.round(height)}`);
  }

  /** 一键回首页：整条播放栈清掉（连点多个推荐视频后不用一层层返回） */
  private goHome(): void {
    if (this.pathStack !== undefined) {
      this.pathStack.clear();
    }
  }


  /**
   * 竖屏连播浮层：盖在视频区上方的独立图层（视频在下、浮层在上）。
   * - 顶栏固定显示，不随点击隐藏；
   * - 底部四块：up 信息 + 视频名称点击屏幕时隐藏/恢复，固定进度条 + 操作行始终显示；
   * - 顶栏与底部之间不渲染任何组件（SpaceBetween 留空），点击可穿透到视频手势。
   */
  @Builder
  portraitOverlay() {
    Column() {
      this.portraitTopBar()

      // 播完（停止推荐）：画面里已经是「结束态推荐卡」，底部这几块（up 信息 / 进度条 / 操作行）
      // 一起让位，否则两套按钮会叠在一起；顶栏保留，返回与回首页仍然可点。
      if (!this.playEnded) {
        Column() {
          if (this.portraitInfoVisible) {
            this.portraitInfoOverlay()
          }
          // 进度条固定显示，位于简介区与操作行之间（与普通播放区同款可拖动 Slider）
          this.portraitProgressBar()
          this.portraitActionBar()
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    // 浮层挂在展开到屏幕上沿的根 Stack 下，不像主 Column 那样自带状态栏 padding。
    // 这里补上等价避让：沉浸时状态栏透明浮在画面上、非沉浸时是增量条，两种都要让开一个状态栏高度。
    .padding({ top: this.fullscreen ? 0 : this.topInset })
    .justifyContent(FlexAlign.SpaceBetween)
    // 切换时只让画面盒里的内容上下滑，顶栏与底部四块保持不动（整页飞出去会晃眼）
    // 容器自身不拦截点击，让视频区的单击/滑动手势能穿透（顶栏与底部子组件仍可点）
    .hitTestBehavior(HitTestMode.Transparent)
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

  // ==================== 竖屏连播沉浸模式（参考 Pilihos verticalExpanded） ====================

  /** 竖屏顶部操作栏：返回 / 悬浮窗(占位) / 分享(系统分享) / 设置(底部弹窗) */
  @Builder
  portraitTopBar() {
    Row() {
      // 返回
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_backward'))
          .fontSize(20)
          .fontColor([$r('app.color.text_on_media')])
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(TOP_ICON_CHIP_BG ? $r('app.color.scrim') : Color.Transparent)
      .borderRadius(18)
      .onClick(() => {
        this.onBack();
      })

      // 一键回首页：连播一路滑下来以后直接清栈回去
      Row() {
        SymbolGlyph($r('sys.symbol.house'))
          .fontSize(18)
          .fontColor([$r('app.color.text_on_media')])
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(TOP_ICON_CHIP_BG ? $r('app.color.scrim') : Color.Transparent)
      .borderRadius(18)
      .onClick(() => {
        this.goHome();
      })

      Blank()

      // 全屏（横屏）：与普通播放页的展开按钮同一个入口，退出全屏回到连播
      Row() {
        SymbolGlyph($r('sys.symbol.arrow_up_left_and_arrow_down_right'))
          .fontSize(17)
          .fontColor([$r('app.color.text_on_media')])
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(TOP_ICON_CHIP_BG ? $r('app.color.scrim') : Color.Transparent)
      .borderRadius(18)
      .onClick(() => {
        this.enterFullscreenFromPortrait();
      })

      // 悬浮窗（占位，图标用素材 xfcb.svg，白色填充；与其他按钮同用半透明圆底，不再单独铺白底）
      Row() {
        Image($r('app.media.xfcb'))
          .width(20)
          .height(20)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(TOP_ICON_CHIP_BG ? $r('app.color.scrim') : Color.Transparent)
      .borderRadius(18)
      .onClick(() => {
        this.toast('悬浮窗播放待接入');
      })

      // 分享（调起系统分享面板）
      Row() {
        SymbolGlyph($r('sys.symbol.share'))
          .fontSize(18)
          .fontColor([$r('app.color.text_on_media')])
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(TOP_ICON_CHIP_BG ? $r('app.color.scrim') : Color.Transparent)
      .borderRadius(18)
      .onClick(() => {
        this.shareVideo();
      })

      // 设置（底部弹窗，内容与播放区设置面板一致）
      Row() {
        SymbolGlyph($r('sys.symbol.gearshape'))
          .fontSize(18)
          .fontColor([$r('app.color.text_on_media')])
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(TOP_ICON_CHIP_BG ? $r('app.color.scrim') : Color.Transparent)
      .borderRadius(18)
      .onClick(() => {
        this.portraitSettingsVisible = true;
      })
    }
    .width('100%')
    .height(PLAYER_BAR_HEIGHT)
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
    .alignItems(VerticalAlign.Center)
  }

  /** 竖屏「设置」底部弹窗：复用播放区设置面板 PlayerSettingsPanel（内容与设置页签一致） */
  @Builder
  portraitSettingsSheet() {
    if (this.portraitSettingsVisible) {
      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.scrim'))
          .onClick(() => {
            this.portraitSettingsVisible = false;
          })

        Column() {
          Row() {
            Text('播放设置')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
              .fontSize(20)
              .fontColor([$r('app.color.text_tertiary')])
              .onClick(() => {
                this.portraitSettingsVisible = false;
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ bottom: 6 })

          Scroll() {
            PlayerSettingsPanel({
              prefs: $prefs,
              onChanged: (key: string, value: number | boolean | string): void => {
                this.onSettingsChanged(key, value);
              },
              onShare: (): void => {
                this.shareVideo();
              }
            })
          }
          .scrollBar(BarState.Off)
          .width('100%')
          .constraintSize({ maxHeight: '60%' })
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: 14,
          bottom: 14 + this.bottomInset
        })
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius({ topLeft: 18, topRight: 18 })
      }
      .width('100%')
      .height('100%')
    }
  }

  /**
   * 评论长按操作面板（底部弹窗）。
   *
   * 复制 = 把正文放进系统剪贴板（表情保留 `[doge]` 原始标记，和 b 站一致）；
   * 分享 / 举报 先做占位；
   * 最后一项按作者判断：自己发的是「删除回复」（走服务端删除），别人的是「删隐回复」
   * （只写本地黑名单，仅自己不可见）。
   */
  @Builder
  commentActionSheet() {
    if (this.sheetCommentVisible) {
      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.scrim'))
          .onClick(() => {
            this.sheetCommentVisible = false;
          })

        Column() {
          // 评论预览：让人确认自己长按的是哪一条
          Text(this.sheetComment.message.length > 0 ? this.sheetComment.message : '（无正文）')
            .width('100%')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .padding({ left: 16, right: 16, top: 14, bottom: 12 })

          Divider()
            .color($r('app.color.divider'))
            .strokeWidth(0.5)

          this.commentSheetAction('复制回复', false, () => {
            this.copyComment();
          })
          this.commentSheetAction('分享回复', false, () => {
            this.toast('分享回复待接入');
          })
          this.commentSheetAction('举报回复', false, () => {
            this.toast('举报回复待接入');
          })
          this.commentSheetAction(this.sheetDeleteLabel(), true, () => {
            this.deleteOrHideComment();
          })

          Divider()
            .color($r('app.color.divider'))
            .strokeWidth(0.5)
            .margin({ top: 4 })

          this.commentSheetAction('取消', false, () => {
            // 只关面板
          })
        }
        .width('100%')
        .padding({ bottom: 6 + this.bottomInset })
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius({ topLeft: 18, topRight: 18 })
        .clip(true)
      }
      .width('100%')
      .height('100%')
    }
  }

  /** 长按面板里的一行操作 */
  @Builder
  commentSheetAction(label: string, danger: boolean, action: () => void) {
    Text(label)
      .width('100%')
      .textAlign(TextAlign.Center)
      .fontSize(15)
      .fontColor(danger ? $r('app.color.danger') : $r('app.color.text_primary'))
      .padding({ top: 15, bottom: 15 })
      .onClick(() => {
        this.sheetCommentVisible = false;
        action();
      })
  }

  /** 竖屏视频下方独立信息区：UP 信息 + 简介（占据视频与操作栏之间的空位） */
  @Builder
  portraitInfoOverlay() {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        if (this.detail.authorFace.length > 0) {
          Image(this.detail.authorFace)
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
              .fontColor([$r('app.color.text_on_media')])
          }
          .width(38)
          .height(38)
        }

        Column({ space: 3 }) {
          Text(this.detail.authorName.length > 0 ? this.detail.authorName : 'UP 主')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_on_media'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.detail.followerText.length > 0) {
            Text(`${this.detail.followerText} 粉丝`)
              .fontSize(10)
              .fontColor($r('app.color.text_on_media'))
              .opacity(0.72)
              .maxLines(1)
          }
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
      .alignItems(VerticalAlign.Center)

      if (this.detail.title.length > 0) {
        Text(this.detail.title)
          .fontSize(12)
          .fontColor($r('app.color.text_on_media'))
          .opacity(0.88)
          .maxLines(this.portraitDescExpanded ? 12 : 1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .onClick(() => {
            this.portraitDescExpanded = !this.portraitDescExpanded;
          })
      }
    }
    .width('100%')
    // 竖屏画面现在铺满屏宽、会一直伸到信息区后面：这里改用「透明 → 黑」的渐变收口，
    // 视频边缘不会被一块纯黑硬切出一条横线，文字也仍然压得住。
    .padding({ left: 16, right: 16, top: 30, bottom: 10 })
    .linearGradient({
      angle: 180,
      colors: [['#00000000', 0.0], ['#99000000', 0.28], ['#CC000000', 0.58], ['#E6000000', 1.0]]
    })
  }

  /**
   * 竖屏点赞项。
   *
   * 单独写一个 Builder 而不是复用 portraitActionCount：@Builder 的值传参不会随状态刷新，
   * 点赞态与数字必须在 Builder 内部直接读 @State，点完才会立刻变色。
   */
  @Builder
  likePortraitItem() {
    Column({ space: 3 }) {
      SymbolGlyph($r('sys.symbol.hand_thumbsup'))
        .fontSize(24)
        .fontColor([this.liked ? $r('app.color.brand_primary') : $r('app.color.text_on_media')])
      Text(this.likeTextUi.length > 0 ? this.bareCount(this.likeTextUi) : '赞')
        .fontSize(9)
        .fontColor(this.liked ? $r('app.color.brand_primary') : $r('app.color.text_on_media'))
        .opacity(this.liked ? 1 : 0.85)
        .maxLines(1)
    }
    .width(40)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.toggleLike();
    })
  }

  /** 竖屏底部操作行：弹幕输入 + 互动图标横排 + 底部细进度线（黑底，参考 Pilihos） */
  @Builder
  portraitActionBar() {
    Column({ space: 0 }) {
      Row({ space: 10 }) {
        // 弹幕输入框（弹幕开关并入最右侧）
        Row() {
          SymbolGlyph($r('sys.symbol.waveform_bubble'))
            .fontSize(15)
            .fontColor([$r('app.color.text_tertiary')])
          Text('发弹幕')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
            .layoutWeight(1)
            .margin({ left: 6 })
            .onClick(() => {
              this.openDanmakuComposer();
            })
          SymbolGlyph($r('sys.symbol.waveform_bubble'))
            .fontSize(16)
            .fontColor([this.prefs.danmakuOn
              ? $r('app.color.brand_primary') : $r('app.color.text_tertiary')])
            .onClick(() => {
              this.toggleDanmaku();
            })
        }
        .height(38)
        .layoutWeight(1)
        .padding({ left: 12, right: 10 })
        .backgroundColor($r('app.color.overlay'))
        .borderRadius(17)
        .alignItems(VerticalAlign.Center)

        this.likePortraitItem()
        this.portraitActionCount($r('sys.symbol.medal'),
          this.detail.coinText.length > 0 ? this.bareCount(this.detail.coinText) : '币', undefined, $r('app.media.toubi'))
        this.portraitActionCount($r('sys.symbol.star'),
          this.detail.favText.length > 0 ? this.bareCount(this.detail.favText) : '藏')
        // 评论：退出竖屏连播，回到普通播放页并直接切到评论区
        this.portraitActionCount($r('sys.symbol.message'),
          this.detail.replyText.length > 0 ? this.bareCount(this.detail.replyText) : '评',
          () => {
            this.exitPortraitToComments();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 8 + this.bottomInset })
    }
    .width('100%')
    .backgroundColor(Color.Black)
  }

  /** 竖屏连播进度条：与普通播放区 bottomBar 同款可拖动 Slider，夹在简介区与操作行之间 */
  @Builder
  portraitProgressBar() {
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
          // 弹幕跟着进度条走：拖动时立刻按新位置重排，松手 seek 后不用再等一次同步
          this.danmakuSetClock(value);
          if (mode === SliderChangeMode.End) {
            this.player.seek(value);
            this.showControls();
          }
        })
      Text(this.formatMs(this.durationMs))
        .fontSize(11)
        .fontColor($r('app.color.text_on_media'))
    }
    .width('100%')
    .height(PLAYER_CTRL_HEIGHT)
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
    .backgroundColor(Color.Black)
  }

  /** 竖屏底部单个互动项（图标 + 数字）。action 传入则替换默认的占位 toast */
  @Builder
  portraitActionCount(icon: Resource, label: string, action?: () => void, imageIcon?: Resource) {
    Column({ space: 3 }) {
      if (imageIcon !== undefined) {
        Image(imageIcon)
          .width(24)
          .height(24)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      } else {
        SymbolGlyph(icon)
          .fontSize(24)
          .fontColor([$r('app.color.text_on_media')])
      }
      Text(label)
        .fontSize(9)
        .fontColor($r('app.color.text_on_media'))
        .opacity(0.85)
        .maxLines(1)
    }
    .width(40)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (action !== undefined) {
        action();
      } else {
        this.toast(`${label} 功能待接入`);
      }
    })
  }

  /** 工具行：左侧简介 / 评论 / 设置 · 正中竖屏连播入口 · 右侧弹幕输入（总开关并入其中） */
  @Builder
  actionBar() {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        Row({ space: 18 }) {
          this.infoTabText('简介', 'brief', 0)
          this.infoTabText('评论', 'comments', 1)
          this.infoTabText('设置', 'settings', 2)
        }

        Blank()

        // 弹幕输入与总开关合成一颗胶囊：开关就贴在输入框最右侧，不再单独占一个图标位
        Row() {
          Text('发一条弹幕')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .onClick(() => {
              this.openDanmakuComposer();
            })

          SymbolGlyph($r('sys.symbol.waveform_bubble'))
            .fontSize(16)
            .fontColor([this.prefs.danmakuOn
              ? $r('app.color.brand_primary') : $r('app.color.text_tertiary')])
            .onClick(() => {
              this.toggleDanmaku();
            })
        }
        .width(132)
        .height(30)
        .padding({ left: 12, right: 10 })
        .backgroundColor($r('app.color.bg_field'))
        .borderRadius(15)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 这一行的正中间：竖屏连播入口（下箭头 = 画面向下铺满，进入后变上箭头收起）。
      // V2.1.0：原「画面下方那条横线把手」已并入这颗箭头 ——
      //   轻点：立刻进出竖屏；按住往下拖：像拉把手一样把画面逐步撑高，拖到 76% 屏高松手即进竖屏。
      // 用互斥手势组（不是同时挂 onClick + PanGesture）：Tap 与 Pan 谁先成立谁生效，不会一下点两次。
      Row() {
        SymbolGlyph(this.portraitMode
          ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(16)
          // 画面已被拖高时箭头跟着变品牌色：既是「正在拉」的反馈，也提示还能继续拖
          .fontColor([!this.portraitMode && this.displayExtra > 0
            ? $r('app.color.brand_primary') : $r('app.color.text_secondary')])
      }
      .width(30)
      .height(30)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.bg_field'))
      .borderRadius(15)
      .gesture(GestureGroup(GestureMode.Exclusive,
        TapGesture({ count: 1 })
          .onAction(() => {
            this.togglePortraitMode();
          }),
        PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 6 })
          .onActionStart(() => {
            this.arrowDragging = false;
            this.displayDragBase = this.displayExtra;
          })
          .onActionUpdate((event: GestureEvent) => {
            // 只有竖屏化视频、且不在全屏 / 连播里，往下拖才有撑高画面的含义；其余情况只当点击
            if (!this.canExpandVertical() || this.playEnded) {
              return;
            }
            if (!this.arrowDragging && Math.abs(event.offsetY) >= 6) {
              this.arrowDragging = true;
            }
            if (this.arrowDragging) {
              this.onDisplayDragUpdate(event.offsetY);
            }
          })
          .onActionEnd(() => {
            if (!this.arrowDragging) {
              return;
            }
            this.arrowDragging = false;
            this.onDisplayDragEnd();
          })
          .onActionCancel(() => {
            if (this.arrowDragging) {
              this.arrowDragging = false;
              this.onDisplayDragEnd();
            }
          })))
      .accessibilityText(this.portraitMode
        ? '轻点退出竖屏模式' : '轻点进入竖屏模式，按住向下拖可逐步放大画面')
    }
    .width('100%')
    .height(ACTION_BAR_HEIGHT)
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
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

  /** 单个互动项：图标在上、数字或动作名在下。action 传入则替换默认的占位 toast */
  @Builder
  actionItem(icon: Resource, label: string, action?: () => void, imageIcon?: Resource) {
    Column({ space: 5 }) {
      if (imageIcon !== undefined) {
        Image(imageIcon)
          .width(23)
          .height(23)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      } else {
        SymbolGlyph(icon)
          .fontSize(23)
          .fontColor([$r('app.color.text_secondary')])
      }
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      if (action !== undefined) {
        action();
      } else {
        this.toast(`${label} 功能待接入`);
      }
    })
  }

  /** 互动行里的点赞项：同上，直接在 Builder 内读 @State，点完立刻变色 / 变数字 */
  @Builder
  likeActionItem() {
    Column({ space: 5 }) {
      SymbolGlyph($r('sys.symbol.hand_thumbsup'))
        .fontSize(23)
        .fontColor([this.liked ? $r('app.color.brand_primary') : $r('app.color.text_secondary')])
      Text(this.likeTextUi.length > 0 ? this.likeTextUi : '点赞')
        .fontSize(11)
        .fontColor(this.liked ? $r('app.color.brand_primary') : $r('app.color.text_tertiary'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.toggleLike();
    })
  }

  /** 六项互动：点赞 / 点踩 / toubi / 收藏 / 再看 / 分享（参考图） */
  @Builder
  actionRow() {
    Row() {
      this.likeActionItem()
      this.actionItem($r('sys.symbol.hand_thumbsdown'), '点踩')
      this.actionItem($r('sys.symbol.medal'),
        this.detail.coinText.length > 0 ? this.detail.coinText : 'toubi', undefined, $r('app.media.toubi'))
      this.actionItem($r('sys.symbol.star'),
        this.detail.favText.length > 0 ? this.detail.favText : '收藏')
      this.actionItem($r('sys.symbol.arrow_clockwise'), '再看')
      this.actionItem($r('sys.symbol.share'),
        this.detail.shareText.length > 0 ? this.detail.shareText : '分享', () => {
          this.shareVideo();
        })
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
        onChanged: (key: string, value: number | boolean | string): void => {
          this.onSettingsChanged(key, value);
        },
        onShare: (): void => {
          this.shareVideo();
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
  /**
   * 把评论正文按「表情标记」切成 文本 / 图片 片段。
   * 接口 content.emote 给出 `[doge]` → 图片地址，渲染时用 ImageSpan 内联成图，
   * 避免正文直接露出 `[doge]` 这种文字标记。
   */
  private splitComment(message: string, emotes: Array<CommentEmote>): Array<CommentSegment> {
    const segments: Array<CommentSegment> = [];
    if (message.length === 0) {
      return segments;
    }
    if (emotes.length === 0) {
      this.pushTextSegments(segments, message);
      return segments;
    }
    let rest: string = message;
    let guard: number = 0;
    while (rest.length > 0 && guard < 500) {
      guard += 1;
      // 在剩余串里找位置最靠前的表情标记（多个表情都在场时按出现顺序切）
      let hitIndex: number = -1;
      let hitUrl: string = '';
      let hitLen: number = 0;
      for (let i = 0; i < emotes.length; i++) {
        if (emotes[i].text.length === 0) {
          continue;
        }
        const pos: number = rest.indexOf(emotes[i].text);
        if (pos >= 0 && (hitIndex < 0 || pos < hitIndex)) {
          hitIndex = pos;
          hitUrl = emotes[i].url;
          hitLen = emotes[i].text.length;
        }
      }
      if (hitIndex < 0) {
        this.pushTextSegments(segments, rest);
        break;
      }
      if (hitIndex > 0) {
        this.pushTextSegments(segments, rest.substring(0, hitIndex));
      }
      segments.push(new CommentSegment('', hitUrl));
      rest = rest.substring(hitIndex + hitLen);
    }
    if (segments.length === 0) {
      this.pushTextSegments(segments, message);
    }
    return segments;
  }

  /** 把一段纯文本按 @昵称 再切一次，@ 片段单独上色，方便以后点击跳主页 */
  private pushTextSegments(out: Array<CommentSegment>, text: string): void {
    if (text.length === 0) {
      return;
    }
    const parts: Array<CommentSegment> = this.splitMention(text);
    for (let i = 0; i < parts.length; i++) {
      out.push(parts[i]);
    }
  }

  /** 切分 @昵称：返回的片段里 mention = true 的是「@ + 昵称」整段 */
  private splitMention(text: string): Array<CommentSegment> {
    const out: Array<CommentSegment> = [];
    const total: number = text.length;
    let cursor: number = 0;
    let i: number = 0;
    while (i < total) {
      if (text.charAt(i) !== '@') {
        i += 1;
        continue;
      }
      let end: number = i + 1;
      while (end < total && this.isNameChar(text.charAt(end))) {
        end += 1;
      }
      // 光一个 @ 后面没有昵称字符：当普通文本
      if (end === i + 1) {
        i += 1;
        continue;
      }
      if (i > cursor) {
        out.push(new CommentSegment(text.substring(cursor, i), ''));
      }
      out.push(new CommentSegment(text.substring(i, end), '', true));
      cursor = end;
      i = end;
    }
    if (cursor < total) {
      out.push(new CommentSegment(text.substring(cursor), ''));
    }
    return out;
  }

  /** @昵称 里允许出现的字符：中英数字、下划线、连字符 */
  private isNameChar(ch: string): boolean {
    if (ch.length === 0) {
      return false;
    }
    const code: number = ch.charCodeAt(0);
    if (code >= 48 && code <= 57) {
      return true;
    }
    if (code >= 65 && code <= 90) {
      return true;
    }
    if (code >= 97 && code <= 122) {
      return true;
    }
    if (code === 95 || code === 45) {
      return true;
    }
    // 中文（含扩展 A）、日文假名：b 站昵称常见
    return code >= 0x3040 && code <= 0x9fa5;
  }

  /** 评论正文：纯文本与表情图片在 Text 内混排（Span / ImageSpan），尺寸随字号自适应 */
  @Builder
  commentRichText(message: string, emotes: Array<CommentEmote>, fontSize: number, lineHeight: number, maxLines: number) {
    Text() {
      ForEach(this.splitComment(message, emotes), (seg: CommentSegment, index: number) => {
        if (seg.url.length > 0) {
          ImageSpan(seg.url)
            .width(fontSize + 5)
            .height(fontSize + 5)
            .objectFit(ImageFit.Contain)
            .verticalAlign(ImageSpanAlignment.CENTER)
        } else if (seg.mention) {
          // @某人：品牌粉 + 中等字重，和正文区分开（后续接点击跳主页）
          Span(seg.text)
            .fontColor($r('app.color.brand_primary'))
            .fontWeight(FontWeight.Medium)
        } else {
          Span(seg.text)
        }
      }, (seg: CommentSegment, index: number) => `cseg_${index}_${seg.text.length}_${seg.url.length}`)
    }
    .width('100%')
    .fontSize(fontSize)
    .lineHeight(lineHeight)
    .fontColor($r('app.color.text_primary'))
    .maxLines(maxLines)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

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
              LevelBadge({ level: item.level, badgeHeight: 18 })
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

          this.commentRichText(item.message, item.emotes, 14, 21, 8)

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
            // 共 N 条回复：移到时间 | 点赞同一行（时间|点赞|共N条回复|回复）
            if (item.rcount > 0) {
              Row({ space: 3 }) {
                Text(`共 ${item.rcount} 条回复`)
                  .fontSize(11)
                  .fontColor($r('app.color.brand_primary'))
                SymbolGlyph($r('sys.symbol.chevron_down'))
                  .fontSize(10)
                  .fontColor([$r('app.color.brand_primary')])
                  .rotate({ angle: this.expandedRpid === item.rpid ? 180 : 0 })
              }
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.toggleSub(item);
              })
            }
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
    // 长按整条评论：底部弹出「复制 / 分享 / 举报 / 删除(删隐)」
    .gesture(LongPressGesture({ repeat: false, duration: 420 })
      .onAction(() => {
        this.openCommentSheet(item, false);
      }))
  }

  /**
   * 把扁平的楼中楼重排成「谁回复谁」的嵌套结构。
   *
   * 接口返回的回复是平铺的，只带 parent rpid：直接铺开会让「回复 B 的内容」和 B 平级，
   * 看起来像是回复楼主 A。这里按 parent 建树、深度优先输出，保证子回复紧跟在自己回的那条下面。
   * 找不到父级（父在更深的分页、已删除）当作直接回复楼主处理；depth 上限 2，避免缩进挤成一列。
   */
  private nestedSubRows(): Array<SubRow> {
    const rows: Array<SubRow> = [];
    if (this.subComments.length === 0) {
      return rows;
    }
    const known: Map<string, boolean> = new Map<string, boolean>();
    for (let i = 0; i < this.subComments.length; i++) {
      known.set(this.subComments[i].rpid, true);
    }
    const children: Map<string, Array<VideoComment>> = new Map<string, Array<VideoComment>>();
    const tops: Array<VideoComment> = [];
    for (let i = 0; i < this.subComments.length; i++) {
      const item: VideoComment = this.subComments[i];
      const parent: string = item.parentRpid;
      const isTop: boolean = parent.length === 0 || parent === this.subRoot || parent === item.rpid ||
        !known.has(parent);
      if (isTop) {
        tops.push(item);
        continue;
      }
      let kids: Array<VideoComment> | undefined = children.get(parent);
      if (kids === undefined) {
        kids = [];
        children.set(parent, kids);
      }
      kids.push(item);
    }
    // 深度优先：先输出父，紧接着输出它的子，再回到下一个兄弟——子回复才不会跑到列表末尾去
    const stack: Array<SubRow> = [];
    for (let i = tops.length - 1; i >= 0; i--) {
      stack.push(new SubRow(tops[i], 0));
    }
    const visited: Map<string, boolean> = new Map<string, boolean>();
    while (stack.length > 0) {
      const row: SubRow | undefined = stack.pop();
      if (row === undefined) {
        break;
      }
      if (visited.has(row.item.rpid)) {
        continue;
      }
      visited.set(row.item.rpid, true);
      rows.push(row);
      const kids: Array<VideoComment> | undefined = children.get(row.item.rpid);
      if (kids === undefined) {
        continue;
      }
      const nextDepth: number = row.depth >= 2 ? 2 : row.depth + 1;
      // 逆序压栈，出栈时才是原来的先后顺序
      for (let i = kids.length - 1; i >= 0; i--) {
        if (!visited.has(kids[i].rpid)) {
          stack.push(new SubRow(kids[i], nextDepth));
        }
      }
    }
    // 兜底：parent 指向自己形成环的，原序补在末尾，别让人看不见
    for (let i = 0; i < this.subComments.length; i++) {
      if (!visited.has(this.subComments[i].rpid)) {
        rows.push(new SubRow(this.subComments[i], 0));
      }
    }
    return rows;
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
        ForEach(this.nestedSubRows(), (row: SubRow) => {
          this.subCommentRow(row.item, root, row.depth)
        }, (row: SubRow) => `sub_${row.item.rpid}_${row.depth}`)

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

    }
    .width('100%')
    .padding({ left: 48, top: 2, bottom: 6 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 单条子回复：头像 + 昵称 + 等级 / 「回复 @某人」+ 正文 + 时间与互动；depth 决定缩进层级 */
  @Builder
  subCommentRow(sub: VideoComment, root: VideoComment, depth: number) {
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
          // 嵌套位置已经表明回的是谁，昵称后面不再重复「回复 @某人」；
          // 等级徽章始终显示（之前被那串前缀顶掉，导致自己的回复看不到 Lv）
          if (sub.level > 0) {
            LevelBadge({ level: sub.level, badgeHeight: 17 })
          }
          Blank()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        this.commentRichText(sub.message, sub.emotes, 13, 19, 6)

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
    // 嵌套回复按层级右移，视觉上能看出「这条是回上面那一条的」
    .padding({ left: depth * 20, top: 6, bottom: 6 })
    .alignItems(VerticalAlign.Top)
    // 长按子回复同样弹操作面板
    .gesture(LongPressGesture({ repeat: false, duration: 420 })
      .onAction(() => {
        this.openCommentSheet(sub, true);
      }))
  }

  /** 评论版块：头部 + 列表（下拉刷新 / 滚到底自动续页）+ 右下角发评论悬浮键 */
  @Builder
  commentsBlock() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      // 下拉刷新：松手后从第一页重拉（排序不变），转圈由 commentRefreshing 控制
      Refresh({ refreshing: $$this.commentRefreshing }) {
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
      }
      .width('100%')
      .height('100%')
      .onRefreshing(() => {
        this.refreshComments();
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
          if (this.composerEmotes.length > 0) {
            // 图片版表情：接口 / 评论里拿到的地址，点一下插入 `[名称]`
            ForEach(this.composerEmotes, (em: CommentEmote) => {
              Image(em.url)
                .width(32)
                .height(32)
                .objectFit(ImageFit.Contain)
                .draggable(false)
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
                  this.insertChunk(em.text);
                })
            }, (em: CommentEmote) => `emote_${em.text}`)
          } else {
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
          }
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

  /** 弹幕输入浮层：复用评论输入卡的键盘避让（系统已让出的高度 + 卡片自身补偿） */
  @Builder
  danmakuComposer() {
    if (this.danmakuComposerVisible) {
      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.scrim'))
          .onClick(() => {
            this.closeDanmakuComposer();
          })

        Column({ space: 10 }) {
          Row() {
            Text(`弹幕 · ${this.formatMs(this.danmakuNow())}`)
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
            Blank()
            Text(`${this.danmakuDraft.length}/100`)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Row({ space: 10 }) {
            TextInput({ text: this.danmakuDraft, placeholder: '发个弹幕见证当下' })
              .id(DANMAKU_INPUT_ID)
              .layoutWeight(1)
              .height(42)
              .maxLength(100)
              .fontSize(14)
              .placeholderColor($r('app.color.text_tertiary'))
              .placeholderFont({ size: 14 })
              .backgroundColor($r('app.color.bg_field'))
              .borderRadius(10)
              .padding({ left: 12, right: 12 })
              .onChange((value: string) => {
                this.danmakuDraft = value;
              })
              .onSubmit(() => {
                this.sendDanmaku();
              })

            Text(this.danmakuSending ? '发送中…' : '发送')
              .fontSize(14)
              .fontColor($r('app.color.text_on_brand'))
              .padding({ left: 18, right: 18, top: 10, bottom: 10 })
              .backgroundColor(this.danmakuDraft.trim().length === 0 || this.danmakuSending
                ? $r('app.color.text_tertiary') : $r('app.color.brand_primary'))
              .borderRadius(18)
              .onClick(() => {
                this.sendDanmaku();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({
          left: 14,
          right: 14,
          top: 12,
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

  /**
   * 播放结束（「停止推荐」模式）：视频区黑屏，居中一块推荐卡（上下两部分，横竖屏通用）。
   */
  @Builder
  endedOverlay() {
    Column() {
      Column() {
        // 上部分：左侧推荐封面 + 右侧两行（视频名称 / UP 主 · 播放量 · 弹幕数）
        Row({ space: 10 }) {
          Stack() {
            if (this.recommendCard.cover.length > 0) {
              Image(this.recommendCard.cover)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .alt($r('app.color.bg_field'))
                .draggable(false)
            } else {
              SymbolGlyph($r('sys.symbol.play_square'))
                .fontSize(22)
                .fontColor([$r('app.color.text_on_media')])
                .opacity(0.45)
            }
          }
          .width(104)
          .height(59)
          .borderRadius(7)
          .backgroundColor($r('app.color.overlay'))
          .clip(true)

          Column({ space: 6 }) {
            Text(this.recommendCard.title.length > 0 ? this.recommendCard.title : '正在为你挑选推荐视频')
              .width('100%')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_on_media'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Row({ space: 8 }) {
              if (this.recommendCard.author.length > 0) {
                Text(this.recommendCard.author)
                  .fontSize(11)
                  .fontColor($r('app.color.text_on_media'))
                  .opacity(0.7)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: '46%' })
              }
              if (this.recommendCard.viewText.length > 0) {
                Text(this.recommendCard.viewText)
                  .fontSize(11)
                  .fontColor($r('app.color.text_on_media'))
                  .opacity(0.7)
                  .maxLines(1)
              }
              if (this.recommendCard.danmuText.length > 0) {
                Text(this.recommendCard.danmuText)
                  .fontSize(11)
                  .fontColor($r('app.color.text_on_media'))
                  .opacity(0.7)
                  .maxLines(1)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.openCard(this.recommendCard);
        })

        // 下部分：两个按钮平分整块宽度（合起来正好占满上部分）
        Row({ space: 10 }) {
          Row({ space: 5 }) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(14)
              .fontColor([$r('app.color.text_on_media')])
            Text('视频重播')
              .fontSize(13)
              .fontColor($r('app.color.text_on_media'))
          }
          .layoutWeight(1)
          .height(38)
          .justifyContent(FlexAlign.Center)
          .border({ width: 1, color: $r('app.color.media_line') })
          .borderRadius(19)
          .onClick(() => {
            this.replayVideo();
          })

          Row() {
            Text('立即播放')
              .fontSize(13)
              .fontColor($r('app.color.text_on_brand'))
          }
          .layoutWeight(1)
          .height(38)
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.brand_primary'))
          .borderRadius(19)
          .opacity(this.recommendCard.bvid.length > 0 ? 1 : 0.45)
          .onClick(() => {
            this.openCard(this.recommendCard);
          })
        }
        .width('100%')
        .margin({ top: 14 })
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.media_card'))
      .borderRadius(14)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 18, right: 18 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(Color.Black)
  }

  /** 简介版块：作者 → 标题 → 元信息 → （展开的简介）→ 六项互动 → 推荐 */
  @Builder
  briefTab() {
    Scroll(this.scroller) {
      Column({ space: 0 }) {
        this.authorBlock()
        this.titleRow()
        this.metaRow()
        // 简介紧跟在「播放量 · 弹幕数」这一行下面展开，不再压到互动行之后
        if (this.briefExpanded) {
          this.briefBlock()
          Divider().color($r('app.color.divider'))
        }
        this.actionRow()
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
            // 播放结束态：黑屏 + 重播 + 推荐（只盖住视频区）
            if (this.playEnded) {
              this.endedOverlay()
            }
          }
          .width('100%')
          // 竖屏连播：画布铺满整屏（底部四块改由独立浮层盖在视频之上，不再挤压画布）；
          // 常规 / 全屏：16:9 或铺满；竖屏化视频在开启展示后可按用户拖动的高度撑开。
          .height(this.fullscreen || this.portraitMode ? '100%' : this.normalCanvasHeight())
          .backgroundColor(Color.Black)
          .clip(true)
          .onAreaChange((oldValue: Area, newValue: Area) => {
            const width: number = Number(newValue.width);
            const height: number = Number(newValue.height);
            if (width > 0) {
              this.surfaceWidth = width;
              this.surfaceHeight = height;
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
        // 关闭顶部沉浸时，用 padding 把内容整体压到增量条下面：
        // 这条 strip 本身由根 Stack 的底色画出（黑色 / 白色），高度正好一个状态栏。
        // 竖屏连播例外：画面盒高度从屏幕最上沿起算（自身再让开状态栏 + 顶栏），
        // 顶栏按钮的避让由浮层自己的 padding 负责（见 portraitOverlay）。
        .padding({ top: (this.fullscreen || this.portraitMode) ? 0 : (this.topImmersive ? 0 : this.topInset) })

        // 竖屏连播浮层：顶栏固定 + 底部四块（up 信息/名称可隐藏，进度条/操作行固定），
        // 盖在视频之上、与视频分属不同图层。中间空白用 Transparent 让点击穿透到视频手势。
        if (this.portraitMode && !this.fullscreen) {
          this.portraitOverlay()
        }

        // 评论输入浮层：盖住整页，含标题栏区域（本页 hideTitleBar）
        this.commentComposer()

        // 弹幕输入浮层（独立于评论区，竖屏连播里也能直接发）
        this.danmakuComposer()

        // 评论长按操作面板（复制 / 分享 / 举报 / 删除或删隐）
        this.commentActionSheet()

        // 竖屏顶部「设置」唤起的底部弹窗（内容与播放区设置面板一致）
        this.portraitSettingsSheet()
      }
      .width('100%')
      .height('100%')
      // 状态栏那一条铺黑：NavDestination 只放开了底部安全区（列表能铺到屏幕下沿），
      // 顶部仍是窗口底色（#F5F6F7），不铺黑就会留一条白边。用 expandSafeArea 把绘制区域顶到屏幕最上沿，
      // 布局仍从状态栏下方开始，所以底色只出现在状态栏这一条上。
      // 关闭沉浸后这条改用「增量颜色」（黑 / 白），内容靠上层 padding 让开这一条。
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .backgroundColor(this.topImmersive ? Color.Black : this.insetColor())
      // 键盘避让用 RESIZE：页面被压矮时能在这里量到，输入卡据此判断还要不要自己上移
      .onAreaChange((oldValue: Area, newValue: Area) => {
        this.onPageResize(Number(newValue.height));
      })
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    // 推荐视频 / 随机连播是「压栈」打开的：本页被盖住时先暂停，返回时再接着播
    .onHidden(() => {
      if (this.playing) {
        this.player.pause();
        this.pausedForPush = true;
      }
    })
    .onShown(() => {
      if (this.pausedForPush) {
        this.pausedForPush = false;
        this.player.play();
      }
    })
    // 整页铺到屏幕上下沿：NavDestination 默认把状态栏和手势条两条让出来，
    // 露出的是窗口底色（#F5F6F7），上下各一条「白边」。这里让布局忽略安全区，
    // 画布压到状态栏下面（顶部留黑），评论列表铺到屏幕最下沿。
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor($r('app.color.bg_page'))
  }
}
