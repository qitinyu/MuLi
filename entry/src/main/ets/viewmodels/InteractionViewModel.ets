import { VideoItem } from '../models/VideoItem';
import { FavFolder, InteractionService } from '../services/InteractionService';
import { BiliHttpClient } from '../services/BiliHttpClient';
import { WbiService } from '../services/WbiService';
import { AuthService, AuthSession } from '../services/AuthService';
import { FollowState } from '../utils/FollowState';

export interface InteractionInitDeps {
  showToast: (msg: string) => void;
}

/**
 * 互动操作管理 ViewModel
 * 管理当前视频的互动状态（点赞、收藏、关注作者）、收藏夹操作、稍后再看、
 * 加载视频上下文信息（作者卡片、关注态、粉丝数、投稿数）
 */
export class InteractionViewModel {
  favSheetVisible: boolean = false;
  favFolders: FavFolder[] = [];
  followStamp: number = 0;
  playModeSheetVisible: boolean = false;

  private showToast: (msg: string) => void = (): void => {};

  init(deps: InteractionInitDeps): void {
    this.showToast = deps.showToast;
  }

  requireSession(authSession: AuthSession | null): AuthSession | null {
    if (authSession === null || authSession.cookie === '' || authSession.csrf === '') {
      this.showToast('请先登录后再互动');
      return null;
    }
    return authSession;
  }

  async toggleLike(item: VideoItem, authSession: AuthSession | null,
    onPatch: (patcher: (target: VideoItem) => void) => void): Promise<void> {
    const session: AuthSession | null = this.requireSession(authSession);
    if (session === null) return;
    if (item.aid <= 0) {
      this.showToast('视频信息加载中，请稍后');
      return;
    }
    const on: boolean = !(item.liked ?? false);
    onPatch((target: VideoItem): void => {
      target.liked = on;
      target.disliked = false;
      target.likeCount = Math.max(0, target.likeCount + (on ? 1 : -1));
    });
    try {
      await InteractionService.like(item.aid, on, session.cookie, session.csrf);
      this.showToast(on ? '已点赞' : '已取消点赞');
    } catch (error) {
      onPatch((target: VideoItem): void => {
        target.liked = !on;
        target.likeCount = Math.max(0, target.likeCount + (on ? -1 : 1));
      });
      this.showToast(`点赞失败: ${String(error)}`);
    }
  }

  async toggleDislike(item: VideoItem, authSession: AuthSession | null,
    onPatch: (patcher: (target: VideoItem) => void) => void): Promise<void> {
    const session: AuthSession | null = this.requireSession(authSession);
    if (session === null || item.aid <= 0) return;
    const on: boolean = !(item.disliked ?? false);
    onPatch((target: VideoItem): void => {
      target.disliked = on;
      if (on && target.liked) {
        target.liked = false;
        target.likeCount = Math.max(0, target.likeCount - 1);
      }
    });
    try {
      await InteractionService.like(item.aid, on ? false : true, session.cookie, session.csrf);
      this.showToast(on ? '已点踩' : '已取消点踩');
    } catch (error) {
      onPatch((target: VideoItem): void => { target.disliked = !on; });
      this.showToast(`点踩失败: ${String(error)}`);
    }
  }

  async toggleFavorite(item: VideoItem, authSession: AuthSession | null,
    onPatch: (patcher: (target: VideoItem) => void) => void): Promise<void> {
    const session: AuthSession | null = this.requireSession(authSession);
    if (session === null) return;
    if (item.aid <= 0) {
      this.showToast('视频信息加载中，请稍后');
      return;
    }
    const on: boolean = !(item.favored ?? false);
    try {
      await InteractionService.favorite(item.aid, on, session.cookie, session.csrf);
      onPatch((target: VideoItem): void => {
        target.favored = on;
      });
      this.showToast(on ? '已收藏到默认收藏夹' : '已取消收藏');
    } catch (error) {
      this.showToast(`收藏失败: ${String(error)}`);
    }
  }

  async addWatchLater(item: VideoItem, authSession: AuthSession | null): Promise<void> {
    const session: AuthSession | null = this.requireSession(authSession);
    if (session === null) return;
    if (item.aid <= 0) return;
    try {
      await InteractionService.watchLater(item.aid, session.cookie, session.csrf);
    } catch (error) {
      this.showToast(`加入再看失败: ${String(error)}`);
    }
  }

  async followAuthor(item: VideoItem, on: boolean, authSession: AuthSession | null,
    onPatch: (patcher: (target: VideoItem) => void) => void): Promise<void> {
    const session: AuthSession | null = this.requireSession(authSession);
    if (session === null) return;
    const mid: number = item.authorMid ?? 0;
    if (mid <= 0) return;
    try {
      await InteractionService.follow(mid, on, session.cookie, session.csrf, '11');
      FollowState.setFollowed(mid, item.author, on);
      this.followStamp += 1;
      onPatch((target: VideoItem): void => {
        target.authorFollowed = on;
      });
      this.showToast(on ? `已关注 ${item.author}` : '已取消关注');
    } catch (error) {
      this.showToast(`关注操作失败: ${String(error)}`);
    }
  }

  async openFavSheet(item: VideoItem, authSession: AuthSession | null): Promise<void> {
    const session: AuthSession | null = this.requireSession(authSession);
    if (session === null) return;
    if (item.aid <= 0) return;
    this.favFolders = [];
    this.favSheetVisible = true;
    try {
      const folders: FavFolder[] = await InteractionService.listFavFolders(item.aid, session.cookie);
      this.favFolders = folders;
    } catch (error) {
      this.showToast(`收藏夹获取失败: ${String(error)}`);
    }
  }

  async toggleFavFolder(item: VideoItem, folder: FavFolder, authSession: AuthSession | null,
    onPatch: (patcher: (target: VideoItem) => void) => void): Promise<void> {
    const session: AuthSession | null = this.requireSession(authSession);
    if (session === null) return;
    if (item.aid <= 0) return;
    const on: boolean = !folder.favoured;
    try {
      await InteractionService.addToFolder(item.aid, folder.id, on, session.cookie, session.csrf);
      folder.favoured = on;
      this.favFolders = this.favFolders.slice(0);
      onPatch((target: VideoItem): void => {
        target.favored = this.favFolders.some((entry: FavFolder): boolean => entry.favoured);
      });
      this.showToast(on ? `已收藏到「${folder.title}」` : `已从「${folder.title}」移除`);
    } catch (error) {
      this.showToast(`收藏操作失败: ${String(error)}`);
    }
  }

  /**
   * 加载互动状态回显 + 作者卡片信息
   */
  async loadVideoContext(item: VideoItem, authSession: AuthSession | null,
    onPatch: (patcher: (target: VideoItem) => void) => void): Promise<void> {
    if (item.placeholder) return;
    // 互动状态回显
    if (authSession !== null && authSession.cookie !== '' && item.aid > 0) {
      try {
        const state = await InteractionService.fetchVideoState(item.aid, authSession.cookie);
        onPatch((target: VideoItem): void => {
          target.liked = state.liked;
          target.coined = state.coined;
          target.favored = state.favored;
        });
      } catch (stateError) {
        console.warn(`Pilihos video user state failed: ${String(stateError)}`);
      }
    }
    // 作者关注态 + 粉丝数 + 投稿数
    const authorMid: number = item.authorMid ?? 0;
    if (authorMid > 0) {
      try {
        const cardQuery: Record<string, string> = {};
        cardQuery['mid'] = String(authorMid);
        const cardResult: Record<string, Object> =
          await BiliHttpClient.getJson('/x/web-interface/card', cardQuery,
            authSession !== null ? authSession.cookie : '');
        if (Number(cardResult['code'] ?? -1) === 0) {
          const cardData: Record<string, Object> = (cardResult['data'] ?? {}) as Record<string, Object>;
          const fans: number = Number(cardData['follower'] ?? 0);
          const cardInfo: Record<string, Object> = (cardData['card'] ?? {}) as Record<string, Object>;
          const levelInfo: Record<string, Object> = (cardInfo['level_info'] ?? {}) as Record<string, Object>;
          const level: number = Number(levelInfo['current_level'] ?? 0);
          onPatch((target: VideoItem): void => {
            target.authorFans = fans;
            target.authorLevel = level;
          });
        }
      } catch (cardError) {
        console.warn(`Pilihos author card failed: ${String(cardError)}`);
      }
    }
    if (authSession !== null && authSession.cookie !== '' && authorMid > 0) {
      try {
        const attribute: number = await InteractionService.relationAttribute(authorMid, authSession.cookie);
        const followed: boolean = attribute === 2 || attribute === 6 || attribute === 128;
        onPatch((target: VideoItem): void => {
          target.authorFollowed = followed;
        });
      } catch (relationError) {
        const fallbackFollowed: boolean = FollowState.isFollowed(authorMid, item.author);
        onPatch((target: VideoItem): void => {
          target.authorFollowed = fallbackFollowed;
        });
      }
      if ((item.authorVideos ?? 0) <= 0) {
        try {
          const arcSigned: string = await WbiService.sign([
            `mid=${authorMid}`, 'pn=1', 'ps=1', 'order=pubdate'
          ]);
          const arcResult: Record<string, Object> =
            await BiliHttpClient.getJsonQuery('/x/space/wbi/arc/search', arcSigned, authSession.cookie);
          if (Number(arcResult['code'] ?? -1) === 0) {
            const arcData: Record<string, Object> = (arcResult['data'] ?? {}) as Record<string, Object>;
            const arcPage: Record<string, Object> = (arcData['page'] ?? {}) as Record<string, Object>;
            const count: number = Number(arcPage['count'] ?? 0);
            onPatch((target: VideoItem): void => {
              target.authorVideos = count;
            });
          }
        } catch (arcError) {
          console.warn(`Pilihos author arc count failed: ${String(arcError)}`);
        }
      }
    } else if (authorMid > 0 || item.author !== '') {
      const followed: boolean = FollowState.isFollowed(authorMid, item.author);
      onPatch((target: VideoItem): void => {
        target.authorFollowed = followed;
      });
    }
  }
}
