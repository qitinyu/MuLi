import { VideoItem } from '../models/VideoItem';
import { BiliHttpClient } from './BiliHttpClient';

export class VideoComment {
  id: number = 0;
  userName: string = '';
  avatar: string = '';
  message: string = '';
  likeCount: number = 0;
  replyCount: number = 0;
  publishTime: number = 0;
  isUp: boolean = false;
}

export interface CommentBatch {
  items: VideoComment[];
  total: number;
  hasMore: boolean;
}

export class ReplyService {
  static async loadVideoComments(item: VideoItem, cookie: string = '', page: number = 1): Promise<CommentBatch> {
    if (item.aid <= 0) throw new Error('视频 aid 缺失，无法获取评论');
    const query: Record<string, string> = {};
    query['oid'] = String(item.aid);
    query['type'] = '1';
    query['sort'] = '2';
    query['pn'] = String(page);
    query['ps'] = '20';
    query['web_location'] = '333.1365';
    const result: Record<string, Object> = await BiliHttpClient.getJson('/x/v2/reply', query, cookie);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '评论加载失败'));
    }
    const data: Record<string, Object> = (result['data'] as Record<string, Object>) ?? {};
    const rawReplies: Object[] = (data['replies'] as Object[]) ?? [];
    const items: VideoComment[] = [];
    rawReplies.forEach((raw: Object): void => {
      const reply: Record<string, Object> = raw as Record<string, Object>;
      const member: Record<string, Object> = (reply['member'] as Record<string, Object>) ?? {};
      const content: Record<string, Object> = (reply['content'] as Record<string, Object>) ?? {};
      const comment: VideoComment = new VideoComment();
      comment.id = Number(reply['rpid'] ?? 0);
      comment.userName = String(member['uname'] ?? '用户');
      comment.avatar = String(member['avatar'] ?? '');
      comment.message = String(content['message'] ?? '');
      comment.likeCount = Number(reply['like'] ?? 0);
      comment.replyCount = Number(reply['rcount'] ?? 0);
      comment.publishTime = Number(reply['ctime'] ?? 0);
      comment.isUp = Boolean(reply['up_action'] ?? false);
      if (comment.message !== '') items.push(comment);
    });
    const pageInfo: Record<string, Object> = (data['page'] as Record<string, Object>) ?? {};
    const total: number = Number(pageInfo['count'] ?? item.commentCount);
    return { items: items, total: total, hasMore: page * 20 < total };
  }
}
