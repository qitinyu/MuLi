import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

/**
 * 「删隐回复」的本地黑名单。
 *
 * 别人的评论发不了删除请求（服务端只允许删自己的），但用户希望把不想看的评论
 * 从自己的视野里拿掉，所以这里在本地按 rpid 记一份黑名单：刷新/重进都还是隐着的，
 * 但对别人没有任何影响 —— 就是需求里的「仅自己不可见」。
 *
 * rpid 是 b 站全局唯一的，所以一份名单可以跨视频复用，不必按 bvid 分开存。
 */
export class HiddenCommentStore {
  private static readonly STORE: string = 'muli_hidden_comments';
  private static readonly KEY: string = 'rpids';
  /** 内存镜像：渲染时同步查，不用每次等磁盘 */
  private static cache: Set<string> = new Set<string>();
  private static loaded: boolean = false;

  /** 进页面读一次；失败就当作空名单，不影响评论展示 */
  static async load(context: common.UIAbilityContext): Promise<void> {
    if (HiddenCommentStore.loaded) {
      return;
    }
    HiddenCommentStore.loaded = true;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(context, HiddenCommentStore.STORE);
      const text: string = store.getSync(HiddenCommentStore.KEY, '') as string;
      if (text.length === 0) {
        return;
      }
      const parts: Array<string> = text.split(',');
      for (let i = 0; i < parts.length; i++) {
        if (parts[i].length > 0) {
          HiddenCommentStore.cache.add(parts[i]);
        }
      }
    } catch (err) {
      console.warn(`MuLiHidden load failed: ${String(err)}`);
    }
  }

  static isHidden(rpid: string): boolean {
    return rpid.length > 0 && HiddenCommentStore.cache.has(rpid);
  }

  static async hide(context: common.UIAbilityContext, rpid: string): Promise<void> {
    if (rpid.length === 0) {
      return;
    }
    HiddenCommentStore.cache.add(rpid);
    HiddenCommentStore.loaded = true;
    await HiddenCommentStore.flush(context);
  }

  private static async flush(context: common.UIAbilityContext): Promise<void> {
    try {
      const list: Array<string> = [];
      HiddenCommentStore.cache.forEach((rpid: string) => {
        list.push(rpid);
      });
      const store: preferences.Preferences = await preferences.getPreferences(context, HiddenCommentStore.STORE);
      store.putSync(HiddenCommentStore.KEY, list.join(','));
      await store.flush();
    } catch (err) {
      console.warn(`MuLiHidden save failed: ${String(err)}`);
    }
  }
}
