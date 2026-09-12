import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';

export interface PlayerSettings {
  keepRefreshContent: boolean;
  autoExpandDescription: boolean;
  defaultQuality: number;
  playMode: number;
  danmakuFontSize: number;
  danmakuOpacity: number;
  danmakuSpeed: number;
  danmakuArea: number;
}

export interface UISettings {
  floatBallSwapped: boolean;
  bottomBarPinned: boolean;
  portraitBadge: boolean;
  autoRotateEnabled: boolean;
  useAdvancedMaterial: boolean;
}

/**
 * 播放器设置持久化服务
 * 封装从 preferences 读写播放器和 UI 设置的逻辑
 */
export class PlayerSettingsService {
  static async loadPlayerSettings(context: common.UIAbilityContext): Promise<PlayerSettings> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, 'pilihos_player');
      return {
        keepRefreshContent: store.getSync('keep_refresh_content', false) as boolean,
        autoExpandDescription: store.getSync('auto_expand_description', false) as boolean,
        defaultQuality: store.getSync('default_quality', 0) as number,
        playMode: store.getSync('play_mode', 0) as number,
        danmakuFontSize: store.getSync('danmaku_font_size', 40) as number,
        danmakuOpacity: store.getSync('danmaku_opacity', 1) as number,
        danmakuSpeed: store.getSync('danmaku_speed', 1) as number,
        danmakuArea: store.getSync('danmaku_area', 100) as number
      };
    } catch (error) {
      console.error('Pilihos player settings load failed: ' + String(error));
      return {
        keepRefreshContent: false,
        autoExpandDescription: false,
        defaultQuality: 0,
        playMode: 0,
        danmakuFontSize: 40,
        danmakuOpacity: 1,
        danmakuSpeed: 1,
        danmakuArea: 100
      };
    }
  }

  static async loadUISettings(context: common.UIAbilityContext): Promise<UISettings> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, 'pilihos_ui');
      return {
        floatBallSwapped: store.getSync('float_ball_swapped', false) as boolean,
        bottomBarPinned: store.getSync('bottom_bar_pinned', true) as boolean,
        portraitBadge: store.getSync('portrait_badge', true) as boolean,
        autoRotateEnabled: store.getSync('auto_rotate_enabled', false) as boolean,
        useAdvancedMaterial: false
      };
    } catch (error) {
      console.error('Pilihos UI settings load failed: ' + String(error));
      return {
        floatBallSwapped: false,
        bottomBarPinned: true,
        portraitBadge: true,
        autoRotateEnabled: false,
        useAdvancedMaterial: false
      };
    }
  }

  static async savePlayMode(mode: number, context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, 'pilihos_player');
      store.putSync('play_mode', mode);
      store.flushSync();
    } catch (error) {
      console.error('Pilihos play mode save failed: ' + String(error));
    }
  }

  static async saveDanmakuSetting(key: string, value: number, context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, 'pilihos_player');
      store.putSync(key, value);
      store.flushSync();
    } catch (error) {
      console.error(`Pilihos danmaku setting save failed: ${String(error)}`);
    }
  }

  static async saveUI_boolean(key: string, value: boolean, context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, 'pilihos_ui');
      store.putSync(key, value);
      store.flushSync();
    } catch (error) {
      console.error(`Pilihos UI setting save failed: ${String(error)}`);
    }
  }

  static async getDefaultQuality(context: common.UIAbilityContext): Promise<number> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, 'pilihos_player');
      return store.getSync('default_quality', 0) as number;
    } catch (error) {
      return 0;
    }
  }
}
