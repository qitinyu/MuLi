import { BiliHttpClient } from './BiliHttpClient';

export class BiliMessageItem {
  id: number = 0;
  userName: string = '';
  avatar: string = '';
  actionText: string = '';
  content: string = '';
  source: string = '';
  timeText: string = '';
  oid: number = 0;
  bvid: string = '';
  mid: number = 0;
  counts: number = 0;
  rootId: number = 0;
}

export class BiliMessageUnread {
  at: number = 0;
  like: number = 0;
  reply: number = 0;
  sysMsg: number = 0;
}

export class ImUser {
  uid: number = 0;
  name: string = '';
  face: string = '';
}

// @提及联系人（mention/search）：最近联系与搜索结果
export class MentionContact {
  uid: number = 0;
  name: string = '';
  face: string = '';
  fans: number = 0;
  group: string = '';
}

export class MessageService {
  // kind: reply / at / like —— 三通道 item 结构不同，分通道解析
  private static async load(path: string, kind: string, cookie: string): Promise<BiliMessageItem[]> {
    const query: Record<string, string> = {};
    query['platform'] = 'web';
    query['build'] = '0';
    query['mobi_app'] = 'web';
    query['web_location'] = '333.40164';
    const result: Record<string, Object> = await BiliHttpClient.getJson(path, query, cookie);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '消息加载失败'));
    }
    const data: Record<string, Object> = (result['data'] as Record<string, Object>) ?? {};
    const raw: Object[] = ((data['items'] ?? []) as Object[]);
    const list: BiliMessageItem[] = [];
    const emptyObj: Record<string, Object> = {};
    raw.forEach((value: Object): void => {
      try {
        const row: Record<string, Object> = value as Record<string, Object>;
        // user 字段：reply/at/like 为 user 或 users[0]（mid/nickname/avatar），兼容旧键名
        let user: Record<string, Object> = emptyObj;
        const userRaw: Object | undefined = row['user'];
        if (userRaw !== undefined && userRaw !== null) {
          user = userRaw as Record<string, Object>;
        } else {
          const users: Object | undefined = row['users'];
          if (users !== undefined && users !== null && Array.isArray(users) &&
            (users as Object[]).length > 0) {
            user = (users as Object[])[0] as Record<string, Object>;
          } else if (row['sender'] !== undefined && row['sender'] !== null) {
            user = row['sender'] as Record<string, Object>;
          }
        }
        const nested: Record<string, Object> =
          ((row['item'] ?? emptyObj) as Record<string, Object>) ?? emptyObj;
        const item: BiliMessageItem = new BiliMessageItem();
        item.id = Number(row['id'] ?? row['id_str'] ?? row['msg_id'] ?? 0);
        item.mid = Number(user['mid'] ?? row['mid'] ?? 0);
        item.userName = String(user['nickname'] ?? user['uname'] ?? row['uname'] ?? '用户');
        item.avatar = String(user['avatar'] ?? user['face'] ?? row['face'] ?? '');
        item.counts = Number(row['counts'] ?? 0);

        if (kind === 'like') {
          // 点赞流：item = { business/title/image/native_uri }
          const business: string = String(nested['business'] ?? '');
          item.actionText = business === 'reply' ? '赞了我的评论'
            : business === 'dynamic' ? '赞了我的动态' : '赞了我的视频';
          item.content = String(nested['title'] ?? '');
          item.oid = Number(nested['pid'] ?? nested['subject_id'] ?? nested['business_id'] ?? 0);
          const likeTime: number = Number(row['like_time'] ?? 0);
          item.timeText = likeTime > 0 ? MessageService.formatDay(likeTime) : '';
        } else {
          // 回复/@我 流：item = { subject_id/source_content/target_reply_content/reply_time }
          item.actionText = kind === 'reply' ? '回复了我的评论' : '在评论或动态中提到了我';
          item.content = String(nested['target_reply_content'] ?? '');
          item.source = String(nested['source_content'] ?? '');
          item.oid = Number(nested['subject_id'] ?? nested['business_id'] ?? 0);
          item.bvid = String(nested['bvid'] ?? '');
          // 根评论 id：跳转后自动展开该楼层的折叠回复
          item.rootId = Number(nested['root_id'] ?? 0);
          const replyTime: number = Number(row['reply_time'] ?? row['at_time'] ??
            nested['reply_time'] ?? 0);
          item.timeText = replyTime > 0 ? MessageService.formatDay(replyTime) : '';
        }
        if (item.userName === '' && item.content === '') return;
        list.push(item);
      } catch (rowError) {
        // 单条解析失败跳过，不拖垮整个通道
        console.warn(`Pilihos message row parse failed: ${String(rowError)}`);
      }
    });
    return list;
  }

  // 消息行时间：具体日期 MM/DD
  private static formatDay(timestamp: number): string {
    const seconds: number = timestamp > 100000000000 ? Math.floor(timestamp / 1000) : timestamp;
    const date: Date = new Date(seconds * 1000);
    const month: string = String(date.getMonth() + 1).padStart(2, '0');
    const day: string = String(date.getDate()).padStart(2, '0');
    return `${month}/${day}`;
  }

  // 会话列表本身不携带对方资料，需按 uids 批量拉取 im 用户信息
  static async loadImUserInfos(uids: string, cookie: string, csrf: string): Promise<Map<number, ImUser>> {
    const result: Map<number, ImUser> = new Map<number, ImUser>();
    if (uids === '') return result;
    const query: Record<string, string> = {};
    query['uids'] = uids;
    query['build'] = '0';
    query['mobi_app'] = 'web';
    query['web_location'] = '333.40164';
    query['csrf_token'] = csrf;
    query['csrf'] = csrf;
    const resultJson: Record<string, Object> = await BiliHttpClient.getJsonHost(
      'api.vc.bilibili.com', '/x/im/user_infos', query, cookie);
    if (Number(resultJson['code'] ?? -1) !== 0) {
      throw new Error(String(resultJson['message'] ?? '用户信息加载失败'));
    }
    const data: Object | undefined = resultJson['data'];
    let raw: Object[] = [];
    if (data !== undefined && data !== null && Array.isArray(data)) {
      raw = data as Object[];
    } else if (data !== undefined && data !== null) {
      const wrapper: Record<string, Object> = data as Record<string, Object>;
      raw = ((wrapper['users'] ?? []) as Object[]);
    }
    raw.forEach((value: Object): void => {
      const row: Record<string, Object> = value as Record<string, Object>;
      const user: ImUser = new ImUser();
      user.uid = Number(row['uid'] ?? row['mid'] ?? 0);
      user.name = String(row['name'] ?? '');
      user.face = String(row['face'] ?? '');
      if (user.uid > 0) {
        result.set(user.uid, user);
      }
    });
    return result;
  }

  static loadReplies(cookie: string): Promise<BiliMessageItem[]> {
    return MessageService.load('/x/msgfeed/reply', 'reply', cookie);
  }

  // @提及联系人：/x/polymer/web-dynamic/v1/mention/search（groups 内 items 展平，标注分组名）
  static async loadMentionContacts(keyword: string, cookie: string): Promise<MentionContact[]> {
    const query: Record<string, string> = {};
    if (keyword !== '') {
      query['keyword'] = keyword;
    }
    query['web_location'] = '333.1365';
    const result: Record<string, Object> =
      await BiliHttpClient.getJson('/x/polymer/web-dynamic/v1/mention/search', query, cookie);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '联系人加载失败'));
    }
    const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
    const groups: Object[] = ((data['groups'] ?? []) as Object[]);
    const contacts: MentionContact[] = [];
    const emptyObj: Record<string, Object> = {};
    groups.forEach((groupRaw: Object): void => {
      const group: Record<string, Object> = groupRaw as Record<string, Object>;
      const groupName: string = String(group['group_name'] ?? '');
      const items: Object[] = ((group['items'] ?? []) as Object[]);
      items.forEach((itemRaw: Object): void => {
        const row: Record<string, Object> = itemRaw as Record<string, Object>;
        const contact: MentionContact = new MentionContact();
        contact.uid = Number(row['uid'] ?? 0);
        contact.name = String(row['name'] ?? '');
        contact.face = String(row['face'] ?? '');
        contact.fans = Number(row['fans'] ?? 0);
        contact.group = groupName;
        if (contact.uid > 0 && contact.name !== '') contacts.push(contact);
      });
    });
    return contacts;
  }

  static loadAtMe(cookie: string): Promise<BiliMessageItem[]> {
    return MessageService.load('/x/msgfeed/at', 'at', cookie);
  }

  static loadLikes(cookie: string): Promise<BiliMessageItem[]> {
    return MessageService.load('/x/msgfeed/like', 'like', cookie);
  }

  // 私信走会话列表接口（api.vc.bilibili.com），/x/msgfeed/private 并非有效端点
  static async loadSessions(cookie: string): Promise<BiliMessageItem[]> {
    const query: Record<string, string> = {};
    query['session_type'] = '1';
    query['group_fold'] = '1';
    query['unfold_fold'] = '0';
    query['build'] = '0';
    query['mobi_app'] = 'web';
    const result: Record<string, Object> = await BiliHttpClient.getJsonHost(
      'api.vc.bilibili.com', '/session_svr/v1/session_svr/get_sessions', query, cookie);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '私信加载失败'));
    }
    const data: Record<string, Object> = (result['data'] as Record<string, Object>) ?? {};
    const raw: Object[] = ((data['session_list'] ?? []) as Object[]);
    const list: BiliMessageItem[] = [];
    const emptyObj: Record<string, Object> = {};
    raw.forEach((value: Object): void => {
      try {
        const row: Record<string, Object> = value as Record<string, Object>;
        const member: Record<string, Object> = (row['member'] ?? row['member_info'] ??
          emptyObj) as Record<string, Object>;
        const lastMsg: Record<string, Object> = (row['last_msg'] ?? emptyObj) as Record<string, Object>;
        const item: BiliMessageItem = new BiliMessageItem();
        const talkerId: number = Number(row['talker_id'] ?? row['talker_id_str'] ?? 0);
        item.id = talkerId;
        item.mid = Number(member['mid'] ?? talkerId);
        item.userName = String(member['nickname'] ?? member['name'] ?? member['username'] ??
          (talkerId > 0 ? `用户${talkerId}` : '未知用户'));
        item.avatar = String(member['face'] ?? member['avatar'] ?? '');
        item.actionText = '发来一条私信';
        // last_msg.content 是 JSON 字符串，正文在 content/text/title 字段
        item.content = MessageService.parseSessionContent(String(lastMsg['content'] ?? ''));
        const timestamp: number = Number(lastMsg['timestamp'] ?? 0);
        item.timeText = timestamp > 0 ? MessageService.formatDay(timestamp) : '';
        item.counts = Number(row['unread_count'] ?? 0);
        list.push(item);
      } catch (rowError) {
        console.warn(`Pilihos session row parse failed: ${String(rowError)}`);
      }
    });
    return list;
  }

  private static parseSessionContent(content: string): string {
    if (content === '') return '';
    try {
      const parsed: Record<string, Object> = JSON.parse(content) as Record<string, Object>;
      const text: string = String(parsed['content'] ?? parsed['text'] ??
        parsed['title'] ?? parsed['jump_text'] ?? '');
      if (text !== '') return text;
      // 纯链接/图片类系统消息
      if (parsed['url'] !== undefined) return '[链接或图片消息]';
      return content;
    } catch (_error) {
      return content;
    }
  }

  static async loadUnread(cookie: string): Promise<BiliMessageUnread> {
    const query: Record<string, string> = {};
    query['platform'] = 'web';
    query['build'] = '0';
    query['mobi_app'] = 'web';
    query['unread_type'] = '0';
    const result: Record<string, Object> = await BiliHttpClient.getJson('/x/msgfeed/unread', query, cookie);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '未读数加载失败'));
    }
    const data: Record<string, Object> = (result['data'] as Record<string, Object>) ?? {};
    const unread: BiliMessageUnread = new BiliMessageUnread();
    unread.at = Number(data['at'] ?? 0);
    unread.like = Number(data['like'] ?? 0);
    unread.reply = Number(data['reply'] ?? 0);
    unread.sysMsg = Number(data['sys_msg'] ?? 0);
    return unread;
  }
}
