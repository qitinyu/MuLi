import router from '@ohos.router';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { common, Want } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { AuthService, AuthSession } from '../services/AuthService';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import { FormatUtils } from '../utils/FormatUtils';
import { MessageService, BiliMessageItem, BiliMessageUnread, ImUser } from '../services/MessageService';
import { InteractionService } from '../services/InteractionService';
import { VideoItem } from '../models/VideoItem';

const LEVEL_TABLE: number[] = [0, 200, 1500, 4500, 10800, 28800];

class LevelTransition {
  label: string = '';
  expLabel: string = '';
  minXp: number = 0;
  maxXp: number = 0;
}

const LEVEL_TRANSITIONS: LevelTransition[] = [
  (() => { const t = new LevelTransition(); t.label = 'LV0→LV1'; t.expLabel = '0/200'; t.minXp = 0; t.maxXp = 200; return t; })(),
  (() => { const t = new LevelTransition(); t.label = 'LV1→LV2'; t.expLabel = '200/1500'; t.minXp = 200; t.maxXp = 1500; return t; })(),
  (() => { const t = new LevelTransition(); t.label = 'LV2→LV3'; t.expLabel = '1500/4500'; t.minXp = 1500; t.maxXp = 4500; return t; })(),
  (() => { const t = new LevelTransition(); t.label = 'LV3→LV4'; t.expLabel = '4500/10800'; t.minXp = 4500; t.maxXp = 10800; return t; })(),
  (() => { const t = new LevelTransition(); t.label = 'LV4→LV5'; t.expLabel = '10800/28800'; t.minXp = 10800; t.maxXp = 28800; return t; })(),
  (() => { const t = new LevelTransition(); t.label = 'LV5→LV6'; t.expLabel = '28800/28800'; t.minXp = 28800; t.maxXp = 28800; return t; })(),
  (() => { const t = new LevelTransition(); t.label = 'LV6 ⚡'; t.expLabel = '28800/28800'; t.minXp = 28800; t.maxXp = 28800; return t; })(),
];

@Component
export struct MineSidebar {
  @Consume sidebar: number;
  @Consume authSession: AuthSession | null;
  @Consume loginVisible: boolean;
  @Consume loginNotice: string;
  @Consume topInset: number;
  @Consume bottomInset: number;
  @State showLevelSheet: boolean = false;
  @State mineCoverUri: string = '';
  private uiPreferences: preferences.Preferences | null = null;

  aboutToAppear(): void {
    this.loadMineCover();
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2500,
        bottom: this.bottomInset + 24
      });
    } catch (error) {
      console.error(`Pilihos mine sidebar toast failed: ${String(error)}`);
    }
  }

  private onAvatarTap(): void {
    if (this.authSession !== null) {
      return;
    }
    this.loginVisible = true;
    this.sidebar = 0;
    this.loginNotice = '';
  }

  private async logout(): Promise<void> {
    await AuthService.logout();
    this.authSession = null;
    this.loginNotice = '已退出登录';
    this.showToast('已成功登出');
  }

  private async loadMineCover(): Promise<void> {
    try {
      this.uiPreferences = await preferences.getPreferences(getContext(this), 'pilihos_ui');
      this.mineCoverUri = this.uiPreferences.getSync('mine_cover_uri', '') as string;
    } catch (error) {
      console.error('Pilihos cover preference load failed: ' + String(error));
    }
  }

  private async chooseMineCover(): Promise<void> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const result = await photoPicker.select({ maxSelectNumber: 1 });
      if (result.photoUris && result.photoUris.length > 0) {
        this.mineCoverUri = result.photoUris[0];
        if (this.uiPreferences === null) {
          this.uiPreferences = await preferences.getPreferences(getContext(this), 'pilihos_ui');
        }
        this.uiPreferences.putSync('mine_cover_uri', this.mineCoverUri);
        this.uiPreferences.flushSync();
      }
    } catch (error) {
      console.error('Pilihos cover picker failed: ' + String(error));
    }
  }

  private openMyFav(): void {
    this.sidebar = 0;
    router.pushUrl({ url: 'pages/MyFav' }).catch((error: BusinessError): void => {
      console.error('Pilihos my fav page failed: ' + String(error));
    });
  }

  private openUrl(url: string): void {
    try {
      const want: Want = { action: 'ohos.want.action.viewData', uri: url };
      (getContext(this) as common.UIAbilityContext).startAbility(want).catch((): void => {
        promptAction.showToast({ message: '无法打开链接' });
      });
    } catch (error) {
      console.error('Pilihos external link failed: ' + String(error));
    }
  }

  private openSoftwareSettings(): void {
    this.sidebar = 0;
    router.pushUrl({ url: 'pages/Settings' }).catch((error: BusinessError): void => {
      console.error('Pilihos settings page failed: ' + String(error));
    });
  }

  @Builder
  mineCoverImage() {
    if (this.mineCoverUri === '') {
      Image($r('app.media.bottom')).width('100%').height(150)
        .objectFit(ImageFit.Cover).borderRadius(14).clip(true);
    } else {
      Image(this.mineCoverUri).width('100%').height(150)
        .objectFit(ImageFit.Cover).borderRadius(14).clip(true);
    }
  }

  @Builder
  levelSheet() {
    Column({ space: 0 }) {
      Row({ space: 10 }) {
        Image(FormatUtils.levelBadge(this.authSession === null ? 0 : this.authSession.level))
          .width(72).height(39).objectFit(ImageFit.Contain);
        Text('等级经验').fontSize(16).fontWeight(FontWeight.Bold);
      }.width('100%').padding({ left: 24, right: 24, top: 20, bottom: 12 });

      Column({ space: 8 }) {
        Stack({ alignContent: Alignment.Start }) {
          Column().width('100%').height(8).borderRadius(4).backgroundColor('#E9EDF0');
          Column()
            .width(this.expBarPercent() + '%').height(8).borderRadius(4).backgroundColor('#1288FA');
        }.width('100%').height(8);
        Row() {
          Text(this.authSession === null ? '0' : String(this.authSession.expCurrent))
            .fontSize(12).fontColor('#858C94');
          Text(this.authSession === null ? '0' : String(this.authSession.expNext))
            .fontSize(12).fontColor('#858C94').layoutWeight(1).textAlign(TextAlign.End);
        }.width('100%');
      }.width('100%').padding({ left: 24, right: 24, bottom: 12 });

      Divider().color('#E9EDF0').margin({ left: 24, right: 24 });

      Column({ space: 0 }) {
        ForEach(LEVEL_TRANSITIONS, (t: LevelTransition, idx: number) => {
          Row() {
            Text(t.label).fontSize(12).fontColor('#858C94').width(60);
            Stack({ alignContent: Alignment.Start }) {
              Column().width('100%').height(8).borderRadius(4).backgroundColor('#E9EDF0');
              Column().width(this.transitionPercent(idx) + '%').height(8).borderRadius(4)
                .backgroundColor(idx < (this.authSession?.level ?? 0) ? FormatUtils.levelColor(idx) :
                  (idx === (this.authSession?.level ?? 0) ? '#1288FA' : '#D0D5DB'));
            }.layoutWeight(1).height(8);
            Text(t.expLabel).fontSize(11).fontColor('#858C94').width(80).textAlign(TextAlign.End);
          }.width('100%').height(32).alignItems(VerticalAlign.Center);
        }, (_t: LevelTransition, idx: number) => String(idx));
      }.width('100%').padding({ left: 24, right: 24, top: 8 });

      Row({ space: 12 }) {
        Button('更换封面')
          .type(ButtonType.ROUNDED_RECTANGLE)
          .layoutWeight(1).height(40).fontSize(15)
          .fontColor('#1288FA').backgroundColor('#E9F4F8')
          .onClick(() => { this.chooseMineCover(); });
        Button('编辑资料')
          .type(ButtonType.ROUNDED_RECTANGLE)
          .layoutWeight(1).height(40).fontSize(15)
          .fontColor('#1288FA').backgroundColor('#E9F4F8')
          .onClick(() => { this.openUrl('https://account.bilibili.com/account/setting'); });
      }.width('100%').padding({ left: 24, right: 24, top: 16, bottom: this.bottomInset + 16 });
    }
    .width('100%').backgroundColor('#FFFFFF');
  }

  private expBarPercent(): number {
    if (this.authSession === null) return 0;
    const range: number = this.authSession.expNext - this.authSession.expMin;
    if (range <= 0) return 100;
    return Math.min(100, Math.max(0,
      Math.floor((this.authSession.expCurrent - this.authSession.expMin) / range * 100)));
  }

  private transitionPercent(idx: number): number {
    if (this.authSession === null) return 0;
    const curLv: number = this.authSession.level;
    const curExp: number = this.authSession.expCurrent;
    if (idx < curLv) return 100;
    if (idx > curLv) return 0;
    const minXp: number = LEVEL_TABLE[idx];
    const nextXp: number = idx < LEVEL_TABLE.length - 1 ? LEVEL_TABLE[idx + 1] : LEVEL_TABLE[idx];
    const range: number = nextXp - minXp;
    if (range <= 0) return 100;
    return Math.min(100, Math.max(0, Math.floor((curExp - minXp) / range * 100)));
  }

  @Builder
  mineStat(value: string, label: string) {
    Column({ space: 4 }) {
      Text(value).fontSize(22).fontWeight(FontWeight.Bold);
      Text(label).fontSize(13).fontColor('#858C94');
    }.layoutWeight(1);
  }

  @Builder
  mineGridAction(iconName: string, label: string, showArrow: boolean) {
    Stack() {
      Column({ space: 8 }) {
        if (iconName === 'offline_cache') {
          Image($r('app.media.offline_cache')).width(24).height(24);
        } else if (iconName === 'bofang') {
          Image($r('app.media.bofang')).width(24).height(24);
        } else if (iconName === 'subscriptions') {
          Image($r('app.media.subscriptions')).width(24).height(24);
        } else if (iconName === 'watch_later') {
          Image($r('app.media.watch_later')).width(24).height(24);
        } else if (iconName === 'favorites') {
          Image($r('app.media.favorites')).width(24).height(24);
        } else if (iconName === 'off') {
          Image($r('app.media.off')).width(24).height(24);
        } else {
          Image($r('app.media.software_settings')).width(24).height(24);
        }
        Text(label).fontSize(13).fontColor('#3E4854').textAlign(TextAlign.Center);
      }.justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center);
      if (showArrow) {
        Image($r('app.media.jinxin_right')).width(16).height(16)
          .position({ right: 10, bottom: 10 });
      }
    }
    .width('100%').aspectRatio(1)
    .borderRadius(12)
    .backgroundColor(ImmersiveMaterial.surfaceBackground(0.42))
    .systemMaterial(ImmersiveMaterial.getRegular() ?? undefined)
    .shadow({ radius: 6, color: '#18000000', offsetX: 0, offsetY: 2 })
    .onClick(() => {
      if (iconName === 'software_settings') {
        this.openSoftwareSettings();
      } else if (iconName === 'favorites') {
        this.openMyFav();
      } else if (iconName === 'bofang') {
        // 观看记录
        router.pushUrl({
          url: 'pages/WatchListPage',
          params: { mode: 'history' }
        }).catch((error: BusinessError): void => {
          console.error('Pilihos watch history push failed: ' + String(error));
        });
      } else if (iconName === 'watch_later') {
        // 稍后再看
        router.pushUrl({
          url: 'pages/WatchListPage',
          params: { mode: 'watchlater' }
        }).catch((error: BusinessError): void => {
          console.error('Pilihos watch later push failed: ' + String(error));
        });
      } else if (iconName === 'offline_cache') {
        this.showToast('离线缓存待适配');
      } else if (iconName === 'off') {
        this.logout();
      }
    });
  }

  build() {
    Column({ space: 14 }) {
      Stack() {
        this.mineCoverImage();
      }
      .width('100%').height(150);

      Row({ space: 14 }) {
        if (this.authSession !== null && this.authSession.face !== '') {
          Image(this.authSession.face).width(104).height(104).borderRadius(52).objectFit(ImageFit.Cover)
            .onClick(() => { this.onAvatarTap(); });
        } else {
          Image($r('app.media.user_me')).width(104).height(104).borderRadius(52).objectFit(ImageFit.Contain)
            .onClick(() => { this.onAvatarTap(); });
        }
        Column({ space: 5 }) {
          Row({ space: 6 }) {
            Text(this.authSession === null ? 'Pilihos 用户' : this.authSession.name)
              .fontSize(18).fontWeight(FontWeight.Bold).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Image(FormatUtils.levelBadge(this.authSession === null ? 0 : this.authSession.level))
              .width(48).height(26).objectFit(ImageFit.Contain).margin({ left: 0 });
            Image($r('app.media.jinxin_right')).width(14).height(14).fillColor('#858C94');
          }.width('100%')
            .onClick(() => { if (this.authSession !== null) this.showLevelSheet = true; });
          Text(this.authSession === null ? 'B币 -- · 硬币 --' :
            `B币 ${this.authSession.bcoin} · 硬币 ${this.authSession.coin}`)
            .fontSize(12).fontColor('#858C94');
          Text(this.authSession === null ? '登录后同步个人签名' :
            (this.authSession.sign === '' ? '这个人很懒，什么都没有留下' : this.authSession.sign))
            .fontSize(13).fontColor('#858C94').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
          Text(this.authSession === null ? 'UID -- · IP属地 --' :
            ('UID ' + this.authSession.uid + ' · IP属地 ' +
              (this.authSession.ipLocation === '' ? '未知' : this.authSession.ipLocation)))
            .fontSize(12).fontColor('#858C94').maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          .margin({ top: 8 });
      }.width('100%')
        .alignItems(VerticalAlign.Top);

      Row({ space: 8 }) {
        this.mineStat(this.authSession === null ? '0' : FormatUtils.formatCount(this.authSession.dynamicCount), '动态');
        this.mineStat(this.authSession === null ? '0' : FormatUtils.formatCount(this.authSession.followingCount), '关注');
        this.mineStat(this.authSession === null ? '0' : FormatUtils.formatCount(this.authSession.followerCount), '粉丝');
      }.width('100%');

      Grid() {
        GridItem() { this.mineGridAction('favorites', '我的收藏', true); }
        GridItem() { this.mineGridAction('bofang', '观看记录', true); }
        GridItem() { this.mineGridAction('watch_later', '稍后再看', true); }
        GridItem() { this.mineGridAction('offline_cache', '离线缓存', true); }
        GridItem() { this.mineGridAction('software_settings', '软件设置', true); }
        GridItem() { this.mineGridAction('off', '一键登出', true); }
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(10)
      .rowsGap(10)
      .width('100%')
      .layoutWeight(1);
    }
    .width('100%').height('100%')
    .padding({ top: this.topInset + 12, left: 18, right: 18, bottom: this.bottomInset + 20 })
    .backgroundColor(Color.Transparent)
    .alignItems(HorizontalAlign.Start)
    .bindSheet($$this.showLevelSheet, this.levelSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true
    });
  }
}

@Component
export struct MessageSidebar {
  @Consume topInset: number;
  @Consume bottomInset: number;
  @State activeMessageSection: string = 'reply';
  @State replyItems: BiliMessageItem[] = [];
  @State atItems: BiliMessageItem[] = [];
  @State likeItems: BiliMessageItem[] = [];
  @State privateItems: BiliMessageItem[] = [];
  @State unreadReply: string = '';
  @State unreadAt: string = '';
  @State unreadLike: string = '';
  @State messageLoading: boolean = false;
  @State messageError: string = '';
  @State suppressRowTap: boolean = false;

  aboutToAppear(): void {
    this.loadMessages();
  }

  loadMessages(): void {
    const session: AuthSession | null = AuthService.currentSession();
    if (session === null || session.cookie === '') {
      this.messageError = '未登录或登录态失效，无法加载消息';
      return;
    }
    this.messageLoading = true;
    this.loadUnreadBadges(session.cookie);
    // 各通道独立加载：一路失败不清空其余列表，错误聚合展示
    const failures: string[] = [];
    const jobs: Promise<void>[] = [
      MessageService.loadReplies(session.cookie)
        .then((items: BiliMessageItem[]): void => { this.replyItems = items; })
        .catch((error: Error): void => { failures.push(`回复：${error.message}`); }),
      MessageService.loadAtMe(session.cookie)
        .then((items: BiliMessageItem[]): void => { this.atItems = items; })
        .catch((error: Error): void => { failures.push(`@我：${error.message}`); }),
      MessageService.loadLikes(session.cookie)
        .then((items: BiliMessageItem[]): void => { this.likeItems = items; })
        .catch((error: Error): void => { failures.push(`点赞：${error.message}`); }),
      MessageService.loadSessions(session.cookie)
        .then((items: BiliMessageItem[]): void => { this.privateItems = items; })
        .catch((error: Error): void => { failures.push(`私信：${error.message}`); })
    ];
    Promise.all(jobs).then((): void => {
      // 会话列表不带对方资料，批量拉取 im 用户信息补头像/昵称
      if (this.privateItems.length > 0) {
        this.loadSessionProfiles(session.cookie, session.csrf);
      }
      const notes: string[] = failures.slice(0);
      if (this.likeItems.length === 0 && this.unreadLike !== '') {
        notes.push('点赞：接口返回为空但存在未读');
      }
      const allEmpty: boolean = this.replyItems.length === 0 && this.atItems.length === 0
        && this.likeItems.length === 0 && this.privateItems.length === 0;
      if (notes.length > 0) {
        this.messageError = notes.join('；');
      } else if (allEmpty) {
        this.messageError = '接口未返回消息数据（账号可能无互动记录或被风控限流）';
      } else {
        this.messageError = '';
      }
    }).finally((): void => { this.messageLoading = false; });
  }

  // 拉取私信对方的真实头像/昵称（im_user_infos，uids 逗号分隔）
  private loadSessionProfiles(cookie: string, csrf: string): void {
    const uids: string = this.privateItems.map((item: BiliMessageItem): string => String(item.mid))
      .filter((value: string, index: number, all: string[]): boolean => all.indexOf(value) === index)
      .join(',');
    MessageService.loadImUserInfos(uids, cookie, csrf).then((users: Map<number, ImUser>): void => {
      this.privateItems = this.privateItems.map((item: BiliMessageItem): BiliMessageItem => {
        const profile: ImUser | undefined = users.get(item.mid);
        if (profile === undefined) return item;
        if (profile.name !== '') item.userName = profile.name;
        if (profile.face !== '') item.avatar = profile.face;
        return item;
      });
    }).catch((_: Error): void => { });
  }

  // 一键清空：仅清空本地展示，不影响服务端消息
  private clearMessages(): void {
    this.replyItems = [];
    this.atItems = [];
    this.likeItems = [];
    this.privateItems = [];
    this.unreadReply = '';
    this.unreadAt = '';
    this.unreadLike = '';
    this.messageError = '';
  }

  // 未读数独立加载：失败时静默忽略，不影响消息列表展示
  private loadUnreadBadges(cookie: string): void {
    MessageService.loadUnread(cookie).then((unread: BiliMessageUnread): void => {
      this.unreadReply = unread.reply > 0 ? String(unread.reply) : '';
      this.unreadAt = unread.at > 0 ? String(unread.at) : '';
      this.unreadLike = unread.like > 0 ? String(unread.like) : '';
    }).catch((_: Error): void => { });
  }

  // 消息行点击：以 oid/bvid 组装最小视频对象，回传 Index 直接进入播放（评论区可达）
  private openMessageVideo(item: BiliMessageItem, kind: string): void {
    if (item.oid <= 0 && item.bvid === '') {
      this.showToast('未能定位原视频，暂无法跳转');
      return;
    }
    const video: VideoItem = {
      id: item.oid,
      aid: item.oid,
      bvid: item.bvid,
      cid: 0,
      title: item.source === '' ? item.content : item.source,
      author: item.userName,
      authorMid: item.mid,
      cover: '',
      viewCount: 0, danmuCount: 0, likeCount: 0, commentCount: 0,
      followed: false, duration: 0, playUrl: '', placeholder: false,
      publishTime: 0, description: '', tags: [], detailLoaded: false
    };
    // 回传 Index：rpid/rootId 供播放落地后自动展开目标楼层
    router.back({
      url: 'pages/Index',
      params: {
        pilihosMessage: {
          video: video,
          rpid: (kind === 'reply' || kind === 'at') ? item.id : 0,
          rootId: (kind === 'reply' || kind === 'at') ? item.rootId : 0,
          nonce: `${Date.now()}`
        }
      }
    });
  }

  // 消息头像点击：进入对方个人空间
  private openMessageUser(item: BiliMessageItem): void {
    if (item.mid <= 0) {
      this.showToast('未能获取对方信息，暂无法进入空间');
      return;
    }
    router.pushUrl({ url: 'pages/UserSpace', params: { mid: item.mid, name: item.userName } })
      .catch((error: BusinessError): void => {
        console.error('Pilihos message user space failed: ' + String(error));
        this.showToast('打开个人空间失败');
      });
  }

  // 私信会话 → 独立聊天页
  private openChat(item: BiliMessageItem): void {
    if (item.mid <= 0) {
      this.showToast('未能获取对方信息');
      return;
    }
    router.pushUrl({
      url: 'pages/ChatPage',
      params: { mid: item.mid, name: item.userName, face: item.avatar }
    }).catch((error: BusinessError): void => {
      console.error('Pilihos chat page push failed: ' + String(error));
      this.showToast('打开聊天失败');
    });
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2200,
        bottom: this.bottomInset + 24
      });
    } catch (error) {
      console.error(`Pilihos message sidebar toast failed: ${String(error)}`);
    }
  }

  @Builder
  messageBubble(label: string, count: string, iconName: string, section: string) {
    Column({ space: 6 }) {
      if (count !== '') {
        // 新事件标记：Badge 组件挂在图标右上角
        Badge({ value: count, position: BadgePosition.RightTop,
          style: { badgeSize: 16, badgeColor: '#C51D2A', fontSize: 10 } }) {
          this.bubbleIconButton(iconName, section)
        }
      } else {
        this.bubbleIconButton(iconName, section)
      }
      Text(label).fontSize(12).textAlign(TextAlign.Center);
    }.layoutWeight(1).alignItems(HorizontalAlign.Center)
      .opacity(this.activeMessageSection === section ? 1 : 0.72)
      .onClick((): void => { this.activeMessageSection = section; });
  }

  @Builder
  bubbleIconButton(iconName: string, section: string) {
    Button() {
      if (iconName === 'message_reply') {
        Image($r('app.media.message_reply')).width(22).height(22);
      } else if (iconName === 'at_me') {
        Image($r('app.media.at_me')).width(22).height(22);
      } else if (iconName === 'received_likes') {
        Image($r('app.media.xiaoxi')).width(22).height(22);
      } else {
        Image($r('app.media.xiaoxi')).width(22).height(22);
      }
    }
    .type(ButtonType.ROUNDED_RECTANGLE)
    .width(52).height(52)
    .borderRadius(26)
    .backgroundColor(ImmersiveMaterial.surfaceBackground(0.42))
    .systemMaterial(ImmersiveMaterial.getThin() ?? undefined)
    .shadow({ radius: 6, color: '#22000000', offsetX: 0, offsetY: 2 });
  }

  @Builder
  messageRow(title: string, summary: string, date: string, iconName: string) {
    Row({ space: 12 }) {
      if (iconName === 'message_reply') {
        Image($r('app.media.message_reply')).width(38).height(38).borderRadius(19);
      } else if (iconName === 'at_me') {
        Image($r('app.media.at_me')).width(38).height(38).borderRadius(19);
      } else if (iconName === 'received_likes') {
        Image($r('app.media.xiaoxi')).width(38).height(38).borderRadius(19);
      } else {
        Image($r('app.media.xiaoxi')).width(38).height(38).borderRadius(19);
      }
      Column({ space: 5 }) {
        Row() {
          Text(title).fontSize(14).layoutWeight(1);
          Text(date).fontSize(11).fontColor('#858C94');
        }.width('100%');
        Text(summary).fontSize(13).fontColor('#858C94').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }.width('100%').padding({ top: 14, bottom: 14 })
      .border({ width: { bottom: 1 }, color: '#E9EDF0' });
  }

  // 快捷点赞：对被点赞/被回复的评论点赞（私信无评论对象则提示）
  private likeMessage(item: BiliMessageItem): void {
    const session: AuthSession | null = AuthService.currentSession();
    if (session === null || session.cookie === '') {
      this.showToast('请先登录后再互动');
      return;
    }
    if (item.oid <= 0 || item.id <= 0) {
      this.showToast('未能定位原评论，暂无法点赞');
      return;
    }
    InteractionService.likeReply(item.oid, item.id, true, session.cookie, session.csrf)
      .then((): void => { this.showToast('已点赞'); })
      .catch((error: Error): void => { this.showToast(`点赞失败: ${error.message}`); });
  }

  // 行首动作后缀：回复/艾特/点赞/私信各不相同
  private actionSuffix(kind: string, item: BiliMessageItem): string {
    if (kind === 'reply') return ' 回复了我的评论';
    if (kind === 'at') return ' 在评论或动态中提到了我';
    if (kind === 'like') return item.actionText;
    return ' 发来一条私信';
  }

  @Builder
  apiMessageRow(item: BiliMessageItem, kind: string) {
    Row({ space: 12 }) {
      Stack() {
        if (item.avatar !== '') {
          Image(item.avatar).width(48).height(48).borderRadius(24).objectFit(ImageFit.Cover);
        } else {
          Image($r('app.media.user_me')).width(48).height(48).borderRadius(24);
        }
        if (kind === 'like') {
          Image($r('app.media.dianzan')).width(18).height(18).fillColor('#1288FA')
            .backgroundColor(Color.White).borderRadius(9).position({ right: -2, bottom: -2 });
        }
      }.width(48).height(48)
        .onClick((): void => {
          // 抑制冒泡到消息行的打开视频点击
          this.suppressRowTap = true;
          this.openMessageUser(item);
        });
      Column({ space: 4 }) {
        // 第一行：用户名 + 灰色小字动作后缀
        Row({ space: 0 }) {
          Text(item.userName).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#1E252D')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '60%' });
          Text(this.actionSuffix(kind, item)).fontSize(11).fontColor('#858C94')
            .maxLines(1).layoutWeight(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }.width('100%');
        // 第二行：正文（黑体）
        if (item.content !== '') {
          Text(item.content).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#1E252D')
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        }
        // 第三行：我的原评论（回复/@我 通道）
        if ((kind === 'reply' || kind === 'at') && item.source !== '') {
          Text(item.source).fontSize(12).fontColor('#A0A6AD')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        }
        // 第四行：日期 + 点赞 + 快捷回复
        Row({ space: 14 }) {
          Text(item.timeText).fontSize(11).fontColor('#A0A6AD').layoutWeight(1);
          Image($r('app.media.dianzan')).width(16).height(16).fillColor('#858C94')
            .onClick((): void => { this.likeMessage(item); });
          Image($r('app.media.reply')).width(16).height(16).fillColor('#858C94')
            .onClick((): void => {
              // 私信：进入独立聊天页
              if (kind === 'private') {
                this.openChat(item);
                return;
              }
              this.openMessageVideo(item, kind);
            });
        }.width('100%');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }.width('100%').padding({ top: 14, bottom: 14 })
      .border({ width: { bottom: 1 }, color: '#E9EDF0' })
      .onClick((): void => {
        if (this.suppressRowTap) {
          this.suppressRowTap = false;
          return;
        }
        // 私信：进入独立聊天页；其余通道跳原视频
        if (kind === 'private') {
          this.openChat(item);
          return;
        }
        this.openMessageVideo(item, kind);
      });
  }

  @Builder
  messageSectionTitle(title: string, count: string) {
    Row() {
      Text(title).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#1E252D')
        .layoutWeight(1);
      if (count !== '') {
        Text(count).fontSize(11).fontColor(Color.White)
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .backgroundColor('#C51D2A')
          .borderRadius(12);
      }
    }
    .width('100%')
    .padding({ top: 6, bottom: 4 });
  }

  @Builder
  replyMessages() {
    Column({ space: 0 }) {
      this.messageSectionTitle('回复我的', this.unreadReply);
      if (this.replyItems.length > 0) {
        ForEach(this.replyItems, (item: BiliMessageItem) => { this.apiMessageRow(item, 'reply'); },
          (item: BiliMessageItem) => `reply_${item.id}`);
      } else {
        this.messageRow('暂无回复', '登录后将在这里显示回复我的消息', '', 'message_reply');
      }
    }.width('100%');
  }

  @Builder
  likeMessages() {
    Column({ space: 0 }) {
      this.messageSectionTitle('收到的赞', this.unreadLike);
      if (this.likeItems.length > 0) {
        ForEach(this.likeItems, (item: BiliMessageItem) => { this.apiMessageRow(item, 'like'); },
          (item: BiliMessageItem) => `like_${item.id}`);
      } else {
        this.messageRow('暂无点赞', '登录后将在这里显示收到的赞', '', 'received_likes');
      }
    }.width('100%');
  }

  build() {
    Column() {
      Row() {
        Button() {
          Image($r('app.media.fanhui_left')).width(24).height(24);
        }
        .type(ButtonType.ROUNDED_RECTANGLE)
        .width(42).height(42)
        .backgroundColor(Color.Transparent)
        .onClick(() => { router.back(); });
        Text('消息').fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1);
        Image($r('app.media.lista')).width(22).height(22).fillColor('#59616B')
          .bindMenu([
            {
              value: '重新加载',
              action: (): void => { this.loadMessages(); }
            },
            {
              value: '一键清空',
              action: (): void => { this.clearMessages(); }
            }
          ], { placement: Placement.Bottom });
      }
      .width('100%')
      .padding({ top: this.topInset + 12, left: 22, right: 22, bottom: 12 })
      .alignItems(VerticalAlign.Center);
      Scroll() {
        Column({ space: 18 }) {
          Row({ space: 8 }) {
            this.messageBubble('回复我的', this.unreadReply, 'message_reply', 'reply');
            this.messageBubble('@我', this.unreadAt, 'at_me', 'at');
            this.messageBubble('收到的赞', this.unreadLike, 'received_likes', 'likes');
            this.messageBubble('私信我的', '', 'xiaoxi', 'private');
          }.width('100%');
          if (this.messageError !== '') {
            Text(`部分消息加载失败：${this.messageError}`)
              .fontSize(11).fontColor('#C51D2A').width('100%');
          }
          if (this.activeMessageSection === 'likes') {
            this.likeMessages();
          } else if (this.activeMessageSection === 'reply') {
            this.replyMessages();
          } else if (this.activeMessageSection === 'at') {
            Column({ space: 0 }) {
              this.messageSectionTitle('@我', this.unreadAt);
              if (this.atItems.length > 0) {
                ForEach(this.atItems, (item: BiliMessageItem) => { this.apiMessageRow(item, 'at'); },
                  (item: BiliMessageItem) => `at_${item.id}`);
              } else {
                this.messageRow('暂无@提醒', '登录后在这里查看 @ 我的评论和动态', '', 'at_me');
              }
            }.width('100%');
          } else if (this.activeMessageSection === 'private') {
            Column({ space: 0 }) {
              this.messageSectionTitle('私信我的', '');
              if (this.privateItems.length > 0) {
                ForEach(this.privateItems, (item: BiliMessageItem) => { this.apiMessageRow(item, 'private'); },
                  (item: BiliMessageItem) => `private_${item.id}`);
              } else {
                this.messageRow('暂无私信', '暂时没有新的私信消息', '', 'xiaoxi');
              }
            }.width('100%');
          }
        }
        .width('100%')
        .padding({ left: 22, right: 22, bottom: this.bottomInset + 20 })
        // 内容不足一屏时也强制从顶部排列（杜绝 Scroll 默认垂直居中）
        .constraintSize({ minHeight: '100%' });
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      // Scroll 内容不足一屏时默认垂直居中，这里固定顶对齐
      .align(Alignment.TopStart);
    }
    .width('100%').height('100%')
    .backgroundColor('#F5F7F9')
    .alignItems(HorizontalAlign.Start);
  }
}
