import { router } from '@ohos.router';
import { common } from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { window } from '@ohos.window';
import { BusinessError } from '@kit.BasicServicesKit';

// 直播数据模型
export class LiveData {
  id: string = '';
  streamerName: string = '';
  streamerAvatar: string = '';
  coverUrl: string = '';
  title: string = '';
  viewerCount: number = 0;
  isLive: boolean = false;
  category: string = '';
  startTime: string = '';
}

// 直播项组件
@Component
struct LiveItem {
  @Prop liveData: LiveData
  
  build() {
    Stack() {
      // 直播封面
      Image(this.liveData.coverUrl)
        .width('100%')
        .height(180)
        .borderRadius(8)
      
      // 直播状态标识
      if (this.liveData.isLive) {
        Badge({ count: 'LIVE' })
          .position({ x: '90%', y: '10%' })
      }
      
      // 主播信息
      Row() {
        Image(this.liveData.streamerAvatar)
          .width(32)
          .height(32)
          .borderRadius(16)
        Column() {
          Text(this.liveData.streamerName)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
          Text(`${this.liveData.viewerCount} 观看`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .position({ x: 16, y: 16 })
      
      // 进入按钮
      Button('进入直播')
        .width('80%')
        .height(36)
        .position({ x: '10%', y: '80%' })
        .onClick(() => {
          router.pushUrl({ url: 'pages/LiveDetail' + this.liveData.id })
        })
    }
    .width('100%')
    .margin({ bottom: 16 })
  }
}

// 直播详情页（占位）
@Component
struct LiveDetailPage {
  @Prop liveData: LiveData
  
  build() {
    Column() {
      Image(this.liveData.coverUrl)
        .width('100%')
        .height(250)
        .objectFit(ImageFit.Cover)
      
      Text(this.liveData.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .padding({ top: 16, bottom: 8 })
      
      Row() {
        Image(this.liveData.streamerAvatar)
          .width(40)
          .height(40)
          .borderRadius(20)
        Column() {
          Text(this.liveData.streamerName)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
          Text(this.liveData.category)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .margin({ left: 12 })
        Text(`${this.liveData.viewerCount} 观看中`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .padding({ left: 16, right: 16 })
      
      Text(this.liveData.startTime)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })
      
      Button('开始观看')
        .width('90%')
        .height(40)
        .margin({ top: 24, bottom: 24 })
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
export struct LivePage {
  @State liveList: LiveData[] = [];
  @State loading: boolean = true;
  @State loadError: string = '';
  @State topInset: number = 24;
  @State bottomInset: number = 8;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.loadLiveList();
    window.getLastWindow(this.context).then((mainWindow: window.Window): void => {
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navigationArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.topInset = px2vp(systemArea.topRect.height);
      this.bottomInset = px2vp(navigationArea.bottomRect.height);
    }).catch((error: BusinessError): void => {
      console.error(`Live page avoid area failed: ${error.code} ${error.message}`);
    });
  }

  private async loadLiveList(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    try {
      // 模拟加载直播数据
      setTimeout(() => {
        this.liveList = this.generateMockData();
        this.loading = false;
      }, 1000);
    } catch (error) {
      this.loadError = '加载直播失败';
      console.error('Live page load failed: ' + String(error));
      this.loading = false;
    }
  }

  private generateMockData(): LiveData[] {
    const mockData: LiveData[] = [];
    const streamerNames = ['主播A', '主播B', '主播C', '主播D', '主播E', '主播F'];
    const categories = ['游戏', '娱乐', '音乐', '聊天', '绘画', '美食'];
    
    for (let i = 0; i < 8; i++) {
      const data: LiveData = {
        id: `live_${i}`,
        streamerName: streamerNames[i % streamerNames.length],
        streamerAvatar: `https://picsum.photos/seed/streamer${i}/40/40.jpg`,
        coverUrl: `https://picsum.photos/seed/live${i}/400/240.jpg`,
        title: `${streamerNames[i % streamerNames.length]}的直播 - ${categories[i % categories.length]}`,
        viewerCount: Math.floor(Math.random() * 10000),
        isLive: Math.random() > 0.3,
        category: categories[i % categories.length],
        startTime: this.formatStartTime(Date.now() - Math.random() * 3600000)
      };
      
      mockData.push(data);
    }
    
    return mockData;
  }

  private formatStartTime(timestamp: number): string {
    const date: Date = new Date(timestamp);
    const hours: number = date.getHours();
    const minutes: number = date.getMinutes();
    return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}`;
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
          Button('重试').onClick(() => this.loadLiveList());
        }
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .width('100%').height('100%');
      } else {
        Scroll() {
          Column() {
            Text('正在直播')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 16, top: 16, bottom: 16 })
            
            ForEach(this.liveList, (item: LiveData) => {
              LiveItem({ liveData: item });
            }, (item: LiveData) => item.id);
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
