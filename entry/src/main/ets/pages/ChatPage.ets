import router from '@ohos.router';
import window from '@ohos.window';
import common from '@ohos.app.ability.common';
import { BiliHttpClient } from '../services/BiliHttpClient';
import { AuthService, AuthSession } from '../services/AuthService';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import { BiliEmoji, EmojiService } from '../services/EmojiService';

// 聊天气泡内容切片：文本或真实渲染的 B 站表情
class ChatPiece {
  public text: string;
  public url: string;

  constructor(text: string, url: string) {
    this.text = text;
    this.url = url;
  }
}

class ChatMessage {
  senderUid: number = 0;
  content: string = '';
  timestamp: number = 0;
  mine: boolean = false;
}

// 私信聊天页：会话消息流 + 底部输入行 + 聊天设置视图
@Entry
@Component
struct ChatPage {
  @State peerMid: number = 0;
  @State peerName: string = '';
  @State peerFace: string = '';
  @State peerSign: string = '';
  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  @State sending: boolean = false;
  @State loading: boolean = true;
  @State settingMode: boolean = false;
  @State topInset: number = 0;
  @State bottomInset: number = 0;
  // 聊天设置占位开关
  @State pinEnabled: boolean = false;
  @State muteEnabled: boolean = false;
  @State blacklistEnabled: boolean = false;
  @State keyInset: number = 0;
  // 表情面板（评论区同款表情，真实渲染）
  @State emojiVisible: boolean = false;
  @State emojiList: BiliEmoji[] = [];
  private emojiMap: Map<string, string> = new Map<string, string>();
  private keyAreaHandler: ((data: window.AvoidAreaOptions) => void) | null = null;
  private scroller: Scroller = new Scroller();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    const params: Object | undefined = router.getParams() as Object | undefined;
    if (params !== undefined) {
      const record: Record<string, Object> = params as Record<string, Object>;
      this.peerMid = Number(record['mid'] ?? 0);
      this.peerName = String(record['name'] ?? '用户');
      this.peerFace = String(record['face'] ?? '');
    }
    this.updateSystemInsets();
    this.watchKeyboard();
    this.loadMessages();
    this.loadPeerProfile();
  }

  aboutToDisappear(): void {
    // 注销键盘避让监听
    window.getLastWindow(this.context).then((mainWindow: window.Window): void => {
      if (this.keyAreaHandler !== null) {
        mainWindow.off('avoidAreaChange', this.keyAreaHandler);
      }
    }).catch((_error: Object): void => { });
  }

  // 键盘弹出时输入行上移（avoidAreaChange 动态监听）
  private watchKeyboard(): void {
    window.getLastWindow(this.context).then((mainWindow: window.Window): void => {
      this.keyAreaHandler = (data: window.AvoidAreaOptions): void => {
        if (data.type === window.AvoidAreaType.TYPE_KEYBOARD) {
          this.keyInset = px2vp(data.area.bottomRect.height);
        }
      };
      mainWindow.on('avoidAreaChange', this.keyAreaHandler);
    }).catch((error: Object): void => {
      console.error(`Pilihos chat keyboard watch failed: ${String(error)}`);
    });
  }

  private async updateSystemInsets(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      const systemArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = px2vp(systemArea.topRect.height);
      const navArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.bottomInset = px2vp(navArea.bottomRect.height);
    } catch (error) {
      console.error('Pilihos chat page inset failed: ' + String(error));
    }
  }

  private session(): AuthSession | null {
    return AuthService.currentSession();
  }

  private cookieValue(): string {
    const session: AuthSession | null = this.session();
    return session === null ? '' : session.cookie;
  }

  private myUid(): number {
    const session: AuthSession | null = this.session();
    return session === null ? 0 : Number(session.uid);
  }

  // 会话消息：/svr_sync/v1/svr_sync/fetch_session_msgs
  private async loadMessages(): Promise<void> {
    if (this.peerMid <= 0 || this.cookieValue() === '') {
      this.loading = false;
      return;
    }
    this.loading = true;
    try {
      const query: Record<string, string> = {};
      query['session_type'] = '1';
      query['talker_id'] = String(this.peerMid);
      query['size'] = '20';
      query['sender_device_id'] = '1';
      query['build'] = '0';
      query['mobi_app'] = 'web';
      const result: Record<string, Object> = await BiliHttpClient.getJsonHost(
        'api.vc.bilibili.com', '/svr_sync/v1/svr_sync/fetch_session_msgs', query, this.cookieValue());
      if (Number(result['code'] ?? -1) !== 0) {
        throw new Error(String(result['message'] ?? '消息加载失败'));
      }
      const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
      const raw: Object[] = ((data['messages'] ?? []) as Object[]);
      const myUid: number = this.myUid();
      const list: ChatMessage[] = [];
      raw.forEach((value: Object): void => {
        const row: Record<string, Object> = value as Record<string, Object>;
        const message: ChatMessage = new ChatMessage();
        message.senderUid = Number(row['sender_uid'] ?? 0);
        message.timestamp = Number(row['timestamp'] ?? 0);
        message.content = ChatPage.parseMessageContent(String(row['content'] ?? ''),
          Number(row['msg_type'] ?? 1));
        message.mine = message.senderUid === myUid;
        list.push(message);
      });
      // 接口按时间正序返回（最新在后）
      this.messages = list;
      setTimeout((): void => {
        this.scroller.scrollEdge(Edge.Bottom);
      }, 120);
    } catch (error) {
      console.error(`Pilihos chat messages failed: ${String(error)}`);
    } finally {
      this.loading = false;
    }
  }

  private static parseMessageContent(content: string, msgType: number): string {
    if (content === '') return '';
    try {
      const parsed: Record<string, Object> = JSON.parse(content) as Record<string, Object>;
      const text: string = String(parsed['content'] ?? '');
      if (text !== '') return text;
      const title: string = String(parsed['title'] ?? '');
      if (title !== '') return title;
      if (msgType === 2) return '[图片]';
    } catch (_error) {
      // JSON 解析失败：尝试正则兜底提取 "content":"..." 字段
      const matched: RegExpMatchArray | null = content.match(/"content"\s*:\s*"([^"]*)"/);
      if (matched !== null && matched[1] !== '') return matched[1];
    }
    if (msgType === 2) return '[图片]';
    if (msgType === 7) return '[系统消息]';
    return '[暂不支持的消息类型]';
  }

  // 对方资料卡（聊天设置页）：card 接口取昵称/签名
  private async loadPeerProfile(): Promise<void> {
    if (this.peerMid <= 0) return;
    try {
      const query: Record<string, string> = {};
      query['mid'] = String(this.peerMid);
      query['photo'] = 'true';
      const result: Record<string, Object> =
        await BiliHttpClient.getJson('/x/web-interface/card', query, this.cookieValue());
      if (Number(result['code'] ?? -1) !== 0) return;
      const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
      const card: Record<string, Object> = (data['card'] ?? {}) as Record<string, Object>;
      if (String(card['name'] ?? '') !== '') this.peerName = String(card['name']);
      this.peerSign = String(card['sign'] ?? '');
    } catch (_error) {
      // 静默：资料卡加载失败不影响聊天
    }
  }

  // 发送文本私信：POST /web_im/v1/web_im/send
  private async sendText(): Promise<void> {
    const text: string = this.inputText.trim();
    const session: AuthSession | null = this.session();
    if (text === '' || this.sending) return;
    if (session === null || session.cookie === '' || session.csrf === '') {
      this.showToast('请先登录后再发私信');
      return;
    }
    this.sending = true;
    try {
      const contentObj: Record<string, Object> = { 'content': text };
      const msgPayload: Record<string, Object> = {
        'sender_uid': Number(session.uid),
        'receiver_id': this.peerMid,
        'receiver_type': 1,
        'msg_type': 1,
        'msg_status': 0,
        'content': contentObj,
        'timestamp': Math.floor(Date.now() / 1000),
        'new_face_version': 1,
        'dev_id': 'A1B2C3D4'
      };
      const form: Record<string, string> = {};
      form['msg'] = JSON.stringify(msgPayload);
      form['from_firework'] = '0';
      form['build'] = '0';
      form['mobi_app'] = 'web';
      form['csrf_token'] = session.csrf;
      form['csrf'] = session.csrf;
      const result: Record<string, Object> = await BiliHttpClient.postFormHost(
        'api.vc.bilibili.com', '/web_im/v1/web_im/send', form, session.cookie);
      if (Number(result['code'] ?? -1) !== 0) {
        throw new Error(String(result['message'] ?? '发送失败'));
      }
      const message: ChatMessage = new ChatMessage();
      message.senderUid = Number(session.uid);
      message.timestamp = Math.floor(Date.now() / 1000);
      message.content = text;
      message.mine = true;
      this.messages = this.messages.concat([message]);
      this.inputText = '';
      setTimeout((): void => { this.scroller.scrollEdge(Edge.Bottom); }, 80);
    } catch (error) {
      this.showToast(`发送失败: ${String(error)}`);
    } finally {
      this.sending = false;
    }
  }

  // 打开/关闭表情面板（懒加载评论区同款表情）
  private toggleEmojiPanel(): void {
    this.emojiVisible = !this.emojiVisible;
    if (this.emojiVisible && this.emojiList.length === 0) {
      const session: AuthSession | null = this.session();
      if (session === null || session.cookie === '') return;
      EmojiService.loadReplyEmojis(session.cookie).then((emojis: BiliEmoji[]): void => {
        this.emojiList = emojis;
        this.emojiMap.clear();
        emojis.forEach((emoji: BiliEmoji): void => {
          const key: string = EmojiService.normalizeName(emoji.name);
          if (!this.emojiMap.has(key)) this.emojiMap.set(key, emoji.url);
        });
      }).catch((_: Error): void => {
        this.showToast('表情加载失败');
      });
    }
  }

  // 气泡内容切片：[表情名] → 表情图片，其余为文本
  private chatContentPieces(content: string): ChatPiece[] {
    const pieces: ChatPiece[] = [];
    const regex: RegExp = /\[[^\[\]]{1,20}\]/g;
    let lastIndex: number = 0;
    let match: RegExpExecArray | null = regex.exec(content);
    while (match !== null) {
      if (match.index > lastIndex) {
        pieces.push(new ChatPiece(content.substring(lastIndex, match.index), ''));
      }
      const name: string = match[0].substring(1, match[0].length - 1);
      const url: string = this.emojiMap.get(name) ?? '';
      pieces.push(new ChatPiece(match[0], url));
      lastIndex = match.index + match[0].length;
      match = regex.exec(content);
    }
    if (lastIndex < content.length) {
      pieces.push(new ChatPiece(content.substring(lastIndex), ''));
    }
    if (pieces.length === 0) pieces.push(new ChatPiece(content, ''));
    return pieces;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2000,
        bottom: this.bottomInset + 70
      });
    } catch (_error) {
      // 忽略 toast 失败
    }
  }

  // 相邻消息间隔超过 5 分钟显示时间戳分隔
  private shouldShowTime(index: number): boolean {
    if (index === 0) return true;
    return this.messages[index].timestamp - this.messages[index - 1].timestamp > 300;
  }

  private formatTime(timestamp: number): string {
    const date: Date = new Date(timestamp * 1000);
    const pad = (value: number): string => String(value).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
      `${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }

  @Builder
  chatHeaderView() {
    Row({ space: 10 }) {
      Button() {
        Image($r('app.media.fanhui_left')).width(24).height(24);
      }
      .type(ButtonType.ROUNDED_RECTANGLE).width(40).height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => { router.back(); });
      if (this.peerFace !== '') {
        Image(this.peerFace).width(34).height(34).borderRadius(17).objectFit(ImageFit.Cover);
      } else {
        Image($r('app.media.user_me')).width(34).height(34).borderRadius(17);
      }
      Text(this.peerName).fontSize(17).fontWeight(FontWeight.Medium).fontColor('#1E252D')
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      Button() {
        Image($r('app.media.sphsz')).width(22).height(22).fillColor('#3E4854');
      }
      .type(ButtonType.ROUNDED_RECTANGLE).width(36).height(36)
      .backgroundColor(Color.Transparent)
      .onClick(() => { this.settingMode = true; });
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: this.topInset + 6, bottom: 6 });
  }

  @Builder
  chatBody() {
    Stack() {
      Column().width('100%').height('100%').backgroundColor('#F5F7F9');
      Column() {
        if (this.settingMode) {
          this.settingHeaderView();
          this.chatSettingContent();
        } else {
          this.chatHeaderView();
          this.chatMessageList();
          this.chatInputBar();
        }
      }
      .width('100%').height('100%');
      // 表情面板打开时：单击空白处即关闭
      if (this.emojiVisible) {
        Column()
          .width('100%').height('100%')
          .backgroundColor(Color.Transparent)
          .onClick((): void => { this.emojiVisible = false; })
          .zIndex(20);
        if (true) {
          this.emojiPanel();
        }
      }
    }
    .width('100%').height('100%')
  }

  // 表情面板：评论区同款表情，位于输入行上方
  @Builder
  emojiPanel() {
    Column() {
      Grid() {
        ForEach(this.emojiList, (emoji: BiliEmoji) => {
          GridItem() {
            Image(emoji.url).width(34).height(34).objectFit(ImageFit.Contain)
              .onClick((): void => { this.inputText = this.inputText + emoji.name; });
          }
        }, (emoji: BiliEmoji) => `em_${emoji.name}`)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr 1fr')
      .rowsGap(6)
      .columnsGap(6)
      .height(200)
      .width('100%');
    }
    .width('100%')
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(14)
    .margin({
      left: 0,
      right: 0,
      // 面板底 = 输入行顶
      bottom: (this.keyInset > 0 ? this.keyInset : this.bottomInset + 8) + 54
    })
    .zIndex(21);
  }

  // 聊天设置视图头部：仅 < + 聊天设置
  @Builder
  settingHeaderView() {
    Row({ space: 10 }) {
      Button() {
        Image($r('app.media.fanhui_left')).width(24).height(24);
      }
      .type(ButtonType.ROUNDED_RECTANGLE).width(40).height(40)
      .backgroundColor(Color.Transparent)
      .onClick(() => { this.settingMode = false; });
      Text('聊天设置').fontSize(17).fontWeight(FontWeight.Medium).fontColor('#1E252D')
        .layoutWeight(1);
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: this.topInset + 6, bottom: 6 });
  }

  @Builder
  chatMessageList() {
    Scroll(this.scroller) {
      Column({ space: 10 }) {
        if (this.loading) {
          Text('正在加载消息…').fontSize(12).fontColor('#858C94').width('100%')
            .textAlign(TextAlign.Center).padding({ top: 20 });
        } else if (this.messages.length === 0) {
          Text('还没有消息，打个招呼吧～').fontSize(12).fontColor('#858C94').width('100%')
            .textAlign(TextAlign.Center).padding({ top: 20 });
        }
        ForEach(this.messages, (message: ChatMessage, index: number) => {
          if (this.shouldShowTime(index)) {
            Text(this.formatTime(message.timestamp)).fontSize(10).fontColor('#8A9AA5')
              .width('100%').textAlign(TextAlign.Center).padding({ top: 6 });
          }
          Row() {
            if (!message.mine) {
              Blank().width(40);
            }
            // 气泡内容：[表情名] 真实渲染为图片
            Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
              ForEach(this.chatContentPieces(message.content), (piece: ChatPiece, pieceIndex: number) => {
                if (piece.url !== '') {
                  Image(piece.url).width(22).height(22).objectFit(ImageFit.Contain)
                    .margin({ right: 2 });
                } else {
                  Text(piece.text).fontSize(14).fontColor('#1E252D');
                }
              }, (piece: ChatPiece, pieceIndex: number) => `cp_${index}_${pieceIndex}`)
            }
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .constraintSize({ maxWidth: '72%' })
            .backgroundColor(message.mine ? '#CCE9FF' : '#FFFFFF')
            .border(message.mine ? { width: 0 } : { width: 1, color: '#E5E8EC' })
            .borderRadius(12);
            if (message.mine) {
              Blank().layoutWeight(1);
            }
          }.width('100%');
        }, (message: ChatMessage, index: number) => `msg_${index}_${message.timestamp}`);
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 8, bottom: 12 });
    }
    .layoutWeight(1).width('100%').scrollBar(BarState.Off).align(Alignment.Bottom);
  }

  @Builder
  chatInputBar() {
    Column() {
      Row({ space: 10 }) {
      Image($r('app.media.bqa')).width(24).height(24).opacity(0.8)
        .onClick((): void => { this.toggleEmojiPanel(); });
      Image($r('app.media.img')).width(24).height(24).opacity(0.8)
        .onClick((): void => { this.showToast('图片发送开发中'); });
      Image($r('app.media.newfiles')).width(24).height(24).opacity(0.8)
        .onClick((): void => { this.showToast('更多功能开发中'); });
      Row({ space: 8 }) {
        TextInput({ placeholder: '说点什么...', text: this.inputText })
          .layoutWeight(1).height(38).fontSize(14).fontColor('#1E252D')
          .backgroundColor(Color.Transparent).padding({ left: 0, right: 0 })
          .onChange((value: string) => { this.inputText = value; })
          .onSubmit((): void => { this.sendText(); });
      }
      .layoutWeight(1).height(38)
      .padding({ left: 12, right: 12 })
      .backgroundColor('#F1F3F5')
      .borderRadius(19);
      Image($r('app.media.send')).width(24).height(24)
        .fillColor(this.inputText.trim() === '' ? '#858C94' : '#1288FA')
        .onClick((): void => { this.sendText(); });
    }
    .width('100%')
    .padding({
      left: 12,
      right: 12,
      top: 8,
      // 键盘弹出时贴键盘上沿，否则落在导航条上方
      bottom: this.keyInset > 0 ? this.keyInset : this.bottomInset + 8
    })
    .backgroundColor(ImmersiveMaterial.fallbackBackground(0.9))
    .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT });
    }
  }

  // 聊天设置视图内容（图二样式）：资料卡 + 开关组（含删除聊天）+ 举报
  @Builder
  chatSettingContent() {
    Column({ space: 12 }) {
      Column() {
        Row({ space: 12 }) {
          if (this.peerFace !== '') {
            Image(this.peerFace).width(48).height(48).borderRadius(24).objectFit(ImageFit.Cover);
          } else {
            Image($r('app.media.user_me')).width(48).height(48).borderRadius(24);
          }
          Column({ space: 3 }) {
            Text(this.peerName).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#1E252D');
            Text(`UID：${this.peerMid}`).fontSize(12).fontColor('#858C94');
            if (this.peerSign !== '') {
              Text(this.peerSign).fontSize(12).fontColor('#858C94').maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis });
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
          Image($r('app.media.jinxin_right')).width(16).height(16).fillColor('#B9C2CC');
        }
        .width('100%').padding(12)
        .onClick((): void => {
          router.pushUrl({
            url: 'pages/UserSpace',
            params: { mid: this.peerMid, name: this.peerName }
          }).catch((_error: Object): void => { });
        });
      }
      .width('100%')
      .backgroundColor('#FFFFFF')
      .borderRadius(14);

      Column() {
        this.settingToggleRow('置顶聊天', this.pinEnabled, (value: boolean): void => {
          this.pinEnabled = value;
        });
        Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 14, right: 14 });
        this.settingToggleRow('消息免打扰', this.muteEnabled, (value: boolean): void => {
          this.muteEnabled = value;
        });
        Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 14, right: 14 });
        this.settingToggleRow('加入黑名单', this.blacklistEnabled, (value: boolean): void => {
          this.blacklistEnabled = value;
        });
        Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 14, right: 14 });
        // 删除聊天：从服务端移除该会话并返回消息页
        Row() {
          Text('删除聊天').fontSize(15).fontColor('#C51D2A').layoutWeight(1);
        }
        .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .onClick((): void => { this.confirmDeleteChat(); });
      }
      .width('100%')
      .backgroundColor('#FFFFFF')
      .borderRadius(14);

      Column() {
        Row() {
          Text('举报').fontSize(15).fontColor('#1E252D').layoutWeight(1);
          Image($r('app.media.jinxin_right')).width(16).height(16).fillColor('#B9C2CC');
        }
        .width('100%').padding(14)
        .onClick((): void => {
          router.pushUrl({
            url: 'pages/WebBrowser',
            params: { url: 'https://www.bilibili.com/appeal/', title: '举报' }
          }).catch((_error: Object): void => { });
        });
      }
      .width('100%')
      .backgroundColor('#FFFFFF')
      .borderRadius(14);
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 4 })
    .alignItems(HorizontalAlign.Start);
  }

  // 删除会话：确认后调 remove_session 并返回消息页
  private confirmDeleteChat(): void {
    const session: AuthSession | null = this.session();
    if (session === null || session.csrf === '') {
      this.showToast('请先登录');
      return;
    }
    AlertDialog.show({
      title: '删除聊天',
      message: '删除后将移除与该用户的会话记录入口，确定删除？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: (): void => { }
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#C51D2A',
        action: (): void => { this.doDeleteChat(session.csrf); }
      }
    });
  }

  private async doDeleteChat(csrf: string): Promise<void> {
    try {
      const form: Record<string, string> = {};
      form['talker_id'] = String(this.peerMid);
      form['session_type'] = '1';
      form['csrf'] = csrf;
      const result: Record<string, Object> = await BiliHttpClient.postFormHost(
        'api.vc.bilibili.com', '/session_svr/v1/session_svr/remove_session', form,
        this.cookieValue());
      if (Number(result['code'] ?? -1) !== 0) {
        throw new Error(String(result['message'] ?? '删除失败'));
      }
      this.showToast('聊天已删除');
      router.back();
    } catch (error) {
      this.showToast(`删除失败: ${String(error)}`);
    }
  }

  @Builder
  settingToggleRow(label: string, value: boolean, onChange: (v: boolean) => void) {
    Row() {
      Text(label).fontSize(15).fontColor('#1E252D').layoutWeight(1);
      Toggle({ type: ToggleType.Switch, isOn: value })
        .selectedColor('#1288FA')
        .onChange((newValue: boolean): void => { onChange(newValue); });
    }
    .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 });
  }

  build() {
    Column() {
      this.chatBody()
    }
    .width('100%').height('100%');
  }
}
