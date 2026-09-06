import router from '@ohos.router';
import { BusinessError } from '@kit.BasicServicesKit';
import { picker } from '@kit.CoreFileKit';
import { preferences } from '@kit.ArkData';
import { AuthSession } from '../services/AuthService';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import { FormatUtils } from '../utils/FormatUtils';

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
  private uiPreferences: preferences.Preferences | null = null;

  aboutToAppear(): void {
    this.loadMineCover();
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
    .systemMaterial(ImmersiveMaterial.thin())
    .shadow({ radius: 6, color: '#18000000', offsetX: 0, offsetY: 2 })
    .onClick(() => {
      if (iconName === 'software_settings') {
        this.openSoftwareSettings();
      }
    });
  }

  build() {
    Column({ space: 14 }) {
      Stack() {
        this.mineCoverImage();
        Button() {
          Image($r('app.media.jinxin_right')).width(22).height(22);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
        .backgroundColor(ImmersiveMaterial.fallbackBackground())
        .systemMaterial(ImmersiveMaterial.thin())
        .borderRadius(22)
        .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
        .position({ top: 12, right: 12 })
        .zIndex(2)
        .onClick(() => { this.sidebar = 0; });
      }
      .width('100%').height(150)
      .onClick(() => { this.showMineCoverSheet = true; });

      Row({ space: 14 }) {
        if (this.authSession !== null && this.authSession.face !== '') {
          Image(this.authSession.face).width(88).height(88).borderRadius(44).objectFit(ImageFit.Cover);
        } else {
          Image($r('app.media.user_me')).width(88).height(88).borderRadius(44).objectFit(ImageFit.Contain);
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
              .padding({ left: 5, right: 5, top: 2, bottom: 2 });
          }.width('100%');
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
          .margin({ top: 22 });
      }.width('100%').height(92)
        .margin({ top: -36 })
        .alignItems(VerticalAlign.Top)
        .onClick(() => {
          this.loginVisible = true;
          this.sidebar = 0;
          this.loginNotice = '';
        });

      Row({ space: 8 }) {
        this.mineStat(this.authSession === null ? '0' : FormatUtils.formatCount(this.authSession.dynamicCount), '动态');
        this.mineStat(this.authSession === null ? '0' : FormatUtils.formatCount(this.authSession.followingCount), '关注');
        this.mineStat(this.authSession === null ? '0' : FormatUtils.formatCount(this.authSession.followerCount), '粉丝');
      }.width('100%');

      Grid() {
        GridItem() { this.mineGridAction('offline_cache', '离线缓存', true); }
        GridItem() { this.mineGridAction('bofang', '观看记录', true); }
        GridItem() { this.mineGridAction('subscriptions', '我的订阅', true); }
        GridItem() { this.mineGridAction('watch_later', '稍后再看', true); }
        GridItem() { this.mineGridAction('favorites', '我的收藏', true); }
        GridItem() { this.mineGridAction('software_settings', '软件设置', true); }
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
    });
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
        .systemMaterial(ImmersiveMaterial.thin())
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
        .systemMaterial(ImmersiveMaterial.thin())
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
