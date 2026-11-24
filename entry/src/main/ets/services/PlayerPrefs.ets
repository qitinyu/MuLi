import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

/**
 * 播放器设置（V2.0.3）：持久化到 preferences。
 *
 * 设置项与 VideoPage 右侧设置面板一一对应：
 * - 基础四项：默认清晰度 / 终端继续播放（断点续播） / 迷你进度条 / 快捷手势
 * - 长按默认倍速、视频播放模式
 * - 弹幕设置（开关 / 显示区域 / 不透明度 / 字号 / 滚动速度），由播放页的弹幕画布即时读取
 *
 * 设计上保持「静态 load + 逐项 save」：页面 aboutToAppear 读一次到 @State，
 * 下拉菜单点选后改内存值并落盘，不做全局单例，避免多页面状态互相污染。
 */
export class PlayerPrefs {
  private static readonly STORE: string = 'muli_player_prefs';

  /**
   * 默认清晰度档位（对应 playUrl 的 qn）。
   * 参考 Pilihos 的档位口径：自动 / 1080P / 720P / 480P / 360P。
   * 说明：html5 单文件流在未登录时通常只给到 720P，请求更高档位服务端会回落，
   * 实际生效清晰度以 playUrl 返回的 data.quality 为准（不改写用户选择）。
   */
  static readonly QUALITIES: Array<number> = [0, 80, 64, 32, 16];
  static readonly QUALITY_LABELS: Array<string> = ['自动', '1080P', '720P', '480P', '360P'];
  /** 长按默认倍速 */
  static readonly SPEEDS: Array<number> = [0.5, 0.75, 1, 1.25, 1.5, 2];
  /** 弹幕显示区域 / 不透明度（占画面高度比例） */
  static readonly DANMAKU_RATIOS: Array<number> = [0.25, 0.5, 0.75, 1];
  static readonly RATIO_LABELS: Array<string> = ['25%', '50%', '75%', '100%'];
  /** 弹幕字号（vp） */
  static readonly DANMAKU_SIZES: Array<number> = [14, 18, 22, 26];
  static readonly SIZE_LABELS: Array<string> = ['小', '标准', '大', '特大'];
  /** 弹幕滚动速度（相对倍率，越大越快） */
  static readonly DANMAKU_SPEEDS: Array<number> = [0.6, 1, 1.6, 2.4];
  static readonly SPEED_LABELS: Array<string> = ['慢', '中', '快', '极快'];

  /** 视频播放模式：0 单集循环 / 1 随机连播 / 2 停止推荐 */
  static readonly PLAY_MODE_LABELS: Array<string> = ['单集循环', '随机连播', '停止推荐'];

  quality: number = 0;
  /** 终端继续播放：上次播放到的位置按 bvid 记录，下次进入自动续播 */
  continuePlay: boolean = true;
  miniProgress: boolean = false;
  quickGestures: boolean = true;
  longPressSpeed: number = 2;
  playMode: number = 2;
  danmakuOn: boolean = true;
  danmakuArea: number = 1;
  danmakuOpacity: number = 1;
  danmakuSize: number = 18;
  danmakuSpeed: number = 1;
  /** 推荐视频过滤词：中文逗号分隔，命中标题的推荐视频不再出现在播放页推荐里 */
  filterRecommend: string = '';
  /** 视频弹幕过滤词：中文逗号分隔，命中的弹幕不上屏 */
  filterDanmaku: string = '';

  static async load(context: common.UIAbilityContext): Promise<PlayerPrefs> {
    const result: PlayerPrefs = new PlayerPrefs();
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PlayerPrefs.STORE);
      result.quality = store.getSync('quality', 0) as number;
      result.continuePlay = store.getSync('continue_play', true) as boolean;
      result.miniProgress = store.getSync('mini_progress', false) as boolean;
      result.quickGestures = store.getSync('quick_gestures', true) as boolean;
      result.longPressSpeed = store.getSync('long_press_speed', 2) as number;
      result.playMode = store.getSync('play_mode', 2) as number;
      result.danmakuOn = store.getSync('danmaku_on', true) as boolean;
      result.danmakuArea = store.getSync('danmaku_area', 1) as number;
      result.danmakuOpacity = store.getSync('danmaku_opacity', 1) as number;
      result.danmakuSize = store.getSync('danmaku_size', 18) as number;
      result.danmakuSpeed = store.getSync('danmaku_speed', 1) as number;
      result.filterRecommend = store.getSync('filter_recommend', '') as string;
      result.filterDanmaku = store.getSync('filter_danmaku', '') as string;
    } catch (err) {
      console.warn(`MuLiPrefs load failed: ${String(err)}`);
    }
    return result;
  }

  async save(context: common.UIAbilityContext, key: string, value: number | boolean | string): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PlayerPrefs.STORE);
      // 调用方传的是内存字段名（驼峰，如 miniProgress），load() 读的是磁盘字段名（下划线），
      // 必须在这里统一映射，否则写进去读不出来、每次重启都回默认值。
      store.putSync(PlayerPrefs.diskKey(key), value);
      await store.flush();
    } catch (err) {
      console.warn(`MuLiPrefs save ${key} failed: ${String(err)}`);
    }
  }

  /** 内存字段名 → 磁盘字段名（与 load() 中 getSync 的 key 一一对应） */
  private static diskKey(key: string): string {
    switch (key) {
      case 'quality':
        return 'quality';
      case 'continuePlay':
        return 'continue_play';
      case 'miniProgress':
        return 'mini_progress';
      case 'quickGestures':
        return 'quick_gestures';
      case 'longPressSpeed':
        return 'long_press_speed';
      case 'playMode':
        return 'play_mode';
      case 'danmakuOn':
        return 'danmaku_on';
      case 'danmakuArea':
        return 'danmaku_area';
      case 'danmakuOpacity':
        return 'danmaku_opacity';
      case 'danmakuSize':
        return 'danmaku_size';
      case 'danmakuSpeed':
        return 'danmaku_speed';
      case 'filterRecommend':
        return 'filter_recommend';
      case 'filterDanmaku':
        return 'filter_danmaku';
      default:
        return key;
    }
  }

  /**
   * 过滤词解析：支持中文逗号 / 英文逗号 / 顿号 / 空格分隔，去空、去重。
   * 设置页与播放页共用同一套口径，避免两边理解不一致。
   */
  static keywords(text: string): Array<string> {
    const result: Array<string> = [];
    const parts: Array<string> = text.split(/[，,、\s]+/);
    for (let i = 0; i < parts.length; i++) {
      const word: string = parts[i].trim();
      if (word.length > 0 && result.indexOf(word) < 0) {
        result.push(word);
      }
    }
    return result;
  }

  /** text 是否命中任一关键词（包含即命中） */
  static hitKeyword(text: string, words: Array<string>): boolean {
    if (text.length === 0 || words.length === 0) {
      return false;
    }
    const lower: string = text.toLowerCase();
    for (let i = 0; i < words.length; i++) {
      if (lower.indexOf(words[i].toLowerCase()) >= 0) {
        return true;
      }
    }
    return false;
  }

  /** 进度按 bvid 存储：key 形如 progress_BV1xx，仅断点续播开启时读写 */
  static async loadProgress(context: common.UIAbilityContext, bvid: string): Promise<number> {
    if (bvid.length === 0) {
      return 0;
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PlayerPrefs.STORE);
      return store.getSync(`progress_${bvid}`, 0) as number;
    } catch (err) {
      return 0;
    }
  }

  static async saveProgress(context: common.UIAbilityContext, bvid: string, positionMs: number): Promise<void> {
    if (bvid.length === 0) {
      return;
    }
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, PlayerPrefs.STORE);
      store.putSync(`progress_${bvid}`, Math.max(0, Math.floor(positionMs)));
      await store.flush();
    } catch (err) {
      console.warn(`MuLiPrefs save progress failed: ${String(err)}`);
    }
  }
}
