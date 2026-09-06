import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';

const STORE_NAME: string = 'pilihos_player';
const STORE_KEY: string = 'playback_progress';
const MAX_ENTRIES: number = 300;

/**
 * 播放记忆：以 aid 为键记录上次观看进度（毫秒），
 * 内存缓存供同步读取，变更后异步落盘，超出上限按插入顺序淘汰。
 */
export class PlaybackMemory {
  private static cache: Record<string, number> = {};
  private static loaded: boolean = false;

  static async load(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      const raw: string = store.getSync(STORE_KEY, '') as string;
      if (raw !== '') {
        const parsed: Record<string, number> = JSON.parse(raw) as Record<string, number>;
        PlaybackMemory.cache = parsed;
      }
      PlaybackMemory.loaded = true;
    } catch (error) {
      console.error(`Pilihos playback memory load failed: ${String(error)}`);
      PlaybackMemory.loaded = true;
    }
  }

  static progressOf(aid: number): number {
    if (aid <= 0) return 0;
    return PlaybackMemory.cache[`${aid}`] ?? 0;
  }

  static async record(context: common.UIAbilityContext, aid: number, positionMs: number): Promise<void> {
    if (aid <= 0 || positionMs < 5000) return;
    const next: Record<string, number> = PlaybackMemory.cache;
    next[`${aid}`] = Math.floor(positionMs);
    const keys: string[] = Object.keys(next);
    if (keys.length > MAX_ENTRIES) {
      // 超出上限时按插入顺序淘汰最旧的记录（ArkTS 不支持 delete，重建对象）
      const evict: number = keys.length - MAX_ENTRIES;
      const kept: Record<string, number> = {};
      for (let index: number = evict; index < keys.length; index++) {
        kept[keys[index]] = next[keys[index]];
      }
      PlaybackMemory.cache = kept;
    }
    if (!PlaybackMemory.loaded) return;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, STORE_NAME);
      store.putSync(STORE_KEY, JSON.stringify(PlaybackMemory.cache));
      store.flushSync();
    } catch (error) {
      console.error(`Pilihos playback memory save failed: ${String(error)}`);
    }
  }
}
