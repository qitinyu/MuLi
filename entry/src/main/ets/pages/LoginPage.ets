import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { MaterialScope } from '../common/Materials';
import { PAGE_PADDING } from '../common/DesignSpec';
import { QrSession, QR_EXPIRED, QR_SCANNED, QR_SUCCESS, UserProfile } from '../model/BiliModels';
import { AuthService, QrPollResult, SmsSendResult } from '../services/AuthService';
import { BiliCookie } from '../services/BiliHttp';

/** 轮询间隔：bilibili 官方建议 2 秒一次 */
const POLL_INTERVAL: number = 2000;
/** 验证码重发倒计时（秒） */
const SMS_COUNTDOWN: number = 60;

/**
 * 登录页（二级页，全局路由 name = 'login'）。
 *
 * 双页切换（V2.0.3）：
 * - 扫码登录：generate 拿二维码 → 每 2 秒 poll → code=0 时 cookie 落盘 → 拉资料并 bump loginTick；
 * - 手机号登录：发送短信验证码 → 校验登录 → 同样走 cookie 落盘与资料刷新。
 *
 * 修复「扫码成功却提示无法获取登录信息」：
 * 1. poll 成功先用 data.url 的 query 兜底拼 cookie（部分网络栈不透传跨域 Set-Cookie）；
 * 2. 资料接口带重试，仍失败但 cookie 有效时按登录成功放行，只提示「资料稍后同步」。
 */
@Component
export struct LoginPage {
  pathStack: NavPathStack | undefined = undefined;
  /** 'qr' 扫码 / 'phone' 手机号 */
  @State mode: string = 'qr';
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  @State qrUrl: string = '';
  @State statusText: string = '正在获取二维码';
  @State expired: boolean = false;
  @State loading: boolean = true;
  @State failed: boolean = false;
  @State tel: string = '';
  @State smsCode: string = '';
  @State countdown: number = 0;
  @State submitting: boolean = false;
  /** 验证码是否真的发送成功：没发出去就不让提交，避免「没收到码却报验证码错误」 */
  @State codeSent: boolean = false;
  /** 手机号登录的内联错误提示（风控 / 网络 / 服务端文案） */
  @State smsError: string = '';
  @State smsCaptcha: boolean = false;
  /** 页面是否已关闭：close() 幂等，避免网页登录与本站收尾重复 pop */
  private closed: boolean = false;
  /** 官方网页登录成功后由 loginTick 通知本页退出 */
  @StorageLink('loginTick') @Watch('onLoginTick') loginTick: number = 0;
  private qrKey: string = '';
  private pollTimer: number = -1;
  private countdownTimer: number = -1;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.materialLevel = MaterialScope.detectLevel();
    this.start();
  }

  aboutToDisappear(): void {
    this.stopPolling();
    this.stopCountdown();
  }

  // ---------- 扫码 ----------

  private start(): void {
    this.loading = true;
    this.failed = false;
    this.expired = false;
    this.statusText = '正在获取二维码';
    this.fetchQr();
  }

  private async fetchQr(): Promise<void> {
    try {
      const session: QrSession = await AuthService.generateQr();
      this.qrUrl = session.url;
      this.qrKey = session.key;
      this.loading = false;
      this.statusText = '打开哔哩哔哩 App 扫一扫';
      this.startPolling();
    } catch (err) {
      this.loading = false;
      this.failed = true;
      this.statusText = err instanceof Error ? err.message : '二维码获取失败';
    }
  }

  private startPolling(): void {
    this.stopPolling();
    this.pollTimer = setInterval(() => {
      this.poll();
    }, POLL_INTERVAL);
  }

  private stopPolling(): void {
    if (this.pollTimer !== -1) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private async poll(): Promise<void> {
    if (this.qrKey.length === 0) {
      return;
    }
    try {
      const result: QrPollResult = await AuthService.pollQr(this.qrKey);
      if (result.code === QR_SUCCESS) {
        this.stopPolling();
        this.statusText = '登录成功';
        await this.finishLogin(result.filled);
        return;
      }
      if (result.code === QR_SCANNED) {
        this.statusText = '已扫码，请在手机上确认';
        return;
      }
      if (result.code === QR_EXPIRED) {
        this.stopPolling();
        this.expired = true;
        this.statusText = '二维码已过期，请刷新';
        return;
      }
      // 其余（86101 未扫码 / 网络抖动）继续轮询
      if (!this.expired) {
        this.statusText = '打开哔哩哔哩 App 扫一扫';
      }
    } catch (err) {
      // 单次轮询失败不打断流程，下一轮继续
    }
  }

  /** 扫码与短信登录共用的收尾：落盘 cookie → 拉资料 → 通知各页签 */
  private async finishLogin(filled: boolean): Promise<void> {
    if (!filled && !BiliCookie.isLogin()) {
      this.statusText = '未取到登录凭证，请重新扫码';
      this.failed = true;
      return;
    }
    try {
      await BiliCookie.saveAuth(this.context(), BiliCookie.authCookie);
    } catch (err) {
      // 落盘失败不影响本次会话
    }
    await this.complete();
  }

  private async complete(): Promise<void> {
    const profile: UserProfile = await AuthService.loadProfileWithRetry(3);
    AppStorage.setOrCreate('loginTick', Date.now());
    if (profile.isLogin) {
      this.toast(`欢迎回来，${profile.name}`);
      this.close();
      return;
    }
    if (BiliCookie.isLogin()) {
      // cookie 已拿到但资料接口没通过：放行不卡流程，同时给出更有效的下一步
      this.toast('登录凭证已保存；若资料为空，请改用官方网页登录');
      this.close();
      return;
    }
    this.statusText = '登录凭证无效，请重新登录';
    this.failed = true;
  }

  private close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    if (this.pathStack !== undefined) {
      this.pathStack.pop();
    }
  }

  /** 网页登录页完成登录后会 bump loginTick，这里同步退出本页 */
  private onLoginTick(): void {
    if (this.closed) {
      return;
    }
    if (BiliCookie.isLogin()) {
      this.statusText = '登录成功';
      this.close();
    }
  }

  // ---------- 手机号 ----------

  private startCountdown(): void {
    this.stopCountdown();
    this.countdown = SMS_COUNTDOWN;
    this.countdownTimer = setInterval(() => {
      if (this.countdown <= 1) {
        this.stopCountdown();
        this.countdown = 0;
        return;
      }
      this.countdown = this.countdown - 1;
    }, 1000);
  }

  private stopCountdown(): void {
    if (this.countdownTimer !== -1) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = -1;
    }
  }

  private validTel(): boolean {
    if (this.tel.length !== 11) {
      return false;
    }
    for (let i = 0; i < this.tel.length; i++) {
      const code: number = this.tel.charCodeAt(i);
      if (code < 48 || code > 57) {
        return false;
      }
    }
    return true;
  }

  private async sendCode(): Promise<void> {
    if (this.countdown > 0) {
      return;
    }
    if (!this.validTel()) {
      this.toast('请输入 11 位手机号');
      return;
    }
    this.smsError = '';
    this.smsCaptcha = false;
    try {
      const result: SmsSendResult = await AuthService.sendSmsCode(this.tel);
      if (result.ok) {
        this.codeSent = true;
        this.startCountdown();
        this.toast('验证码已发送');
        return;
      }
      this.codeSent = false;
      this.smsCaptcha = result.captchaRequired;
      this.smsError = result.captchaRequired
        ? '哔哩哔哩要求先完成官方图形校验，内置短信入口无法直接发码'
        : (result.message.length > 0 ? result.message : `验证码发送失败（${result.code}）`);
    } catch (err) {
      this.codeSent = false;
      this.smsError = err instanceof Error ? err.message : '网络异常，请稍后重试';
    }
  }

  /** 打开官方网页登录（页面内完成图形校验与短信发码，成功后自动取 cookie） */
  private openWebLogin(): void {
    if (this.pathStack !== undefined) {
      this.pathStack.pushPathByName('weblogin', '');
    }
  }

  private async submitSms(): Promise<void> {
    if (this.submitting) {
      return;
    }
    if (!this.validTel()) {
      this.toast('请输入 11 位手机号');
      return;
    }
    if (!this.codeSent) {
      this.smsError = '请先点「获取验证码」，收到短信后再提交';
      this.toast('还没有成功发送验证码');
      return;
    }
    if (this.smsCode.length < 4) {
      this.toast('请输入收到的验证码');
      return;
    }
    this.submitting = true;
    try {
      await AuthService.loginBySms(this.tel, this.smsCode);
      if (!BiliCookie.isLogin()) {
        this.smsError = '登录校验未通过，请重试或改用扫码登录';
        return;
      }
      await BiliCookie.saveAuth(this.context(), BiliCookie.authCookie);
      await this.complete();
    } catch (err) {
      this.smsError = err instanceof Error ? err.message : '登录失败，请稍后重试';
      this.toast(this.smsError);
    } finally {
      this.submitting = false;
    }
  }

  // ---------- 通用 ----------

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text, duration: 1800 });
    } catch (err) {
      // 提示失败不影响主流程
    }
  }

  private switchMode(mode: string): void {
    if (this.mode === mode) {
      return;
    }
    this.mode = mode;
    if (mode === 'phone') {
      this.stopPolling();
    } else if (this.qrKey.length > 0) {
      this.startPolling();
    } else {
      this.start();
    }
  }

  @Builder
  modeSwitch() {
    Row() {
      Column({ space: 6 }) {
        Text('扫码登录')
          .fontSize(15)
          .fontWeight(this.mode === 'qr' ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.mode === 'qr' ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
        Row()
          .width(this.mode === 'qr' ? 44 : 0)
          .height(2.5)
          .backgroundColor($r('app.color.brand_primary'))
          .borderRadius(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.switchMode('qr');
      })

      Column({ space: 6 }) {
        Text('手机号登录')
          .fontSize(15)
          .fontWeight(this.mode === 'phone' ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.mode === 'phone' ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
        Row()
          .width(this.mode === 'phone' ? 56 : 0)
          .height(2.5)
          .backgroundColor($r('app.color.brand_primary'))
          .borderRadius(2)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.switchMode('phone');
      })
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  qrBlock() {
    Column({ space: 14 }) {
      Stack() {
        Column()
          .width(228)
          .height(228)
          .backgroundColor(Color.White)
          .borderRadius(14)

        if (this.qrUrl.length > 0) {
          QRCode(this.qrUrl)
            .width(200)
            .height(200)
            .color(Color.Black)
            .backgroundColor(Color.White)
        } else {
          Column({ space: 8 }) {
            if (this.failed) {
              SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
                .fontSize(30)
                .fontColor([$r('app.color.text_tertiary')])
            } else {
              LoadingProgress()
                .width(32)
                .height(32)
                .color($r('app.color.brand_primary'))
            }
          }
          .justifyContent(FlexAlign.Center)
        }

        // 过期遮罩
        if (this.expired) {
          Column({ space: 10 }) {
            Text('二维码已过期')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Row() {
              Text('点击刷新')
                .fontSize(13)
                .fontColor($r('app.color.text_on_brand'))
                .padding({ left: 16, right: 16, top: 7, bottom: 7 })
                .backgroundColor($r('app.color.brand_primary'))
                .borderRadius(16)
            }
            .onClick(() => {
              this.start();
            })
          }
          .width(228)
          .height(228)
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#EEFFFFFF')
          .borderRadius(14)
        }
      }
      .width(228)
      .height(228)

      Text(this.statusText)
        .fontSize(13)
        .fontColor(this.expired || this.failed ? $r('app.color.text_tertiary') : $r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)

      Text('改用官方网页登录')
        .fontSize(12)
        .fontColor($r('app.color.brand_primary'))
        .padding({ top: 2, bottom: 2, left: 8, right: 8 })
        .onClick(() => {
          this.openWebLogin();
        })

      if (this.failed) {
        Row() {
          Text('重新获取')
            .fontSize(13)
            .fontColor($r('app.color.text_on_brand'))
            .padding({ left: 20, right: 20, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.brand_primary'))
            .borderRadius(18)
        }
        .onClick(() => {
          this.start();
        })
      }
    }
    .width('100%')
    .padding({ top: 24, bottom: 22 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
  }

  @Builder
  phoneBlock() {
    Column({ space: 14 }) {
      Text('未注册的手机号将自动创建哔哩哔哩账号')
        .width('100%')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))

      TextInput({ text: this.tel, placeholder: '请输入手机号' })
        .type(InputType.PhoneNumber)
        .maxLength(11)
        .fontSize(14)
        .height(46)
        .backgroundColor($r('app.color.bg_field'))
        .borderRadius(12)
        .onChange((value: string) => {
          this.tel = value;
        })

      Row({ space: 10 }) {
        TextInput({ text: this.smsCode, placeholder: '请输入验证码' })
          .type(InputType.Number)
          .maxLength(6)
          .fontSize(14)
          .height(46)
          .layoutWeight(1)
          .backgroundColor($r('app.color.bg_field'))
          .borderRadius(12)
          .onChange((value: string) => {
            this.smsCode = value;
          })

        Text(this.countdown > 0 ? `${this.countdown}s` : '获取验证码')
          .fontSize(13)
          .fontColor(this.countdown > 0
            ? $r('app.color.text_tertiary') : $r('app.color.brand_primary'))
          .padding({ left: 14, right: 14, top: 12, bottom: 12 })
          .backgroundColor($r('app.color.brand_tint'))
          .borderRadius(12)
          .onClick(() => {
            this.sendCode();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 发送失败 / 风控要求图形校验时的内联说明（附官方网页登录入口）
      if (this.smsError.length > 0) {
        Column({ space: 10 }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
              .fontSize(14)
              .fontColor([$r('app.color.danger')])
            Text(this.smsError)
              .fontSize(12)
              .lineHeight(18)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          if (this.smsCaptcha) {
            Row({ space: 10 }) {
              Text('打开官方网页登录')
                .fontSize(12)
                .fontColor($r('app.color.text_on_brand'))
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .backgroundColor($r('app.color.brand_primary'))
                .borderRadius(14)
                .onClick(() => {
                  this.openWebLogin();
                })
              Text('改用扫码登录')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .backgroundColor($r('app.color.bg_field'))
                .borderRadius(14)
                .onClick(() => {
                  this.switchMode('qr');
                })
            }
            .width('100%')
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.bg_field'))
        .borderRadius(12)
        .alignItems(HorizontalAlign.Start)
      }

      Row() {
        Text(this.submitting ? '登录中…' : '登录')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_on_brand'))
      }
      .width('100%')
      .height(46)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.brand_primary'))
      .borderRadius(23)
      .opacity(this.submitting || !this.codeSent ? 0.5 : 1)
      .onClick(() => {
        this.submitSms();
      })

      Text('哔哩哔哩对短信登录有图形校验限制，未收到验证码时请使用扫码或官方网页登录')
        .width('100%')
        .fontSize(11)
        .lineHeight(17)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 18, bottom: 20 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  hintBlock() {
    Column({ space: 8 }) {
      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
          .fontSize(15)
          .fontColor([$r('app.color.brand_primary')])
        Text('登录即代表同意哔哩哔哩的用户协议')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 6 }) {
        SymbolGlyph($r('sys.symbol.lock'))
          .fontSize(15)
          .fontColor([$r('app.color.text_tertiary')])
        Text('登录信息仅保存在本机，用于同步关注、动态与稍后再看')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(14)
  }

  build() {
    HdsNavDestination() {
      Scroll(this.scroller) {
        Column({ space: 14 }) {
          Row()
            .width('100%')
            .height(64)
          this.modeSwitch()
          if (this.mode === 'qr') {
            this.qrBlock()
          } else {
            this.phoneBlock()
          }
          this.hintBlock()
          Row()
            .width('100%')
            .height(40)
        }
        .width('100%')
        .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .titleBar({
      content: {
        title: { mainTitle: '登录' }
      },
      style: {
        originalStyle: {
          contentStyle: {
            titleStyle: { mainTitleColor: $r('app.color.text_primary') },
            menuStyle: { iconColor: $r('app.color.text_primary') },
            backIconStyle: { iconColor: $r('app.color.text_primary') }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            titleStyle: { mainTitleColor: $r('app.color.text_primary') },
            menuStyle: { iconColor: $r('app.color.text_primary') },
            backIconStyle: { iconColor: $r('app.color.text_primary') }
          }
        },
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(64)
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: this.materialLevel
        }
      }
    })
    .hideBackButton(false)
    .bindToScrollable([this.scroller])
    .backgroundColor($r('app.color.bg_page'))
  }
}
