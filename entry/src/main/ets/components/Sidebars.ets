import router from '@ohos.router';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { AuthService, AuthSession } from '../services/AuthService';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import { FormatUtils } from '../utils/FormatUtils';

class LevelTier {
  from: number = 0;
  to: number = 0;
  exp: number = 0;
}

// B站会员等级门槛：升级到 LVn 所需的总经验值
const LEVEL_EXP_THRESHOLDS: number[] = [200, 1500, 4500, 9000, 28000, 108000];

@Component
export struct MineSidebar {
  @Consume sidebar: number;
  @Consume authSession: AuthSession | null;
  @Consume loginVisible: boolean;
  @Consume loginNotice: string;
  @Consume topInset: number;
  @Consume bottomInset: number;
  @Link showMineCoverSheet: boolean;
  @State mineCoverUri: string = '';
  @State levelSheetVisible: boolean = false;
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
      // 已登录：单击无动作（登出走下方"一键登出"卡片）
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
    this.showMineCoverSheet = false;
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
  mineCoverSheet() {
    Column({ space: 14 }) {
      Text('编辑内容').fontSize(18).fontWeight(FontWeight.Bold);
      Button('更换图片')
        .type(ButtonType.ROUNDED_RECTANGLE)
        .width('100%').height(40).fontSize(16)
        .backgroundColor('#F1F3F5').fontColor('#1E252D')
        .onClick(() => { this.chooseMineCover(); });
    }
    .width('100%').padding({ left: 24, right: 24, top: 20, bottom: this.bottomInset + 15 });
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
    .backgroundColor(ImmersiveMaterial.fallbackBackground())
    .borderRadius(12)
    .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
    .shadow({ radius: 6, color: '#18000000', offsetX: 0, offsetY: 2 })
    .onClick(() => {
      if (iconName === 'software_settings') {
        this.openSoftwareSettings();
      } else if (iconName === 'favorites') {
        this.openMyFav();
      } else if (iconName === 'off') {
        this.logout();
      }
    });
  }

  private static levelTiers(): LevelTier[] {
    const tiers: LevelTier[] = [];
    for (let level: number = 0; level < 6; level++) {
      const tier: LevelTier = new LevelTier();
      tier.from = level;
      tier.to = level + 1;
      tier.exp = LEVEL_EXP_THRESHOLDS[level];
      tiers.push(tier);
    }
    return tiers;
  }

  private currentLevelSegment(): string {
    const level: number = this.authSession === null ? 0 : this.authSession.level;
    if (level >= 6) return 'LV6';
    return `LV${level}-LV${level + 1}`;
  }

  private expProgress(): number[] {
    const session: AuthSession | null = this.authSession;
    // 已满级或经验数据未取到时展示满进度
    if (session === null || session.expNext <= session.expMin) return [1, 1];
    const total: number = session.expNext - session.expMin;
    return [Math.min(Math.max(0, session.expCurrent - session.expMin), total), total];
  }

  private expProgressText(): string {
    const session: AuthSession | null = this.authSession;
    if (session === null || session.expCurrent <= 0) return '经验 --';
    if (session.expNext <= session.expMin) return `经验 ${session.expCurrent} · 已达最高等级`;
    return `${Math.max(0, session.expCurrent - session.expMin)}/${session.expNext - session.expMin}`;
  }

  @Builder
  levelTierRow(tier: LevelTier) {
    Row() {
      Text(`LV${tier.from}-LV${tier.to}`)
        .fontSize(13)
        .fontColor(tier.from === (this.authSession === null ? -1 : this.authSession.level)
          ? '#F08A24' : '#3E4854')
        .fontWeight(tier.from === (this.authSession === null ? -1 : this.authSession.level)
          ? FontWeight.Bold : FontWeight.Normal)
        .layoutWeight(1);
      Text(String(tier.exp))
        .fontSize(13)
        .fontColor(tier.from === (this.authSession === null ? -1 : this.authSession.level)
          ? '#F08A24' : '#858C94');
    }.width('100%').padding({ top: 5, bottom: 5 });
  }

  @Builder
  levelSheet() {
    if (this.levelSheetVisible) {
      Stack({ alignContent: Alignment.Center }) {
      Column({ space: 12 }) {
        // 顶部：当前所处等级分段
        Text(this.currentLevelSegment()).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#F08A24');
        // 中部：分段内经验进度条 + 具体积分
        Progress({ value: this.expProgress()[0], total: Math.max(1, this.expProgress()[1]),
          type: ProgressType.Linear })
          .color('#F08A24').width('100%').height(8);
        Text(this.expProgressText()).fontSize(12).fontColor('#858C94')
          .width('100%').textAlign(TextAlign.Center);
        Divider().color('#E9EDF0');
        ForEach(MineSidebar.levelTiers(), (tier: LevelTier) => {
          this.levelTierRow(tier);
        }, (tier: LevelTier) => `tier_${tier.from}`);
        Divider().color('#E9EDF0');
        Text('获取经验：每日登录、观看视频、投币、点赞、分享均可获得经验积分，具体数值以B站官方规则为准')
          .fontSize(10).fontColor('#A4A9AF').lineHeight(15).width('100%');
        Button('关闭').height(34).fontSize(13)
          .onClick((): void => { this.levelSheetVisible = false; });
      }
      .width('82%')
      .padding(20)
      .backgroundColor(Color.White)
      .borderRadius(16)
      .alignItems(HorizontalAlign.Start);
    }
    .width('100%').height('100%')
    .backgroundColor('#66000000')
    .onClick((): void => { this.levelSheetVisible = false; });
    }
  }

  build() {
    Column({ space: 14 }) {
      Stack() {
        this.mineCoverImage();
      }
      .width('100%').height(150)
      .onClick(() => { this.showMineCoverSheet = true; });

      Row({ space: 14 }) {
        if (this.authSession !== null && this.authSession.face !== '') {
          Image(this.authSession.face).width(104).height(104).borderRadius(52).objectFit(ImageFit.Cover)
            .onClick(() => { this.onAvatarTap(); })
            .gesture(LongPressGesture({ repeat: false, duration: 500 }).onAction((): void => {
              // 换头像（试行）：复用封面更换弹层
              this.showMineCoverSheet = true;
            }));
        } else {
          Image($r('app.media.user_me')).width(104).height(104).borderRadius(52).objectFit(ImageFit.Contain)
            .onClick(() => { this.onAvatarTap(); })
            .gesture(LongPressGesture({ repeat: false, duration: 500 }).onAction((): void => {
              this.showMineCoverSheet = true;
            }));
        }
        Column({ space: 5 }) {
          Row({ space: 6 }) {
            Text(this.authSession === null ? 'Pilihos 用户' : this.authSession.name)
              .fontSize(18).fontWeight(FontWeight.Bold).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            Text('LV' + (this.authSession === null ? '0' : String(this.authSession.level)))
              .margin({ left: 6 })
              .fontSize(11).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
              .backgroundColor('#F08A24').borderRadius(5)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 })
              .onClick((): void => { this.levelSheetVisible = true; });
          }.width('100%');
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
        .margin({ top: -24 })
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
    .backgroundColor('#F7F8FA')
    .alignItems(HorizontalAlign.Start)
    .bindSheet($$this.showMineCoverSheet, this.mineCoverSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true
    })
    // 等级成长弹层：树内 overlay 条件渲染（bindContentCover 呈现在部分场景不弹出）
    .overlay(this.levelSheet(), { align: Alignment.Center });
  }
}

@Component
export struct MessageSidebar {
  @Consume sidebar: number;
  @Consume topInset: number;
  @Consume bottomInset: number;

  @Builder
  messageBubble(label: string, count: string, iconName: string) {
    Column({ space: 6 }) {
      Stack() {
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
        .backgroundColor(ImmersiveMaterial.fallbackBackground())
        .borderRadius(26)
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
        .shadow({ radius: 6, color: '#22000000', offsetX: 0, offsetY: 2 });
        if (count !== '') {
          Text(count).fontSize(10).fontColor(Color.White).backgroundColor('#C51D2A')
            .borderRadius(12).padding({ left: 7, right: 7, top: 3, bottom: 3 })
            .position({ right: -4, top: -4 });
        }
      }
      Text(label).fontSize(12).textAlign(TextAlign.Center);
    }.layoutWeight(1).alignItems(HorizontalAlign.Center);
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

  build() {
    Column({ space: 18 }) {
      Row() {
        Button() {
          Image($r('app.media.fanhui_left')).width(24).height(24);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(42).height(42)
        .backgroundColor(ImmersiveMaterial.fallbackBackground())
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
        .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
        .onClick(() => { this.sidebar = 0; });
        Text('消息').fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.Black).layoutWeight(1);
        Text('清空').fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.Black);
      }.width('100%').alignItems(VerticalAlign.Center);
      Row({ space: 8 }) {
        this.messageBubble('回复我的', '3', 'message_reply');
        this.messageBubble('@我', '', 'at_me');
        this.messageBubble('收到的赞', '12', 'received_likes');
        this.messageBubble('系统通知', '', 'xiaoxi');
      }.width('100%');
      Column({ space: 0 }) {
        this.messageRow('社区中心', '举报进展反馈', '08-17', 'message_reply');
        this.messageRow('特别关注', '新的关注动态将在这里显示', '08-21', 'at_me');
        this.messageRow('系统通知', '欢迎使用 Pilihos', '今天', 'xiaoxi');
        this.messageRow('互动消息', '评论、点赞和回复将在这里显示', '更早', 'received_likes');
      }.width('100%');
    }
    .width('100%').height('100%')
    .padding({ top: this.topInset + 12, left: 22, right: 22, bottom: this.bottomInset + 20 })
    .backgroundColor('#F7F8FA')
    .alignItems(HorizontalAlign.Start);
  }
}
