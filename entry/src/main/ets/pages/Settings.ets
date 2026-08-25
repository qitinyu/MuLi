import router from '@ohos.router';
import { common, Want } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

@Entry
@Component
struct Settings {
  @State showAbout: boolean = false;
  @State topInset: number = 24;
  @State bottomInset: number = 8;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  private showInfo(title: string, message: string): void {
    promptAction.showDialog({
      title: title,
      message: message,
      buttons: [{ text: '知道了', color: '#1677A8' }]
    });
  }

  private openUrl(url: string): void {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url
      };
      this.context.startAbility(want).catch((): void => {
        promptAction.showToast({ message: '无法打开链接' });
      });
    } catch (error) {
      console.error('Pilihos external link failed: ' + String(error));
      promptAction.showToast({ message: '无法打开链接' });
    }
  }

  private goBack(): void {
    if (this.showAbout) {
      this.showAbout = false;
      return;
    }
    router.back();
  }

  onBackPress(): boolean {
    if (this.showAbout) {
      this.showAbout = false;
      return true;
    }
    return false;
  }

  build() {
    if (this.showAbout) {
      this.aboutPage();
    } else {
      this.settingsPage();
    }
  }

  @Builder
  pageHeader(title: string) {
    Row({ space: 10 }) {
      Button() {
        Image($r('app.media.fanhui_left')).width(24).height(24);
      }
      .type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
      .backgroundColor(Color.Transparent)
      .onClick(() => { this.goBack(); });
      Text(title).fontSize(22).fontWeight(FontWeight.Medium).layoutWeight(1);
    }
    .width('100%')
    .padding({ left: 12, right: 18, top: this.topInset + 8, bottom: 8 });
  }

  @Builder
  settingsPage() {
    Column() {
      this.pageHeader('设置');
      Scroll() {
        Column({ space: 10 }) {
          Text('外观').fontSize(18).fontWeight(FontWeight.Bold)
            .width('100%').margin({ top: 8, bottom: 2 });
          this.settingsCard('主题', '跟随系统', false);

          Text('播放器').fontSize(18).fontWeight(FontWeight.Bold)
            .width('100%').margin({ top: 10, bottom: 2 });
          this.settingsCard('播放质量', '自动选择', false);
          this.settingsCard('弹幕显示', '默认开启', false);

          Text('关于').fontSize(18).fontWeight(FontWeight.Bold)
            .width('100%').margin({ top: 10, bottom: 2 });
          this.settingsCard('关于 Pilihos', '应用信息与版本', true);
        }
        .width('100%')
        .padding({ left: 18, right: 18, bottom: this.bottomInset + 18 });
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off);
    }
    .width('100%').height('100%')
    .backgroundColor('#F7F8FA')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }

  @Builder
  settingsCard(title: string, detail: string, openAbout: boolean) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(title).fontSize(16).fontColor('#1E252D');
        Text(detail).fontSize(12).fontColor('#858C94');
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
      Image($r('app.media.jinxin_right')).width(18).height(18);
    }
    .width('100%').height(64)
    .padding({ left: 16, right: 14 })
    .backgroundColor(Color.White)
    .borderRadius(10)
    .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 })
    .onClick(() => {
      if (openAbout) this.showAbout = true;
    });
  }

  @Builder
  aboutPage() {
    Column() {
      this.pageHeader('关于 Pilihos');
      Scroll() {
        Column({ space: 10 }) {
          Column({ space: 8 }) {
            Image($r('app.media.app_logo')).width(112).height(112).borderRadius(22);
            Text('Pilihos').fontSize(28).fontWeight(FontWeight.Bold);
            Text('Version 1.0.1').fontSize(15).fontColor('#646A73');
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 18, bottom: 10 });

          Row({ space: 10 }) {
            this.aboutInfoCard('软件说明', 'Pilihos 是B站鸿蒙移植版,开源无广,纯净高效。');
            this.aboutInfoCard('隐私政策', '应用仅在登录和请求服务时使用必要数据。');
          }.width('100%');
          Row({ space: 10 }) {
            this.aboutInfoCard('软件协议', '本软件采用 MIT 开源协议');
            this.aboutInfoCard('版本日志', '当前版本：1.0.0。');
          }.width('100%');

          this.aboutLinkCard('用户反馈', 'https://github.com/qitinyu/Pilihos/discussions/');
          this.aboutLinkCard('开源链接', 'https://github.com/qitinyu/Pilihos');
          this.aboutLinkCard('软件更新', 'https://github.com/qitinyu/Pilihos/releases');
          this.aboutLinkCard('上游仓库', 'https://github.com/YQAMM/Sumy-Music');
        }
        .width('100%')
        .padding({ left: 18, right: 18, bottom: this.bottomInset + 18 });
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off);
    }
    .width('100%').height('100%')
    .backgroundColor('#F8F7FF')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }

  @Builder
  aboutInfoCard(label: string, message: string) {
    Row() {
      Text(label).fontSize(15).fontColor('#1E252D').layoutWeight(1);
      Image($r('app.media.jinxin_right')).width(17).height(17);
    }
    .layoutWeight(1).height(60)
    .padding({ left: 14, right: 12 })
    .backgroundColor(Color.White)
    .borderRadius(10)
    .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 })
    .onClick(() => { this.showInfo(label, message); });
  }

  @Builder
  aboutLinkCard(label: string, url: string) {
    Row({ space: 8 }) {
      Text(label).fontSize(15).fontColor('#1E252D').layoutWeight(1);
      Text('浏览器打开').fontSize(11).fontColor('#646A73');
      Image($r('app.media.jinxin_right')).width(17).height(17);
    }
    .width('100%').height(60)
    .padding({ left: 14, right: 12 })
    .backgroundColor(Color.White)
    .borderRadius(10)
    .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 })
    .onClick(() => { this.openUrl(url); });
  }
}