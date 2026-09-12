import router from '@ohos.router';
import { AnimeSeason, AnimeService } from '../services/AnimeService';

// 模块级缓存：版块切入切出保留首次内容，仅手动刷新更新
let cachedAnimeList: AnimeSeason[] = [];

@Component
export struct AnimePage {
  @Prop bottomInset: number = 8;
  @State animeList: AnimeSeason[] = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State loadError: string = '';

  aboutToAppear(): void {
    if (cachedAnimeList.length > 0) {
      this.animeList = cachedAnimeList;
      this.loading = false;
      return;
    }
    this.loadRankList();
  }

  private async loadRankList(): Promise<void> {
    if (this.animeList.length > 0) {
      this.refreshing = true;
    } else {
      this.loading = true;
    }
    this.loadError = '';
    try {
      this.animeList = await AnimeService.loadRank();
      cachedAnimeList = this.animeList;
    } catch (error) {
      this.loadError = '番剧榜单加载失败，请检查网络';
      console.error('Pilihos anime page load failed: ' + String(error));
    } finally {
      this.loading = false;
      this.refreshing = false;
    }
  }

  private openAnimeDetail(season: AnimeSeason): void {
    router.pushUrl({
      url: 'pages/AnimeDetail',
      params: { seasonId: season.seasonId, title: season.title }
    }).catch((error: Object): void => {
      console.error('Pilihos anime detail page failed: ' + String(error));
    });
  }

  private formatCount(value: number): string {
    if (value >= 100000000) return `${(value / 100000000).toFixed(2).replace(/\.00$/, '')}亿`;
    if (value >= 10000) return `${(value / 10000).toFixed(1).replace(/\.0$/, '')}万`;
    return `${value}`;
  }

  @Builder
  animeCard(season: AnimeSeason, rank: number) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        Image(season.cover).width('100%').aspectRatio(0.72).objectFit(ImageFit.Cover).borderRadius(8);
        Row({ space: 4 }) {
          if (rank <= 3) {
            Text(String(rank)).fontSize(11).fontWeight(FontWeight.Bold).fontColor(Color.White)
              .width(20).height(20).textAlign(TextAlign.Center).lineHeight(20)
              .backgroundColor(rank === 1 ? '#E6A23C' : rank === 2 ? '#98A2AE' : '#C77B4A')
              .borderRadius(10);
          }
          if (season.badge !== '') {
            Text(season.badge).fontSize(10).fontColor(Color.White)
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('#E661A0D8').borderRadius(4);
          }
        }.margin(6);
      }.width('100%');
      Text(season.title).fontSize(14).fontColor('#20242A').maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').lineHeight(19);
      Row({ space: 6 }) {
        if (season.ratingText !== '') {
          Text(season.ratingText).fontSize(12).fontColor('#E6A23C').fontWeight(FontWeight.Bold);
        }
        Text(season.indexShow).fontSize(11).fontColor('#8B9199').layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }.width('100%');
      Text(this.formatCount(season.followCount) + ' 追番').fontSize(11).fontColor('#A4A9AF').width('100%');
    }.width('100%')
      .onClick((): void => { this.openAnimeDetail(season); });
  }

  build() {
    Refresh({ refreshing: $$this.refreshing, offset: 56, friction: 80 }) {
      Scroll() {
        Column() {
          Text('热门番剧').fontSize(20).fontWeight(FontWeight.Bold).fontColor('#1E252D')
            .width('100%').padding({ left: 4, bottom: 12 });
          if (this.animeList.length === 0 && this.loading) {
            Row({ space: 8 }) {
              LoadingProgress().width(26).height(26).color('#1288FA');
              Text('正在加载番剧榜单...').fontSize(14).fontColor('#1288FA');
            }.justifyContent(FlexAlign.Center).width('100%').margin({ top: 60 });
          } else if (this.animeList.length === 0 && this.loadError !== '') {
            Column({ space: 12 }) {
              Text(this.loadError).fontSize(14).fontColor('#8B9199');
              Button('重试').onClick(() => this.loadRankList());
            }.width('100%').margin({ top: 60 }).alignItems(HorizontalAlign.Center);
          } else {
            Grid() {
              ForEach(this.animeList, (season: AnimeSeason, index: number) => {
                GridItem() {
                  this.animeCard(season, index + 1);
                }
              }, (season: AnimeSeason) => `anime_${season.seasonId}`);
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(12)
            .rowsGap(14)
            .width('100%');
          }
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: this.bottomInset + 88 });
      }
      .width('100%').height('100%')
      .scrollBar(BarState.Off);
    }
    .width('100%').height('100%')
    .onRefreshing(() => { this.loadRankList(); });
  }
}
