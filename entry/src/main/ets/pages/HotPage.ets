import { router } from '@ohos.router';
import { common } from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { window } from '@ohos.window';
import { BusinessError } from '@kit.BasicServicesKit';

// 热门数据模型
export class HotData {
  id: string = '';
  rank: number = 0;
  title: string = '';
  heat: number = 0;
  playCount: number = 0;
  publishTime: string = '';
  category: string = '';
}

// 热门项组件
@Component
struct HotItem {
  @Prop hotData: HotData
  
  build() {
    Row() {
      // 排名标识
      if (this.hotData.rank <= 3) {
        // 前3名特殊样式
        Text(this.hotData.rank.toString())
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.hotData.rank === 1 ? $r('app.color.gold') : 
                   this.hotData.rank === 2 ? $r('app.color.silver') : 
                   $r('app.color.bronze'))
          .width(32)
          .height(32)
          .backgroundColor($r('app.color.background_light'))
          .borderRadius(16)
          .textAlign(TextAlign.Center)
          .lineHeight(32)
      } else {
        // 其他排名
        Text(this.hotData.rank.toString())
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width(24)
          .height(24)
          .backgroundColor($r('app.color.background_light'))
          .borderRadius(12)
          .textAlign(TextAlign.Center)
          .lineHeight(24)
      }
      
      // 内容区域
      Column() {
        Text(this.hotData.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .maxLines(2)
        
        Row() {
          Text(`热度: ${this.formatNumber(this.hotData.heat)}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text(`播放: ${this.formatNumber(this.hotData.playCount)}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .marginLeft(12)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.background'))
    .borderRadius(8)
    .onClick(() => {
      router.pushUrl({ url: 'pages/HotDetail' + this.hotData.id })
    })
  }

  private formatNumber(value: number): string {
    if (value >= 100000000) return `${(value / 100000000).toFixed(2).replace(/\.00$/, '')}亿`;
    if (value >= 10000) return `${(value / 10000).toFixed(1).replace(/\.0$/, '')}万`;
    return `${value}`;
  }
}

// 热门详情页（占位）
@Component
struct HotDetailPage {
  @Prop hotData: HotData
  
  build() {
    Column() {
      Text(this.hotData.title)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .padding({ top: 16, bottom: 8 })
      
      Row() {
        Text(`排名 #${this.hotData.rank}`)
          .fontSize(16)
          .fontColor($r('app.color.text_secondary))
        Text(`热度: ${this.formatNumber(this.hotData.heat)}`)
          .fontSize(16)
          .fontColor($r('app.color.text_secondary))
        Text(`播放: ${this.formatNumber(this.hotData.playCount)}`)
          .fontSize(16)
          .fontColor($r('app.color.text_secondary))
      }
      .padding({ bottom: 16 })
      
      Text(this.hotData.category)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary))
        .padding({ bottom: 16 })
      
      Text(this.hotData.publishTime)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary))
        .padding({ bottom: 24 })
      
      Button('查看详情')
        .width('80%')
        .height(40)
        .onClick(() => {
          // 查看详情逻辑
        })
    }
    .padding(16)
    .backgroundColor($r('app.color.background))
  }

  private formatNumber(value: number): string {
    if (value >= 100000000) return `${(value / 100000000).toFixed(2).replace(/\.00$/, '')}亿`;
    if (value >= 10000) return `${(value / 10000).toFixed(1).replace(/\.0$/, '')}万`;
    return `${value}`;
  }
}

@Entry
@Component
export struct HotPage {
  @State hotList: HotData[] = [];
  @State loading: boolean = true;
  @State loadError: string = '';
  @State topInset: number = 24;
  @State bottomInset: number = 8;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.loadHotList();
    window.getLastWindow(this.context).then((mainWindow: window.Window): void => {
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navigationArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.topInset = px2vp(systemArea.topRect.height);
      this.bottomInset = px2vp(navigationArea.bottomRect.height);
    }).catch((error: BusinessError): void => {
      console.error(`Hot page avoid area failed: ${error.code} ${error.message}`);
    });
  }

  private async loadHotList(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    try {
      // 模拟加载热门数据
      setTimeout(() => {
        this.hotList = this.generateMockData();
        this.loading = false;
      }, 1000);
    } catch (error) {
      this.loadError = '加载热门失败';
      console.error('Hot page load failed: ' + String(error));
      this.loading = false;
    }
  }

  private generateMockData(): HotData[] {
    const mockData: HotData[] = [];
    const titles = [
      '年度最佳番剧推荐', '热门游戏直播回顾', '音乐节精彩瞬间', 
      '美食探店指南', '旅行攻略分享', '科技产品评测', '时尚穿搭技巧', '健身运动指南'
    ];
    
    for (let i = 0; i < 20; i++) {
      const data: HotData = {
        id: `hot_${i}`,
        rank: i + 1,
        title: titles[i % titles.length],
        heat: Math.floor(Math.random() * 1000000),
        playCount: Math.floor(Math.random() * 500000),
        publishTime: this.formatPublishTime(Date.now() - Math.random() * 86400000),
        category: ['娱乐', '游戏', '音乐', '美食', '旅行', '科技', '时尚', '运动'][i % 8]
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
          Button('重试').onClick(() => this.loadHotList());
        }
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .width('100%').height('100%');
      } else {
        Scroll() {
          Column() {
            Text('热门榜单')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .padding({ left: 16, top: 16, bottom: 16 })
            
            ForEach(this.hotList, (item: HotData) => {
              HotItem({ hotData: item });
            }, (item: HotData) => item.id);
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
