import { router } from '@ohos.router';
import { common } from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { window } from '@ohos.window';
import { BusinessError } from '@kit.BasicServicesKit';

// 番剧数据模型
export class AnimeData {
  id: string = '';
  title: string = '';
  coverUrl: string = '';
  currentEpisode: number = 1;
  totalEpisodes: number = 24;
  rating: number = 0;
  isUpdated: boolean = false;
  publishTime: string = '';
  description: string = '';
  tags: string[] = [];
}

// 番剧卡片组件
@Component
struct AnimeCard {
  @Prop animeData: AnimeData
  
  build() {
    Column() {
      // 封面图
      Image(this.animeData.coverUrl)
        .width('100%')
        .height(200)
        .borderRadius(8)
      
      // 标题和评分
      Row() {
        Column() {
          Text(this.animeData.title)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
          Text(`第${this.animeData.currentEpisode}集`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        RatingBar(this.animeData.rating)
          .starSize(16)
      }
      
      // 更新状态
      if (this.animeData.isUpdated) {
        Badge({ count: '更新' })
          .position({ x: '90%', y: '10%' })
      }
    }
    .width('48%')
    .margin({ bottom: 16 })
    .onClick(() => {
      router.pushUrl({ url: 'pages/AnimeDetail' + this.animeData.id })
    })
  }
}

// 番剧详情页（占位）
@Component
struct AnimeDetailPage {
  @Prop animeData: AnimeData
  
  build() {
    Column() {
      Image(this.animeData.coverUrl)
        .width('100%')
        .height(300)
        .objectFit(ImageFit.Cover)
      
      Text(this.animeData.title)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .padding({ top: 16, bottom: 8 })
      
      Row() {
        RatingBar(this.animeData.rating)
          .starSize(20)
        Text(`${this.animeData.currentEpisode}/${this.animeData.totalEpisodes}集`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 8 })
      }
      
      Text(this.animeData.description)
        .fontSize(14)
        .lineHeight(22)
        .padding({ top: 16, bottom: 16 })
      
      Text('标签: ' + this.animeData.tags.join(', '))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      
      Button('开始观看')
        .width('80%')
        .height(40)
        .margin({ top: 24 })
        .onClick(() => {
          // 播放逻辑
        })
    }
    .padding(16)
    .backgroundColor($r('app.color.background'))
  }
}

@Entry
@Component
export struct AnimePage {
  @State animeList: AnimeData[] = [];
  @State loading: boolean = true;
  @State loadError: string = '';
  @State topInset: number = 24;
  @State bottomInset: number = 8;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.loadAnimeList();
    window.getLastWindow(this.context).then((mainWindow: window.Window): void => {
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navigationArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.topInset = px2vp(systemArea.topRect.height);
      this.bottomInset = px2vp(navigationArea.bottomRect.height);
    }).catch((error: BusinessError): void => {
      console.error(`Anime page avoid area failed: ${error.code} ${error.message}`);
    });
  }

  private async loadAnimeList(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    try {
      // 模拟加载番剧数据
      setTimeout(() => {
        this.animeList = this.generateMockData();
        this.loading = false;
      }, 1000);
    } catch (error) {
      this.loadError = '加载番剧失败';
      console.error('Anime page load failed: ' + String(error));
      this.loading = false;
    }
  }

  private generateMockData(): AnimeData[] {
    const mockData: AnimeData[] = [];
    const titles = [
      '进击的巨人 最终季', '鬼灭之刃 游郭篇', '间谍过家家 第二季', 
      '夏日重现', '电锯人', '我的英雄学院', '东京复仇者', '咒术回战'
    ];
    
    for (let i = 0; i < 12; i++) {
      const data: AnimeData = {
        id: `anime_${i}`,
        title: titles[i % titles.length],
        coverUrl: `https://picsum.photos/seed/anime${i}/400/600.jpg`,
        currentEpisode: Math.floor(Math.random() * 24) + 1,
        totalEpisodes: 24,
        rating: Math.random() * 5,
        isUpdated: Math.random() > 0.5,
        publishTime: this.formatPublishTime(Date.now() - Math.random() * 86400000),
        description: `这是${titles[i % titles.length]}的简介，这是一部非常精彩的番剧作品。`,
        tags: ['热血', '动作', '冒险']
      };
      
      mockData.push(data);
    }
    
    return mockData;
  }

  private formatPublishTime(timestamp: number): string {
    const seconds: number = Math.max(0, Math.floor(Date.now() / 1000) - timestamp);
    if (seconds < 60) return '刚刚';
    if (seconds < 3600) return `${Math.floor(seconds / 60)}分钟前`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}小时前`;
    return `${Math.floor(seconds / 86400)}天前`;
  }

  @Builder
  loadingIndicator() {
    Row({ space: 8 }) {
      LoadingProgress().width(26).height(26).color('#1677A8');
      Text('加载中...').fontSize(14).fontColor('#1677A8');
    }
    .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center);
  }

  build() {
    Stack() {
      if (this.loading) {
        this.loadingIndicator();
      } else if (this.loadError) {
        Column() {
          Text(this.loadError).fontSize(16).fontColor('#FF4444');
          Button('重试').onClick(() => this.loadAnimeList());
        }
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .width('100%').height('100%');
      } else {
        Scroll() {
          Column() {
            Text('热门番剧')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 16, top: 16, bottom: 16 })
            
            Grid() {
              ForEach(this.animeList, (item: AnimeData) => {
                GridItem() {
                  AnimeCard({ animeData: item });
                }
              }, (item: AnimeData) => item.id);
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(16)
            .rowsGap(16)
            .width('100%')
            .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .padding({ top: this.topInset + 16, bottom: this.bottomInset + 16 })
          .alignItems(HorizontalAlign.Start);
        }
        .width('100%').height('100%')
        .scrollBar(BarState.Off);
      }
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.background'));
  }
}
