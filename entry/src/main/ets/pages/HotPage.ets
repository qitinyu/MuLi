import router from '@ohos.router';
import { VideoItem } from '../models/VideoItem';
import { HotService } from '../services/HotService';

@Component
export struct HotPage {
  @Prop bottomInset: number = 8;
  @State hotList: VideoItem[] = [];
  @State loading: boolean = true;
  @State loadingMore: boolean = false;
  @State refreshing: boolean = false;
  @State loadError: string = '';
  private page: number = 1;
  private fetching: boolean = false;

  aboutToAppear(): void {
    this.loadHotList(true);
  }

  private async loadHotList(refresh: boolean = false): Promise<void> {
    if (this.fetching) return;
    this.fetching = true;
    if (refresh) {
      this.refreshing = true;
      this.loading = true;
      this.loadError = '';
      this.page = 1;
    } else {
      this.loadingMore = true;
    }
    try {
      const items: VideoItem[] = await HotService.loadPopular(this.page);
      this.hotList = refresh ? items : this.hotList.concat(items);
    } catch (error) {
      if (refresh) {
        this.loadError = '热门榜单加载失败，请检查网络';
      }
      console.error('Pilihos hot page load failed: ' + String(error));
    } finally {
      this.loading = false;
      this.loadingMore = false;
      this.refreshing = false;
      this.fetching = false;
    }
  }

  private openHotDetail(item: VideoItem): void {
    router.pushUrl({
      url: 'pages/HotDetail',
      params: { hotItem: item }
    }).catch((error: Object): void => {
      console.error('Pilihos hot detail page failed: ' + String(error));
    });
  }

  private formatCount(value: number): string {
    if (value >= 100000000) return `${(value / 100000000).toFixed(2).replace(/\.00$/, '')}亿`;
    if (value >= 1000000) return `${(value / 100000).toFixed(2).replace(/\.00$/, '')}万`;
    if (value >= 1000) return `${(value / 1000).toFixed(1).replace(/\.0$/, '')}千`;
    return `${value}`;
  }

  @Builder
  hotCard(item: VideoItem, rank: number) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Image(item.cover).width('100%').aspectRatio(1.6).objectFit(ImageFit.Cover).borderRadius(8);
        if (rank <= 3) {
          Text(String(rank)).fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.White)
            .width(26).height(26).textAlign(TextAlign.Center).lineHeight(26)
            .backgroundColor(rank === 1 ? '#E6A23C' : rank === 2 ? '#98A2AE' : '#C77B4A')
            .borderRadius({ topLeft: 8, bottomRight: 8 });
        }
        Text(this.formatDuration(item.duration)).fontSize(11).fontColor(Color.White)
          .backgroundColor('#B0000000').padding({ left: 5, right: 5, top: 2, bottom: 2 })
          .borderRadius(4).markAnchor({ x: '100%', y: '100%' })
          .position({ right: 6, bottom: 6 });
      }.width('100%');
      Text(item.title).fontSize(14).fontColor('#20242A').maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').lineHeight(20);
      Text(item.author === '' ? '未知用户' : item.author).fontSize(12).fontColor('#8B9199')
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
      Text(this.formatCount(item.viewCount) + ' 播放').fontSize(11).fontColor('#A4A9AF').width('100%');
    }.width('100%')
      .onClick((): void => { this.openHotDetail(item); });
  }

  private formatDuration(seconds: number): string {
    const total: number = Math.max(0, Math.floor(seconds));
    const minutes: number = Math.floor(total / 60);
    const secs: number = total % 60;
    return `${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  }

  build() {
    Refresh({ refreshing: $$this.refreshing, offset: 56, friction: 80 }) {
      Scroll() {
        Column() {
          Text('热门榜单').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#1E252D')
            .width('100%').padding({ left: 4, bottom: 12 });
          if (this.hotList.length === 0 && this.loading) {
            Row({ space: 8 }) {
              LoadingProgress().width(26).height(26).color('#1677A8');
              Text('正在加载热门榜单...').fontSize(14).fontColor('#1677A8');
            }.justifyContent(FlexAlign.Center).width('100%').margin({ top: 60 });
          } else if (this.hotList.length === 0 && this.loadError !== '') {
            Column({ space: 12 }) {
              Text(this.loadError).fontSize(14).fontColor('#8B9199');
              Button('重试').onClick(() => this.loadHotList(true));
            }.width('100%').margin({ top: 60 }).alignItems(HorizontalAlign.Center);
          } else {
            Grid() {
              ForEach(this.hotList, (item: VideoItem, index: number) => {
                GridItem() {
                  this.hotCard(item, index + 1);
                }
              }, (item: VideoItem) => `hot_${item.aid}_${item.bvid}`);
              if (this.loadingMore) {
                GridItem().height(48);
              }
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(10)
            .rowsGap(14)
            .width('100%');
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: this.bottomInset + 88 });
      }
      .width('100%').height('100%')
      .scrollBar(BarState.Off)
      .onReachEnd((): void => {
        if (this.loading || this.loadingMore) return;
        if (this.hotList.length < 20 * this.page) return;
        this.page += 1;
        this.loadHotList(false);
      });
    }
    .width('100%').height('100%')
    .onRefreshing(() => { this.loadHotList(true); });
  }
}
