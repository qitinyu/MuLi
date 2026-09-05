import router from '@ohos.router';
import { AuthService } from '../services/AuthService';
import { LiveRoom, LiveService } from '../services/LiveService';

// 模块级缓存：版块切入切出保留首次内容，仅手动刷新更新
let cachedFollowedRooms: LiveRoom[] = [];
let cachedHotRooms: LiveRoom[] = [];
let cachedOtherRooms: LiveRoom[] = [];

@Component
export struct LivePage {
  @Prop bottomInset: number = 8;
  @State followedRooms: LiveRoom[] = [];
  @State hotRooms: LiveRoom[] = [];
  @State otherRooms: LiveRoom[] = [];
  @State followedHint: string = '登录后查看关注的主播直播';
  @State loading: boolean = true;
  @State loadingMore: boolean = false;
  @State refreshing: boolean = false;
  @State loadError: string = '';
  private page: number = 1;
  private fetching: boolean = false;
  private followedFetching: boolean = false;

  aboutToAppear(): void {
    if (cachedFollowedRooms.length > 0 || cachedHotRooms.length > 0) {
      this.followedRooms = cachedFollowedRooms;
      this.hotRooms = cachedHotRooms;
      this.otherRooms = cachedOtherRooms;
      this.loading = false;
      this.refreshFollowedHint();
      return;
    }
    this.loadFollowed();
    this.loadLiveList(true);
  }

  private refreshFollowedHint(): void {
    if (this.followedRooms.length > 0) return;
    const session = AuthService.currentSession();
    this.followedHint = session === null || session.cookie === '' || session.uid === ''
      ? '登录后查看关注的主播直播' : '暂无关注的主播直播';
  }

  private async loadFollowed(): Promise<void> {
    if (this.followedFetching) return;
    this.followedFetching = true;
    try {
      const session = AuthService.currentSession();
      if (session === null || session.cookie === '' || session.uid === '') {
        this.followedRooms = [];
        this.followedHint = '登录后查看关注的主播直播';
        return;
      }
      this.followedRooms = await LiveService.loadFollowedLive(session.cookie, session.uid);
      if (this.followedRooms.length === 0) {
        this.followedHint = '暂无关注的主播直播';
      }
      cachedFollowedRooms = this.followedRooms;
    } catch (error) {
      // 关注区静默降级：失败时不阻塞热门直播展示
      this.followedRooms = [];
      this.followedHint = '暂无关注的主播直播';
      console.error('Pilihos followed live load failed: ' + String(error));
    } finally {
      this.followedFetching = false;
    }
  }

  private async loadLiveList(refresh: boolean = false): Promise<void> {
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
      const rooms: LiveRoom[] = await LiveService.loadLiveList(this.page);
      if (refresh) {
        this.hotRooms = rooms;
        this.otherRooms = [];
      } else {
        this.otherRooms = this.otherRooms.concat(rooms);
      }
      cachedHotRooms = this.hotRooms;
      cachedOtherRooms = this.otherRooms;
    } catch (error) {
      if (refresh) {
        this.loadError = '直播列表加载失败，请检查网络';
      }
      console.error('Pilihos live page load failed: ' + String(error));
    } finally {
      this.loading = false;
      this.loadingMore = false;
      this.refreshing = false;
      this.fetching = false;
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
    if (value >= 10000) return `${(value / 10000).toFixed(1).replace(/\.0$/, '')}万`;
    return `${value}`;
  }

  @Builder
  sectionHeader(title: string, subtitle: string) {
    Row({ space: 8 }) {
      Text(title).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#1E252D');
      Text(subtitle).fontSize(11).fontColor('#A4A9AF').layoutWeight(1);
    }.width('100%').padding({ top: 8, bottom: 10 });
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
          this.sectionHeader('我的关注', '关注的主播');
          if (this.followedRooms.length > 0) {
            ForEach(this.followedRooms, (room: LiveRoom) => {
              Column() {
                this.liveCard(room);
              }.width('100%').padding({ bottom: 10 });
            }, (room: LiveRoom) => `followed_${room.roomId}`);
          } else {
            Text(this.followedHint).fontSize(13).fontColor('#8B9199').width('100%')
              .textAlign(TextAlign.Center).padding({ top: 8, bottom: 14 });
          }
          this.sectionHeader('推荐直播', '全平台实时人气排行');
          if (this.hotRooms.length === 0 && this.loading) {
            Row({ space: 8 }) {
              LoadingProgress().width(26).height(26).color('#1677A8');
              Text('正在获取直播列表...').fontSize(14).fontColor('#1677A8');
            }.justifyContent(FlexAlign.Center).width('100%').margin({ top: 50 });
          } else if (this.hotRooms.length === 0 && this.loadError !== '') {
            Column({ space: 12 }) {
              Text(this.loadError).fontSize(14).fontColor('#8B9199');
              Button('重试').onClick(() => this.loadLiveList(true));
            }.width('100%').margin({ top: 50 }).alignItems(HorizontalAlign.Center);
          } else {
            ForEach(this.hotRooms, (room: LiveRoom) => {
              Column() {
                this.liveCard(room);
              }.width('100%').padding({ bottom: 10 });
            }, (room: LiveRoom) => `hot_${room.roomId}`);
          }
          if (this.otherRooms.length > 0) {
            this.sectionHeader('相关直播', '继续探索更多直播间');
            ForEach(this.otherRooms, (room: LiveRoom) => {
              Column() {
                this.liveCard(room);
              }.width('100%').padding({ bottom: 10 });
            }, (room: LiveRoom) => `other_${room.roomId}`);
          }
          if (this.loadingMore) {
            Row({ space: 8 }) {
              LoadingProgress().width(22).height(22).color('#1677A8');
              Text('加载中...').fontSize(13).fontColor('#1677A8');
            }.justifyContent(FlexAlign.Center).width('100%').padding({ top: 10 });
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: this.bottomInset + 88 });
      }
      .width('100%').height('100%')
      .scrollBar(BarState.Off)
      .onReachEnd((): void => {
        if (this.loading || this.loadingMore) return;
        if (this.hotRooms.length + this.otherRooms.length < 20 * this.page) return;
        this.page += 1;
        this.loadLiveList(false);
      });
    }
    .width('100%').height('100%')
    .onRefreshing(() => {
      this.loadFollowed();
      this.loadLiveList(true);
    });
  }
}
