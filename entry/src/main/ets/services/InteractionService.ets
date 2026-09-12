import { BiliHttpClient } from './BiliHttpClient';
import { VideoComment } from './ReplyService';
import { WbiService } from './WbiService';


export interface VideoUserState {
  liked: boolean;
  disliked: boolean;
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
    const state: VideoUserState = { liked: false, disliked: false, coined: false, favored: false };
    if (aid <= 0 || cookie === '') return state;
    const query: Record<string, string> = {};
    query['aid'] = String(aid);
    const result: Record<string, Object> =
      await BiliHttpClient.getJson('/x/web-interface/archive/detail', query, cookie);
    if (Number(result['code'] ?? -1) !== 0) return state;
    const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
    const reqUser: Record<string, Object> = (data['req_user'] ?? {}) as Record<string, Object>;
    state.liked = Number(reqUser['like'] ?? 0) === 1;
    state.disliked = Number(reqUser['like'] ?? 0) === 2;
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

  static async rate(aid: number, value: number, cookie: string, csrf: string): Promise<void> {
    const result: Record<string, Object> = await BiliHttpClient.postForm('/x/web-interface/archive/like', {
      'aid': String(aid),
      'like': String(value),
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
    listQuery['up_mid'] = '0';
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

  static async addComment(aid: number, message: string, cookie: string, csrf: string,
    rootId: number = 0, parentId: number = 0): Promise<void> {
    const form: Record<string, string> = {
      'oid': String(aid),
      'type': '1',
      'plat': '1',
      'message': message,
      'csrf': csrf
    };
    if (rootId > 0) form['root'] = String(rootId);
    if (parentId > 0) form['parent'] = String(parentId);
    const result: Record<string, Object> = await BiliHttpClient.postForm('/x/v2/reply/add', form, cookie);
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

  // 消息快捷点赞：直接对 oid+rpid 点赞（消息中心无完整评论对象）
  static async likeReply(oid: number, rpid: number, on: boolean,
    cookie: string, csrf: string): Promise<void> {
    const result: Record<string, Object> = await BiliHttpClient.postForm('/x/v2/reply/action', {
      'oid': String(oid),
      'type': '1',
      'rpid': String(rpid),
      'action': on ? '1' : '0',
      'csrf': csrf
    }, cookie);
    InteractionService.ensureOk(result);
  }

  static async deleteComment(aid: number, rpid: number, cookie: string, csrf: string): Promise<void> {
    const result: Record<string, Object> = await BiliHttpClient.postForm('/x/v2/reply/del', {
      'oid': String(aid),
      'type': '1',
      'rpid': String(rpid),
      'csrf': csrf
    }, cookie);
    InteractionService.ensureOk(result);
  }

  static async blockUser(mid: number, cookie: string, csrf: string): Promise<void> {
    const result: Record<string, Object> = await BiliHttpClient.postForm('/x/relation/modify', {
      'fid': String(mid),
      'act': '5',
      're_src': '11',
      'csrf': csrf
    }, cookie);
    InteractionService.ensureOk(result);
  }

  /**
   * 用户创建的收藏夹列表（含当前视频是否已在夹内）。
   * 主路径用 /x/v3/fav/folder/created/list（WBI 签名，与我的收藏页一致，已验证可用），
   * favoured 标记尽力用 rid 接口合并；全部失败时回退 list-all 兜底链。
   */
  static async listFavFolders(aid: number, cookie: string, uid: string = '',
    upMid: number = 0): Promise<FavFolder[]> {
    let base: FavFolder[] = [];
    let baseFailed: Error | null = null;
    try {
      base = await InteractionService.listCreatedFoldersWbi(cookie, uid);
    } catch (wbiError) {
      baseFailed = wbiError as Error;
      console.warn(`Pilihos fav created/list(wbi) failed: ${String(wbiError)}`);
    }
    // rid 接口尽力合并 favoured 标记
    try {
      const ridFolders: FavFolder[] = await InteractionService.listFavFoldersWithRid(aid, cookie, upMid);
      const favouredIds: number[] = [];
      ridFolders.forEach((entry: FavFolder): void => {
        if (entry.favoured) favouredIds.push(entry.id);
      });
      if (base.length > 0) {
        base.forEach((entry: FavFolder): void => {
          entry.favoured = favouredIds.indexOf(entry.id) >= 0;
        });
        return base;
      }
      return ridFolders;
    } catch (ridError) {
      console.warn(`Pilihos fav rid merge failed: ${String(ridError)}`);
      if (base.length > 0) return base;
    }
    if (baseFailed !== null) {
      // 兜底：list-all 纯文件夹链
      return await InteractionService.listCreatedFolders(cookie, uid);
    }
    return base;
  }

  // WBI 签名的 created/list（我的收藏页同款，稳定可用）
  private static async listCreatedFoldersWbi(cookie: string, uid: string): Promise<FavFolder[]> {
    let mid: number = Number(uid);
    if (!(mid > 0)) {
      const navResult: Record<string, Object> =
        await BiliHttpClient.getJson('/x/web-interface/nav', {}, cookie);
      if (Number(navResult['code'] ?? -1) === 0) {
        const navData: Record<string, Object> = (navResult['data'] ?? {}) as Record<string, Object>;
        mid = Number(navData['mid'] ?? 0);
      }
    }
    const signedQuery: string = await WbiService.sign(
      [`up_mid=${mid}`, 'pn=1', 'ps=50', 'up_type=0']);
    const result: Record<string, Object> =
      await BiliHttpClient.getJsonQuery('/x/v3/fav/folder/created/list', signedQuery, cookie);
    const code: number = Number(result['code'] ?? -1);
    if (code !== 0) {
      throw new Error(`${code}: ${String(result['message'] ?? '收藏夹获取失败')}`);
    }
    const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
    const list: Object[] = (data['list'] as Object[]) ?? [];
    const folders: FavFolder[] = [];
    list.forEach((raw: Object): void => {
      const record: Record<string, Object> = raw as Record<string, Object>;
      const folder: FavFolder = new FavFolder();
      folder.id = Number(record['id'] ?? 0);
      folder.title = String(record['title'] ?? '');
      folder.mediaCount = Number(record['media_count'] ?? 0);
      folder.favoured = false;
      if (folder.id > 0) folders.push(folder);
    });
    return folders;
  }

  // 新建收藏夹：POST /x/v3/fav/folder/add
  static async createFavFolder(title: string, cookie: string, csrf: string): Promise<number> {
    const result: Record<string, Object> = await BiliHttpClient.postForm('/x/v3/fav/folder/add', {
      'title': title,
      'privacy': '0',
      'csrf': csrf
    }, cookie);
    InteractionService.ensureOk(result);
    const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
    return Number(data['folder_id'] ?? data['id'] ?? 0);
  }

  // 点赞动态：POST /x/polymer/web-dynamic/v1/like
  static async likeDynamic(dynId: string, cookie: string, csrf: string): Promise<void> {
    const result: Record<string, Object> = await BiliHttpClient.postForm(
      '/x/polymer/web-dynamic/v1/like', {
      'dyn_id': dynId,
      'up': '1',
      'csrf': csrf
    }, cookie);
    InteractionService.ensureOk(result);
  }

  // 删除收藏夹：POST /x/v3/fav/folder/del（media_ids 支持批量逗号分隔；默认收藏夹由服务端拒绝）
  static async deleteFavFolders(ids: number[], cookie: string, csrf: string): Promise<void> {
    if (ids.length === 0) return;
    const result: Record<string, Object> = await BiliHttpClient.postForm('/x/v3/fav/folder/del', {
      'media_ids': ids.join(','),
      'csrf': csrf
    }, cookie);
    InteractionService.ensureOk(result);
  }

  private static async listFavFoldersWithRid(aid: number, cookie: string,
    upMid: number): Promise<FavFolder[]> {
    const query: Record<string, string> = {};
    query['rid'] = String(aid);
    query['type'] = '2';
    query['up_mid'] = String(upMid);
    const listResult: Record<string, Object> = await BiliHttpClient.getJson(
      '/x/v3/fav/folder/created/list-all', query, cookie);
    if (Number(listResult['code'] ?? -1) !== 0) {
      throw new Error(String(listResult['message'] ?? '收藏夹获取失败'));
    }
    return InteractionService.parseFolders(listResult);
  }

  private static async listCreatedFolders(cookie: string, uid: string): Promise<FavFolder[]> {
    const query: Record<string, string> = {};
    query['up_mid'] = uid !== '' ? uid : '0';
    query['type'] = '2';
    const listResult: Record<string, Object> = await BiliHttpClient.getJson(
      '/x/v3/fav/folder/created/list-all', query, cookie);
    if (Number(listResult['code'] ?? -1) !== 0) {
      throw new Error(String(listResult['message'] ?? '收藏夹获取失败'));
    }
    return InteractionService.parseFolders(listResult);
  }

  private static parseFolders(listResult: Record<string, Object>): FavFolder[] {
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
    if (on) {
      form['add_media_ids'] = String(folderId);
    } else {
      form['del_media_ids'] = String(folderId);
    }
    const result: Record<string, Object> =
      await BiliHttpClient.postForm('/x/v3/fav/resource/deal', form, cookie);
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
