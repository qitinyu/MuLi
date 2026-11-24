import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ChannelRegistry } from '../model/ChannelRegistry';

/**
 * 应用级设置（V2.0.3）：统一持久化到 preferences，并同步到 AppStorage。
 *
 * 为什么走 AppStorage：设置页与首页 / 我的页是不同页面实例，
 * 用 @StorageLink 订阅同一份 key 才能做到「设置里一改，其他页面立刻生效」。
 * 因此约定：**所有可即时生效的设置都以 AppStorage key 为准**，preferences 只负责跨启动留存。
 */
export class AppPrefs {
  private static readonly STORE: string = 'muli_app_prefs';

  /** 设置是否已从磁盘载入（未载入前页面按默认值渲染） */
  static readonly KEY_READY: string = 'muli_prefsReady';
  /** 底部隐藏：开启后上滑收起底部栏，关闭后底部栏常驻 */
  static readonly KEY_BOTTOM_HIDE: string = 'muli_bottomHide';
  /** 默认启动页（下标对应 START_TAB_LABELS） */
  static readonly KEY_START_TAB: string = 'muli_startTab';
  /** 推荐页卡片布局：0 = 1×N，1 = 2×N，2 = 自适应 */
  static readonly KEY_CARD_LAYOUT: string = 'muli_cardLayout';
  /** 顶部分区条是否显示 */
  static readonly KEY_LIST_VISIBLE: string = 'muli_listVisible';
  /** 顶部分区条是否跟随界面移动隐藏 */
  static readonly KEY_LIST_FOLLOW: string = 'muli_listFollow';
  /** 顶部分区选择集（逗号分隔 key 串） */
  static readonly KEY_PARTITIONS: string = 'muli_partitions';
  /** 我的页背景（http 链接或沙箱图片路径） */
  static readonly KEY_MINE_COVER: string = 'muli_mineCover';
  /** 视频卡 UP 主名过长时的处理：0 = 过长隐藏（省略号），1 = 循环滚动 */
  static readonly KEY_AUTHOR_NAME_MODE: string = 'muli_authorNameMode';
  /** 播放区顶部是否沉浸到系统状态栏（默认开启；关闭时顶部加一条增量色块） */
  static readonly KEY_TOP_IMMERSIVE: string = 'muli_playerTopImmersive';
  /** 关闭沉浸时顶部增量条颜色：0 = 黑色，1 = 白色 */
  static readonly KEY_TOP_INSET_COLOR: string = 'muli_playerTopInsetColor';
  /** 下拉刷新是否保存前置内容（默认开；关闭后下拉刷新会先清空当前列表） */
  static readonly KEY_REC_SAVE: string = 'muli_recSaveOnRefresh';
  /** 下拉刷新一次拉多少条：下标对应 REC_COUNT_VALUES */
  static readonly KEY_REC_COUNT: string = 'muli_recRefreshCount';
  /** 竖屏化视频是否在推荐流里混排展示（默认关；开启后卡片在播放量前标「竖屏」） */
  static readonly KEY_SHOW_VERTICAL: string = 'muli_showVertical';
  /** 播放页顶部分区 List 点击是否全量刷新（默认关，实验性） */
  static readonly KEY_LIST_TAP_REFRESH: string = 'muli_listTapRefresh';

  /** 默认启动页候选：与底部栏版块一一对应，番剧暂未建版块 */
  static readonly START_TAB_LABELS: Array<string> = ['首页', '动态', '番剧', '热门', '直播'];
  /** 候选 → 底部栏页签下标，-1 表示该版块尚未建立 */
  private static readonly START_TAB_TO_MAIN: Array<number> = [0, 1, -1, 3, 4];

  static readonly CARD_LAYOUT_LABELS: Array<string> = ['1×N 单列', '2×N 双列', '自适应'];
  /** 下拉刷新数目候选（与 KEY_REC_COUNT 下标一一对应） */
  static readonly REC_COUNT_VALUES: Array<number> = [10, 20];
  static readonly REC_COUNT_LABELS: Array<string> = ['10 条', '20 条'];

  /** UP 主名过长策略：下标即存储值 */
  static readonly AUTHOR_NAME_LABELS: Array<string> = ['过长隐藏', '循环滚动'];
  /** 关闭顶部沉浸时增量条颜色 */
  static readonly TOP_INSET_LABELS: Array<string> = ['黑色', '白色'];

  /** 启动时把磁盘设置灌进 AppStorage（默认值先写，磁盘值覆盖） */
  static async load(context: common.UIAbilityContext): Promise<void> {
    AppPrefs.publishDefaults();
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, AppPrefs.STORE);
      AppStorage.setOrCreate(AppPrefs.KEY_BOTTOM_HIDE, store.getSync('bottom_hide', true) as boolean);
      AppStorage.setOrCreate(AppPrefs.KEY_START_TAB, store.getSync('start_tab', 0) as number);
      AppStorage.setOrCreate(AppPrefs.KEY_CARD_LAYOUT, store.getSync('card_layout', 1) as number);
      AppStorage.setOrCreate(AppPrefs.KEY_LIST_VISIBLE, store.getSync('list_visible', true) as boolean);
      AppStorage.setOrCreate(AppPrefs.KEY_LIST_FOLLOW, store.getSync('list_follow', true) as boolean);
      AppStorage.setOrCreate(AppPrefs.KEY_PARTITIONS,
        store.getSync('partitions', ChannelRegistry.defaultKeys()) as string);
      AppStorage.setOrCreate(AppPrefs.KEY_MINE_COVER, store.getSync('mine_cover', '') as string);
      AppStorage.setOrCreate(AppPrefs.KEY_AUTHOR_NAME_MODE, store.getSync('author_name_mode', 0) as number);
      AppStorage.setOrCreate(AppPrefs.KEY_TOP_IMMERSIVE, store.getSync('player_top_immersive', true) as boolean);
      AppStorage.setOrCreate(AppPrefs.KEY_TOP_INSET_COLOR, store.getSync('player_top_inset_color', 0) as number);
      AppStorage.setOrCreate(AppPrefs.KEY_REC_SAVE, store.getSync('rec_save_on_refresh', true) as boolean);
      AppStorage.setOrCreate(AppPrefs.KEY_REC_COUNT, store.getSync('rec_refresh_count', 0) as number);
      AppStorage.setOrCreate(AppPrefs.KEY_SHOW_VERTICAL, store.getSync('show_vertical', false) as boolean);
      AppStorage.setOrCreate(AppPrefs.KEY_LIST_TAP_REFRESH, store.getSync('list_tap_refresh', false) as boolean);
    } catch (err) {
      console.warn(`MuLiAppPrefs load failed: ${String(err)}`);
    }
    AppStorage.setOrCreate(AppPrefs.KEY_READY, true);
  }

  /** 默认值：保证首帧就有合法值，页面不必判空 */
  static publishDefaults(): void {
    AppStorage.setOrCreate(AppPrefs.KEY_BOTTOM_HIDE, true);
    AppStorage.setOrCreate(AppPrefs.KEY_START_TAB, 0);
    AppStorage.setOrCreate(AppPrefs.KEY_CARD_LAYOUT, 1);
    AppStorage.setOrCreate(AppPrefs.KEY_LIST_VISIBLE, true);
    AppStorage.setOrCreate(AppPrefs.KEY_LIST_FOLLOW, true);
    AppStorage.setOrCreate(AppPrefs.KEY_PARTITIONS, ChannelRegistry.defaultKeys());
    AppStorage.setOrCreate(AppPrefs.KEY_MINE_COVER, '');
    AppStorage.setOrCreate(AppPrefs.KEY_AUTHOR_NAME_MODE, 0);
    AppStorage.setOrCreate(AppPrefs.KEY_TOP_IMMERSIVE, true);
    AppStorage.setOrCreate(AppPrefs.KEY_TOP_INSET_COLOR, 0);
    AppStorage.setOrCreate(AppPrefs.KEY_REC_SAVE, true);
    AppStorage.setOrCreate(AppPrefs.KEY_REC_COUNT, 0);
    AppStorage.setOrCreate(AppPrefs.KEY_SHOW_VERTICAL, false);
    AppStorage.setOrCreate(AppPrefs.KEY_LIST_TAP_REFRESH, false);
  }

  static async save(context: common.UIAbilityContext, key: string, value: number | boolean | string): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, AppPrefs.STORE);
      store.putSync(AppPrefs.diskKey(key), value);
      await store.flush();
    } catch (err) {
      console.warn(`MuLiAppPrefs save ${key} failed: ${String(err)}`);
    }
  }

  /** AppStorage key → 磁盘字段名 */
  private static diskKey(key: string): string {
    switch (key) {
      case AppPrefs.KEY_BOTTOM_HIDE:
        return 'bottom_hide';
      case AppPrefs.KEY_START_TAB:
        return 'start_tab';
      case AppPrefs.KEY_CARD_LAYOUT:
        return 'card_layout';
      case AppPrefs.KEY_LIST_VISIBLE:
        return 'list_visible';
      case AppPrefs.KEY_LIST_FOLLOW:
        return 'list_follow';
      case AppPrefs.KEY_PARTITIONS:
        return 'partitions';
      case AppPrefs.KEY_MINE_COVER:
        return 'mine_cover';
      case AppPrefs.KEY_AUTHOR_NAME_MODE:
        return 'author_name_mode';
      case AppPrefs.KEY_TOP_IMMERSIVE:
        return 'player_top_immersive';
      case AppPrefs.KEY_TOP_INSET_COLOR:
        return 'player_top_inset_color';
      case AppPrefs.KEY_REC_SAVE:
        return 'rec_save_on_refresh';
      case AppPrefs.KEY_REC_COUNT:
        return 'rec_refresh_count';
      case AppPrefs.KEY_SHOW_VERTICAL:
        return 'show_vertical';
      case AppPrefs.KEY_LIST_TAP_REFRESH:
        return 'list_tap_refresh';
      default:
        return key;
    }
  }

  /** 默认启动页 → 底部栏页签下标；番剧未建版块时回退首页 */
  static mainTabOfStart(startIndex: number): number {
    if (startIndex < 0 || startIndex >= AppPrefs.START_TAB_TO_MAIN.length) {
      return 0;
    }
    const mainIndex: number = AppPrefs.START_TAB_TO_MAIN[startIndex];
    return mainIndex < 0 ? 0 : mainIndex;
  }

  /** 该启动项是否已建立对应版块（番剧当前未建） */
  static startTabAvailable(startIndex: number): boolean {
    if (startIndex < 0 || startIndex >= AppPrefs.START_TAB_TO_MAIN.length) {
      return false;
    }
    return AppPrefs.START_TAB_TO_MAIN[startIndex] >= 0;
  }

  static startTabLabel(startIndex: number): string {
    if (startIndex < 0 || startIndex >= AppPrefs.START_TAB_LABELS.length) {
      return AppPrefs.START_TAB_LABELS[0];
    }
    return AppPrefs.START_TAB_LABELS[startIndex];
  }

  static cardLayoutLabel(layout: number): string {
    if (layout < 0 || layout >= AppPrefs.CARD_LAYOUT_LABELS.length) {
      return AppPrefs.CARD_LAYOUT_LABELS[1];
    }
    return AppPrefs.CARD_LAYOUT_LABELS[layout];
  }

  static authorNameLabel(mode: number): string {
    if (mode < 0 || mode >= AppPrefs.AUTHOR_NAME_LABELS.length) {
      return AppPrefs.AUTHOR_NAME_LABELS[0];
    }
    return AppPrefs.AUTHOR_NAME_LABELS[mode];
  }

  static topInsetLabel(index: number): string {
    if (index < 0 || index >= AppPrefs.TOP_INSET_LABELS.length) {
      return AppPrefs.TOP_INSET_LABELS[0];
    }
    return AppPrefs.TOP_INSET_LABELS[index];
  }

  /** 下拉刷新数目：下标 → 条数（越界按 10 条） */
  static recCount(index: number): number {
    if (index < 0 || index >= AppPrefs.REC_COUNT_VALUES.length) {
      return AppPrefs.REC_COUNT_VALUES[0];
    }
    return AppPrefs.REC_COUNT_VALUES[index];
  }

  static recCountLabel(index: number): string {
    if (index < 0 || index >= AppPrefs.REC_COUNT_LABELS.length) {
      return AppPrefs.REC_COUNT_LABELS[0];
    }
    return AppPrefs.REC_COUNT_LABELS[index];
  }
}
