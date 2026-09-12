import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import { AnimeEpisode, AnimeSeasonDetail, AnimeService } from '../services/AnimeService';

@Entry
@Component
struct AnimeDetail {
  @State seasonId: number = 0;
  @State detail: AnimeSeasonDetail | null = null;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State currentEpisodeIndex: number = -1;
  @State playUrl: string = '';
  @State playLoading: boolean = false;
  @State playError: string = '';
  @State descriptionExpanded: boolean = false;
  @State topInset: number = 0;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.updateSystemInsets();
    const params: Object | undefined = router.getParams() as Object | undefined;
    if (params !== undefined) {
      const paramsRecord: Record<string, Object> = params as Record<string, Object>;
      this.seasonId = Number(paramsRecord['seasonId'] ?? 0);
    }
    this.loadSeason();
  }

  private async updateSystemInsets(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = px2vp(systemArea.topRect.height);
    } catch (error) {
      console.error('Pilihos anime detail inset update failed: ' + String(error));
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2500,
        bottom: 24
      });
    } catch (error) {
      console.error(`Pilihos anime toast failed: ${String(error)}`);
    }
  }

  private async loadSeason(): Promise<void> {
    if (this.seasonId <= 0) {
      this.loading = false;
      this.loadError = '番剧参数缺失';
      return;
    }
    this.loading = true;
    this.loadError = '';
    try {
      this.detail = await AnimeService.loadSeasonDetail(this.seasonId);
    } catch (error) {
      this.loadError = '番剧详情加载失败，请检查网络';
      console.error('Pilihos anime detail load failed: ' + String(error));
    } finally {
      this.loading = false;
    }
  }

  private async playEpisode(index: number): Promise<void> {
    if (this.detail === null || this.playLoading) return;
    if (index < 0 || index >= this.detail.episodes.length) return;
    const episode: AnimeEpisode = this.detail.episodes[index];
    this.playLoading = true;
    this.playError = '';
    try {
      const url: string = await AnimeService.resolveEpisodeUrl(episode.epId, episode.cid);
      this.playUrl = url;
      this.currentEpisodeIndex = index;
    } catch (error) {
      this.playError = String(error);
      this.showToast(this.playError);
      console.error('Pilihos anime episode play failed: ' + String(error));
    } finally {
      this.playLoading = false;
    }
  }

  private episodeLabel(episode: AnimeEpisode): string {
    if (episode.longTitle !== '' && episode.title !== '') {
      return `${episode.title} ${episode.longTitle}`;
    }
    if (episode.title !== '') return episode.title;
    return '正片';
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
              .onError((): void => {
                this.showToast('播放异常，请尝试其他选集');
              });
          } else {
            Stack({ alignContent: Alignment.Center }) {
              if (this.detail !== null && this.detail.cover !== '') {
                Image(this.detail.cover).width('100%').height('100%').objectFit(ImageFit.Cover);
              } else {
                Column().width('100%').height('100%').backgroundColor('#101418');
              }
              if (this.detail !== null && this.detail.episodes.length > 0) {
                Button() {
                  Row({ space: 6 }) {
                    if (this.playLoading) {
                      LoadingProgress().width(18).height(18).color(Color.White);
                    } else {
                      Image($r('app.media.bofang')).width(26).height(26).fillColor(Color.White);
                    }
                    Text(this.playLoading ? '获取播放地址...' : '播放')
                      .fontSize(15).fontColor(Color.White);
                  }.alignItems(VerticalAlign.Center);
                }
                .type(ButtonType.Capsule)
                .height(44)
                .backgroundColor('#99000000')
                .enabled(!this.playLoading)
                .onClick((): void => { this.playEpisode(0); });
              } else if (this.playLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(24).height(24).color(Color.White);
                  Text('加载中...').fontSize(13).fontColor(Color.White);
                };
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

      if (this.loading) {
        Column() {
          Row({ space: 8 }) {
            LoadingProgress().width(26).height(26).color('#1288FA');
            Text('正在加载番剧详情...').fontSize(14).fontColor('#1288FA');
          }.justifyContent(FlexAlign.Center);
        }.layoutWeight(1).width('100%');
      } else if (this.detail === null) {
        Column({ space: 12 }) {
          Text(this.loadError).fontSize(14).fontColor('#8B9199');
          Button('重试').onClick((): void => { this.loadSeason(); });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 12 }) {
            Text(this.detail.title).fontSize(19).fontWeight(FontWeight.Bold).fontColor('#20242A')
              .lineHeight(27).width('100%');
            Row({ space: 8 }) {
              if (this.detail.score !== '') {
                Text(this.detail.score + ' 分').fontSize(14).fontWeight(FontWeight.Bold)
                  .fontColor('#E6A23C');
                Text(this.detail.scoreCount + ' 人评分').fontSize(11).fontColor('#A4A9AF');
              }
              ForEach(this.detail.styles.slice(0, 4), (style: string) => {
                Text(style).fontSize(11).fontColor('#1288FA')
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .backgroundColor('#1A1288FA').borderRadius(4);
              }, (style: string) => style);
            }.width('100%');
            if (this.detail.evaluate !== '') {
              Column({ space: 6 }) {
                Text('简介').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#20242A');
                Text(this.detail.evaluate).fontSize(13).fontColor('#59616B').lineHeight(21)
                  .maxLines(this.descriptionExpanded ? 1000 : 3)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
                Text(this.descriptionExpanded ? '收起' : '展开全部').fontSize(13).fontColor('#1288FA')
                  .onClick(() => { this.descriptionExpanded = !this.descriptionExpanded; });
              }.width('100%').alignItems(HorizontalAlign.Start);
            }
            Row() {
              Text('选集').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#20242A').layoutWeight(1);
              Text(`共 ${this.detail.episodes.length} 集`).fontSize(12).fontColor('#8B9199');
            }.width('100%');
            if (this.detail.episodes.length > 0) {
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.detail.episodes, (episode: AnimeEpisode, index: number) => {
                    Column({ space: 2 }) {
                      Text(this.episodeLabel(episode)).fontSize(12)
                        .fontColor(index === this.currentEpisodeIndex ? Color.White : '#59616B')
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                      if (episode.badge !== '') {
                        Text(episode.badge).fontSize(9)
                          .fontColor(index === this.currentEpisodeIndex ? Color.White : '#E661A0D8');
                      }
                    }
                    .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                    .backgroundColor(index === this.currentEpisodeIndex ? '#1288FA' : '#F1F4F6')
                    .borderRadius(16)
                    .onClick((): void => { this.playEpisode(index); });
                  }, (episode: AnimeEpisode, index: number) => `ep_${index}_${episode.epId}`);
                }.padding({ left: 2, right: 2 });
              }
              .width('100%')
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off);
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 40 })
          .alignItems(HorizontalAlign.Start);
        }
        .layoutWeight(1).width('100%')
        .scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%')
    .backgroundColor('#F7F8FA');
  }
}
