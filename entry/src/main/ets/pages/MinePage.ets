import {
  BOTTOM_PAD_LG, BOTTOM_PAD_PHONE, CARD_RADIUS, MINE_AVATAR_SIZE, MINE_COVER_HEIGHT, PAGE_PADDING,
  TITLE_BAR_HEIGHT
} from '../common/DesignSpec';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { uiMaterial } from '@kit.ArkUI';
import { UserProfile } from '../model/BiliModels';
import { AuthService } from '../services/AuthService';
import { AppPrefs } from '../services/AppPrefs';
import { plainCount } from '../common/Format';
import { LevelBadge } from '../components/LevelBadge';

/** 资料卡上沿相对背景底边的上移量：让头像压住背景下沿 */
const CARD_LIFT: number = 56;

/**
 * 我的页（由首页点头像进入，全局二级路由）。
 *
 * 版式（V2.0.3）：
 * - 背景层默认高度 = 固定高度 + 状态栏高度，页面隐藏标题栏并忽略顶部安全区，
 *   因此背景图直接抵达系统状态栏，下方内容整体上移（不再有标题栏占位行）；
 * - 顶部只留浮动返回键与「更换背景」入口，去掉原资料卡上方的文字提示；
 * - 更换背景弹窗用系统材质（bindSheet systemMaterial），支持相册导入与 URL 导入。
 *
 * 数据来自 AuthService：登录后展示真实头像/昵称/等级/B币/硬币/签名/UID/IP 属地。
 */
@Component
export struct MinePage {
  pathStack: NavPathStack | undefined = undefined;
  scroller: Scroller = new Scroller();
  /** 状态栏高度（vp）：背景与浮动控件据此避让 */
  @Prop topInset: number = 32;
  @Prop breakpoint: string = 'sm';
  @StorageLink('muli_mineCover') coverPath: string = '';
  @State sheetVisible: boolean = false;
  /** 'cover' = 更换背景；'level' = 等级经验详情 */
  @State sheetKind: string = 'cover';
  @State profile: UserProfile = new UserProfile();
  @State urlInput: string = '';
  @State picking: boolean = false;
  @State sheetMaterialOn: boolean = false;
  @StorageLink('loginTick') @Watch('onLoginTick') loginTick: number = 0;
  /** 标题栏图标触发的动作（路由壳持有标题栏，通过自增 tick 通知本页） */
  @Link @Watch('onCoverTick') coverTick: number;
  @Link @Watch('onLogoutTick') logoutTick: number;
  /** 内容是否已滚离顶部：路由壳据此切换标题行底色 */
  @Link scrolled: boolean;
  /** cookie 还在但资料没拿到时的「已登录」标记 */
  @State hasCookie: boolean = false;
  private sheetMaterial: uiMaterial.ImmersiveMaterial | undefined = undefined;

  aboutToAppear(): void {
    this.profile = AuthService.current().clone();
    this.hasCookie = AuthService.isLogin();
    if (AuthService.isLogin() && !this.profile.isLogin) {
      AuthService.loadProfile().then((loaded: UserProfile) => {
        this.profile = loaded.clone();
        this.hasCookie = AuthService.isLogin();
      }).catch(() => {
        // 拉取失败保留当前展示
      });
    }
    try {
      this.sheetMaterialOn = uiMaterial.isImmersiveMaterialSupported();
      if (this.sheetMaterialOn) {
        this.sheetMaterial = new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR });
      }
    } catch (err) {
      this.sheetMaterialOn = false;
      this.sheetMaterial = undefined;
    }
  }

  /** 标题栏 rotate 图标 → 打开更换背景弹窗 */
  private onCoverTick(): void {
    this.openSheet('cover');
  }

  /** 标题栏 off 图标 → 退出登录 */
  private onLogoutTick(): void {
    this.doLogout().then(() => {
      // 结果由 doLogout 内部提示
    });
  }

  private onLoginTick(): void {
    this.hasCookie = AuthService.isLogin();
    AuthService.loadProfile().then((loaded: UserProfile) => {
      this.profile = loaded.clone();
      this.hasCookie = AuthService.isLogin();
    }).catch(() => {
      // 忽略
    });
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private openLogin(): void {
    if (this.pathStack !== undefined) {
      this.pathStack.pushPathByName('login', '');
    }
  }

  private openSettings(): void {
    if (this.pathStack !== undefined) {
      this.pathStack.pushPathByName('settings', '');
    }
  }

  private openChangeLog(): void {
    if (this.pathStack !== undefined) {
      this.pathStack.pushPathByName('changelog', '');
    }
  }

  /** 我的收藏 / 观看历史 / 稍后再看：同一页按 kind 区分 */
  private openLibrary(kind: string): void {
    if (this.pathStack !== undefined) {
      this.pathStack.pushPathByName('library', kind);
    }
  }

  private openAbout(): void {
    if (this.pathStack !== undefined) {
      this.pathStack.pushPathByName('about', '');
    }
  }

  /** 是否「已登录」：cookie 存在即算登录成功（资料可能还在同步） */
  private loggedIn(): boolean {
    return this.profile.isLogin || this.hasCookie;
  }

  /** 资料接口失败时重新拉取 */
  private reloadProfile(): void {
    this.hasCookie = AuthService.isLogin();
    AuthService.loadProfile().then((loaded: UserProfile) => {
      this.profile = loaded.clone();
      this.hasCookie = AuthService.isLogin();
      this.notify(loaded.isLogin ? '资料已更新' : '资料同步失败，请稍后重试');
    }).catch(() => {
      this.notify('资料同步失败，请稍后重试');
    });
  }

  private goBack(): void {
    if (this.pathStack !== undefined) {
      this.pathStack.pop();
    }
  }

  /** cookie 还在但登录态接口不认：直接去网页登录并清掉这份废 cookie */
  private relogin(): void {
    if (this.pathStack !== undefined) {
      this.pathStack.pushPathByName('weblogin', 'reset');
    }
  }

  /** 未登录时点头像 → 去登录；已登录但资料没拿到 → 重试；正常 → 提示 */
  private onAvatarTap(): void {
    if (!this.loggedIn()) {
      this.openLogin();
      return;
    }
    if (this.profile.publicOnly) {
      this.relogin();
      return;
    }
    if (!this.profile.isLogin) {
      this.reloadProfile();
      return;
    }
    this.notify('头像与个人主页编辑待建设');
  }

  private openSheet(kind: string): void {
    this.sheetKind = kind;
    if (kind === 'cover') {
      this.urlInput = this.coverPath.startsWith('http') ? this.coverPath : '';
    }
    this.sheetVisible = true;
  }

  /** 退出登录：清 cookie + 清资料，并通知各页签重载 */
  private async doLogout(): Promise<void> {
    try {
      const ctx = this.context();
      await AuthService.logout(ctx);
      this.profile = new UserProfile();
      this.hasCookie = false;
      AppStorage.setOrCreate('loginTick', Date.now());
      this.notify('已退出登录');
    } catch (err) {
      this.notify('退出登录失败，请稍后重试');
    }
  }

  private notify(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (err) {
      // 无 UI 上下文时忽略
    }
  }

  // ---------- 背景 ----------

  private coverHeight(): number {
    return MINE_COVER_HEIGHT + this.topInset;
  }

  /** 背景图高度：http 链接直接用，沙箱路径补 file:// 前缀 */
  private coverSource(): string {
    const path: string = this.coverPath;
    if (path.length === 0) {
      return '';
    }
    if (path.startsWith('http') || path.startsWith('file://')) {
      return path;
    }
    return `file://${path}`;
  }

  /** 相册选图 → 复制进沙箱 → 记录路径（系统给的是临时授权 URI，必须落盘才能长期使用） */
  private async pickLocalCover(): Promise<void> {
    if (this.picking) {
      return;
    }
    this.picking = true;
    try {
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      if (result.photoUris.length === 0) {
        this.picking = false;
        return;
      }
      const ctx: common.UIAbilityContext = this.context();
      const source = fs.openSync(result.photoUris[0], fs.OpenMode.READ_ONLY);
      const target: string = `${ctx.filesDir}/mine_cover_${Date.now()}.jpg`;
      const output = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.copyFileSync(source.fd, output.fd);
      fs.closeSync(source);
      fs.closeSync(output);
      const saved: string = `file://${target}`;
      this.coverPath = saved;
      await AppPrefs.save(ctx, AppPrefs.KEY_MINE_COVER, saved);
      this.sheetVisible = false;
      this.notify('背景已更新');
    } catch (err) {
      this.notify('相册图片导入失败，可改用图片链接');
    } finally {
      this.picking = false;
    }
  }

  private async applyUrlCover(): Promise<void> {
    const url: string = this.urlInput.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      this.notify('请输入 http(s) 开头的图片链接');
      return;
    }
    this.coverPath = url;
    await AppPrefs.save(this.context(), AppPrefs.KEY_MINE_COVER, url);
    this.sheetVisible = false;
    this.notify('背景已更新');
  }

  private async resetCover(): Promise<void> {
    this.coverPath = '';
    await AppPrefs.save(this.context(), AppPrefs.KEY_MINE_COVER, '');
    this.sheetVisible = false;
    this.notify('已恢复默认背景');
  }

  // ---------- 背景层 ----------

  @Builder
  coverLayer() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.coverSource().length > 0) {
        Image(this.coverSource())
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .alt($r('app.color.brand_soft'))
          .draggable(false)
      } else {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            angle: 135,
            colors: [
              [$r('app.color.brand_primary'), 0.0],
              [$r('app.color.brand_soft'), 0.55],
              [$r('app.color.brand_tint'), 1.0]
            ]
          })
      }

      // 顶部轻微压暗：标题栏与状态栏图标压在图片上时依然可读
      Column()
        .width('100%')
        .height(96)
        .linearGradient({
          angle: 180,
          colors: [['#33000000', 0.0], ['#00000000', 1.0]]
        })
    }
    .width('100%')
    .height(this.coverHeight())
    .clip(true)
    .onClick(() => {
      this.openSheet('cover');
    })
  }

  // ---------- 资料卡 ----------

  @Builder
  levelBadge() {
    Row() {
      LevelBadge({ level: this.profile.isLogin ? this.profile.level : 0, badgeHeight: 22 })
    }
    .onClick(() => {
      this.openSheet('level');
    })
  }

  @Builder
  profileCard() {
    Row() {
      Row({ space: 12 }) {
        // 头像：高度等于右侧四行资料的总高
        Stack() {
          if (this.profile.isLogin && this.profile.face.length > 0) {
            Image(this.profile.face)
              .width(MINE_AVATAR_SIZE)
              .height(MINE_AVATAR_SIZE)
              .objectFit(ImageFit.Cover)
              .alt($r('app.color.bg_field'))
              .draggable(false)
          } else {
            SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
              .fontSize(44)
              .fontColor([$r('app.color.text_tertiary')])
          }
          Row()
            .width('100%')
            .height('100%')
            .borderRadius(MINE_AVATAR_SIZE / 2)
            .border({ width: 2, color: $r('app.color.bg_card') })
        }
        .width(MINE_AVATAR_SIZE)
        .height(MINE_AVATAR_SIZE)
        .borderRadius(MINE_AVATAR_SIZE / 2)
        .backgroundColor($r('app.color.bg_field'))
        .clip(true)
        .onClick(() => {
          this.onAvatarTap();
        })

        Column() {
          // 第一行：昵称 + 等级徽章
          Row({ space: 5 }) {
            Text(this.displayName())
              .fontSize(19)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              // 不用 layoutWeight 撑满整行，否则徽章被顶到最右、和昵称间隔过大；
              // 改为按内容宽度并设上限，超长昵称省略，徽章紧跟在昵称右侧。
              .constraintSize({ maxWidth: '78%' })
            this.levelBadge()
          }
          .width('100%')
          .height(24)
          .alignItems(VerticalAlign.Center)

          // 第二行：B 币 + 硬币（公开资料兜底时这两项拿不到，显示 ——）
          Row({ space: 14 }) {
            Text(this.coinText('B币', this.profile.bcoin))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Text(this.coinText('硬币', this.profile.coin))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .height(18)
          .margin({ top: 4 })

          // 第三行：个性签名
          Text(this.profile.isLogin && this.profile.sign.length > 0 ? this.profile.sign : '这个人很懒，什么都没写')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .height(18)
            .margin({ top: 4 })

          // 第四行：UID + IP 属地（登录态异常时右侧给「重新登录」入口）
          Row({ space: 6 }) {
            Text(this.uidLine())
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (this.profile.publicOnly) {
              Text('重新登录')
                .fontSize(11)
                .fontColor($r('app.color.brand_primary'))
                .onClick(() => {
                  this.relogin();
                })
            }
          }
          .width('100%')
          .height(16)
          .margin({ top: 4 })
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .height(MINE_AVATAR_SIZE)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.bg_card'))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .borderRadius(CARD_RADIUS)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.onAvatarTap();
      })
    }
    .width('100%')
    .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
  }

  /** UID 行：未登录显示提示，已登录拼 UID 与 IP 属地 */
  private uidLine(): string {
    if (!this.loggedIn()) {
      return '点击登录，同步关注与收藏';
    }
    if (!this.profile.isLogin) {
      return '登录成功，资料同步中 · 点击重试';
    }
    // 公开资料兜底：cookie 还在但登录态接口没通过，明确告知而不是假装正常
    if (this.profile.publicOnly) {
      return `UID: ${this.profile.mid} · 登录态未生效`;
    }
    const ip: string = this.profile.ipLocation.length > 0 ? this.profile.ipLocation : '未知';
    return `UID: ${this.profile.mid} · IP属地：${ip}`;
  }

  /** B币 / 硬币：公开资料兜底时未知 */
  private coinText(label: string, value: number): string {
    if (this.profile.publicOnly) {
      return `${label} —`;
    }
    return `${label} ${plainCount(value)}`;
  }

  /** 昵称：资料没同步下来时退化成「已登录」占位，不显示成未登录 */
  private displayName(): string {
    if (this.profile.isLogin && this.profile.name.length > 0) {
      return this.profile.name;
    }
    return this.loggedIn() ? '已登录' : '未登录';
  }

  // ---------- 社交卡 ----------

  @Builder
  socialItem(value: string, label: string) {
    Column({ space: 4 }) {
      Text(value)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.notify(`${label}：待建设`);
    })
  }

  @Builder
  socialCard() {
    Row() {
      this.socialItem(plainCount(this.profile.follower), '粉丝')
      Divider()
        .vertical(true)
        .height(24)
        .color($r('app.color.divider'))
      this.socialItem(plainCount(this.profile.following), '关注')
      Divider()
        .vertical(true)
        .height(24)
        .color($r('app.color.divider'))
      this.socialItem(plainCount(this.profile.likes), '获赞')
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
  }

  // ---------- 数据卡 ----------

  @Builder
  dataBlock(icon: Resource, label: string, kind: string) {
    Column({ space: 8 }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([$r('app.color.brand_primary')])
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ top: 14, bottom: 14 })
    .onClick(() => {
      if (kind.length === 0) {
        this.notify(`${label}：待建设`);
        return;
      }
      this.openLibrary(kind);
    })
  }

  @Builder
  dataCard() {
    Row() {
      this.dataBlock($r('sys.symbol.star'), '我的收藏', 'fav')
      this.dataBlock($r('sys.symbol.clock'), '观看历史', 'history')
      this.dataBlock($r('sys.symbol.bookmark'), '稍后再看', 'toview')
      this.dataBlock($r('sys.symbol.arrow_clockwise'), '离线缓存', '')
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Center)
  }

  // ---------- 设置卡 ----------

  @Builder
  settingsRow(icon: Resource, label: string, isLast: boolean) {
    Column() {
      Row({ space: 10 }) {
        SymbolGlyph(icon)
          .fontSize(20)
          .fontColor([$r('app.color.text_secondary')])
        Text(label)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .width('100%')
      .height(48)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)

      if (!isLast) {
        Divider()
          .color($r('app.color.divider'))
          .strokeWidth(0.5)
          .margin({ left: 44 })
      }
    }
    .width('100%')
    .onClick(() => {
      if (label === '沐哩设置') {
        this.openSettings();
        return;
      }
      if (label === '更新日志') {
        this.openChangeLog();
        return;
      }
      if (label === '关于沐哩') {
        this.openAbout();
        return;
      }
      this.notify(`${label}：待建设`);
    })
  }

  @Builder
  settingsCard() {
    Column() {
      this.settingsRow($r('sys.symbol.gearshape'), '沐哩设置', false)
      this.settingsRow($r('sys.symbol.heart'), '关于沐哩', false)
      this.settingsRow($r('sys.symbol.arrow_clockwise'), '更新日志', true)
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
  }

  // ---------- 弹窗 ----------

  @Builder
  coverOption(icon: Resource, label: string, tap: () => void) {
    Column({ space: 8 }) {
      Row() {
        SymbolGlyph(icon)
          .fontSize(24)
          .fontColor([$r('app.color.brand_primary')])
      }
      .width(52)
      .height(52)
      .borderRadius(16)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.brand_tint'))

      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
    }
    .layoutWeight(1)
    .padding({ top: 16, bottom: 16 })
    .backgroundColor($r('app.color.bg_field'))
    .borderRadius(16)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      tap();
    })
  }

  @Builder
  coverSheet() {
    Column({ space: 14 }) {
      Row() {
        Text('更换背景')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(16)
          .fontColor([$r('app.color.text_tertiary')])
          .padding(4)
          .onClick(() => {
            this.sheetVisible = false;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('从相册选择一张图片，或填入图片链接；设置后立即生效')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))

      Row({ space: 10 }) {
        this.coverOption($r('sys.symbol.picture'), '从相册选择', () => {
          this.pickLocalCover();
        })
        this.coverOption($r('sys.symbol.link'), '图片链接', () => {
          this.urlInput = this.coverPath.startsWith('http') ? this.coverPath : '';
        })
      }
      .width('100%')

      Row({ space: 8 }) {
        TextInput({ text: this.urlInput, placeholder: 'https://example.com/cover.jpg' })
          .fontSize(13)
          .height(40)
          .layoutWeight(1)
          .backgroundColor($r('app.color.bg_field'))
          .borderRadius(10)
          .onChange((value: string) => {
            this.urlInput = value;
          })
        Text('应用')
          .fontSize(13)
          .fontColor($r('app.color.text_on_brand'))
          .padding({ left: 16, right: 16, top: 9, bottom: 9 })
          .backgroundColor($r('app.color.brand_primary'))
          .borderRadius(10)
          .onClick(() => {
            this.applyUrlCover();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('恢复默认背景')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height(42)
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.bg_field'))
      .borderRadius(10)
      .onClick(() => {
        this.resetCover();
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  levelSheet() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.star_fill'))
          .fontSize(18)
          .fontColor([$r('app.color.brand_primary')])
        Text('等级经验')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        LevelBadge({ level: this.profile.isLogin ? this.profile.level : 0, badgeHeight: 22 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Progress({ value: this.profile.expCurrent, total: this.expTotal(), type: ProgressType.Linear })
        .width('100%')
        .height(6)
        .color($r('app.color.brand_primary'))
        .backgroundColor($r('app.color.bg_field'))

      Text(this.expText())
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
      Text('经验获取规则：登录、观看、分享、投稿等行为累积，具体数值由账号接口下发')
        .fontSize(11)
        .lineHeight(17)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 当前等级的经验上限：接口给不到时按 20000 兜底 */
  private expTotal(): number {
    return this.profile.expNext > 0 ? this.profile.expNext : 20000;
  }

  private expText(): string {
    if (!this.profile.isLogin) {
      return '登录后查看等级经验';
    }
    const remain: number = Math.max(0, this.expTotal() - this.profile.expCurrent);
    return `经验值 ${this.profile.expCurrent} / ${this.expTotal()}，距 LV${this.profile.level + 1} 还需 ${remain}`;
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 12 }) {
        // 背景 + 资料卡：背景贴顶（含状态栏区域），资料卡上沿压在背景下沿之内
        Stack({ alignContent: Alignment.TopStart }) {
          this.coverLayer()
          Column() {
            this.profileCard()
          }
          .width('100%')
          .position({ x: 0, y: this.coverHeight() - CARD_LIFT })
        }
        .width('100%')
        .height(this.coverHeight() + CARD_LIFT)

        Column({ space: 12 }) {
          this.socialCard()
          this.dataCard()
          this.settingsCard()
        }
        .width('100%')
        .padding({ left: PAGE_PADDING, right: PAGE_PADDING })

        Row()
          .width('100%')
          .height(this.breakpoint === 'lg' ? BOTTOM_PAD_LG : BOTTOM_PAD_PHONE)
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onDidScroll(() => {
      // 只有内容真正滚过封面（标题栏下方已是白色内容区）时才转实底；
      // 提前转白会让标题栏看起来像一张浮在背景图上的白色卡片。
      const solidAt: number = this.coverHeight() - this.topInset - TITLE_BAR_HEIGHT;
      this.scrolled = this.scroller.currentOffset().yOffset > solidAt;
    })
    .bindSheet($$this.sheetVisible, this.sheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      // 系统材质：不支持沉浸材质的设备退回默认半透明底
      systemMaterial: this.sheetMaterialOn ? this.sheetMaterial : undefined,
      onDisappear: () => {
        this.sheetKind = 'cover';
      }
    })
  }

  @Builder
  sheetBuilder() {
    if (this.sheetKind === 'level') {
      this.levelSheet()
    } else {
      this.coverSheet()
    }
  }
}
