import { VideoItem } from '../models/VideoItem';
import { BiliHttpClient } from './BiliHttpClient';

export class VideoComment {
  id: number = 0;
  mid: number = 0;
  userName: string = '';
  avatar: string = '';
  message: string = '';
  level: number = 0;
  likeCount: number = 0;
  replyCount: number = 0;
  publishTime: number = 0;
  isUp: boolean = false;
  // 楼中楼间接回复（回复的不是楼主而是楼层内他人）：被回复人昵称，展示为"@某人"
  replyToName: string = '';
  // 评论正文里被 @ 的用户：昵称 → mid（点击跳转个人主页用）
  ats: Map<string, number> = new Map<string, number>();
  liked: boolean = false;
  // 评论接口会返回当前评论实际使用的表情映射，优先用它渲染，
  // 不能只依赖用户表情面板（否则未收藏的表情会退化成文字）。
  emotes: Map<string, string> = new Map<string, string>();
}

export interface CommentBatch {
  items: VideoComment[];
  total: number;
  hasMore: boolean;
}

export class ReplyService {
  static async loadVideoComments(item: VideoItem, cookie: string = '', page: number = 1,
    sort: string = '0'): Promise<CommentBatch> {
    if (item.aid <= 0) throw new Error('视频 aid 缺失，无法获取评论');
    const query: Record<string, string> = {};
    query['oid'] = String(item.aid);
    query['type'] = '1';
    query['sort'] = sort;
    query['pn'] = String(page);
    query['ps'] = '20';
    query['web_location'] = '333.1365';
    const result: Record<string, Object> = await BiliHttpClient.getJson('/x/v2/reply', query, cookie);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '评论加载失败'));
    }
    const data: Record<string, Object> = (result['data'] as Record<string, Object>) ?? {};
    const upper: Record<string, Object> = (data['upper'] ?? {}) as Record<string, Object>;
    const upperMid: number = Number(upper['mid'] ?? 0);
    const rawReplies: Object[] = (data['replies'] as Object[]) ?? [];
    const items: VideoComment[] = [];
    rawReplies.forEach((raw: Object): void => {
      const comment: VideoComment | null = ReplyService.parseReply(raw, upperMid);
      if (comment !== null && comment.message !== '') items.push(comment);
    });
    const pageInfo: Record<string, Object> = (data['page'] as Record<string, Object>) ?? {};
    const total: number = Number(pageInfo['count'] ?? item.commentCount);
    return { items: items, total: total, hasMore: page * 20 < total };
  }

  static async loadSubReplies(aid: number, rootId: number, cookie: string = '',
    page: number = 1): Promise<CommentBatch> {
    const query: Record<string, string> = {};
    query['oid'] = String(aid);
    query['type'] = '1';
    query['root'] = String(rootId);
    query['pn'] = String(page);
    query['ps'] = '10';
    const result: Record<string, Object> = await BiliHttpClient.getJson('/x/v2/reply/reply', query, cookie);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '回复加载失败'));
    }
    const data: Record<string, Object> = (result['data'] as Record<string, Object>) ?? {};
    const upper: Record<string, Object> = (data['upper'] ?? {}) as Record<string, Object>;
    const upperMid: number = Number(upper['mid'] ?? 0);
    const rawReplies: Object[] = (data['replies'] as Object[]) ?? [];
    const items: VideoComment[] = [];
    rawReplies.forEach((raw: Object): void => {
      const comment: VideoComment | null = ReplyService.parseReply(raw, upperMid);
      if (comment !== null && comment.message !== '') items.push(comment);
    });
    const pageInfo: Record<string, Object> = (data['page'] as Record<string, Object>) ?? {};
    const total: number = Number(pageInfo['count'] ?? 0);
    return { items: items, total: total, hasMore: page * 10 < total };
  }

  private static parseReply(raw: Object, upperMid: number): VideoComment | null {
    const reply: Record<string, Object> = raw as Record<string, Object>;
    const member: Record<string, Object> = (reply['member'] as Record<string, Object>) ?? {};
    const content: Record<string, Object> = (reply['content'] as Record<string, Object>) ?? {};
    const levelInfo: Record<string, Object> = (member['level_info'] ?? {}) as Record<string, Object>;
    const comment: VideoComment = new VideoComment();
    comment.id = Number(reply['rpid'] ?? 0);
    comment.mid = Number(reply['mid'] ?? 0);
    comment.userName = String(member['uname'] ?? '用户');
    comment.avatar = String(member['avatar'] ?? '');
    comment.message = String(content['message'] ?? '');
    comment.level = Number(levelInfo['current_level'] ?? 0);
    comment.likeCount = Number(reply['like'] ?? 0);
    comment.replyCount = Number(reply['rcount'] ?? 0);
    comment.publishTime = Number(reply['ctime'] ?? 0);
    comment.isUp = upperMid > 0 && Number(reply['mid'] ?? 0) === upperMid;
    // 楼中楼间接回复携带 parent（被回复的那条）：取其昵称用于"A 回复 @B"展示
    const parentObj: Object | undefined = reply['parent'];
    if (parentObj !== undefined && parentObj !== null) {
      const parent: Record<string, Object> = parentObj as Record<string, Object>;
      const parentMember: Record<string, Object> = (parent['member'] ?? {}) as Record<string, Object>;
      comment.replyToName = String(parentMember['uname'] ?? '');
    }
    // content.members 是正文中 @ 到的用户（按出现顺序），建立昵称→mid 映射
    const members: Object | undefined = content['members'];
    if (members !== undefined && members !== null && Array.isArray(members)) {
      ((members as Object[])).forEach((memberRaw: Object): void => {
        const member: Record<string, Object> = memberRaw as Record<string, Object>;
        const atName: string = String(member['uname'] ?? '');
        const atMid: number = Number(member['mid'] ?? 0);
        if (atName !== '' && atMid > 0 && !comment.ats.has(atName)) {
          comment.ats.set(atName, atMid);
        }
      });
    }
    // action: 0 未点赞 / 1 已点赞（需携带登录 cookie）
    comment.liked = Number(reply['action'] ?? 0) === 1;
    const rawEmotes: Record<string, Object> =
      (content['emote'] as Record<string, Object>) ??
      (content['emotes'] as Record<string, Object>) ??
      {};
    Object.keys(rawEmotes).forEach((key: string): void => {
      const value: Record<string, Object> = (rawEmotes[key] as Record<string, Object>) ?? {};
      const url: string = String(value['url'] ?? value['gif_url'] ?? '');
      if (url === '') return;
      comment.emotes.set(key, url);
      if (key.startsWith('[') && key.endsWith(']') && key.length > 2) {
        comment.emotes.set(key.substring(1, key.length - 1), url);
      }
    });
    return comment;
  }
}
