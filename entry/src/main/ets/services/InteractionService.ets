import { BiliHttpClient } from './BiliHttpClient';
import { VideoComment } from './ReplyService';

export interface VideoUserState {
  liked: boolean;
  coined: boolean;
  favored: boolean;
}

export class FavFolder {
  id: number = 0;
  title: string = '';
  mediaCount: number = 0;
  favoured: boolean = false;
}

/**
 * 互动接口封装：点赞/投币/收藏/再看、评论发布与评论点赞（web 端，cookie+csrf）。
 */
export class InteractionService {
  static async fetchVideoState(aid: number, cookie: string): Promise<VideoUserState> {
    const state: VideoUserState = { liked: false, coined: false, favored: false };
    if (aid <= 0 || cookie === '') return state;
    const query: Record<string, string> = {};
    query['aid'] = String(aid);
    const result: Record<string, Object> =
      await BiliHttpClient.getJson('/x/web-interface/archive/detail', query, cookie);
    if (Number(result['code'] ?? -1) !== 0) return state;
    const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
    const reqUser: Record<string, Object> = (data['req_user'] ?? {}) as Record<string, Object>;
    state.liked = Number(reqUser['like'] ?? 0) === 1;
    state.coined = Number(reqUser['coin'] ?? 0) > 0;
    state.favored = Number(reqUser['favorite'] ?? 0) === 1;
    return state;
  }

  static async like(aid: number, on: boolean, cookie: string, csrf: string): Promise<void> {
    const result: Record<string, Object> = await BiliHttpClient.postForm('/x/web-interface/archive/like', {
      'aid': String(aid),
      'like': on ? '1' : '2',
      'csrf': csrf
    }, cookie);
    InteractionService.ensureOk(result);
  }

  static async coin(aid: number, multiply: number, alsoLike: boolean, cookie: string, csrf: string): Promise<void> {
    const result: Record<string, Object> = await BiliHttpClient.postForm('/x/web-interface/coin/add', {
      'aid': String(aid),
      'multiply': String(multiply),
      'select_like': alsoLike ? '1' : '0',
      'csrf': csrf
    }, cookie);
    InteractionService.ensureOk(result);
  }

  static async watchLater(aid: number, cookie: string, csrf: string): Promise<void> {
    const result: Record<string, Object> = await BiliHttpClient.postForm('/x/v2/history/toview/add', {
      'aid': String(aid),
      'csrf': csrf
    }, cookie);
    InteractionService.ensureOk(result);
  }

  static async favorite(aid: number, on: boolean, cookie: string, csrf: string): Promise<void> {
    // 默认收藏夹 id（第一个创建的夹子）
    const listQuery: Record<string, string> = {};
    listQuery['rid'] = String(aid);
    listQuery['type'] = '2';
    const listResult: Record<string, Object> = await BiliHttpClient.getJson(
      '/x/v3/fav/folder/created/list-all', listQuery, cookie);
    if (Number(listResult['code'] ?? -1) !== 0) {
      throw new Error(String(listResult['message'] ?? '收藏夹获取失败'));
    }
    const data: Record<string, Object> = (listResult['data'] ?? {}) as Record<string, Object>;
    const list: Object[] = (data['list'] as Object[]) ?? [];
    if (list.length === 0) throw new Error('未找到收藏夹');
    const first: Record<string, Object> = list[0] as Record<string, Object>;
    const folderId: number = Number(first['id'] ?? 0);
    if (folderId <= 0) throw new Error('收藏夹信息异常');
    await InteractionService.addToFolder(aid, folderId, on, cookie, csrf);
  }

  static async addComment(aid: number, message: string, cookie: string, csrf: string): Promise<void> {
    const result: Record<string, Object> = await BiliHttpClient.postForm('/x/v2/reply/add', {
      'oid': String(aid),
      'type': '1',
      'plat': '1',
      'message': message,
      'csrf': csrf
    }, cookie);
    InteractionService.ensureOk(result);
  }

  static async likeComment(comment: VideoComment, aid: number, on: boolean,
    cookie: string, csrf: string): Promise<void> {
    const result: Record<string, Object> = await BiliHttpClient.postForm('/x/v2/reply/action', {
      'oid': String(aid),
      'type': '1',
      'rpid': String(comment.id),
      'action': on ? '1' : '0',
      'csrf': csrf
    }, cookie);
    InteractionService.ensureOk(result);
  }

  /**
   * 用户创建的收藏夹列表（含当前视频是否已在夹内）
   */
  static async listFavFolders(aid: number, cookie: string): Promise<FavFolder[]> {
    const query: Record<string, string> = {};
    query['rid'] = String(aid);
    query['type'] = '2';
    const listResult: Record<string, Object> = await BiliHttpClient.getJson(
      '/x/v3/fav/folder/created/list-all', query, cookie);
    if (Number(listResult['code'] ?? -1) !== 0) {
      throw new Error(String(listResult['message'] ?? '收藏夹获取失败'));
    }
    const data: Record<string, Object> = (listResult['data'] ?? {}) as Record<string, Object>;
    const list: Object[] = (data['list'] as Object[]) ?? [];
    const folders: FavFolder[] = [];
    list.forEach((raw: Object): void => {
      const record: Record<string, Object> = raw as Record<string, Object>;
      const folder: FavFolder = new FavFolder();
      folder.id = Number(record['id'] ?? 0);
      folder.title = String(record['title'] ?? '');
      folder.mediaCount = Number(record['media_count'] ?? 0);
      folder.favoured = Number(record['favoured'] ?? 0) === 1;
      if (folder.id > 0) folders.push(folder);
    });
    return folders;
  }

  static async addToFolder(aid: number, folderId: number, on: boolean,
    cookie: string, csrf: string): Promise<void> {
    const form: Record<string, string> = {};
    form['rid'] = String(aid);
    form['type'] = '2';
    form['csrf'] = csrf;
    form['csrf_token'] = csrf;
    if (on) {
      form['add_media_ids'] = String(folderId);
    } else {
      form['del_media_ids'] = String(folderId);
    }
    const result: Record<string, Object> =
      await BiliHttpClient.postForm('/x/api/v3/fav/resource/deal', form, cookie);
    InteractionService.ensureOk(result);
  }

  /**
   * 关注/取关（UP主或主播通用）：act 1=关注 2=取关
   */
  static async follow(mid: number, on: boolean, cookie: string, csrf: string,
    reSrc: string = '11'): Promise<void> {
    const result: Record<string, Object> = await BiliHttpClient.postForm('/x/relation/modify', {
      'fid': String(mid),
      'act': on ? '1' : '2',
      're_src': reSrc,
      'csrf': csrf
    }, cookie);
    InteractionService.ensureOk(result);
  }

  static async relationAttribute(mid: number, cookie: string): Promise<number> {
    if (mid <= 0 || cookie === '') return -1;
    const query: Record<string, string> = {};
    query['fid'] = String(mid);
    const result: Record<string, Object> = await BiliHttpClient.getJson('/x/relation', query, cookie);
    if (Number(result['code'] ?? -1) !== 0) return -1;
    const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
    return Number(data['attribute'] ?? 0);
  }

  private static ensureOk(result: Record<string, Object>): void {
    const code: number = Number(result['code'] ?? -1);
    if (code !== 0) {
      throw new Error(`${code}: ${String(result['message'] ?? '操作失败')}`);
    }
  }
}
