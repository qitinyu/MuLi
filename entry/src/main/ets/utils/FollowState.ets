import { BiliHttpClient } from '../services/BiliHttpClient';

/**
 * 关注状态缓存：登录后拉取关注列表（mid+昵称），
 * 供推荐/热门/搜索卡片"已关注"标志与详情页关注按钮回显；
 * 优先按 mid 匹配，feed 数据缺 mid 时按昵称兜底。
 */
export class FollowState {
  private static midSet: Set<number> = new Set<number>();
  private static nameSet: Set<string> = new Set<string>();

  static async refresh(cookie: string): Promise<void> {
    if (cookie === '') return;
    for (let page: number = 1; page <= 4; page++) {
      try {
        const query: Record<string, string> = {};
        query['vmid'] = 'self';
        query['ps'] = '50';
        query['pn'] = String(page);
        const result: Record<string, Object> =
          await BiliHttpClient.getJson('/x/relation/followings', query, cookie);
        if (Number(result['code'] ?? -1) !== 0) return;
        const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
        const list: Object[] = (data['list'] as Object[]) ?? [];
        if (list.length === 0) return;
        list.forEach((raw: Object): void => {
          const record: Record<string, Object> = raw as Record<string, Object>;
          const mid: number = Number(record['mid'] ?? 0);
          const name: string = String(record['uname'] ?? record['name'] ?? '');
          if (mid > 0) FollowState.midSet.add(mid);
          if (name !== '') FollowState.nameSet.add(name);
        });
        const total: number = Number(data['total'] ?? 0);
        if (page * 50 >= total) return;
      } catch (error) {
        console.warn(`Pilihos follow state refresh failed: ${String(error)}`);
        return;
      }
    }
  }

  static isFollowed(mid: number, name: string): boolean {
    if (mid > 0 && FollowState.midSet.has(mid)) return true;
    return name !== '' && FollowState.nameSet.has(name);
  }

  static setFollowed(mid: number, name: string, on: boolean): void {
    if (on) {
      if (mid > 0) FollowState.midSet.add(mid);
      if (name !== '') FollowState.nameSet.add(name);
    } else {
      if (mid > 0) FollowState.midSet.delete(mid);
      FollowState.nameSet.delete(name);
    }
  }
}
