import { BOTTOM_PAD_LG, BOTTOM_PAD_PHONE, PAGE_PADDING } from '../common/DesignSpec';
import { LiveCard } from '../model/BiliModels';
import { LiveService } from '../services/LiveService';
import { LiveCardView } from '../components/LiveCardView';
import { ListFooter, StateView } from '../components/StateView';
import { ScrollSignal } from '../common/ScrollSignal';

/**
 * 直播页（页签五）：推荐直播间两列网格。
 * 接口按 page 分页，上拉到底取下一页。
 */
@Component
export struct LivePage {
  scroller: Scroller = new Scroller();
  @Prop topInset: number = 96;
  @Prop breakpoint: string = 'sm';
  @State items: Array<LiveCard> = [];
  @State loading: boolean = false;
  @State refreshing: boolean = false;
  @State loadingMore: boolean = false;
  @State errorText: string = '';
  @State hasMore: boolean = true;
  private page: number = 0;

  aboutToAppear(): void {
    this.loadFirstPage();
  }

  private async loadFirstPage(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      const cards: Array<LiveCard> = await LiveService.load(1);
      this.items = cards;
      this.page = 1;
      this.hasMore = cards.length > 0;
    } catch (err) {
      this.errorText = err instanceof Error ? err.message : '加载失败，请稍后重试';
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private async loadMore(): Promise<void> {
    if (this.loadingMore || this.loading || !this.hasMore) {
      return;
    }
    this.loadingMore = true;
    try {
      const next: number = this.page + 1;
      const cards: Array<LiveCard> = await LiveService.load(next);
      if (cards.length === 0) {
        this.hasMore = false;
      } else {
        const appended: Array<LiveCard> = this.items.slice();
        for (let i = 0; i < cards.length; i++) {
          let duplicated: boolean = false;
          for (let j = 0; j < appended.length; j++) {
            if (appended[j].roomId === cards[i].roomId) {
              duplicated = true;
              break;
            }
          }
          if (!duplicated) {
            appended.push(cards[i]);
          }
        }
        this.items = appended;
        this.page = next;
      }
    } catch (err) {
      this.hasMore = false;
    } finally {
      this.loadingMore = false;
    }
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text, duration: 1800 });
    } catch (err) {
      // 提示失败不影响主流程
    }
  }

  /** 两列网格：每行两间直播间 */
  @Builder
  liveGrid() {
    List({ scroller: this.scroller }) {
      ListItem() {
        Row()
          .width('100%')
          .height(this.topInset)
      }

      if (this.loading && this.items.length === 0) {
        ListItem() {
          StateView({ kind: 'loading', message: '正在加载直播间' })
        }
      } else if (this.errorText.length > 0 && this.items.length === 0) {
        ListItem() {
          StateView({
            kind: 'error',
            message: this.errorText,
            hint: '直播接口对未登录请求限流，稍后重试',
            onRetry: () => {
              this.loadFirstPage();
            }
          })
        }
      } else if (this.items.length === 0) {
        ListItem() {
          StateView({ kind: 'empty', message: '暂时没有直播推荐' })
        }
      } else {
        ForEach(this.pairRows(), (row: Array<LiveCard>, rowIndex: number) => {
          ListItem() {
            Row({ space: 0 }) {
              ForEach(row, (card: LiveCard, cellIndex: number) => {
                Column() {
                  LiveCardView({
                    card: card,
                    onCardTap: (item: LiveCard) => {
                      this.toast(`「${item.uname}」的直播间待建设`);
                    }
                  })
                }
                .layoutWeight(1)
              }, (card: LiveCard, cellIndex: number) => `${rowIndex}-${cellIndex}-${card.roomId}`)
              // 单数个时补一个占位，保持左对齐布局
              if (row.length === 1) {
                Column()
                  .layoutWeight(1)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          }
        }, (row: Array<LiveCard>, rowIndex: number) => `${rowIndex}-${row.length}`)

        if (this.loadingMore) {
          ListItem() {
            ListFooter({ text: '正在加载更多' })
          }
        } else if (!this.hasMore) {
          ListItem() {
            ListFooter({ text: '没有更多直播间了', showProgress: false })
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
    .padding({ left: PAGE_PADDING - 4, right: PAGE_PADDING - 4 })
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onScroll(() => {
      ScrollSignal.report(this.scroller);
    })
    .onReachEnd(() => {
      this.loadMore();
    })
  }

  /** 把一维列表切成每行两个 */
  private pairRows(): Array<Array<LiveCard>> {
    const rows: Array<Array<LiveCard>> = [];
    for (let i = 0; i < this.items.length; i += 2) {
      const row: Array<LiveCard> = [this.items[i]];
      if (i + 1 < this.items.length) {
        row.push(this.items[i + 1]);
      }
      rows.push(row);
    }
    return rows;
  }

  build() {
    Refresh({ refreshing: $$this.refreshing }) {
      this.liveGrid()
    }
    .width('100%')
    .height('100%')
    .onRefreshing(() => {
      this.refreshing = true;
      this.hasMore = true;
      this.loadFirstPage();
    })
  }
}