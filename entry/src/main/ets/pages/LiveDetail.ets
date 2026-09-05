import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import { LiveRoom, LiveRoomStatus, LiveService } from '../services/LiveService';

@Entry
@Component
struct LiveDetail {
  @State room: LiveRoom = new LiveRoom();
  @State status: LiveRoomStatus | null = null;
  @State playUrl: string = '';
  @State loading: boolean = true;
  @State loadError: string = '';
  @State streamError: string = '';
  @State topInset: number = 0;
  @State onlineText: string = '';
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.updateSystemInsets();
    const params: Object | undefined = router.getParams() as Object | undefined;
    if (params !== undefined) {
      const rawRoom: Object | undefined =
        (params as Record<string, Object>)['room'] as Object | undefined;
      if (rawRoom !== undefined) {
        this.room = rawRoom as LiveRoom;
      }
    }
    this.loadRoom();
  }

  private async updateSystemInsets(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = px2vp(systemArea.topRect.height);
    } catch (error) {
      console.error('Pilihos live detail inset update failed: ' + String(error));
    }
  }

  private async loadRoom(): Promise<void> {
    if (this.room.roomId <= 0) {
      this.loading = false;
      this.loadError = '直播间参数缺失';
      return;
    }
    this.loading = true;
    this.loadError = '';
    this.streamError = '';
    this.playUrl = '';
    try {
      this.status = await LiveService.loadRoomStatus(this.room.roomId);
      if (this.status.title !== '') {
        this.room.title = this.status.title;
      }
      if (this.status.liveStatus !== 1) {
        this.loadError = '当前主播未开播';
        this.loading = false;
        return;
      }
      await this.refreshStream();
    } catch (error) {
      this.loadError = '直播间信息加载失败，请检查网络';
      console.error('Pilihos live detail load failed: ' + String(error));
    } finally {
      this.loading = false;
    }
  }

  private async refreshStream(): Promise<void> {
    this.streamError = '';
    try {
      this.playUrl = await LiveService.loadPlayUrl(this.room.roomId);
    } catch (error) {
      this.streamError = String(error);
      console.error('Pilihos live stream resolve failed: ' + String(error));
    }
  }

  private formatCount(value: number): string {
    if (value >= 100000000) return `${(value / 100000000).toFixed(2).replace(/\.00$/, '')}亿`;
    if (value >= 1000000) return `${(value / 100000).toFixed(2).replace(/\.00$/, '')}万`;
    if (value >= 1000) return `${(value / 1000).toFixed(1).replace(/\.0$/, '')}千`;
    return `${value}`;
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          if (this.playUrl !== '') {
            Video({ src: this.playUrl })
              .width('100%').height('100%')
              .objectFit(ImageFit.Contain)
              .controls(true)
              .autoPlay(true)
              .loop(false)
              .onError((): void => {
                this.streamError = '直播流播放异常，可尝试更换线路';
              });
          } else if (this.streamError !== '') {
            Column({ space: 12 }) {
              Text(this.streamError).fontSize(13).fontColor('#E8F0F4').textAlign(TextAlign.Center);
              Button('更换线路').onClick((): void => { this.refreshStream(); });
            }.justifyContent(FlexAlign.Center).width('100%').height('100%');
          } else {
            Stack({ alignContent: Alignment.Center }) {
              Image(this.status !== null && this.status.keyframe !== '' ? this.status.keyframe : this.room.cover)
                .width('100%').height('100%').objectFit(ImageFit.Cover);
              if (this.loading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(26).height(26).color(Color.White);
                  Text('正在连接直播间...').fontSize(13).fontColor(Color.White);
                }.justifyContent(FlexAlign.Center);
              }
            }.width('100%').height('100%');
          }
        }
        .width('100%').height('100%')
        .backgroundColor('#101418');

        Button() {
          Image($r('app.media.fanhui_left')).width(24).height(24).fillColor(Color.White);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(42).height(42)
        .backgroundColor('#66000000').borderRadius(21)
        .margin({ left: 12, top: this.topInset + 10 })
        .onClick(() => { router.back(); });
      }
      .width('100%').aspectRatio(1.78);

      Scroll() {
        Column({ space: 12 }) {
          Text(this.room.title === '' ? '未开播' : this.room.title)
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor('#20242A')
            .lineHeight(25).width('100%');
          Row({ space: 10 }) {
            Image(this.room.face).width(40).height(40).borderRadius(20).objectFit(ImageFit.Cover);
            Column({ space: 3 }) {
              Text(this.room.uname === '' ? '未知主播' : this.room.uname)
                .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#20242A')
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              Row({ space: 8 }) {
                if (this.room.areaName !== '') {
                  Text(this.room.areaName).fontSize(11).fontColor('#1677A8')
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .backgroundColor('#1A1677A8').borderRadius(4);
                }
                Text(this.status !== null ? this.formatCount(this.status.online) + ' 人观看'
                  : this.formatCount(this.room.online) + ' 人观看')
                  .fontSize(11).fontColor('#A4A9AF');
              };
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            Button('刷新线路').height(32).fontSize(12)
              .onClick((): void => { this.refreshStream(); });
          }.width('100%');
          if (this.loadError !== '') {
            Text(this.loadError).fontSize(13).fontColor('#C51D2A').width('100%');
            Button('重新加载').onClick((): void => { this.loadRoom(); });
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 14, bottom: 40 })
        .alignItems(HorizontalAlign.Start);
      }
      .layoutWeight(1).width('100%')
      .scrollBar(BarState.Off);
    }
    .width('100%').height('100%')
    .backgroundColor('#F7F8FA');
  }
}
