import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { AdvancedFeatures } from '../../utils/AdvancedFeatures';
import { FilterWords } from '../../utils/FilterWords';
import { PlaybackService } from '../../services/PlaybackService';
import { SettingsItem } from '../settings/ListItemView';

export class SettingsViewModel {
  // 外观设置
  public floatBallSwapped: boolean = false;
  public bottomBarPinned: boolean = true;
  public portraitBadgeEnabled: boolean = true;
  public autoRotateEnabled: boolean = false;

  // 播放器设置
  public keepRefreshContent: boolean = false;
  public autoExpandDescription: boolean = false;
  public defaultQuality: number = 0;
  public videoQuickActionsEnabled: boolean = false;

  // 搜索设置
  public searchHistoryEnabled: boolean = false;
  public searchSuggestEnabled: boolean = false;

  // 播放行为设置（打断接续默认开；后台悬浮窗为占位开关，功能暂未实现）
  public interruptResumeEnabled: boolean = true;
  public pipMasterEnabled: boolean = false;
  public pipManualEnabled: boolean = true;
  public pipAutoEnabled: boolean = false;
  public miniProgressEnabled: boolean = false;

  // 高级功能设置
  public advancedMasterEnabled: boolean = false;
  public advancedImmersiveEnabled: boolean = true;
  public advancedPlayerEnabled: boolean = true;
  public advancedHuksEnabled: boolean = true;
  public advancedWebCookieEnabled: boolean = true;
  public advancedSegmentEnabled: boolean = true;

  // 过滤词
  public videoFilterSummary: string = '未设置';
  public danmakuFilterSummary: string = '未设置';

  // 主设置分组
  public appearanceGroup: SettingsItem[] = [
    { id: 'bottomBarPinned', title: '底部常驻', subtitle: '关闭后，HDS 底部栏会随列表滑动自动隐藏' },
    { id: 'portraitBadge', title: '竖屏提示', subtitle: '视频卡片在播放量/弹幕量后展示竖屏标记' },
    { id: 'autoRotate', title: '自动横屏', subtitle: '开启后不受系统控制即可自动横屏' }
  ];

  public playerGroup: SettingsItem[] = [
    { id: 'defaultQuality', title: '播放质量', value: '自动' },
    { id: 'keepRefreshContent', title: '推荐页刷新保留', subtitle: '下拉刷新将保留刷新前的内容' },
    { id: 'videoQuickActions', title: '视频快捷操作', subtitle: '开启后即可长按对视频进行快捷操作' }
  ];

  public searchGroup: SettingsItem[] = [
    { id: 'searchHistory', title: '搜索历史记忆', subtitle: '开启后将记忆搜索历史' }
  ];

  public advancedGroup: SettingsItem[] = [
    { id: 'advancedMaster', title: 'API 26 高级能力', subtitle: '控制 API 26 专属能力；界面材质会按设备版本自动适配' }
  ];

  public advancedApi26Group: SettingsItem[] = [
    { id: 'enhancedPlayer', title: '增强播放器', subtitle: '支持自定义 HTTP 头部，提升视频加载兼容性' },
    { id: 'huksSession', title: 'HUKS 会话式加密', subtitle: '使用新版密钥库会话 API，提升安全性' },
    { id: 'webCookie', title: 'WebView Cookie 管理', subtitle: '使用新版 Cookie 管理器获取登录凭证' }
  ];

  private context: common.UIAbilityContext | null = null;

  public setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  public qualityLabel(value: number): string {
    if (value === 0) return '自动';
    return PlaybackService.qualityLabel(value);
  }

  public async loadAllSettings(): Promise<void> {
    if (this.context === null) return;
    await this.loadAppearanceSettings();
    await this.loadPlayerSettings();
    await this.loadSearchSettings();
    await this.loadAdvancedSettings();
    await this.loadFilterSummaries();
    await this.loadPlayerBehaviorSettings();
  }

  // 播放行为设置：读取并同步 AppStorage（PlayerScreen @StorageProp 消费）
  private async loadPlayerBehaviorSettings(): Promise<void> {
    if (this.context === null) return;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_ui');
      this.interruptResumeEnabled = store.getSync('interrupt_resume', true) as boolean;
      this.pipMasterEnabled = store.getSync('pip_master', false) as boolean;
      this.pipManualEnabled = store.getSync('pip_manual', true) as boolean;
      this.pipAutoEnabled = store.getSync('pip_auto', false) as boolean;
      this.miniProgressEnabled = store.getSync('mini_progress_on', false) as boolean;
      AppStorage.setOrCreate('interrupt_resume_on', this.interruptResumeEnabled);
      AppStorage.setOrCreate('mini_progress_on', this.miniProgressEnabled);
    } catch (error) {
      console.error('Pilihos player behavior settings load failed: ' + String(error));
    }
  }

  public async savePlayerBehaviorSetting(key: string, value: boolean): Promise<void> {
    if (this.context === null) return;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_ui');
      store.putSync(key, value);
      store.flushSync();
      if (key === 'interrupt_resume') {
        AppStorage.setOrCreate('interrupt_resume_on', value);
      }
      if (key === 'mini_progress_on') {
        AppStorage.setOrCreate('mini_progress_on', value);
      }
    } catch (error) {
      console.error('Pilihos player behavior settings save failed: ' + String(error));
    }
  }

  private async loadAppearanceSettings(): Promise<void> {
    if (this.context === null) return;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_ui');
      this.floatBallSwapped = store.getSync('float_ball_swapped', false) as boolean;
      this.bottomBarPinned = store.getSync('bottom_bar_pinned', true) as boolean;
      this.portraitBadgeEnabled = store.getSync('portrait_badge', true) as boolean;
      this.autoRotateEnabled = store.getSync('auto_rotate_enabled', false) as boolean;
    } catch (error) {
      console.error('Pilihos appearance settings load failed: ' + String(error));
    }
  }

  public async saveAppearanceSetting(key: string, value: boolean | string | number): Promise<void> {
    if (this.context === null) return;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_ui');
      if (typeof value === 'boolean') {
        store.putSync(key, value);
      } else if (typeof value === 'string') {
        store.putSync(key, value);
      } else {
        store.putSync(key, value);
      }
      store.flushSync();
    } catch (error) {
      console.error('Pilihos appearance settings save failed: ' + String(error));
    }
  }

  private async loadPlayerSettings(): Promise<void> {
    if (this.context === null) return;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_player');
      this.keepRefreshContent = store.getSync('keep_refresh_content', false) as boolean;
      this.autoExpandDescription = store.getSync('auto_expand_description', false) as boolean;
      this.defaultQuality = store.getSync('default_quality', 0) as number;
      this.videoQuickActionsEnabled = store.getSync('video_quick_actions', false) as boolean;
    } catch (error) {
      console.error('Pilihos player settings load failed: ' + String(error));
    }
  }

  public async savePlayerSetting(key: string, value: boolean | string | number): Promise<void> {
    if (this.context === null) return;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_player');
      if (typeof value === 'boolean') {
        store.putSync(key, value);
      } else if (typeof value === 'string') {
        store.putSync(key, value);
      } else {
        store.putSync(key, value);
      }
      store.flushSync();
    } catch (error) {
      console.error('Pilihos player settings save failed: ' + String(error));
    }
  }

  public cycleDefaultQuality(): void {
    const options: number[] = [0, 80, 64, 32, 16];
    const index: number = options.indexOf(this.defaultQuality);
    const next: number = options[(index + 1) % options.length];
    this.defaultQuality = next;
    this.savePlayerSetting('default_quality', next);
    // 更新显示值
    this.playerGroup[0].value = this.qualityLabel(next);
  }

  private async loadSearchSettings(): Promise<void> {
    if (this.context === null) return;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_search');
      this.searchHistoryEnabled = store.getSync('history_enabled', false) as boolean;
      this.searchSuggestEnabled = store.getSync('suggest_enabled', false) as boolean;
      AppStorage.setOrCreate('search_suggest_on', this.searchSuggestEnabled);
    } catch (error) {
      console.error('Pilihos search settings load failed: ' + String(error));
    }
  }

  public async saveSearchSetting(key: string, value: boolean): Promise<void> {
    if (this.context === null) return;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_search');
      store.putSync(key, value);
      store.flushSync();
      if (key === 'suggest_enabled') {
        AppStorage.setOrCreate('search_suggest_on', value);
      }
    } catch (error) {
      console.error('Pilihos search settings save failed: ' + String(error));
    }
  }

  private async loadAdvancedSettings(): Promise<void> {
    if (this.context === null) return;
    await AdvancedFeatures.loadSettings(this.context);
    this.advancedMasterEnabled = AdvancedFeatures.isMasterEnabled();
    this.advancedImmersiveEnabled = AdvancedFeatures.isImmersiveMaterialEnabled();
    this.advancedPlayerEnabled = AdvancedFeatures.isEnhancedPlayerEnabled();
    this.advancedHuksEnabled = AdvancedFeatures.isHuksSessionEnabled();
    this.advancedWebCookieEnabled = AdvancedFeatures.isWebCookieManagerEnabled();
    this.advancedSegmentEnabled = AdvancedFeatures.isSegmentButtonEnabled();
  }

  public async saveAdvancedSetting(setting: string, value: boolean): Promise<void> {
    if (this.context === null) return;
    switch (setting) {
      case 'master':
        AdvancedFeatures.setMasterEnabled(value);
        break;
      case 'immersive':
        AdvancedFeatures.setImmersiveMaterialEnabled(value);
        break;
      case 'player':
        AdvancedFeatures.setEnhancedPlayerEnabled(value);
        break;
      case 'huks':
        AdvancedFeatures.setHuksSessionEnabled(value);
        break;
      case 'webCookie':
        AdvancedFeatures.setWebCookieManagerEnabled(value);
        break;
      case 'segment':
        AdvancedFeatures.setSegmentButtonEnabled(value);
        break;
    }
    await AdvancedFeatures.saveSettings(this.context);
  }

  private async loadFilterSummaries(): Promise<void> {
    if (this.context === null) return;
    await FilterWords.load(this.context);
    this.refreshFilterSummaries();
  }

  public refreshFilterSummaries(): void {
    const videoWords: string[] = FilterWords.getWords('video');
    const danmakuWords: string[] = FilterWords.getWords('danmaku');
    this.videoFilterSummary = videoWords.length > 0 ? videoWords.join('|') : '未设置';
    this.danmakuFilterSummary = danmakuWords.length > 0 ? danmakuWords.join('|') : '未设置';
  }

  public async saveFilterWords(kind: string, text: string): Promise<void> {
    if (this.context === null) return;
    await FilterWords.save(this.context, kind, text);
    this.refreshFilterSummaries();
  }

  public getFilterWords(kind: string): string {
    return FilterWords.getWords(kind).join('|');
  }

  public isApi26Supported(): boolean {
    return AdvancedFeatures.isApi26Supported();
  }

  public getDeviceApiLevel(): number {
    return AdvancedFeatures.getDeviceApiLevel();
  }
}
