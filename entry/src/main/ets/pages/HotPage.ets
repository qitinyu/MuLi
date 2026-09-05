import router from '@ohos.router';
import { VideoItem } from '../models/VideoItem';
import { HotService } from '../services/HotService';

// 模块级缓存：版块切入切出保留首次内容，仅手动刷新更新
let cachedHotList: VideoItem[] = [];

@Component
export struct HotPage {
  @Prop bottomInset: number = 8;
  @Prop showPortraitBadge: boolean = true;
  @State hotList: VideoItem[] = [];
  @State loading: boolean = true;
  @State loadingMore: boolean = false;
  @State refreshing: boolean = false;
  @State loadError: string = '';
  private page: number = 1;
  private fetching: boolean = false;

  aboutToAppear(): void {
    if (cachedHotList.length > 0) {
      this.hotList = cachedHotList;
      this.page = Math.max(1, Math.ceil(cachedHotList.length / 20));
      this.loading = false;
      return;
    }
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
      cachedHotList = this.hotList;
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
    if (value >= 10000) return `${(value / 10000).toFixed(1).replace(/\.0$/, '')}万`;
    return `${value}`;
  }

  @Builder
  hotCard(item: VideoItem, rank: number) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Image(item.cover).width('100%').aspectRatio(1.6).objectFit(ImageFit.Cover).borderRadius(8);
        Row() {
          if (rank <= 3) {
            Text(String(rank)).fontSize(13).fontWeight(FontWeight.Bold).fontColor(Color.White)
              .width(24).height(24).textAlign(TextAlign.Center).lineHeight(24)
              .backgroundColor(rank === 1 ? '#E6A23C' : rank === 2 ? '#98A2AE' : '#C77B4A')
              .borderRadius(12);
          }
          Blank();
          Text(this.formatDuration(item.duration)).fontSize(11).fontColor(Color.White)
            .backgroundColor('#B0000000').padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .borderRadius(4);
        }.width('100%').padding(6).alignItems(VerticalAlign.Center);
      }.width('100%');
      Text(item.title).fontSize(14).fontColor('#20242A').maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').lineHeight(20);
      Text(item.author === '' ? '未知用户' : item.author).fontSize(12).fontColor('#8B9199')
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
      Row({ space: 10 }) {
        Row({ space: 3 }) {
          Image($r('app.media.bofang')).width(11).height(11);
          Text(this.formatCount(item.viewCount)).fontSize(11).fontColor('#A4A9AF');
        }
        Row({ space: 3 }) {
          Image($r('app.media.dm')).width(11).height(11);
          Text(this.formatCount(item.danmuCount)).fontSize(11).fontColor('#A4A9AF');
        }
        if (this.showPortraitBadge && Number(item.videoWidth ?? 0) > 0
          && Number(item.videoWidth ?? 0) < Number(item.videoHeight ?? 0)) {
          Text('竖屏').fontSize(9).fontColor('#E661A0')
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor('#1AE661A0').borderRadius(3);
        }
        Text(this.formatPublishTime(item.publishTime)).fontSize(11).fontColor('#A4A9AF')
          .layoutWeight(1).textAlign(TextAlign.End)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.width('100%');
    }.width('100%')
      .onClick((): void => { this.openHotDetail(item); });
  }

  private formatPublishTime(timestamp: number): string {
    if (timestamp <= 0) return '';
    const seconds: number = Math.max(0, Math.floor(Date.now() / 1000) - timestamp);
    if (seconds < 3600) return `${String(Math.max(1, Math.floor(seconds / 60)))}分钟前`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}小时前`;
    if (seconds < 259200) return `${Math.floor(seconds / 86400)}天前`;
    const date: Date = new Date(timestamp * 1000);
    return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`;
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
