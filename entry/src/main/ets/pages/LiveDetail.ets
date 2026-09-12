import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import { LiveQnOption, LiveRoom, LiveRoomStatus, LiveService } from '../services/LiveService';
import { AuthService } from '../services/AuthService';
import { InteractionService } from '../services/InteractionService';

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
  @State qnOptions: LiveQnOption[] = [];
  @State currentQn: number = 0;
  @State lineCount: number = 1;
  @State lineIndex: number = 0;
  @State anchorMid: number = 0;
  @State followed: boolean = false;
  @State followBusy: boolean = false;
  @State qualityMenuVisible: boolean = false;
  @State lineMenuVisible: boolean = false;
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
      const result = await LiveService.loadPlayUrlEx(this.room.roomId, this.currentQn, this.lineIndex);
      this.playUrl = result.url;
      this.currentQn = result.currentQn;
      this.qnOptions = result.qnOptions;
      this.lineCount = result.lineCount;
      this.lineIndex = result.lineIndex;
      if (result.anchorMid > 0 && this.anchorMid === 0) {
        this.anchorMid = result.anchorMid;
        this.loadFollowState();
      }
    } catch (error) {
      this.streamError = String(error);
      console.error('Pilihos live stream resolve failed: ' + String(error));
    }
  }

  private async loadFollowState(): Promise<void> {
    const session = AuthService.currentSession();
    if (session === null || session.cookie === '') return;
    try {
      const attribute: number = await InteractionService.relationAttribute(this.anchorMid, session.cookie);
      this.followed = attribute === 2 || attribute === 6 || attribute === 128;
    } catch (error) {
      console.warn(`Pilihos live follow state failed: ${String(error)}`);
    }
  }

  private async toggleFollow(): Promise<void> {
    if (this.followBusy) return;
    const session = AuthService.currentSession();
    if (session === null || session.cookie === '' || session.csrf === '') {
      this.showToast('请先登录后再关注');
      return;
    }
    this.followBusy = true;
    const on: boolean = !this.followed;
    try {
      await InteractionService.follow(this.anchorMid, on, session.cookie, session.csrf, '14');
      this.followed = on;
      this.showToast(on ? `已关注 ${this.room.uname}` : '已取消关注');
    } catch (error) {
      this.showToast(`关注操作失败: ${String(error)}`);
    } finally {
      this.followBusy = false;
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2500, bottom: 24 });
    } catch (error) {
      console.error(`Pilihos live detail toast failed: ${String(error)}`);
    }
  }

  private currentQnDesc(): string {
    const matched: LiveQnOption | undefined =
      this.qnOptions.find((option: LiveQnOption): boolean => option.qn === this.currentQn);
    if (matched !== undefined) return matched.desc;
    return this.currentQn > 0 ? `${this.currentQn}` : '清晰度';
  }

  private formatCount(value: number): string {
    if (value >= 100000000) return `${(value / 100000000).toFixed(2).replace(/\.00$/, '')}亿`;
    if (value >= 10000) return `${(value / 10000).toFixed(1).replace(/\.0$/, '')}万`;
    return `${value}`;
  }

  @Builder
  qualityMenu() {
    Column({ space: 2 }) {
      Text('清晰度').fontSize(12).fontWeight(FontWeight.Bold).fontColor('#20252B')
        .width('100%').height(28).textAlign(TextAlign.Center);
      ForEach(this.qnOptions, (option: LiveQnOption) => {
        Text(option.qn === this.currentQn ? `${option.desc} ✓` : option.desc).fontSize(12)
          .fontColor(option.qn === this.currentQn ? '#1288FA' : '#1E252D')
          .width('100%').height(28).textAlign(TextAlign.Center)
          .onClick((): void => {
            this.qualityMenuVisible = false;
            if (option.qn !== this.currentQn) {
              this.currentQn = option.qn;
              this.refreshStream();
            }
          });
      }, (option: LiveQnOption) => `lqn_${option.qn}`);
    }.width(96).padding({ top: 6, bottom: 6 }).backgroundColor('#F7F8FA')
      .borderRadius(10).shadow({ radius: 10, color: '#33000000', offsetX: 0, offsetY: 3 });
  }

  @Builder
  lineMenu() {
    Column({ space: 2 }) {
      Text('线路').fontSize(12).fontWeight(FontWeight.Bold).fontColor('#20252B')
        .width('100%').height(28).textAlign(TextAlign.Center);
      ForEach(Array.from({ length: this.lineCount }, (_v: Object, i: number): number => i), (index: number) => {
        Text(index === this.lineIndex ? `线路${index + 1} ✓` : `线路${index + 1}`).fontSize(12)
          .fontColor(index === this.lineIndex ? '#1288FA' : '#1E252D')
          .width('100%').height(28).textAlign(TextAlign.Center)
          .onClick((): void => {
            this.lineMenuVisible = false;
            if (index !== this.lineIndex) {
              this.lineIndex = index;
              this.refreshStream();
            }
          });
      }, (index: number) => `line_${index}`);
    }.width(88).padding({ top: 6, bottom: 6 }).backgroundColor('#F7F8FA')
      .borderRadius(10).shadow({ radius: 10, color: '#33000000', offsetX: 0, offsetY: 3 });
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

        if (this.playUrl !== '') {
          Row({ space: 8 }) {
            Text(this.currentQnDesc())
              .fontSize(12).fontColor(Color.White)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor('#66000000').borderRadius(14)
              .bindMenu(this.qualityMenuVisible, this.qualityMenu(), {
                placement: Placement.Top,
                enableArrow: false,
                showInSubWindow: true
              })
              .onClick((): void => {
                this.qualityMenuVisible = !this.qualityMenuVisible;
                this.lineMenuVisible = false;
              });
            Text(this.lineCount > 1 ? `线路${this.lineIndex + 1}/${this.lineCount}` : '线路')
              .fontSize(12).fontColor(Color.White)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor('#66000000').borderRadius(14)
              .bindMenu(this.lineMenuVisible, this.lineMenu(), {
                placement: Placement.Top,
                enableArrow: false,
                showInSubWindow: true
              })
              .onClick((): void => {
                this.lineMenuVisible = !this.lineMenuVisible;
                this.qualityMenuVisible = false;
              });
          }
          .position({ right: 12, bottom: 12 });
        }
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
                  Text(this.room.areaName).fontSize(11).fontColor('#1288FA')
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .backgroundColor('#1A1288FA').borderRadius(4);
                }
                Text(this.status !== null ? this.formatCount(this.status.online) + ' 人观看'
                  : this.formatCount(this.room.online) + ' 人观看')
                  .fontSize(11).fontColor('#A4A9AF');
              };
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            Button(this.followed ? '已关注' : '关注').height(32).fontSize(12)
              .backgroundColor(this.followed ? '#F1F3F5' : '#F04B55')
              .fontColor(this.followed ? '#59616B' : Color.White)
              .visibility(this.anchorMid > 0 ? Visibility.Visible : Visibility.None)
              .onClick((): void => { this.toggleFollow(); });
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
