import { VideoItem } from '../models/VideoItem';
import { VideoComment, ReplyService, CommentBatch } from '../services/ReplyService';
import { AuthService, AuthSession } from '../services/AuthService';
import { InteractionService } from '../services/InteractionService';
import { VideoDetailService } from '../services/VideoDetailService';

export interface CommentInitDeps {
  showToast: (msg: string) => void;
}

/**
 * 评论状态管理 ViewModel
 * 管理视频评论列表的加载、分页、展开/收起子评论、发布评论、评论点赞
 */
export class CommentViewModel {
  comments: VideoComment[] = [];
  expandedCommentId: number = -1;
  subReplies: VideoComment[] = [];
  subLoading: boolean = false;
  subHasMore: boolean = false;
  showCommentInput: boolean = false;
  commentInputText: string = '';
  commentLoading: boolean = false;
  commentError: string = '';
  commentTotal: number = 0;
  commentHasMore: boolean = false;

  private commentPage: number = 1;
  private subPage: number = 1;
  private showToast: (msg: string) => void = (): void => {};

  init(deps: CommentInitDeps): void {
    this.showToast = deps.showToast;
  }

  async loadComments(currentVideo: VideoItem, authSession: AuthSession | null,
    refresh: boolean = true): Promise<void> {
    if (this.commentLoading) return;
    this.commentLoading = true;
    this.commentError = '';
    const nextPage: number = refresh ? 1 : this.commentPage + 1;
    try {
      let detailed: VideoItem = currentVideo;
      if (currentVideo.aid <= 0) {
        detailed = await VideoDetailService.load(currentVideo);
      }
      const cookie: string = authSession === null ? '' : authSession.cookie;
      const batch: CommentBatch = await ReplyService.loadVideoComments(detailed, cookie, nextPage);
      this.comments = refresh ? batch.items : this.comments.concat(batch.items);
      this.commentPage = nextPage;
      this.commentTotal = batch.total;
      this.commentHasMore = batch.hasMore;
    } catch (error) {
      this.commentError = '评论加载失败，请稍后重试';
      console.error('Pilihos comments failed: ' + String(error));
    } finally {
      this.commentLoading = false;
    }
  }

  toggleSubReplies(comment: VideoComment): void {
    if (this.expandedCommentId === comment.id) {
      this.expandedCommentId = -1;
      this.subReplies = [];
      this.subHasMore = false;
      return;
    }
    this.expandedCommentId = comment.id;
    this.loadSubReplies(comment.id, null, true);
  }

  async loadSubReplies(rootId: number, authSession: AuthSession | null,
    refresh: boolean = true): Promise<void> {
    if (this.subLoading) return;
    this.subLoading = true;
    const nextPage: number = refresh ? 1 : this.subPage + 1;
    try {
      const cookie: string = authSession === null ? '' : authSession.cookie;
      const batch: CommentBatch = await ReplyService.loadSubReplies(
        0, rootId, cookie, nextPage);
      this.subReplies = refresh ? batch.items : this.subReplies.concat(batch.items);
      this.subPage = nextPage;
      this.subHasMore = batch.hasMore;
    } catch (error) {
      this.showToast('回复加载失败，请稍后重试');
      console.error(`Pilihos sub replies failed: ${String(error)}`);
    } finally {
      this.subLoading = false;
    }
  }

  async submitComment(currentVideo: VideoItem, authSession: AuthSession | null): Promise<boolean> {
    const message: string = this.commentInputText.trim();
    if (message === '') {
      this.showToast('先说点什么吧');
      return false;
    }
    if (authSession === null || authSession.cookie === '' || authSession.csrf === '') {
      this.showToast('请先登录后再互动');
      return false;
    }
    if (currentVideo.aid <= 0) {
      this.showToast('视频信息加载中，请稍后');
      return false;
    }
    try {
      await InteractionService.addComment(currentVideo.aid, message,
        authSession.cookie, authSession.csrf);
      this.commentInputText = '';
      this.showCommentInput = false;
      this.showToast('评论发布成功');
      return true;
    } catch (error) {
      this.showToast(`评论发布失败: ${String(error)}`);
      return false;
    }
  }

  async toggleCommentLike(comment: VideoComment, aid: number,
    authSession: AuthSession | null): Promise<void> {
    if (authSession === null || authSession.cookie === '' || authSession.csrf === '') {
      this.showToast('请先登录后再互动');
      return;
    }
    if (aid <= 0) return;
    const on: boolean = !comment.liked;
    try {
      await InteractionService.likeComment(comment, aid, on,
        authSession.cookie, authSession.csrf);
      comment.liked = on;
      comment.likeCount = Math.max(0, comment.likeCount + (on ? 1 : -1));
      this.comments = this.comments.slice(0);
    } catch (error) {
      this.showToast(`点赞失败: ${String(error)}`);
    }
  }

  reset(): void {
    this.comments = [];
    this.expandedCommentId = -1;
    this.subReplies = [];
    this.subHasMore = false;
    this.showCommentInput = false;
    this.commentInputText = '';
    this.commentLoading = false;
    this.commentError = '';
    this.commentTotal = 0;
    this.commentHasMore = false;
    this.commentPage = 1;
    this.subPage = 1;
  }
}
