import { BOTTOM_PAD_LG, BOTTOM_PAD_PHONE } from '../common/DesignSpec';
import { VideoCard, VideoOpenParam } from '../model/BiliModels';
import { HotService } from '../services/HotService';
import { VideoCardView } from '../components/VideoCardView';
import { StateView } from '../components/StateView';
import { ScrollSignal } from '../common/ScrollSignal';

/**
 * 热门页（页签四）：全网排行榜。
 * 排行榜接口一次返回约 100 条且无分页，因此这里不做上拉翻页，只有下拉刷新。
 */
@Component
export struct HotPage {
  pathStack: NavPathStack | undefined = undefined;
  scroller: Scroller = new Scroller();
  @Prop topInset: number = 96;
  @Prop breakpoint: string = 'sm';
  @State items: Array<VideoCard> = [];
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State errorText: string = '';
  /** 首屏只铺 20 条，其余按需展开，避免一次渲染上百个卡片 */
  @State visibleCount: number = 20;

  aboutToAppear(): void {
    this.loadData();
  }

  private async loadData(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      this.items = await HotService.load();
      this.visibleCount = 20;
    } catch (err) {
      this.errorText = err instanceof Error ? err.message : '加载失败，请稍后重试';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text, duration: 1800 });
    } catch (err) {
      // 提示失败不影响主流程
    }
  }

  /** 打开视频二级播放页 */
  private openVideo(item: VideoCard): void {
    if (this.pathStack === undefined) {
      this.toast('播放页暂不可用');
      return;
    }
    this.pathStack.pushPathByName('video', new VideoOpenParam(item.bvid, item.aid, item.cid));
  }

  @Builder
  hotList() {
    List({ scroller: this.scroller }) {
      ListItem() {
        Row()
          .width('100%')
          .height(this.topInset)
      }

      if (this.loading && this.items.length === 0) {
        ListItem() {
          StateView({ kind: 'loading', message: '正在加载热门' })
        }
      } else if (this.errorText.length > 0 && this.items.length === 0) {
        ListItem() {
          StateView({
            kind: 'error',
            message: this.errorText,
            hint: '排行榜接口偶发限流，稍后重试',
            onRetry: () => {
              this.loadData();
            }
          })
        }
      } else if (this.items.length === 0) {
        ListItem() {
          StateView({ kind: 'empty', message: '暂时没有热门内容' })
        }
      } else {
        ForEach(this.items.slice(0, this.visibleCount), (card: VideoCard) => {
          ListItem() {
            VideoCardView({
              card: card,
              onCardTap: (item: VideoCard) => {
                this.openVideo(item);
              },
              onMoreTap: (item: VideoCard) => {
                this.toast(`《${item.title}》更多操作待建设`);
              }
            })
          }
        }, (card: VideoCard, index: number) => `${index}-${card.bvid}-${card.aid}`)

        if (this.visibleCount < this.items.length) {
          ListItem() {
            Row() {
              Text(`展开全部 ${this.items.length} 条`)
                .fontSize(13)
                .fontColor($r('app.color.brand_primary'))
            }
            .width('100%')
            .height(52)
            .justifyContent(FlexAlign.Center)
            .onClick(() => {
              this.visibleCount = this.items.length;
            })
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
  }

  build() {
    Refresh({ refreshing: $$this.refreshing }) {
      this.hotList()
    }
    .width('100%')
    .height('100%')
    .onRefreshing(() => {
      this.refreshing = true;
      this.loadData();
    })
  }
}