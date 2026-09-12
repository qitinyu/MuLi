import { BiliHttpClient } from './BiliHttpClient';
import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';

export interface BiliEmoji {
  name: string;
  url: string;
}

/** Loads the user's available Bilibili reply emoji set and recent-used records. */
export class EmojiService {
  private static readonly recentLimit: number = 12;

  static normalizeName(value: string): string {
    let name: string = value.trim();
    if (name.startsWith('[') && name.endsWith(']') && name.length > 2) {
      name = name.substring(1, name.length - 1);
    }
    return name;
  }

  static async loadReplyEmojis(cookie: string): Promise<BiliEmoji[]> {
    const query: Record<string, string> = {
      'business': 'reply',
      'mobi_app': 'web',
      'platform': 'web',
      'web_location': '333.1365'
    };
    const result: Record<string, Object> =
      await BiliHttpClient.getJson('/x/emote/user/panel/web', query, cookie);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '表情包获取失败'));
    }
    const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
    const packages: Object[] = (data['packages'] as Object[]) ?? [];
    const output: BiliEmoji[] = [];
    packages.forEach((rawPackage: Object): void => {
      const packageData: Record<string, Object> = rawPackage as Record<string, Object>;
      const emotes: Object[] = (packageData['emote'] as Object[]) ??
        (packageData['emotes'] as Object[]) ?? [];
      emotes.forEach((rawEmoji: Object): void => {
        const emoji: Record<string, Object> = rawEmoji as Record<string, Object>;
        const name: string = EmojiService.normalizeName(
          String(emoji['text'] ?? emoji['name'] ?? ''));
        const url: string = String(emoji['url'] ?? emoji['gif_url'] ?? '');
        if (name !== '' && url !== '') output.push({ name: name, url: url });
      });
    });
    return output;
  }

  static async loadRecentEmojis(context: common.UIAbilityContext): Promise<string[]> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, 'pilihos_player');
      const raw: string = store.getSync('emoji_recent', '[]') as string;
      const parsed: Object = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];
      const names: string[] = (parsed as Object[]).map((item: Object): string =>
        EmojiService.normalizeName(String(item)));
      return names.slice(0, EmojiService.recentLimit);
    } catch (error) {
      console.warn(`Pilihos recent emoji load failed: ${String(error)}`);
      return [];
    }
  }

  static async saveRecentEmojis(context: common.UIAbilityContext, names: string[]): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, 'pilihos_player');
      store.putSync('emoji_recent', JSON.stringify(names.slice(0, EmojiService.recentLimit)));
      store.flushSync();
    } catch (error) {
      console.warn(`Pilihos recent emoji save failed: ${String(error)}`);
    }
  }
}
