import { VideoItem } from '../models/VideoItem';
import { DynamicEntry } from '../services/DynamicService';
import { AuthSession } from '../services/AuthService';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import { FormatUtils } from '../utils/FormatUtils';
import { FollowState } from '../utils/FollowState';
import { loadingIndicator } from '../utils/CommonBuilders';
import { HotPage } from '../pages/HotPage';
import { LivePage } from '../pages/LivePage';
import { DynamicPage } from '../pages/DynamicPage';
import { AnimePage } from '../pages/AnimePage';
import display from '@ohos.display';
import router from '@ohos.router';

@Component
export struct HomeTab {
  @Consume activeTab: number;
  @Consume contentTab: number;
  @Consume selectedTopTab: number;
  @Consume sidebar: number;
  @Consume authSession: AuthSession | null;
  @Consume videos: VideoItem[];
  @Consume loading: boolean;
  @Consume loadingMore: boolean;
  @Consume compactGrid: boolean;
  @Consume portraitBadge: boolean;
  @Consume videoQuickActionsEnabled: boolean;
  @Consume followStamp: number;
  @Consume topInset: number;
  @Consume bottomInset: number;
  @Link refreshing: boolean;
  @State quickMenuItemId: number = -1;
  @State quickMenuItem: VideoItem | null = null;
  @State quickMenuX: number = 16;
  @State quickMenuY: number = 120;
  @State suppressNextTap: boolean = false;
  @State listMenuVisible: boolean = false;
  private suppressTapTimer: number = -1;
  scroller: Scroller = new Scroller();
  onOpenVideo: (item: VideoItem) => void = (item: VideoItem): void => {};
  onPlayDynamic: (item: VideoItem, showComments: boolean) => void =
    (item: VideoItem, showComments: boolean): void => {};
  onLoadMore: () => void = (): void => {};
  onRefresh: () => void = (): void => {};
  onOpenSearch: () => void = (): void => {};
  onScrollDelta: (delta: number) => void = (delta: number): void => {};
  onSelectTab: (index: number) => void = (index: number): void => {};
  onOpenAuthor: (item: VideoItem) => void = (item: VideoItem): void => {};
  onLikeDynamicVideo: (item: VideoItem) => void = (item: VideoItem): void => {};
  onShareDynamicVideo: (item: VideoItem) => void = (item: VideoItem): void => {};
  onLikeDynamicEntry: (entry: DynamicEntry) => void = (entry: DynamicEntry): void => {};
  onShareDynamicEntry: (entry: DynamicEntry) => void = (entry: DynamicEntry): void => {};
  onVideoQuickAction: (item: VideoItem, action: string) => void =
    (item: VideoItem, action: string): void => {};

  // 快捷操作菜单：自绘 overlay（全屏透明遮罩 + 按锚点绝对定位的菜单）。
  // 不用 bindPopup——真机弹层内子组件交互不可靠；overlay 交互原生可用。
  @Builder
  videoQuickMenu(item: VideoItem) {
    Column({ space: 2 }) {
      this.quickMenuAction('保存封面', item, 'saveCover');
      this.quickMenuAction('删隐视频', item, 'hide');
      this.quickMenuAction('分享视频', item, 'share');
      this.quickMenuAction('举报视频', item, 'report');
      this.quickMenuAction('拉黑用户', item, 'block');
    }.width(156).padding({ top: 6, bottom: 6 })
      .backgroundColor(ImmersiveMaterial.surfaceBackground(0.94))
      .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
      .borderRadius(12)
      .border({ width: 1, color: '#35FFFFFF' })
      .shadow({ radius: 10, color: '#33000000', offsetX: 0, offsetY: 3 })
      .position({ x: this.quickMenuX, y: this.quickMenuY })
      .zIndex(41)
  }

  // 以 anchor 组件的窗口矩形计算菜单落点：优先向下弹出，空间不足向上翻。
  // getRectangleById 返回 px，需换算 vp；build 的 Stack 带 topInset 内边距，y 再减去它。
  private openQuickMenu(item: VideoItem, anchorId: string): void {
    const menuWidth: number = 156;
    const menuHeight: number = 206;
    try {
      const rect = this.getUIContext().getComponentUtils().getRectangleById(anchorId);
      const anchorX: number = px2vp(Number(rect.windowOffset.x));
      const anchorY: number = px2vp(Number(rect.windowOffset.y));
      const anchorW: number = px2vp(Number(rect.size.width));
      const anchorH: number = px2vp(Number(rect.size.height));
      let left: number = anchorX + anchorW - menuWidth;
      if (left < 8) left = 8;
      const screenHeight: number = px2vp(display.getDefaultDisplaySync().height);
      let top: number = anchorY + anchorH + 6;
      if (top + menuHeight > screenHeight - 8) {
        top = Math.max(this.topInset + 8, anchorY - menuHeight - 6);
      }
      this.quickMenuX = left;
      this.quickMenuY = top - this.topInset;
    } catch (error) {
      console.error(`Pilihos quick menu anchor failed: ${String(error)}`);
      this.quickMenuX = 16;
      this.quickMenuY = 120;
    }
    this.quickMenuItem = item;
    this.quickMenuItemId = item.id;
  }

  private closeQuickMenu(): void {
    this.quickMenuItem = null;
    this.quickMenuItemId = -1;
    this.suppressNextTap = false;
  }

  @Builder
  quickMenuAction(label: string, item: VideoItem, action: string) {
    Button() {
      Text(label)
        .fontSize(14)
        .fontColor(action === 'report' || action === 'block' ? '#C51D2A' : '#1E252D')
        .width('100%')
        .textAlign(TextAlign.Center);
    }
    .type(ButtonType.ROUNDED_RECTANGLE)
    .width('100%')
    .height(38)
    .padding(0)
    .backgroundColor(Color.Transparent)
      .onClick((): void => {
        // 菜单在 overlay 层，点击不会落到卡片；关闭菜单并执行动作
        this.closeQuickMenu();
        this.onVideoQuickAction(item, action);
      });
  }

  @Builder
  topCircleButton(label: string, action: () => void) {
    Button() {
      if (label === '我') {
        if (this.authSession !== null && this.authSession.face !== '') {
          Image(this.authSession.face).width(36).height(36).borderRadius(18).objectFit(ImageFit.Cover);
        } else {
          Image($r('app.media.user_me')).width(34).height(34).objectFit(ImageFit.Contain);
        }
      } else if (label === '消息') {
        Image($r('app.media.xiaoxi')).width(24).height(24);
      } else if (label === '频道') {
        Image($r('app.media.list')).width(22).height(22).fillColor('#3E4854');
      } else if (label === '刷新') {
        Image($r('app.media.qp')).width(22).height(22).fillColor('#3E4854');
      } else {
        // 单双列切换气泡
        Column({ space: 2 }) {
          Row({ space: 2 }) {
            Row().width(8).height(14).borderRadius(2)
              .backgroundColor(this.compactGrid ? '#B9C2CC' : '#1288FA');
            Row().width(8).height(14).borderRadius(2)
              .backgroundColor(this.compactGrid ? '#1288FA' : '#B9C2CC');
          }
        }
      }
    }
      .type(ButtonType.ROUNDED_RECTANGLE)
      .controlSize(ControlSize.NORMAL)
      .width(48)
      .height(48)
      .padding(0)
      .borderRadius(24)
      .backgroundColor(ImmersiveMaterial.surfaceBackground(0.42))
      .systemMaterial(ImmersiveMaterial.getThin() ?? undefined)
      .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
      .onClick(action);
  }

  @Builder
  topSearchBar() {
    Row({ space: 8 }) {
      Image($r('app.media.ic_public_search_filled'))
        .width(20).height(20).fillColor('#697582');
      Text('搜索视频')
        .fontSize(14).fontColor('#697582')
        .layoutWeight(1);
    }
    .height(40)
    .layoutWeight(1)
    .padding({ left: 14, right: 14 })
    .backgroundColor(Color.White)
    .borderRadius(20)
    .onClick((): void => { this.onOpenSearch(); });
  }

  @Builder
  topNavButton(label: string, tabIndex: number) {
    Button() {
      Text(label)
        .fontSize(this.selectedTopTab === tabIndex ? 15 : 14)
        .fontColor(this.selectedTopTab === tabIndex ? '#1288FA' : '#3E4854')
        .fontWeight(this.selectedTopTab === tabIndex ? FontWeight.Bold : FontWeight.Normal);
    }
    .type(ButtonType.ROUNDED_RECTANGLE)
    .width(52).height(40)
    .padding(0)
    .backgroundColor(ImmersiveMaterial.surfaceBackground(0.42))
    .systemMaterial(ImmersiveMaterial.getThin() ?? undefined)
    .borderRadius(20)
    .shadow({ radius: 6, color: '#25000000', offsetX: 0, offsetY: 2 })
    .onClick((): void => {
      this.onSelectTab(tabIndex);
    });
  }

  @Builder
  homeTopBar() {
    Row({ space: 4 }) {
      this.topCircleButton('我', (): void => { this.sidebar = 1; });
      this.topNavButton('直播', 0);
      this.topNavButton('推荐', 1);
      this.topNavButton('番剧', 4);
            this.topCircleButton('消息', (): void => {
              router.pushUrl({ url: 'pages/MessagePage' }).catch((error: Object): void => {
                console.error('Pilihos message page push failed: ' + String(error));
              });
            });
    }
    .width('100%')
    .height(66)
    .padding({ left: 8, right: 8, top: 4, bottom: 14 })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceBetween)
    .backgroundColor(Color.Transparent);
  }

  @Builder
  homeCard(item: VideoItem) {
    Stack() {
      Column({ space: 6 }) {
        Stack() {
          if (item.placeholder) {
            Row().width('100%').aspectRatio(1.62).backgroundColor('#E1E6EE');
          } else if (item.cover !== '') {
            Image(item.cover).width('100%').aspectRatio(1.62).objectFit(ImageFit.Cover);
          } else {
            Row().width('100%').aspectRatio(1.62).backgroundColor('#DCE3EF');
          }
        }
        .borderRadius(10)
        .clip(true)
        if (item.placeholder) {
          Row().width('82%').height(16).backgroundColor('#E1E6EE').borderRadius(4);
          Row().width('58%').height(16).backgroundColor('#E1E6EE').borderRadius(4);
        } else {
          Text(item.title).fontSize(14).maxLines(2).fontWeight(FontWeight.Medium).lineHeight(22);
        }
        Row() {
          if (item.placeholder) {
            Row().width('35%').height(12).backgroundColor('#E1E6EE').borderRadius(4).layoutWeight(1);
            Row().width('25%').height(12).backgroundColor('#E1E6EE').borderRadius(4);
          } else {
            Row({ space: 4 }) {
              Image($r('app.media.bfl')).width(14).height(14);
              Text(FormatUtils.formatCount(item.viewCount)).fontSize(11).fontColor('#8B9199');
            }.layoutWeight(1);
            Row({ space: 4 }) {
              Image($r('app.media.dm')).width(14).height(14);
              Text(FormatUtils.formatCount(item.danmuCount)).fontSize(11).fontColor('#8B9199');
            }.layoutWeight(1);
            if (FormatUtils.isPortraitVideo(item, this.portraitBadge)) {
              Text('竖屏').fontSize(10).fontColor('#E661A0')
                .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                .backgroundColor('#1AE661A0').borderRadius(4);
            }
          }
        }.width('100%');
        Row() {
          if (item.placeholder) {
            Row().width('45%').height(12).backgroundColor('#E1E6EE').borderRadius(4);
          } else if (item.followed) {
            Text('已关注').fontSize(10).fontColor('#1288FA').backgroundColor('#E5F3FA')
              .padding({ left: 5, right: 5, top: 2, bottom: 2 }).borderRadius(4).margin({ right: 4 });
          }
          if (!item.placeholder) {
            Row({ space: 4 }) {
              Text(`@${item.author}`).fontSize(11).fontColor('#8B9199').layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick((): void => {
                  // 抑制冒泡到卡片的打开视频点击（卡片 onClick 会消费一次 suppressNextTap）
                  this.suppressNextTap = true;
                  this.onOpenAuthor(item);
                });
              if (FollowState.isFollowed(item.authorMid ?? 0, item.author)) {
                Text('已关注').fontSize(9).fontColor('#1288FA')
                  .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                  .backgroundColor('#1A1288FA').borderRadius(3);
              }
            }.layoutWeight(1);
            Text(FormatUtils.formatPublishTime(item.publishTime)).fontSize(11).fontColor('#8B9199');
            if (this.videoQuickActionsEnabled) {
              Button() {
                Image($r('app.media.lista')).width(17).height(17)
                  .fillColor(this.quickMenuItemId === item.id ? '#1288FA' : '#8B9199');
              }
              .type(ButtonType.ROUNDED_RECTANGLE)
              .width(25).height(25)
              .padding(0)
              .backgroundColor(Color.Transparent)
              .id(`quickbtn_${item.id}`)
              .onClick((): void => {
                this.suppressNextTap = true;
                if (this.quickMenuItemId === item.id) {
                  this.closeQuickMenu();
                  return;
                }
                this.openQuickMenu(item, `quickbtn_${item.id}`);
              });
            }
          }
        }.width('100%');
      }
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .backgroundColor(Color.White)
      .borderRadius(12)
      .height(this.compactGrid ? 320 : 210);
    }
    .alignContent(Alignment.TopEnd)
    .onClick((): void => {
      if (this.suppressNextTap) {
        this.suppressNextTap = false;
        return;
      }
      this.quickMenuItemId = -1;
      if (!item.placeholder) {
        this.onOpenVideo(item);
      }
    })
    .gesture(LongPressGesture({ repeat: false, duration: 500 }).onAction((): void => {
      if (this.videoQuickActionsEnabled && !item.placeholder) {
        this.suppressNextTap = true;
        this.openQuickMenu(item, `homecard_${item.id}`);
      }
    }))
    .backgroundColor(Color.Transparent)
    .borderRadius(12)
    .id(`homecard_${item.id}`);
  }

  // 频道气泡弹出菜单：推荐/热门/直播，替代原左侧迷你球的列表菜单。
  @Builder
  channelListMenu() {
    if (this.listMenuVisible) {
      Column({ space: 4 }) {
        this.channelMenuItem('推荐', 1);
        this.channelMenuItem('热门', 2);
        this.channelMenuItem('直播', 0);
      }
      .width(96).padding({ top: 6, bottom: 6 })
      .backgroundColor(ImmersiveMaterial.surfaceBackground(0.92))
      .systemMaterial(ImmersiveMaterial.getThick() ?? undefined)
      .borderRadius(14)
      .border({ width: 1, color: '#35FFFFFF' })
      .shadow({ radius: 10, color: '#33000000', offsetX: 0, offsetY: 3 })
      .position({ left: 10, top: 58 })
      .zIndex(21)
      .transition({ type: TransitionType.Insert, opacity: 0.0 })
      .animation({ duration: 180, curve: Curve.EaseOut });
    }
  }

  @Builder
  channelMenuItem(label: string, index: number) {
    Text(label).fontSize(14)
      .fontColor(this.contentTab === index ? '#1288FA' : '#3E4854')
      .fontWeight(this.contentTab === index ? FontWeight.Bold : FontWeight.Normal)
      .width('100%').height(36).textAlign(TextAlign.Center)
      .onClick((): void => {
        this.listMenuVisible = false;
        this.onSelectTab(index);
      });
  }

  build() {
    Stack() {
      Column() {
      this.homeTopBar();
      if (this.activeTab === 1) {
        if (this.contentTab === 1) {
          Refresh({ refreshing: $$this.refreshing, offset: 64, friction: 80 }) {
            Grid(this.scroller) {
              if (this.loading && (this.videos.length === 0 || this.videos[0].placeholder)) {
                GridItem() {
                  loadingIndicator('正在加载推荐', '#1288FA');
                }
                .height(72);
              }
              ForEach(this.videos, (item: VideoItem) => {
                GridItem() { this.homeCard(item); }
              }, (item: VideoItem) => `${item.id}_${this.followStamp}`);
              if (this.loadingMore) {
                GridItem() {
                  loadingIndicator('正在加载', '#1288FA');
                }
                .height(52);
              }
            }
            .columnsTemplate(this.compactGrid ? '1fr' : '1fr 1fr')
            .columnsGap(8)
            .rowsGap(10)
            .padding({ left: 12, right: 12, bottom: 12 })
            .onScrollIndex((_first: number, last: number): void => {
              if (last < Math.max(0, this.videos.length - 4)) return;
              if (this.loadingMore) return;
              this.onLoadMore();
            })
            .onDidScroll((offset: number, _state: ScrollState): void => {
              // 列表滚动时关闭锚定菜单，避免菜单与卡片错位
              if (this.quickMenuItemId !== -1) {
                this.closeQuickMenu();
              }
              this.onScrollDelta(offset);
            })
            .width('100%').height('100%').scrollBar(BarState.Off);
          }
          .layoutWeight(1).width('100%')
          .onRefreshing(() => { this.onRefresh(); });
        } else if (this.contentTab === 0) {
          LivePage({ bottomInset: this.bottomInset });
        } else if (this.contentTab === 2) {
          HotPage({ bottomInset: this.bottomInset, showPortraitBadge: this.portraitBadge, followStamp: this.followStamp });
        } else if (this.contentTab === 3) {
          DynamicPage({
            bottomInset: this.bottomInset,
            onPlayVideo: (item: VideoItem, showComments: boolean): void => {
              this.onPlayDynamic(item, showComments);
            },
            onLikeEntry: (entry: DynamicEntry): void => { this.onLikeDynamicEntry(entry); },
            onShareEntry: (entry: DynamicEntry): void => { this.onShareDynamicEntry(entry); }
          });
        } else {
          AnimePage({ bottomInset: this.bottomInset });
        }
      } else if (this.activeTab === 0) {
        DynamicPage({
          bottomInset: this.bottomInset,
          onPlayVideo: (item: VideoItem, showComments: boolean): void => {
            this.onPlayDynamic(item, showComments);
          },
          onLikeEntry: (entry: DynamicEntry): void => { this.onLikeDynamicEntry(entry); },
          onShareEntry: (entry: DynamicEntry): void => { this.onShareDynamicEntry(entry); }
        });
      } else {
        AnimePage({ bottomInset: this.bottomInset });
      }
      }
      // 覆盖层：点击空白处关闭频道菜单
      if (this.listMenuVisible) {
        Column()
          .width('100%').height('100%')
          .backgroundColor(Color.Transparent)
          .onClick((): void => { this.listMenuVisible = false; });
      }
      // 快捷操作菜单 overlay：遮罩 + 锚定菜单，层级高于网格
      if (this.quickMenuItem !== null) {
        Column()
          .width('100%').height('100%')
          .backgroundColor('#1A000000')
          .onClick((): void => { this.closeQuickMenu(); })
          .zIndex(40);
        this.videoQuickMenu(this.quickMenuItem);
      }
    }
    .width('100%').height('100%')
    .alignContent(Alignment.TopStart)
    .padding({ top: this.topInset })
    // Keep the home surface transparent so system material can sample the
    // light-blue page background and the white video cards behind it.
    .backgroundColor(Color.Transparent);
  }

  private homeGridScrollerTop(): void {
    this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }
}
