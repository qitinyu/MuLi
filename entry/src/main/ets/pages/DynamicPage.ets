import { BOTTOM_PAD_LG, BOTTOM_PAD_PHONE, PAGE_PADDING } from '../common/DesignSpec';
import { DynamicCard, VideoCard, VideoOpenParam } from '../model/BiliModels';
import { AuthService } from '../services/AuthService';
import { DynamicService } from '../services/DynamicService';
import { DynamicCardView } from '../components/DynamicCardView';
import { ListFooter, StateView } from '../components/StateView';
import { ScrollSignal } from '../common/ScrollSignal';

/**
 * 动态页（页签二）：关注 UP 主动态流。
 * 该接口未登录恒返回 -101，因此未登录时不发请求，直接给登录引导；
 * 登录成功后由 AppStorage 的 loginTick 信号触发重载（登录页在别的路由，无法直接回调）。
 */
@Component
export struct DynamicPage {
  pathStack: NavPathStack | undefined = undefined;
  scroller: Scroller = new Scroller();
  @Prop topInset: number = 96;
  @Prop breakpoint: string = 'sm';
  @StorageLink('loginTick') @Watch('onLoginTick') loginTick: number = 0;
  @State items: Array<DynamicCard> = [];
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State loadingMore: boolean = false;
  @State errorText: string = '';
  @State needLogin: boolean = false;
  @State hasMore: boolean = true;
  /** 翻页游标：用上一页最后一条动态的 id（不能叫 offset，会与 CustomComponent 的同名属性冲突） */
  private nextOffset: string = '';

  aboutToAppear(): void {
    this.loadFirstPage();
  }

  private onLoginTick(): void {
    // 登录态变化：重置并重新加载
    this.items = [];
    this.nextOffset = '';
    this.hasMore = true;
    this.loadFirstPage();
  }

  private async loadFirstPage(): Promise<void> {
    if (this.loading) {
      return;
    }
    if (!AuthService.isLogin()) {
      this.needLogin = true;
      this.items = [];
      this.refreshing = false;
      return;
    }
    this.needLogin = false;
    this.loading = true;
    this.errorText = '';
    try {
      const cards: Array<DynamicCard> = await DynamicService.load('');
      this.items = cards;
      this.nextOffset = cards.length > 0 ? cards[cards.length - 1].id : '';
      this.hasMore = cards.length > 0;
    } catch (err) {
      const message: string = err instanceof Error ? err.message : '加载失败，请稍后重试';
      if (message.indexOf('未登录') >= 0) {
        this.needLogin = true;
      } else {
        this.errorText = message;
      }
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private async loadMore(): Promise<void> {
    if (this.loadingMore || this.loading || !this.hasMore || this.needLogin || this.nextOffset.length === 0) {
      return;
    }
    this.loadingMore = true;
    try {
      const cards: Array<DynamicCard> = await DynamicService.load(this.nextOffset);
      if (cards.length === 0) {
        this.hasMore = false;
      } else {
        const appended: Array<DynamicCard> = this.items.slice();
        for (let i = 0; i < cards.length; i++) {
          let duplicated: boolean = false;
          for (let j = 0; j < appended.length; j++) {
            if (appended[j].id === cards[i].id) {
              duplicated = true;
              break;
            }
          }
          if (!duplicated) {
            appended.push(cards[i]);
          }
        }
        this.items = appended;
        this.nextOffset = cards[cards.length - 1].id;
      }
    } catch (err) {
      this.hasMore = false;
    } finally {
      this.loadingMore = false;
    }
  }

  private openLogin(): void {
    if (this.pathStack !== undefined) {
      this.pathStack.pushPathByName('login', '');
    }
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text, duration: 1800 });
    } catch (err) {
      // 提示失败不影响主流程
    }
  }

  @Builder
  loginGuide() {
    Column({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
        .fontSize(44)
        .fontColor([$r('app.color.text_tertiary')])
      Text('登录后查看动态')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      Text('关注的人发布了什么，登录沐哩即可同步')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
        .padding({ left: PAGE_PADDING * 2, right: PAGE_PADDING * 2 })
      Row() {
        Text('扫码登录')
          .fontSize(14)
          .fontColor($r('app.color.text_on_brand'))
          .padding({ left: 26, right: 26, top: 9, bottom: 9 })
          .backgroundColor($r('app.color.brand_primary'))
          .borderRadius(19)
      }
      .margin({ top: 6 })
      .onClick(() => {
        this.openLogin();
      })
    }
    .width('100%')
    .padding({ top: 90, bottom: 80 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  dynamicList() {
    List({ scroller: this.scroller }) {
      ListItem() {
        Row()
          .width('100%')
          .height(this.topInset)
      }

      if (this.needLogin) {
        ListItem() {
          this.loginGuide()
        }
      } else if (this.loading && this.items.length === 0) {
        ListItem() {
          StateView({ kind: 'loading', message: '正在加载动态' })
        }
      } else if (this.errorText.length > 0 && this.items.length === 0) {
        ListItem() {
          StateView({
            kind: 'error',
            message: this.errorText,
            hint: '动态接口偶发限流，稍后重试',
            onRetry: () => {
              this.loadFirstPage();
            }
          })
        }
      } else if (this.items.length === 0) {
        ListItem() {
          StateView({ kind: 'empty', message: '关注的 UP 还没有新动态', hint: '去首页逛逛，关注更多人' })
        }
      } else {
        ForEach(this.items, (card: DynamicCard) => {
          ListItem() {
            // 左右留白由这里统一提供：卡片自身已是 width('100%')，
            // 若卡片再加左右 margin 会溢出被裁（右半边不可见）。
            Column() {
              DynamicCardView({
                card: card,
                onCardTap: (item: DynamicCard) => {
                  if (item.kind === 'video' && item.video !== null) {
                    const video: VideoCard = item.video as VideoCard;
                    if (this.pathStack !== undefined) {
                      this.pathStack.pushPathByName('video', new VideoOpenParam(video.bvid, video.aid, video.cid));
                    }
                    return;
                  }
                  this.toast(`动态「${item.authorName}」详情待建设`);
                }
              })
            }
            .width('100%')
            .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
          }
        }, (card: DynamicCard) => card.id)

        if (this.loadingMore) {
          ListItem() {
            ListFooter({ text: '正在加载更多' })
          }
        } else if (!this.hasMore) {
          ListItem() {
            ListFooter({ text: '没有更多动态了', showProgress: false })
          }
        }
      }

      ListItem() {
        Row()
          .width('100%')
          .height(this.breakpoint === 'lg' ? BOTTOM_PAD_LG : BOTTOM_PAD_PHONE)
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onScroll(() => {
      ScrollSignal.report(this.scroller);
    })
    .onReachEnd(() => {
      this.loadMore();
    })
  }

  build() {
    Refresh({ refreshing: $$this.refreshing }) {
      this.dynamicList()
    }
    .width('100%')
    .height('100%')
    .onRefreshing(() => {
      this.refreshing = true;
      this.nextOffset = '';
      this.hasMore = true;
      this.loadFirstPage();
    })
  }
}