import { preferences } from '@kit.ArkData';
import common from '@ohos.app.ability.common';

export class FilterWords {
  private static videoWords: string[] = [];
  private static danmakuWords: string[] = [];

  static async load(context: common.UIAbilityContext): Promise<void> {
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(context, 'pilihos_filter');
      FilterWords.videoWords = FilterWords.parse(String(store.getSync('video_words', '') as string));
      FilterWords.danmakuWords = FilterWords.parse(String(store.getSync('danmaku_words', '') as string));
    } catch (error) {
      console.error('Pilihos filter words load failed: ' + String(error));
    }
  }

  static async save(context: common.UIAbilityContext, kind: string, text: string): Promise<void> {
    // 先更新内存态，保证界面摘要立即生效；存储失败不阻塞
    if (kind === 'video') {
      FilterWords.videoWords = FilterWords.parse(text);
    } else {
      FilterWords.danmakuWords = FilterWords.parse(text);
    }
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(context, 'pilihos_filter');
      store.putSync(kind === 'video' ? 'video_words' : 'danmaku_words', text);
      store.flushSync();
    } catch (error) {
      console.error('Pilihos filter words save failed: ' + String(error));
    }
  }

  static getWords(kind: string): string[] {
    return kind === 'video' ? FilterWords.videoWords : FilterWords.danmakuWords;
  }

  static isVideoFiltered(text: string): boolean {
    return FilterWords.matches(text, FilterWords.videoWords);
  }

  static isDanmakuFiltered(text: string): boolean {
    return FilterWords.matches(text, FilterWords.danmakuWords);
  }

  private static matches(text: string, words: string[]): boolean {
    if (text === '' || words.length === 0) return false;
    const lower: string = text.toLowerCase();
    return words.some((word: string): boolean => lower.includes(word.toLowerCase()));
  }

  private static parse(text: string): string[] {
    return text.split(/[|\n\r]/).map((item: string): string => item.trim())
      .filter((item: string): boolean => item !== '');
  }
}
