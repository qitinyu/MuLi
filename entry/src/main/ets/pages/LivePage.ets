import router from '@ohos.router';
import { LiveRoom, LiveService } from '../services/LiveService';

@Component
export struct LivePage {
  @Prop bottomInset: number = 8;
  @State liveList: LiveRoom[] = [];
  @State loading: boolean = true;
  @State loadingMore: boolean = false;
  @State refreshing: boolean = false;
  @State loadError: string = '';
  private page: number = 1;

  aboutToAppear(): void {
    this.loadLiveList(true);
  }

  private async loadLiveList(refresh: boolean = false): Promise<void> {
    if (refresh) {
      if (this.loading) return;
      this.refreshing = true;
      this.loading = true;
      this.loadError = '';
      this.page = 1;
    } else {
      if (this.loadingMore) return;
      this.loadingMore = true;
    }
    try {
      const rooms: LiveRoom[] = await LiveService.loadLiveList(this.page);
      this.liveList = refresh ? rooms : this.liveList.concat(rooms);
    } catch (error) {
      if (refresh) {
        this.loadError = '直播列表加载失败，请检查网络';
      }
      console.error('Pilihos live page load failed: ' + String(error));
    } finally {
      this.loading = false;
      this.loadingMore = false;
      this.refreshing = false;
    }
  }

  private openLiveDetail(room: LiveRoom): void {
    router.pushUrl({
      url: 'pages/LiveDetail',
      params: { room: room }
    }).catch((error: Object): void => {
      console.error('Pilihos live detail page failed: ' + String(error));
    });
  }

  private formatCount(value: number): string {
    if (value >= 100000000) return `${(value / 100000000).toFixed(2).replace(/\.00$/, '')}亿`;
    if (value >= 1000000) return `${(value / 100000).toFixed(2).replace(/\.00$/, '')}万`;
    if (value >= 1000) return `${(value / 1000).toFixed(1).replace(/\.0$/, '')}千`;
    return `${value}`;
  }

  @Builder
  liveCard(room: LiveRoom) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        Image(room.cover !== '' ? room.cover : room.face)
          .width(128).height(82).borderRadius(8).objectFit(ImageFit.Cover);
        Row({ space: 3 }) {
          Circle({ width: 6, height: 6 }).fill(Color.White);
          Text('LIVE').fontSize(10).fontWeight(FontWeight.Bold).fontColor(Color.White);
        }
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .backgroundColor('#E6000044').borderRadius(10)
        .margin(6);
      };
      Column({ space: 6 }) {
        Text(room.title === '' ? '未开播' : room.title).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor('#20242A').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(20).width('100%');
        Row({ space: 6 }) {
          Image(room.face).width(20).height(20).borderRadius(10).objectFit(ImageFit.Cover);
          Text(room.uname).fontSize(12).fontColor('#8B9199').layoutWeight(1)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        }.width('100%');
        Row({ space: 8 }) {
          if (room.areaName !== '') {
            Text(room.areaName).fontSize(10).fontColor('#1677A8')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('#1A1677A8').borderRadius(4);
          }
          Text(this.formatCount(room.online) + ' 人观看').fontSize(11).fontColor('#A4A9AF')
            .layoutWeight(1).maxLines(1);
        }.width('100%');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .padding(10)
    .backgroundColor(Color.White)
    .borderRadius(10)
    .onClick((): void => { this.openLiveDetail(room); });
  }

  build() {
    Refresh({ refreshing: $$this.refreshing, offset: 56, friction: 80 }) {
      Scroll() {
        Column() {
          Text('正在直播').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#1E252D')
            .width('100%').padding({ left: 4, bottom: 12 });
          if (this.liveList.length === 0 && this.loading) {
            Row({ space: 8 }) {
              LoadingProgress().width(26).height(26).color('#1677A8');
              Text('正在获取直播列表...').fontSize(14).fontColor('#1677A8');
            }.justifyContent(FlexAlign.Center).width('100%').margin({ top: 60 });
          } else if (this.liveList.length === 0 && this.loadError !== '') {
            Column({ space: 12 }) {
              Text(this.loadError).fontSize(14).fontColor('#8B9199');
              Button('重试').onClick(() => this.loadLiveList(true));
            }.width('100%').margin({ top: 60 }).alignItems(HorizontalAlign.Center);
          } else {
            ForEach(this.liveList, (room: LiveRoom) => {
              Column() {
                this.liveCard(room);
              }.width('100%').padding({ bottom: 10 });
            }, (room: LiveRoom) => `live_${room.roomId}`);
            if (this.loadingMore) {
              Row({ space: 8 }) {
                LoadingProgress().width(22).height(22).color('#1677A8');
                Text('加载中...').fontSize(13).fontColor('#1677A8');
              }.justifyContent(FlexAlign.Center).width('100%').padding({ top: 10 });
            }
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: this.bottomInset + 88 });
      }
      .width('100%').height('100%')
      .scrollBar(BarState.Off)
      .onReachEnd((): void => {
        if (this.loading || this.loadingMore) return;
        if (this.liveList.length < 20 * this.page) return;
        this.page += 1;
        this.loadLiveList(false);
      });
    }
    .width('100%').height('100%')
    .onRefreshing(() => { this.loadLiveList(true); });
  }
}
