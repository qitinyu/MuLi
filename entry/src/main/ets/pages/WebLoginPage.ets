import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { MaterialScope } from '../common/Materials';
import { AuthService } from '../services/AuthService';
import { BiliCookie, J } from '../services/BiliHttp';
import { UserProfile } from '../model/BiliModels';

/** 官方登录页地址：网页里可以正常完成图形校验与短信发码 */
const LOGIN_URL: string = 'https://passport.bilibili.com/login?gourl=https%3A%2F%2Fwww.bilibili.com';
/** 用移动端 UA，避免打开桌面版布局 */
const MOBILE_UA: string =
  'Mozilla/5.0 (Linux; Android 13; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
/** 取 cookie 的轮询间隔（毫秒） */
const COOKIE_INTERVAL: number = 1200;
/** 在页面内复核登录态的轮询间隔 / 次数 */
const PROBE_INTERVAL: number = 350;
const PROBE_TIMES: number = 10;

/**
 * 官方网页登录（二级路由 name = 'weblogin'）。
 *
 * 为什么需要它：passport 的短信接口要求先过 geetest 图校验（返回「验证码错误」），
 * 内置表单无法完成校验，而官方登录页自带校验，登录成功后在 WebView 里下发 cookie。
 *
 * 取 cookie 的顺序（V2.0.3 修订）：
 * 1. 先用 `document.cookie` 读当前页面的 cookie —— 这是浏览器真正会发给该域名的值，
 *    比 WebCookieManager 的域视图更可靠（后者可能给出同名旧值）；
 * 2. 再回退到 WebCookieManager（www / passport 两个域各读一次）。
 *
 * 复核方式：不再把 WebView 导航到 nav 接口（那会把登录页顶掉），
 * 改成在页面里 `fetch` nav 接口再读回结果，页面保持不动，失败时用户可以直接重试。
 */
@Component
export struct WebLoginPage {
  pathStack: NavPathStack | undefined = undefined;
  /** 'reset' 表示进入前清空 WebView cookie 与本机登录态（登录态已失效时从我的页带过来） */
  @Prop mode: string = '';
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  @State progress: number = 0;
  @State tip: string = '在页面内完成登录，提示短信验证时请在本页输入验证码';
  @State done: boolean = false;
  /** 登录态没被原生接口认下来，需要用户在本页重新登录 */
  @State needRelogin: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private timer: number = -1;
  /** 进入页面时 WebView 里已有的 SESSDATA：用来识别「历史残留 cookie」 */
  private initialSess: string = '';

  aboutToAppear(): void {
    this.materialLevel = MaterialScope.detectLevel();
    this.timer = setInterval(() => {
      this.tryFetchCookie();
    }, COOKIE_INTERVAL);
  }

  /**
   * Web 控制器就绪。
   *
   * 这一步很关键：如果 WebView 里本来就躺着上次登录留下的 SESSDATA，
   * 页面一加载就会被当成「已登录」，于是保存了一份服务端早已失效的 cookie，
   * 结果就是「显示已登录但没有任何数据」。所以先记下初始值，跳过它。
   */
  private onWebReady(): void {
    this.initialSess = this.readSessFromWeb();
    console.info(`MuLiAuth weblogin initial sessLen=${this.initialSess.length} mode=${this.mode}`);
    // 从「我的页 · 登录态未生效」进来时，先清掉那份已被服务端判废的 cookie，
    // 否则登录页会带着它自动登录，用户怎么登拿到的都还是同一份废凭证。
    if (this.mode === 'reset') {
      this.resetAndReload();
    }
  }

  /** 读 WebView 里的 SESSDATA：document.cookie 优先，退回 WebCookieManager */
  private readSessFromWeb(): string {
    // 同步接口拿不到 document.cookie，这里只用它记录初始值，
    // 真正的采信发生在 tryFetchCookie 的异步读取里。
    try {
      const raw: string = webview.WebCookieManager.fetchCookieSync('https://www.bilibili.com');
      return WebLoginPage.sessOf(raw);
    } catch (err) {
      return '';
    }
  }

  private static sessOf(raw: string): string {
    if (raw === undefined || raw === null || raw.length === 0) {
      return '';
    }
    const segments: Array<string> = raw.split(';');
    for (let i = 0; i < segments.length; i++) {
      const segment: string = segments[i].trim();
      const eq: number = segment.indexOf('=');
      if (eq > 0 && segment.substring(0, eq) === 'SESSDATA') {
        return segment.substring(eq + 1);
      }
    }
    return '';
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  private stopTimer(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private startTimer(): void {
    this.stopTimer();
    this.timer = setInterval(() => {
      this.tryFetchCookie();
    }, COOKIE_INTERVAL);
  }

  /** 从页面里读 cookie：命中 SESSDATA 就收尾登录 */
  private async tryFetchCookie(): Promise<void> {
    if (this.done) {
      return;
    }
    let raw: string = await this.readPageCookie();
    let sess: string = WebLoginPage.sessOf(raw);
    if (sess.length === 0) {
      raw = this.readCookieManager();
      sess = WebLoginPage.sessOf(raw);
    }
    if (sess.length === 0) {
      return;
    }
    // 记录 SESSDATA 指纹（长度 + 前 6 位）：只有它变了才说明用户真的完成了一次新登录。
    // 「登录后状态没变化」这类问题，先看这行日志就知道 cookie 到底有没有换。
    console.info(`MuLiAuth weblogin sess len=${sess.length} head=${sess.substring(0, 6)} ` +
      `initialLen=${this.initialSess.length} same=${sess === this.initialSess}`);
    // 和进入页面时是同一份 SESSDATA：说明用户还没完成登录，
    // 这只是上次残留的失效 cookie，采信它就会「显示已登录但没有数据」。
    if (this.initialSess.length > 0 && sess === this.initialSess) {
      return;
    }
    if (!BiliCookie.mergeRawCookie(raw)) {
      return;
    }
    await this.finish();
  }

  /** document.cookie：当前页面真正持有的 cookie（含 httpOnly 之外的登录三件套） */
  private async readPageCookie(): Promise<string> {
    try {
      const text: string = await this.controller.runJavaScript('document.cookie');
      return text === undefined || text === null ? '' : `${text}`;
    } catch (err) {
      return '';
    }
  }

  /** WebCookieManager 兜底：www 与 passport 两个域都读，合并后返回 */
  private readCookieManager(): string {
    let raw: string = '';
    try {
      raw = webview.WebCookieManager.fetchCookieSync('https://www.bilibili.com');
    } catch (err) {
      raw = '';
    }
    try {
      const passportRaw: string = webview.WebCookieManager.fetchCookieSync('https://passport.bilibili.com');
      if (passportRaw.length > 0) {
        raw = raw.length > 0 ? `${raw}; ${passportRaw}` : passportRaw;
      }
    } catch (err) {
      // 取不到 passport 域就只用 www 域
    }
    return raw;
  }

  private async finish(): Promise<void> {
    this.done = true;
    this.stopTimer();
    this.tip = '登录成功，正在同步资料';
    try {
      const ctx: common.UIAbilityContext = this.context();
      await BiliCookie.saveAuth(ctx, BiliCookie.authCookie);
      // WebView 的 buvid3 必须跟着落盘，否则下次启动换成 spi 指纹，
      // 已有的登录 cookie 会被服务端判为「来自别的设备」。
      await BiliCookie.persistFingerprint(ctx);
    } catch (err) {
      // 落盘失败不影响本次会话
    }
    const profile: UserProfile = await AuthService.loadProfileWithRetry(2);
    if (profile.isLogin && !profile.publicOnly) {
      AppStorage.setOrCreate('loginTick', Date.now());
      this.toast(`欢迎回来，${profile.name}`);
      if (this.pathStack !== undefined) {
        this.pathStack.pop();
      }
      return;
    }
    // 原生接口没通过登录态校验：在页面里 fetch 一次 nav 复核，页面保持不动
    this.tip = '正在用浏览器校验登录态…';
    const nav: Record<string, Object> | null = await this.probeNavInPage();
    const browserProfile: UserProfile | null = nav === null ? null : WebLoginPage.profileOfNav(nav);
    if (browserProfile !== null) {
      await this.saveBrowserCookie();
      AuthService.adoptProfile(browserProfile);
      AppStorage.setOrCreate('loginTick', Date.now());
      this.toast(`欢迎回来，${browserProfile.name}`);
      this.tip = '登录成功（浏览器已确认）';
      if (this.pathStack !== undefined) {
        this.pathStack.pop();
      }
      return;
    }
    // 浏览器里也拿不到登录态：cookie 本身无效，需要用户在本页重新登录
    this.done = false;
    this.needRelogin = true;
    this.initialSess = '';
    this.tip = '登录态未生效，请在本页重新登录一次';
    this.toast('登录态未生效，请重新登录');
    this.startTimer();
  }

  /**
   * 在页面内 fetch nav 接口（带上浏览器自己的 cookie），读回 JSON。
   * 用轮询 window.__muliNav 的方式拿异步结果，避免把登录页导航走。
   */
  private async probeNavInPage(): Promise<Record<string, Object> | null> {
    const script: string = "window.__muliNav='';" +
      "fetch('https://api.bilibili.com/x/web-interface/nav',{credentials:'include'})" +
      ".then(function(r){return r.text();})" +
      ".then(function(t){window.__muliNav=t;})" +
      ".catch(function(){window.__muliNav='ERR';});";
    try {
      await this.controller.runJavaScript(script);
    } catch (err) {
      return null;
    }
    for (let i = 0; i < PROBE_TIMES; i++) {
      await WebLoginPage.delay(PROBE_INTERVAL);
      let text: string = '';
      try {
        text = await this.controller.runJavaScript('window.__muliNav');
      } catch (err) {
        return null;
      }
      if (text === undefined || text === null || text.length === 0) {
        continue;
      }
      const start: number = text.indexOf('{');
      const end: number = text.lastIndexOf('}');
      if (start < 0 || end <= start) {
        return null;
      }
      try {
        return JSON.parse(text.substring(start, end + 1)) as Record<string, Object>;
      } catch (err) {
        return null;
      }
    }
    return null;
  }

  private static delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  /** nav 响应 → UserProfile；未登录返回 null */
  private static profileOfNav(body: Record<string, Object>): UserProfile | null {
    const data: Record<string, Object> = J.obj(body, 'data');
    if (!J.bool(data, 'isLogin')) {
      return null;
    }
    const profile: UserProfile = new UserProfile();
    profile.isLogin = true;
    profile.mid = J.num(data, 'mid');
    profile.name = J.str(data, 'uname');
    profile.face = J.str(data, 'face');
    profile.level = J.num(data, 'level');
    const wallet: Record<string, Object> = J.obj(data, 'wallet');
    profile.coin = J.num(data, 'money');
    profile.bcoin = J.num(wallet, 'bcoin_balance');
    if (profile.coin === 0) {
      profile.coin = J.num(wallet, 'coin_balance');
    }
    const levelInfo: Record<string, Object> = J.obj(data, 'level_info');
    if (profile.level === 0) {
      profile.level = J.num(levelInfo, 'current_level');
    }
    profile.expCurrent = J.num(levelInfo, 'current_exp');
    profile.expNext = J.num(levelInfo, 'next_exp');
    console.info(`MuLiAuth browser nav ok mid=${profile.mid} uname=${profile.name}`);
    return profile;
  }

  /**
   * 浏览器侧确认登录态有效后，再按 api 域读一次 cookie 覆盖保存。
   * WebCookieManager 对 www 域返回的可能是同名的旧值，api 域的视图才是浏览器真正发给接口的那份。
   */
  private async saveBrowserCookie(): Promise<void> {
    try {
      const apiRaw: string = webview.WebCookieManager.fetchCookieSync('https://api.bilibili.com');
      if (apiRaw.length > 0) {
        BiliCookie.mergeRawCookie(apiRaw);
      }
    } catch (err) {
      // 读不到就保留已同步的那份
    }
    try {
      const ctx: common.UIAbilityContext = this.context();
      await BiliCookie.saveAuth(ctx, BiliCookie.authCookie);
      await BiliCookie.persistFingerprint(ctx);
    } catch (err) {
      // 落盘失败不影响本次会话
    }
  }

  private reloadLogin(): void {
    this.needRelogin = false;
    this.tip = '在页面内完成登录，提示短信验证时请在本页输入验证码';
    try {
      this.controller.loadUrl(LOGIN_URL);
    } catch (err) {
      // 重新加载失败就停在当前页
    }
  }

  /**
   * 彻底重来：清空 WebView 的 cookie 桶 + 清掉本机那份登录态，再加载登录页。
   *
   * 为什么需要它：如果本机存着一份服务端早已失效的 SESSDATA，
   * 登录页会带着它去「自动登录」，用户看到的界面像已登录，
   * 实际下发的还是同一份废 cookie —— 表现就是「怎么登状态都不变」。
   * 清空后第一次拿到的 SESSDATA 一定是本次登录产生的。
   */
  private async resetAndReload(): Promise<void> {
    this.done = false;
    this.needRelogin = false;
    this.initialSess = '';
    this.tip = '已清除本机登录缓存，请重新登录';
    try {
      await webview.WebCookieManager.clearAllCookies();
    } catch (err) {
      // 清不掉也继续，至少不会卡住流程
    }
    try {
      await BiliCookie.clearAuth(this.context());
    } catch (err) {
      // 忽略
    }
    AppStorage.setOrCreate('loginTick', Date.now());
    this.reloadLogin();
    this.startTimer();
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text, duration: 1600 });
    } catch (err) {
      // 提示失败不影响主流程
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        // HdsNavDestination 的标题栏是沉浸式的，内容从屏幕顶端开始排，
        // 这里让出标题栏高度，否则提示条会被标题压住。
        Row()
          .width('100%')
          .height(56)
        Row({ space: 8 }) {
          Text(this.tip)
            .fontSize(11)
            .fontColor(this.needRelogin ? $r('app.color.danger') : $r('app.color.text_tertiary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.needRelogin ? '重新登录' : '清除登录缓存')
            .fontSize(11)
            .fontColor(this.needRelogin ? $r('app.color.brand_primary') : $r('app.color.text_tertiary'))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .onClick(() => {
              this.resetAndReload();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.bg_field'))
        .alignItems(VerticalAlign.Center)

        if (this.progress > 0 && this.progress < 100) {
          Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(2)
            .color($r('app.color.brand_primary'))
        }

        Web({ src: LOGIN_URL, controller: this.controller })
          .width('100%')
          .layoutWeight(1)
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(true)
          .mixedMode(MixedMode.All)
          .userAgent(MOBILE_UA)
          .onControllerAttached(() => {
            this.onWebReady();
          })
          .onProgressChange((event: OnProgressChangeEvent) => {
            this.progress = event.newProgress;
          })
          .onPageEnd(() => {
            this.tryFetchCookie();
          })
          .onErrorReceive(() => {
            this.tip = '页面加载失败，请检查网络后重试';
          })
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({
      content: {
        title: { mainTitle: '官方网页登录' }
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
    .backgroundColor($r('app.color.bg_page'))
  }
}
