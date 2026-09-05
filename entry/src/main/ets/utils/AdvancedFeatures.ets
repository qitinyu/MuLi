import { preferences } from '@kit.ArkData';
import { deviceInfo } from '@kit.BasicServicesKit';
import common from '@ohos.app.ability.common';

/**
 * 高级功能管理器
 * 控制 API 26 特性在 API 24+ 设备上的启用/禁用
 */
export class AdvancedFeatures {
  // 主开关：是否启用所有高级功能
  private static masterEnabled: boolean = true;

  // 子功能开关
  private static immersiveMaterialEnabled: boolean = true;
  private static enhancedPlayerEnabled: boolean = true;
  private static huksSessionEnabled: boolean = true;
  private static webCookieManagerEnabled: boolean = true;
  private static segmentButtonEnabled: boolean = true;

  // 设备 API 版本缓存
  private static deviceApiLevel: number = 0;

  // Preferences 存储键名
  private static readonly PREFS_NAME = 'pilihos_advanced';
  private static readonly KEY_MASTER = 'advanced_master';
  private static readonly KEY_IMMERSIVE = 'immersive_material';
  private static readonly KEY_PLAYER = 'enhanced_player';
  private static readonly KEY_HUKS = 'huks_session';
  private static readonly KEY_WEB_COOKIE = 'web_cookie_manager';
  private static readonly KEY_SEGMENT = 'segment_button';

  /**
   * 获取设备支持的最高 API 版本
   */
  static getDeviceApiLevel(): number {
    if (AdvancedFeatures.deviceApiLevel === 0) {
      AdvancedFeatures.deviceApiLevel = deviceInfo.sdkApiVersion;
    }
    return AdvancedFeatures.deviceApiLevel;
  }

  /**
   * 检查设备是否支持 API 26
   */
  static isApi26Supported(): boolean {
    return AdvancedFeatures.getDeviceApiLevel() >= 26;
  }

  /**
   * 获取主开关状态
   */
  static isMasterEnabled(): boolean {
    return AdvancedFeatures.masterEnabled && AdvancedFeatures.isApi26Supported();
  }

  /**
   * 设置主开关
   */
  static setMasterEnabled(enabled: boolean): void {
    AdvancedFeatures.masterEnabled = enabled;
  }

  /**
   * 检查沉浸式材质是否启用
   */
  static isImmersiveMaterialEnabled(): boolean {
    if (!AdvancedFeatures.isApi26Supported()) return false;
    return AdvancedFeatures.masterEnabled && AdvancedFeatures.immersiveMaterialEnabled;
  }

  /**
   * 设置沉浸式材质开关
   */
  static setImmersiveMaterialEnabled(enabled: boolean): void {
    AdvancedFeatures.immersiveMaterialEnabled = enabled;
  }

  /**
   * 检查增强播放器是否启用
   */
  static isEnhancedPlayerEnabled(): boolean {
    if (!AdvancedFeatures.isApi26Supported()) return false;
    return AdvancedFeatures.masterEnabled && AdvancedFeatures.enhancedPlayerEnabled;
  }

  /**
   * 设置增强播放器开关
   */
  static setEnhancedPlayerEnabled(enabled: boolean): void {
    AdvancedFeatures.enhancedPlayerEnabled = enabled;
  }

  /**
   * 检查 HUKS 会话式 API 是否启用
   */
  static isHuksSessionEnabled(): boolean {
    if (!AdvancedFeatures.isApi26Supported()) return false;
    return AdvancedFeatures.masterEnabled && AdvancedFeatures.huksSessionEnabled;
  }

  /**
   * 设置 HUKS 会话式 API 开关
   */
  static setHuksSessionEnabled(enabled: boolean): void {
    AdvancedFeatures.huksSessionEnabled = enabled;
  }

  /**
   * 检查 WebView Cookie 管理器是否启用
   */
  static isWebCookieManagerEnabled(): boolean {
    if (!AdvancedFeatures.isApi26Supported()) return false;
    return AdvancedFeatures.masterEnabled && AdvancedFeatures.webCookieManagerEnabled;
  }

  /**
   * 设置 WebView Cookie 管理器开关
   */
  static setWebCookieManagerEnabled(enabled: boolean): void {
    AdvancedFeatures.webCookieManagerEnabled = enabled;
  }

  /**
   * 检查 SegmentButton 是否启用
   */
  static isSegmentButtonEnabled(): boolean {
    if (!AdvancedFeatures.isApi26Supported()) return false;
    return AdvancedFeatures.masterEnabled && AdvancedFeatures.segmentButtonEnabled;
  }

  /**
   * 设置 SegmentButton 开关
   */
  static setSegmentButtonEnabled(enabled: boolean): void {
    AdvancedFeatures.segmentButtonEnabled = enabled;
  }

  /**
   * 从本地存储加载设置
   */
  static async loadSettings(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, AdvancedFeatures.PREFS_NAME);
      AdvancedFeatures.masterEnabled = store.getSync(AdvancedFeatures.KEY_MASTER, true) as boolean;
      AdvancedFeatures.immersiveMaterialEnabled = store.getSync(AdvancedFeatures.KEY_IMMERSIVE, true) as boolean;
      AdvancedFeatures.enhancedPlayerEnabled = store.getSync(AdvancedFeatures.KEY_PLAYER, true) as boolean;
      AdvancedFeatures.huksSessionEnabled = store.getSync(AdvancedFeatures.KEY_HUKS, true) as boolean;
      AdvancedFeatures.webCookieManagerEnabled = store.getSync(AdvancedFeatures.KEY_WEB_COOKIE, true) as boolean;
      AdvancedFeatures.segmentButtonEnabled = store.getSync(AdvancedFeatures.KEY_SEGMENT, true) as boolean;
    } catch (error) {
      console.error('Pilihos advanced features load failed: ' + String(error));
    }
  }

  /**
   * 保存设置到本地存储
   */
  static async saveSettings(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, AdvancedFeatures.PREFS_NAME);
      store.putSync(AdvancedFeatures.KEY_MASTER, AdvancedFeatures.masterEnabled);
      store.putSync(AdvancedFeatures.KEY_IMMERSIVE, AdvancedFeatures.immersiveMaterialEnabled);
      store.putSync(AdvancedFeatures.KEY_PLAYER, AdvancedFeatures.enhancedPlayerEnabled);
      store.putSync(AdvancedFeatures.KEY_HUKS, AdvancedFeatures.huksSessionEnabled);
      store.putSync(AdvancedFeatures.KEY_WEB_COOKIE, AdvancedFeatures.webCookieManagerEnabled);
      store.putSync(AdvancedFeatures.KEY_SEGMENT, AdvancedFeatures.segmentButtonEnabled);
      store.flushSync();
    } catch (error) {
      console.error('Pilihos advanced features save failed: ' + String(error));
    }
  }

  /**
   * 重置所有设置为默认值
   */
  static async resetSettings(context: common.UIAbilityContext): Promise<void> {
    AdvancedFeatures.masterEnabled = false;
    AdvancedFeatures.immersiveMaterialEnabled = true;
    AdvancedFeatures.enhancedPlayerEnabled = true;
    AdvancedFeatures.huksSessionEnabled = true;
    AdvancedFeatures.webCookieManagerEnabled = true;
    AdvancedFeatures.segmentButtonEnabled = true;
    await AdvancedFeatures.saveSettings(context);
  }

  /**
   * 获取所有功能状态的摘要
   */
  static getFeatureSummary(): string {
    const apiSupported = AdvancedFeatures.isApi26Supported();
    const masterOn = AdvancedFeatures.masterEnabled;

    let summary = `设备 API: ${AdvancedFeatures.getDeviceApiLevel()}\n`;
    summary += `API 26 支持: ${apiSupported ? '是' : '否'}\n`;
    summary += `主开关: ${masterOn ? '开启' : '关闭'}\n\n`;

    if (apiSupported) {
      summary += `沉浸式材质: ${AdvancedFeatures.immersiveMaterialEnabled ? '开启' : '关闭'}\n`;
      summary += `增强播放器: ${AdvancedFeatures.enhancedPlayerEnabled ? '开启' : '关闭'}\n`;
      summary += `HUKS 会话: ${AdvancedFeatures.huksSessionEnabled ? '开启' : '关闭'}\n`;
      summary += `Cookie 管理: ${AdvancedFeatures.webCookieManagerEnabled ? '开启' : '关闭'}\n`;
      summary += `分段按钮: ${AdvancedFeatures.segmentButtonEnabled ? '开启' : '关闭'}`;
    } else {
      summary += 'API 26 功能不可用';
    }

    return summary;
  }
}
