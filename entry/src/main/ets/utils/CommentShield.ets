import common from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';

/**
 * 本地评论屏蔽：被标记的评论在个人端永久隐藏（存于本地 preferences）。
 */
export class CommentShield {
  private static hiddenIds: Set<number> = new Set<number>();
  private static loaded: boolean = false;

  static load(context: common.UIAbilityContext): void {
    if (CommentShield.loaded) return;
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: 'pilihos_comment' });
      const raw: string = store.getSync('hidden_comments', '[]') as string;
      const parsed: Object = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        (parsed as Object[]).forEach((item: Object): void => {
          const id: number = Number(item);
          if (id > 0) CommentShield.hiddenIds.add(id);
        });
      }
      CommentShield.loaded = true;
    } catch (error) {
      console.warn(`Pilihos comment shield load failed: ${String(error)}`);
    }
  }

  static isHidden(rpid: number): boolean {
    return CommentShield.hiddenIds.has(rpid);
  }

  static hide(context: common.UIAbilityContext, rpid: number): void {
    if (rpid <= 0) return;
    CommentShield.hiddenIds.add(rpid);
    try {
      const store: preferences.Preferences =
        preferences.getPreferencesSync(context, { name: 'pilihos_comment' });
      store.putSync('hidden_comments', JSON.stringify(Array.from(CommentShield.hiddenIds)));
      store.flushSync();
    } catch (error) {
      console.warn(`Pilihos comment shield save failed: ${String(error)}`);
    }
  }
}