import { VideoItem } from '../models/VideoItem';
import { AuthService } from '../services/AuthService';
import { DynamicAuthor, DynamicEntry, DynamicFeedBatch, DynamicPic, DynamicService } from '../services/DynamicService';

@Component
export struct DynamicPage {
  @Prop bottomInset: number = 8;
  onPlayVideo: (item: VideoItem, showComments: boolean) => void =
    (_item: VideoItem, _showComments: boolean) => {};
  @State entries: DynamicEntry[] = [];
  @State authors: DynamicAuthor[] = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State loadingMore: boolean = false;
  @State loadError: string = '';
  @State selectedAuthor: string = '';
  private feedOffset: string = '';
  private hasMore: boolean = false;
  private fetching: boolean = false;

  private toggleAuthorFilter(name: string): void {
    this.selectedAuthor = this.selectedAuthor === name ? '' : name;
  }

  private visibleEntries(): DynamicEntry[] {
    if (this.selectedAuthor === '') return this.entries;
    return this.entries.filter((entry: DynamicEntry): boolean =>
      entry.authorName === this.selectedAuthor);
  }

  aboutToAppear(): void {
    this.loadFeed(true);
  }

  private async loadFeed(refresh: boolean = false): Promise<void> {
    if (this.fetching) return;
    if (!refresh && !this.hasMore) return;
    this.fetching = true;
    if (refresh) {
      this.refreshing = true;
      this.loading = true;
      this.loadError = '';
      this.feedOffset = '';
    } else {
      this.loadingMore = true;
    }
    try {
      const session = AuthService.currentSession();
      const cookie: string = session === null ? '' : session.cookie;
      if (cookie === '') {
        this.entries = [];
        this.loadError = '登录后查看关注用户的最新动态';
        return;
      }
      const batch: DynamicFeedBatch =
        await DynamicService.loadFeed(cookie, refresh ? '' : this.feedOffset);
      this.feedOffset = batch.offset;
      this.hasMore = batch.hasMore;
      this.entries = refresh ? batch.entries : this.entries.concat(batch.entries);
      if (refresh) {
        this.authors = batch.authors;
      } else {
        const merged: DynamicAuthor[] = this.authors.slice();
        batch.authors.forEach((author: DynamicAuthor): void => {
          if (!merged.some((candidate: DynamicAuthor): boolean => candidate.name === author.name)) {
            merged.push(author);
          }
        });
        this.authors = merged;
      }
    } catch (error) {
      if (refresh) {
        this.loadError = '动态加载失败，请检查网络或登录状态';
      }
      console.error('Pilihos dynamic page load failed: ' + String(error));
    } finally {
      this.loading = false;
      this.refreshing = false;
      this.loadingMore = false;
      this.fetching = false;
    }
  }

  private formatPublishTime(timestamp: number): string {
    if (timestamp <= 0) return '';
    const seconds: number = Math.max(0, Math.floor(Date.now() / 1000) - timestamp);
    if (seconds < 3600) return `${String(Math.max(1, Math.floor(seconds / 60)))}分钟前`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}小时前`;
    if (seconds < 2592000) return `${Math.floor(seconds / 86400)}天前`;
    const date: Date = new Date(timestamp * 1000);
    return `${date.getFullYear()}/${date.getMonth() + 1}/${date.getDate()}`;
  }

  private formatCount(value: number): string {
    if (value >= 100000000) return `${(value / 100000000).toFixed(2).replace(/\.00$/, '')}亿`;
    if (value >= 10000) return `${(value / 10000).toFixed(1).replace(/\.0$/, '')}万`;
    return `${value}`;
  }

  @Builder
  picGrid(entry: DynamicEntry) {
    if (entry.pics.length === 1) {
      Image(entry.pics[0].url).width('100%').height(210).objectFit(ImageFit.Cover)
        .borderRadius(8);
    } else {
      Grid() {
        ForEach(entry.pics.slice(0, 9), (pic: DynamicPic) => {
          GridItem() {
            Image(pic.url).width('100%').height(96).objectFit(ImageFit.Cover).borderRadius(6);
          }
        }, (pic: DynamicPic, index: number) => `pic_${index}_${pic.url.length}`);
      }
      .columnsTemplate('1fr 1fr 1fr')
      .columnsGap(4)
      .rowsGap(4)
      .height(entry.pics.length <= 3 ? 96 : entry.pics.length <= 6 ? 196 : 296)
      .width('100%');
    }
  }

  @Builder
  videoCard(item: VideoItem) {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Image(item.cover).width(128).height(80).borderRadius(8).objectFit(ImageFit.Cover);
        if (item.duration > 0) {
          Text(this.formatDuration(item.duration)).fontSize(10).fontColor(Color.White)
            .backgroundColor('#B0000000').padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .borderRadius(3).margin(4);
        }
      };
      Text(item.title).fontSize(14).fontColor('#20242A').maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(20).layoutWeight(1);
    }
    .width('100%')
    .padding(8)
    .backgroundColor('#F4F6F8')
    .borderRadius(8)
    .onClick((): void => { this.onPlayVideo(item, false); });
  }

  private formatDuration(seconds: number): string {
    const total: number = Math.max(0, Math.floor(seconds));
    const minutes: number = Math.floor(total / 60);
    const secs: number = total % 60;
    return `${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  }

  @Builder
  dynamicEntryCard(entry: DynamicEntry) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Image(entry.authorFace).width(40).height(40).borderRadius(20).objectFit(ImageFit.Cover);
        Column({ space: 2 }) {
          Text(entry.authorName).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#20242A')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.formatPublishTime(entry.publishTime)).fontSize(11).fontColor('#A4A9AF');
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      }.width('100%');
      if (entry.text !== '') {
        Text(entry.text).fontSize(15).fontColor('#20242A').lineHeight(23).width('100%');
      }
      if (entry.type === 'video' && entry.video !== null) {
        this.videoCard(entry.video);
      } else if (entry.type === 'pics' && entry.pics.length > 0) {
        this.picGrid(entry);
      }
      if (entry.repostName !== '') {
        Column({ space: 8 }) {
          Text('转发自 @' + entry.repostName).fontSize(12).fontColor('#1677A8').width('100%');
          if (entry.repostVideo !== null) {
            this.videoCard(entry.repostVideo);
          } else if (entry.repostText !== '') {
            Text(entry.repostText).fontSize(13).fontColor('#59616B').lineHeight(20).width('100%');
          }
        }
        .width('100%')
        .padding(10)
        .backgroundColor('#F4F6F8')
        .borderRadius(8)
        .alignItems(HorizontalAlign.Start);
      }
      Row({ space: 24 }) {
        Row({ space: 5 }) {
          Image($r('app.media.dianzan')).width(16).height(16).fillColor('#8B9199');
          Text(this.formatCount(entry.stat.like)).fontSize(12).fontColor('#8B9199');
        };
        Row({ space: 5 }) {
          Image($r('app.media.pl')).width(16).height(16).fillColor('#8B9199');
          Text(this.formatCount(entry.stat.comment)).fontSize(12).fontColor('#8B9199');
        }
          .onClick((): void => {
            if (entry.video !== null) {
              this.onPlayVideo(entry.video, true);
            } else if (entry.repostVideo !== null) {
              this.onPlayVideo(entry.repostVideo, true);
            }
          });
        Row({ space: 5 }) {
          Image($r('app.media.share')).width(16).height(16).fillColor('#8B9199');
          Text(this.formatCount(entry.stat.share)).fontSize(12).fontColor('#8B9199');
        };
      }.width('100%').justifyContent(FlexAlign.Start);
    }
    .width('100%')
    .padding(14)
    .backgroundColor(Color.White)
    .borderRadius(10)
    .alignItems(HorizontalAlign.Start);
  }

  build() {
    Refresh({ refreshing: $$this.refreshing, offset: 56, friction: 80 }) {
      Scroll() {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Text('最近更新').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1E252D')
              .layoutWeight(1);
            if (this.selectedAuthor !== '') {
              Row({ space: 5 }) {
                Text('只看 @' + this.selectedAuthor).fontSize(11).fontColor('#1677A8')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 150 });
                Text('✕').fontSize(11).fontColor('#1677A8').fontWeight(FontWeight.Bold);
              }
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor('#1A1677A8').borderRadius(12)
              .onClick(() => { this.selectedAuthor = ''; });
            }
          }.width('100%').height(40);
          if (this.authors.length > 0) {
            Scroll() {
              Row({ space: 14 }) {
                ForEach(this.authors, (author: DynamicAuthor) => {
                  Column({ space: 4 }) {
                    Image(author.face).width(50).height(50).borderRadius(25).objectFit(ImageFit.Cover)
                      .border({
                        width: this.selectedAuthor === author.name ? 2.5 : 0,
                        color: '#1677A8'
                      });
                    Text(author.name).fontSize(11)
                      .fontColor(this.selectedAuthor === author.name ? '#1677A8' : '#59616B')
                      .fontWeight(this.selectedAuthor === author.name ? FontWeight.Bold : FontWeight.Normal)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width(58).textAlign(TextAlign.Center);
                  }.width(58)
                    .onClick(() => { this.toggleAuthorFilter(author.name); });
                }, (author: DynamicAuthor) => `dynamic_author_${author.name}`);
              }.width(Math.max(4, this.authors.length * 72 + 4))
                .padding({ left: 2, right: 2 });
            }.width('100%').height(78)
              .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off);
          }
          if (this.entries.length === 0 && this.loading) {
            Row({ space: 8 }) {
              LoadingProgress().width(26).height(26).color('#1677A8');
              Text('正在加载动态...').fontSize(14).fontColor('#1677A8');
            }.justifyContent(FlexAlign.Center).width('100%').margin({ top: 50 });
          } else if (this.entries.length === 0 && this.loadError !== '') {
            Text(this.loadError).fontSize(14).fontColor('#8B9199').width('100%')
              .textAlign(TextAlign.Center).margin({ top: 50 });
          } else if (this.visibleEntries().length === 0) {
            Text('该UP主暂无可展示的动态').fontSize(14).fontColor('#8B9199').width('100%')
              .textAlign(TextAlign.Center).margin({ top: 50 });
          } else {
            ForEach(this.visibleEntries(), (entry: DynamicEntry) => {
              this.dynamicEntryCard(entry);
            }, (entry: DynamicEntry) => `entry_${entry.id}_${entry.authorName}`);
            if (this.loadingMore) {
              Row({ space: 8 }) {
                LoadingProgress().width(22).height(22).color('#1677A8');
                Text('加载更多动态...').fontSize(13).fontColor('#1677A8');
              }.justifyContent(FlexAlign.Center).width('100%').padding({ top: 8, bottom: 8 });
            } else if (!this.hasMore && this.entries.length > 0) {
              Text('没有更多动态了').fontSize(12).fontColor('#A4A9AF').width('100%')
                .textAlign(TextAlign.Center).padding({ top: 8, bottom: 8 });
            }
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: this.bottomInset + 88 })
        .alignItems(HorizontalAlign.Start);
      }
      .width('100%').height('100%')
      .scrollBar(BarState.Off)
      .onReachEnd((): void => { this.loadFeed(false); });
    }
    .width('100%').height('100%')
    .onRefreshing(() => { this.loadFeed(true); });
  }
}
