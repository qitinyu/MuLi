import {
  BOTTOM_PAD_LG, BOTTOM_PAD_PHONE, CARD_RADIUS, MINE_AVATAR_SIZE, MINE_COVER_HEIGHT, PAGE_PADDING,
  TITLE_BAR_HEIGHT
} from '../common/DesignSpec';
import {
  DynamicCard,
  FollowTag,
  SpaceArchivePage,
  SpaceBangumi,
  SpaceBangumiPage,
  UserSpace,
  VideoCard,
  VideoOpenParam
} from '../model/BiliModels';
import { SpaceService } from '../services/SpaceService';
import { DynamicService } from '../services/DynamicService';
import { AuthService } from '../services/AuthService';
import { AppPrefs } from '../services/AppPrefs';
import { LevelBadge } from '../components/LevelBadge';
import { DynamicCardView } from '../components/DynamicCardView';
import { VideoCardView } from '../components/VideoCardView';
import { shortCount } from '../common/Format';
import { pasteboard } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { uiMaterial } from '@kit.ArkUI';

/** 资料卡上沿相对背景底边的上移量：让头像压住背景下沿 */
const CARD_LIFT: number = 56;
/** 投稿列表每页条数（与 space/arc/search 的 ps 一致） */
const ARCHIVE_PAGE_SIZE: number = 20;
/** 追番列表每页条数 */
const BANGUMI_PAGE_SIZE: number = 20;
/** 番剧网格列数 */
const BANGUMI_COLUMNS: number = 3;
/** 分组面板内列表最大高度（vp；固定值，不用百分比 —— FIT_CONTENT + 百分比会让内容塌成一行） */
const TAG_SHEET_MAX_HEIGHT: number = 420;

/**
 * 其他用户个人主页（V2.1.2）。
 *
 * 版式参照 D:\YQ\PiliNara 的 member 页与本站我的页（MinePage）：
 * - 顶部是用户个人背景（top_photo_v2 大图）；解析不到时用头像大图铺满；
 * - 资料卡压住背景下沿，含头像 / 昵称 / 等级 / 签名 / UID / IP 属地；
 * - 下方是操作卡与内容切换（动态 / 投稿 / 番剧）。
 *
 * IP 属地受「设置 - 外观 · 通用 - 全局显示 IP 属地」总开关控制：
 * 关掉后本人主页与其他用户主页都不再出现该字段。
 *
 * 版式约定：
 * - 资料卡不锁死头像高度，签名最多三行 —— 简介长一点的 UP 主能看全；
 * - 操作行拆成 关注 | 分组 | 私信 三段，分组只对已关注用户可用；
 * - 内容页签三等分：动态 / 投稿 / 番剧。
 */
@Component
export struct UserPage {
  pathStack: NavPathStack | undefined = undefined;
  scroller: Scroller = new Scroller();
  /** 状态栏高度（vp） */
  @Prop topInset: number = 32;
  @Prop breakpoint: string = 'sm';
  /** 目标用户 mid（路由参数） */
  @Prop mid: number = 0;
  /** 资料加载完成后回传昵称，供路由壳改标题 */
  onLoaded: (name: string) => void = () => {
  };
  /** 内容是否已滚离顶部：路由壳据此切换标题行底色 */
  @Link scrolled: boolean;
  /** 全局显示 IP 属地（默认开） */
  @StorageLink(AppPrefs.KEY_SHOW_IP) showIpLocation: boolean = true;
  @State space: UserSpace = new UserSpace();
  @State dynamics: Array<DynamicCard> = [];
  @State archives: Array<VideoCard> = [];
  @State bangumi: Array<SpaceBangumi> = [];
  /** 0 = 动态，1 = 投稿，2 = 番剧 */
  @State activeTab: number = 0;
  @State loading: boolean = true;
  @State errorText: string = '';
  @State archiveLoading: boolean = false;
  @State archiveHasMore: boolean = true;
  @State bangumiLoading: boolean = false;
  @State bangumiHasMore: boolean = true;
  /** 目标用户把追番列表设成了隐私（接口 code 53013） */
  @State bangumiRestricted: boolean = false;
  /** 关注操作进行中：避免连点重复提交 */
  @State followBusy: boolean = false;
  /** 分组底部面板 */
  @State tagSheetVisible: boolean = false;
  @State tags: Array<FollowTag> = [];
  @State tagLoading: boolean = false;
  @State tagError: string = '';
  /** 当前所在分组 tagid（0 = 默认分组） */
  @State currentTagId: number = 0;
  @State sheetMaterialOn: boolean = false;
  /** 资料卡实测高度：签名最多三行，卡高不再等于头像高度，容器要跟着长 */
  @State profileHeight: number = MINE_AVATAR_SIZE + 24;
  private sheetMaterial: uiMaterial.ImmersiveMaterial | undefined = undefined;
  private archivePage: number = 0;
  private bangumiPage: number = 0;

  aboutToAppear(): void {
    this.initSheetMaterial();
    this.loadSpace();
  }

  private initSheetMaterial(): void {
    try {
      this.sheetMaterialOn = uiMaterial.isImmersiveMaterialSupported();
      if (this.sheetMaterialOn) {
        this.sheetMaterial = new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.REGULAR
        });
      }
    } catch (err) {
      this.sheetMaterialOn = false;
      this.sheetMaterial = undefined;
    }
  }

  /** 重新加载（失败重试共用） */
  private async loadSpace(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      const bundle = await SpaceService.bundle(this.mid);
      this.space = bundle.space;
      this.dynamics = bundle.dynamics;
      this.onLoaded(this.space.name);
    } catch (err) {
      this.errorText = `主页加载失败：${String(err)}`;
    } finally {
      this.loading = false;
    }
  }

  /** 切到投稿页时懒加载第一页 */
  private async ensureArchives(): Promise<void> {
    if (this.archives.length > 0 || this.archiveLoading) {
      return;
    }
    await this.loadArchives(false);
  }

  private async loadArchives(append: boolean): Promise<void> {
    if (this.archiveLoading) {
      return;
    }
    if (append && !this.archiveHasMore) {
      return;
    }
    this.archiveLoading = true;
    const nextPage: number = append ? this.archivePage + 1 : 1;
    try {
      const page: SpaceArchivePage = await SpaceService.archives(this.mid, nextPage, ARCHIVE_PAGE_SIZE);
      this.archivePage = nextPage;
      this.archiveHasMore = page.hasMore;
      this.archives = append ? this.archives.concat(page.cards) : page.cards;
    } catch (err) {
      this.notify(`投稿加载失败：${String(err)}`);
    } finally {
      this.archiveLoading = false;
    }
  }

  /** 切到番剧页时懒加载第一页 */
  private async ensureBangumi(): Promise<void> {
    if (this.bangumi.length > 0 || this.bangumiLoading || this.bangumiRestricted) {
      return;
    }
    await this.loadBangumi(false);
  }

  private async loadBangumi(append: boolean): Promise<void> {
    if (this.bangumiLoading) {
      return;
    }
    if (append && !this.bangumiHasMore) {
      return;
    }
    this.bangumiLoading = true;
    const nextPage: number = append ? this.bangumiPage + 1 : 1;
    try {
      const page: SpaceBangumiPage = await SpaceService.bangumi(this.mid, nextPage, BANGUMI_PAGE_SIZE);
      this.bangumiPage = nextPage;
      this.bangumiRestricted = page.restricted;
      this.bangumiHasMore = page.hasMore;
      this.bangumi = append ? this.bangumi.concat(page.items) : page.items;
    } catch (err) {
      this.notify(`追番加载失败：${String(err)}`);
    } finally {
      this.bangumiLoading = false;
    }
  }

  private notify(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1600 });
    } catch (err) {
      // 无 UI 上下文时忽略
    }
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  // ---------- 背景 ----------

  private coverHeight(): number {
    return MINE_COVER_HEIGHT + this.topInset;
  }

  @Builder
  coverLayer() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.space.cover.length > 0) {
        Image(this.space.cover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .alt($r('app.color.brand_soft'))
          .draggable(false)
      } else if (this.space.face.length > 0) {
        // 没有空间背景图时用用户头像大图铺满；头像像素不够，加模糊避免放大后发糊
        Image(this.space.face)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .blur(18)
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

      // 顶部压暗：标题栏与状态栏图标压在图上时依然可读
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
  }

  // ---------- 资料卡 ----------

  private displayName(): string {
    if (this.space.name.length > 0) {
      return this.space.name;
    }
    return this.loading ? '加载中' : '未知用户';
  }

  /** UID 行：IP 属地受全局开关控制，关闭时整段不出现 */
  private uidLine(): string {
    const base: string = `UID: ${this.mid}`;
    if (!this.showIpLocation) {
      return base;
    }
    const ip: string = this.space.ipLocation.length > 0 ? this.space.ipLocation : '未知';
    return `${base} · IP属地：${ip}`;
  }

  private hasSign(): boolean {
    return this.space.sign.length > 0;
  }

  @Builder
  profileCard() {
    Row({ space: 12 }) {
      Stack() {
        if (this.space.face.length > 0) {
          Image(this.space.face)
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

      Column({ space: 4 }) {
        // 第一行：昵称 + 等级徽章
        Row({ space: 5 }) {
          Text(this.displayName())
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '76%' })
          if (this.space.level > 0) {
            LevelBadge({ level: this.space.level, badgeHeight: 22 })
          }
        }
        .width('100%')
        .height(24)
        .alignItems(VerticalAlign.Center)

        // 第二行：粉丝 / 关注 / 投稿
        Row({ space: 14 }) {
          Text(`粉丝 ${this.follower()}`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text(`关注 ${this.following()}`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text(`投稿 ${this.archiveCount()}`)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height(18)

        // 第三行：个性签名（最多三行，超出省略）
        // 头像与关注按钮之间的区间就是这块：签名长的 UP 主靠它撑开资料卡高度。
        Text(this.hasSign() ? this.space.sign : '这个人很懒，什么都没写')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(17)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        // 第四行：UID（+ IP 属地）
        Text(this.uidLine())
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .constraintSize({ minHeight: MINE_AVATAR_SIZE })
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.bg_card'))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .borderRadius(CARD_RADIUS)
    .alignItems(VerticalAlign.Top)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      // 签名撑高资料卡后，下方内容要跟着让位（卡高不再恒等于 CARD_LIFT + 头像高度）
      const cardHeight: number = Number(newArea.height);
      if (cardHeight > 0) {
        this.profileHeight = cardHeight;
      }
    })
  }

  private follower(): string {
    return this.space.followerText.length > 0 ? this.space.followerText : '—';
  }

  private following(): string {
    return this.space.followingText.length > 0 ? this.space.followingText : '—';
  }

  private archiveCount(): string {
    return this.space.archiveText.length > 0 ? this.space.archiveText : '—';
  }

  // ---------- 操作卡 ----------

  /** 关注 / 取消关注：真实调用 /x/relation/modify，失败给出服务端文案 */
  private async toggleFollow(): Promise<void> {
    if (this.followBusy) {
      return;
    }
    if (!AuthService.isLogin()) {
      this.notify('请先登录后再关注');
      return;
    }
    const next: boolean = !this.space.followed;
    this.followBusy = true;
    // 乐观更新，失败回滚
    this.space.followed = next;
    try {
      await SpaceService.setFollow(this.mid, next);
      this.notify(next ? '已关注' : '已取消关注');
    } catch (err) {
      this.space.followed = !next;
      this.notify(err instanceof Error ? err.message : '关注操作失败');
    } finally {
      this.followBusy = false;
    }
  }

  /** 打开分组面板：先拉一次分组列表（未登录 / 未关注直接拒绝） */
  private async openTagSheet(): Promise<void> {
    if (!this.space.followed) {
      this.notify('关注后才能设置分组');
      return;
    }
    if (!AuthService.isLogin()) {
      this.notify('请先登录后再设置分组');
      return;
    }
    this.tagSheetVisible = true;
    if (this.tags.length > 0 || this.tagLoading) {
      return;
    }
    this.tagLoading = true;
    this.tagError = '';
    try {
      this.tags = await SpaceService.followTags();
    } catch (err) {
      this.tagError = err instanceof Error ? err.message : '分组加载失败';
    } finally {
      this.tagLoading = false;
    }
  }

  private async pickTag(tag: FollowTag): Promise<void> {
    if (this.tagLoading) {
      return;
    }
    this.tagLoading = true;
    try {
      await SpaceService.addToTag(this.mid, tag.tagid);
      this.currentTagId = tag.tagid;
      this.tagSheetVisible = false;
      this.notify(`已移到「${tag.name.length > 0 ? tag.name : '默认分组'}」`);
    } catch (err) {
      this.notify(err instanceof Error ? err.message : '分组操作失败');
    } finally {
      this.tagLoading = false;
    }
  }

  @Builder
  actionButton(icon: Resource, label: string, enabled: boolean, primary: boolean,
    tap: () => void) {
    Row({ space: 5 }) {
      SymbolGlyph(icon)
        .fontSize(14)
        .fontColor([this.actionColor(enabled, primary)])
      Text(label)
        .fontSize(14)
        .fontColor(this.actionColor(enabled, primary))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(38)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.actionBg(enabled, primary))
    .borderRadius(19)
    .opacity(enabled ? 1 : 0.45)
    .onClick(() => {
      tap();
    })
  }

  /** 未关注时把「分组」「私信」标灰：底与字都退到三级色 */
  private actionColor(enabled: boolean, primary: boolean): Resource {
    if (!enabled) {
      return $r('app.color.text_tertiary');
    }
    return primary ? $r('app.color.text_on_brand') : $r('app.color.text_secondary');
  }

  private actionBg(enabled: boolean, primary: boolean): Resource {
    if (!enabled) {
      return $r('app.color.bg_field');
    }
    return primary ? $r('app.color.brand_primary') : $r('app.color.bg_field');
  }

  @Builder
  actionCard() {
    Row({ space: 8 }) {
      this.actionButton(this.space.followed ? $r('sys.symbol.checkmark') : $r('sys.symbol.plus'),
        this.space.followed ? '已关注' : '关注', true, !this.space.followed, () => {
          this.toggleFollow();
        })

      this.actionButton($r('sys.symbol.square_grid_2x2'), '分组', this.space.followed, false, () => {
        this.openTagSheet();
      })

      this.actionButton($r('sys.symbol.ellipsis_message'), '私信', this.space.followed, false, () => {
        if (!this.space.followed) {
          this.notify('关注后才能私信');
          return;
        }
        this.notify('私信：待接入');
      })
    }
    .width('100%')
    .padding(10)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
  }

  // ---------- 内容切换 ----------

  private tabLabel(index: number): string {
    if (index === 1) {
      return `投稿 ${this.archiveCount()}`;
    }
    if (index === 2) {
      return '番剧';
    }
    return '动态';
  }

  private pickTab(index: number): void {
    if (this.activeTab === index) {
      return;
    }
    this.activeTab = index;
    if (index === 1) {
      this.ensureArchives();
    } else if (index === 2) {
      this.ensureBangumi();
    }
  }

  /** 三等分页签：每个占 1/3 宽，选中态用品牌色下划线 + 加粗 */
  @Builder
  tabItem(index: number) {
    Column({ space: 6 }) {
      Text(this.tabLabel(index))
        .fontSize(14)
        .fontWeight(this.activeTab === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.activeTab === index ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row()
        .width(this.activeTab === index ? 20 : 0)
        .height(3)
        .borderRadius(2)
        .backgroundColor($r('app.color.brand_primary'))
    }
    .layoutWeight(1)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.pickTab(index);
    })
  }

  @Builder
  tabStrip() {
    Row() {
      this.tabItem(0)
      this.tabItem(1)
      this.tabItem(2)
    }
    .width('100%')
    .padding({ top: 4 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
  }

  // ---------- 动态 ----------

  @Builder
  dynamicSection() {
    Column() {
      if (this.loading) {
        this.loadingRow('正在加载主页')
      } else if (this.errorText.length > 0) {
        Column({ space: 10 }) {
          Text(this.errorText)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
          Text('点击重试')
            .fontSize(13)
            .fontColor($r('app.color.brand_primary'))
            .padding({ left: 16, right: 16, top: 7, bottom: 7 })
            .backgroundColor($r('app.color.brand_tint'))
            .borderRadius(15)
            .onClick(() => {
              this.loadSpace();
            })
        }
        .width('100%')
        .padding({ top: 32, bottom: 32 })
        .justifyContent(FlexAlign.Center)
      } else if (this.dynamics.length === 0) {
        Column({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.paperplane'))
            .fontSize(30)
            .fontColor([$r('app.color.text_tertiary')])
          Text('TA 还没有发布动态')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .padding({ top: 36, bottom: 36 })
        .justifyContent(FlexAlign.Center)
      } else {
        ForEach(this.dynamics, (card: DynamicCard) => {
          DynamicCardView({
            card: card,
            onCardTap: (tapped: DynamicCard) => {
              this.openDynamic(tapped);
            },
            onComment: (tapped: DynamicCard) => {
              this.openDynamicComments(tapped);
            },
            onLike: (tapped: DynamicCard) => {
              this.toggleLike(tapped);
            },
            onForward: (tapped: DynamicCard) => {
              this.notify('转发到我的动态：发布页尚未接入，先占位');
            },
            onShare: (tapped: DynamicCard) => {
              this.shareDynamic(tapped);
            }
          })
        }, (card: DynamicCard) => `${card.id}_${card.liked ? 1 : 0}`)

        Text('更多动态：待接入该用户动态分页')
          .width('100%')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .padding({ top: 6, bottom: 6 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  loadingRow(label: string) {
    Row({ space: 8 }) {
      LoadingProgress()
        .width(22)
        .height(22)
        .color($r('app.color.brand_primary'))
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .height(120)
    .justifyContent(FlexAlign.Center)
  }

  // ---------- 投稿 ----------

  @Builder
  archiveSection() {
    Column() {
      if (this.archives.length === 0) {
        Row({ space: 8 }) {
          if (this.archiveLoading) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color($r('app.color.brand_primary'))
          }
          Text(this.archiveLoading ? '正在加载投稿' : 'TA 还没有投稿')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .padding({ top: 32, bottom: 32 })
        .justifyContent(FlexAlign.Center)
      } else {
        ForEach(this.archives, (card: VideoCard) => {
          VideoCardView({
            card: card,
            onCardTap: (tapped: VideoCard) => {
              this.openVideo(tapped);
            },
            onMoreTap: (tapped: VideoCard) => {
              this.openVideo(tapped);
            }
          })
        }, (card: VideoCard) => `${card.bvid}_${card.aid}`)

        this.sectionFooter(this.archiveLoading, this.archiveHasMore, '投稿', () => {
          this.loadArchives(true);
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ---------- 番剧 ----------

  @Builder
  bangumiSection() {
    Column() {
      if (this.bangumiRestricted) {
        Column({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.lock'))
            .fontSize(30)
            .fontColor([$r('app.color.text_tertiary')])
          Text('该用户的追番 / 追剧列表未公开')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .padding({ top: 36, bottom: 36 })
        .justifyContent(FlexAlign.Center)
      } else if (this.bangumi.length === 0) {
        Row({ space: 8 }) {
          if (this.bangumiLoading) {
            LoadingProgress()
              .width(22)
              .height(22)
              .color($r('app.color.brand_primary'))
          }
          Text(this.bangumiLoading ? '正在加载番剧' : 'TA 还没有追番')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .padding({ top: 32, bottom: 32 })
        .justifyContent(FlexAlign.Center)
      } else {
        // 番剧封面比较竖，按三列网格排；每格是封面 + 标题 + 进度
        // 用「先切行再排 Row」而不是 Flex wrap + 百分比宽度：
        // 百分比宽度带百分比右边距时三者相加会超过 100%，实测会退化成两列。
        Column({ space: 0 }) {
          ForEach(this.bangumiRows(), (row: Array<SpaceBangumi>) => {
            Row({ space: 0 }) {
              ForEach(row, (item: SpaceBangumi) => {
                this.bangumiCell(item)
              }, (item: SpaceBangumi) => `c-${item.seasonId}_${item.title}`)
              // 末行不足三列时补空位，保证列宽恒等于 1/3
              if (row.length < BANGUMI_COLUMNS) {
                ForEach(this.fillers(row.length), (index: number) => {
                  Row()
                    .layoutWeight(1)
                }, (index: number) => `f-${index}`)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }, (row: Array<SpaceBangumi>, index: number) => `r-${index}-${row.length}`)
        }
        .width('100%')

        this.sectionFooter(this.bangumiLoading, this.bangumiHasMore, '番剧', () => {
          this.loadBangumi(true);
        })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 番剧分页切成每行三列 */
  private bangumiRows(): Array<Array<SpaceBangumi>> {
    const rows: Array<Array<SpaceBangumi>> = [];
    let current: Array<SpaceBangumi> = [];
    for (let i = 0; i < this.bangumi.length; i++) {
      current.push(this.bangumi[i]);
      if (current.length === BANGUMI_COLUMNS) {
        rows.push(current);
        current = [];
      }
    }
    if (current.length > 0) {
      rows.push(current);
    }
    return rows;
  }

  /** 末行补位用的占位索引 */
  private fillers(filled: number): Array<number> {
    const result: Array<number> = [];
    for (let i = filled; i < BANGUMI_COLUMNS; i++) {
      result.push(i);
    }
    return result;
  }

  @Builder
  bangumiCell(item: SpaceBangumi) {
    Column({ space: 5 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        // 封面容器自身定死比例：比例给 Image 会与百分比子层互相等待
        Image(item.cover)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .alt($r('app.color.bg_field'))
          .draggable(false)

        if (item.badge.length > 0) {
          Text(item.badge)
            .fontSize(9)
            .fontColor($r('app.color.text_on_brand'))
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.brand_primary'))
            .borderRadius(4)
            .margin({ left: 6, bottom: 6 })
        }
      }
      .width('100%')
      .aspectRatio(3 / 4)
      .borderRadius(10)
      .clip(true)

      Text(item.title)
        .width('100%')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .lineHeight(18)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 5 }) {
        Text(item.progressText.length > 0 ? item.progressText : item.typeName)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (item.viewCount > 0) {
          Text(`${shortCount(item.viewCount)}播放`)
            .fontSize(10)
            .fontColor($r('app.color.text_tertiary'))
        }
      }
      .width('100%')
    }
    .width('100%')
    .layoutWeight(1)
    .margin({ right: 8, bottom: 12 })
    .onClick(() => {
      this.notify('番剧详情页：待接入');
    })
  }

  @Builder
  sectionFooter(loading: boolean, hasMore: boolean, label: string, tap: () => void) {
    Row({ space: 6 }) {
      if (loading) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color($r('app.color.brand_primary'))
        Text('正在加载')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      } else if (hasMore) {
        Text(`加载更多${label}`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      } else {
        Text(`没有更多${label}了`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
    }
    .width('100%')
    .height(44)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      tap();
    })
  }

  // ---------- 分组底部面板 ----------

  @Builder
  tagSheet() {
    Column() {
      Row() {
        Text('移动到分组')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Row() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(32)
        .height(32)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.tagSheetVisible = false;
        })
      }
      .width('100%')
      .padding({ bottom: 6 })

      Text('选一个分组，把这名 UP 主移过去')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ bottom: 8 })

      Scroll() {
        Column() {
          if (this.tagLoading) {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(20)
                .height(20)
                .color($r('app.color.brand_primary'))
              Text('正在加载分组')
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            .height(80)
            .justifyContent(FlexAlign.Center)
          } else if (this.tagError.length > 0) {
            Text(this.tagError)
              .width('100%')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .textAlign(TextAlign.Center)
              .padding({ top: 24, bottom: 24 })
          } else {
            ForEach(this.tags, (tag: FollowTag) => {
              this.tagRow(tag)
            }, (tag: FollowTag) => `${tag.tagid}`)

            // 默认分组永远在最后：tagid=0 表示移回默认分组
            this.tagRow({ tagid: 0, name: '默认分组', count: 0 })
          }
        }
        .width('100%')
      }
      .width('100%')
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: TAG_SHEET_MAX_HEIGHT })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 24 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  tagRow(tag: FollowTag) {
    Row({ space: 10 }) {
      SymbolGlyph(this.currentTagId === tag.tagid && tag.tagid !== 0
        ? $r('sys.symbol.checkmark') : $r('sys.symbol.square_grid_2x2'))
        .fontSize(16)
        .fontColor([this.currentTagId === tag.tagid && tag.tagid !== 0
          ? $r('app.color.brand_primary') : $r('app.color.text_secondary')])
      Column({ space: 2 }) {
        Text(tag.name.length > 0 ? tag.name : '默认分组')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (tag.count > 0) {
          Text(`${tag.count} 人`)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.currentTagId === tag.tagid && tag.tagid !== 0) {
        Text('当前')
          .fontSize(11)
          .fontColor($r('app.color.brand_primary'))
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 4, right: 4 })
    .borderRadius(10)
    .onClick(() => {
      this.pickTag(tag);
    })
  }

  // ---------- 交互 ----------

  private openDynamic(card: DynamicCard): void {
    if (card.kind === 'video' && card.video !== null) {
      this.openVideo(card.video as VideoCard);
      return;
    }
    this.notify('图片 / 文字动态：详情页待建设');
  }

  /** 点评论：视频动态进播放页评论区并展开输入框 */
  private openDynamicComments(card: DynamicCard): void {
    if (card.kind !== 'video' || card.video === null) {
      this.notify('这条动态还没有接入评论区');
      return;
    }
    const video: VideoCard = card.video as VideoCard;
    if (this.pathStack === undefined || video.bvid.length === 0) {
      return;
    }
    const param: VideoOpenParam = new VideoOpenParam(video.bvid, video.aid, video.cid);
    param.focusComment = true;
    this.pathStack.pushPathByName('video', param);
  }

  /** 点赞：先乐观更新，失败回滚（未登录直接提示） */
  private async toggleLike(card: DynamicCard): Promise<void> {
    if (!AuthService.isLogin()) {
      this.notify('请先登录后再点赞');
      return;
    }
    const next: boolean = !card.liked;
    this.setLiked(card.id, next);
    try {
      await DynamicService.setLike(card.id, next);
    } catch (err) {
      this.setLiked(card.id, !next);
      this.notify(err instanceof Error ? err.message : '点赞失败');
    }
  }

  private setLiked(id: string, liked: boolean): void {
    const next: Array<DynamicCard> = this.dynamics.slice();
    for (let i = 0; i < next.length; i++) {
      if (next[i].id === id) {
        next[i].liked = liked;
        break;
      }
    }
    this.dynamics = next;
  }

  /** 分享：优先系统面板，失败退化为复制链接 */
  private async shareDynamic(card: DynamicCard): Promise<void> {
    if (card.kind === 'video' && card.video !== null) {
      const video: VideoCard = card.video as VideoCard;
      await this.share(video.title.length > 0 ? video.title : `${card.authorName}的投稿`,
        video.bvid.length > 0 ? `https://www.bilibili.com/video/${video.bvid}` : '');
      return;
    }
    await this.share(`${card.authorName}的动态`, `https://t.bilibili.com/${card.id}`);
  }

  private async share(title: string, url: string): Promise<void> {
    const content: string = url.length > 0 ? `${title} ${url}` : title;
    try {
      const record: systemShare.SharedRecord = {
        utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
        title: title,
        content: content
      };
      const data: systemShare.SharedData = new systemShare.SharedData(record);
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      await controller.show(this.context(), {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
    } catch (err) {
      console.warn(`MuLiSpace share failed: ${String(err)}`);
      this.copyLink(url.length > 0 ? url : title);
    }
  }

  private copyLink(text: string): void {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data).then(() => {
        this.notify('链接已复制，可粘贴分享');
      }).catch(() => {
        this.notify('复制失败，请手动分享');
      });
    } catch (err) {
      this.notify('复制失败，请手动分享');
    }
  }

  private openVideo(card: VideoCard): void {
    if (this.pathStack === undefined || card.bvid.length === 0) {
      return;
    }
    this.pathStack.pushPathByName('video', new VideoOpenParam(card.bvid, card.aid, card.cid));
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 12 }) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.coverLayer()
          Column() {
            this.profileCard()
          }
          .width('100%')
          .position({ x: 0, y: this.coverHeight() - CARD_LIFT })
        }
        .width('100%')
        .height(this.coverHeight() - CARD_LIFT + this.profileHeight)

        Column({ space: 12 }) {
          this.actionCard()
          this.tabStrip()
          if (this.activeTab === 0) {
            this.dynamicSection()
          } else if (this.activeTab === 1) {
            this.archiveSection()
          } else {
            this.bangumiSection()
          }
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
      const solidAt: number = this.coverHeight() - this.topInset - TITLE_BAR_HEIGHT;
      this.scrolled = this.scroller.currentOffset().yOffset > solidAt;
    })
    .onScrollEdge((side: Edge) => {
      if (side !== Edge.Bottom) {
        return;
      }
      if (this.activeTab === 1) {
        this.loadArchives(true);
      } else if (this.activeTab === 2) {
        this.loadBangumi(true);
      }
    })
    .bindSheet($$this.tagSheetVisible, this.tagSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      systemMaterial: this.sheetMaterialOn ? this.sheetMaterial : undefined
    })
  }
}