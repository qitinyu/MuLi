import router from '@ohos.router';
import { VideoItem } from '../models/VideoItem';

@Entry
@Component
struct HotDetail {
  @State item: VideoItem | null = null;
  @State descriptionExpanded: boolean = false;

  aboutToAppear(): void {
    const params: Object | undefined = router.getParams() as Object | undefined;
    if (params === undefined) return;
    const rawItem: Object | undefined =
      (params as Record<string, Object>)['hotItem'] as Object | undefined;
    if (rawItem !== undefined && Array.isArray(rawItem) === false) {
      this.item = rawItem as VideoItem;
    }
  }

  private playVideo(): void {
    if (this.item === null) return;
    try {
      router.back({
        url: 'pages/Index',
        params: {
          pilihosPlayback: {
            results: [this.item],
            index: 0,
            nonce: `${Date.now()}`
          }
        }
      });
    } catch (error) {
      console.error('Pilihos hot detail playback handoff failed: ' + String(error));
    }
  }

  private formatCount(value: number): string {
    if (value >= 100000000) return `${(value / 100000000).toFixed(2).replace(/\.00$/, '')}亿`;
    if (value >= 1000000) return `${(value / 100000).toFixed(2).replace(/\.00$/, '')}万`;
    if (value >= 1000) return `${(value / 1000).toFixed(1).replace(/\.0$/, '')}千`;
    return `${value}`;
  }

  private formatDuration(seconds: number): string {
    const total: number = Math.max(0, Math.floor(seconds));
    const minutes: number = Math.floor(total / 60);
    const secs: number = total % 60;
    return `${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  }

  private formatPublishTime(timestamp: number): string {
    if (timestamp <= 0) return '发布时间未知';
    const date: Date = new Date(timestamp * 1000);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }

  build() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Scroll() {
          Column() {
            if (this.item !== null) {
              Stack({ alignContent: Alignment.BottomEnd }) {
                Image(this.item.cover).width('100%').aspectRatio(1.78).objectFit(ImageFit.Cover);
                Text(this.formatDuration(this.item.duration)).fontSize(12).fontColor(Color.White)
                  .backgroundColor('#B0000000').padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(4).margin(8);
              }.width('100%');

              Column({ space: 10 }) {
                Text(this.item.title).fontSize(19).fontWeight(FontWeight.Bold).fontColor('#20242A')
                  .lineHeight(27).width('100%');
                Row({ space: 10 }) {
                  if (this.item.authorFace !== '') {
                    Image(this.item.authorFace).width(38).height(38).borderRadius(19)
                      .objectFit(ImageFit.Cover);
                  } else {
                    Row().width(38).height(38).borderRadius(19).backgroundColor('#DCE3EF');
                  }
                  Text(this.item.author === '' ? '未知用户' : this.item.author)
                    .fontSize(15).fontColor('#20242A').layoutWeight(1)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                }.width('100%');
                Row({ space: 16 }) {
                  Text(this.formatCount(this.item.viewCount) + ' 播放').fontSize(12).fontColor('#8B9199');
                  Text(this.formatCount(this.item.danmuCount) + ' 弹幕').fontSize(12).fontColor('#8B9199');
                  Text(this.formatCount(this.item.likeCount) + ' 点赞').fontSize(12).fontColor('#8B9199');
                  Text(this.formatCount(this.item.commentCount) + ' 评论').fontSize(12).fontColor('#8B9199');
                }.width('100%');
                Text('发布于 ' + this.formatPublishTime(this.item.publishTime))
                  .fontSize(12).fontColor('#A4A9AF').width('100%');
                if (this.item.description !== '') {
                  Column({ space: 6 }) {
                    Text('简介').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#20242A');
                    Text(this.item.description).fontSize(14).fontColor('#59616B').lineHeight(22)
                      .maxLines(this.descriptionExpanded ? 1000 : 4)
                      .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
                    Text(this.descriptionExpanded ? '收起' : '展开全部').fontSize(13).fontColor('#1677A8')
                      .onClick(() => { this.descriptionExpanded = !this.descriptionExpanded; });
                  }.width('100%').alignItems(HorizontalAlign.Start);
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14, bottom: 120 })
              .alignItems(HorizontalAlign.Start);
            }
          }.width('100%');
        }
        .width('100%').height('100%')
        .scrollBar(BarState.Off)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);

        Button() {
          Image($r('app.media.fanhui_left')).width(24).height(24).fillColor('#20242A');
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
        .backgroundColor('#E5FFFFFF').borderRadius(22)
        .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
        .margin({ left: 12, top: 12 })
        .onClick(() => { router.back(); });
      }
      .width('100%').height('100%');

      Row() {
        Button('立即播放')
          .type(ButtonType.ROUNDED_RECTANGLE)
          .width('92%').height(46)
          .fontSize(16).fontWeight(FontWeight.Medium)
          .fontColor(Color.White).backgroundColor('#1677A8')
          .enabled(this.item !== null)
          .onClick((): void => { this.playVideo(); });
      }
      .width('100%').justifyContent(FlexAlign.Center)
      .padding({ top: 10, bottom: 24 })
      .backgroundColor(Color.White)
      .shadow({ radius: 12, color: '#1A000000', offsetX: 0, offsetY: -2 });
    }
    .width('100%').height('100%')
    .backgroundColor('#F7F8FA');
  }
}
