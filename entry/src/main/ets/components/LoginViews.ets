import common from '@ohos.app.ability.common';
import web_webview from '@ohos.web.webview';
import { AuthService, AuthSession } from '../services/AuthService';
import { AdvancedFeatures } from '../utils/AdvancedFeatures';

@Component
export struct LoginPage {
  @Consume loginVisible: boolean;
  @Consume webLoginVisible: boolean;
  @Consume loginNotice: string;
  @Consume authSession: AuthSession | null;
  @Consume sidebar: number;
  @Consume topInset: number;
  @Consume bottomInset: number;

  private closeLoginPage(): void {
    this.loginVisible = false;
    this.sidebar = 0;
  }

  private openWebLogin(): void {
    this.loginNotice = '';
    this.webLoginVisible = true;
  }

  private async logout(): Promise<void> {
    await AuthService.logout();
    this.authSession = null;
    this.loginNotice = '已退出登录';
  }

  build() {
    Column() {
      Row({ space: 14 }) {
        Button() {
          Image($r('app.media.fanhui_left')).width(26).height(26);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(46).height(46)
        .backgroundColor(Color.Transparent)
        .onClick(() => { this.closeLoginPage(); });
        Text('登录').fontSize(26).fontWeight(FontWeight.Medium);
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: this.topInset + 8, bottom: 8 });

      if (this.authSession !== null) {
        Row({ space: 10 }) {
          if (this.authSession.face !== '') {
            Image(this.authSession.face).width(42).height(42).borderRadius(21);
          } else {
            Row().width(42).height(42).borderRadius(21).backgroundColor('#DCE3EF');
          }
          Column({ space: 2 }) {
            Text(this.authSession.name).fontSize(16).fontWeight(FontWeight.Bold);
            Text('UID ' + this.authSession.uid).fontSize(12).fontColor('#858C94');
          }.layoutWeight(1).alignItems(HorizontalAlign.Start);
          Button('退出').height(34).fontSize(13).onClick(() => { this.logout(); });
        }.width('100%').padding({ left: 18, right: 18, bottom: 12 });
      }

      Scroll() {
        Column({ space: 18 }) {
          Text('请使用哔哩哔哩官方页面登录')
            .fontSize(23).fontWeight(FontWeight.Medium)
            .margin({ top: 28, bottom: 10 });
          Button('打开官方登录')
            .type(ButtonType.ROUNDED_RECTANGLE).width(220).height(48)
            .fontColor('#1677A8').backgroundColor('#E9F4F8')
            .onClick(() => { this.openWebLogin(); });
          if (this.loginNotice !== '') {
            Text(this.loginNotice).fontSize(13).fontColor('#C51D2A')
              .textAlign(TextAlign.Center).width('100%');
          }
          Text('登录状态会安全保存在本机，重启应用后自动恢复。')
            .fontSize(12).fontColor('#A4A9AF')
            .textAlign(TextAlign.Center).width('100%')
            .margin({ top: 28, bottom: 24 });
        }
        .width('100%')
        .padding({ left: 30, right: 30, bottom: this.bottomInset + 20 })
        .alignItems(HorizontalAlign.Center);
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }
    .width('100%').height('100%').backgroundColor('#FAFBFC');
  }
}

@Component
export struct WebLoginPage {
  @Consume webLoginVisible: boolean;
  @Consume loginVisible: boolean;
  @Consume sidebar: number;
  @Consume loginNotice: string;
  @Consume authSession: AuthSession | null;
  @Consume topInset: number;
  @State webLoginStatus: string = '请在官方页面完成登录、验证码和人机校验';
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private webController: web_webview.WebviewController = new web_webview.WebviewController();

  private async syncWebLoginCookie(): Promise<void> {
    if (!this.webLoginVisible) return;
    try {
      let cookie: string = '';
      if (AdvancedFeatures.isWebCookieManagerEnabled()) {
        cookie = await web_webview.WebCookieManager.fetchCookie('https://www.bilibili.com');
      } else {
        try {
          cookie = web_webview.WebCookieManager.getCookie('https://www.bilibili.com');
        } catch (e) {
          console.error('Pilihos web cookie fetch fallback failed: ' + String(e));
        }
      }
      if (cookie === '' || !cookie.includes('SESSDATA=')) return;
      const session: AuthSession = await AuthService.validateCookie(cookie, this.context);
      this.authSession = session;
      this.loginNotice = '登录成功，欢迎 ' + session.name;
      this.webLoginStatus = '登录成功';
      this.webLoginVisible = false;
      this.loginVisible = false;
      this.sidebar = 0;
    } catch (error) {
      this.webLoginStatus = '等待官方登录完成';
      console.error('Pilihos web login cookie sync failed: ' + String(error));
    }
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Button() {
          Image($r('app.media.fanhui_left')).width(24).height(24);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
        .backgroundColor(Color.Transparent)
        .onClick(() => { this.webLoginVisible = false; });
        Text('官方登录').fontSize(20).fontWeight(FontWeight.Medium)
          .layoutWeight(1);
        Button('完成登录').height(38)
          .onClick(() => { this.syncWebLoginCookie(); });
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: this.topInset + 8, bottom: 6 });
      Text(this.webLoginStatus).fontSize(12).fontColor('#1677A8')
        .width('100%').padding({ left: 18, right: 18, bottom: 6 });
      Web({ src: 'https://passport.bilibili.com/login', controller: this.webController })
        .width('100%').layoutWeight(1)
        .onPageEnd(() => { this.syncWebLoginCookie(); });
    }
    .width('100%').height('100%')
    .backgroundColor('#FAFBFC');
  }
}
