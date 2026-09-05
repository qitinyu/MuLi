import { router } from '@ohos.router';
import { common } from '@ohos.app.ability.common';
import { preferences } from '@kit.ArkData';
import { window } from '@ohos.window';
import { BusinessError } from '@kit.BasicServicesKit';

// 动态数据模型
export class DynamicData {
  id: string = '';
  type: 'text' | 'image' | 'video' | 'link' = 'text';
  userName: string = '';
  userAvatar: string = '';
  publishTime: string = '';
  content: string = '';
  imageUrl: string = '';
  videoUrl: string = '';
  linkUrl: string = '';
  likeCount: number = 0;
  commentCount: number = 0;
  shareCount: number = 0;
}

// 动态项组件
@Component
struct DynamicItem {
  @Prop dynamicData: DynamicData
  
  build() {
    Column() {
      // 用户信息行
      Row() {
        Image(this.dynamicData.userAvatar)
          .width(40)
          .height(40)
          .borderRadius(20)
        Column() {
          Text(this.dynamicData.userName)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
          Text(this.dynamicData.publishTime)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      
      // 内容区域
      if (this.dynamicData.type === 'text') {
        Text(this.dynamicData.content)
          .fontSize(16)
          .lineHeight(24)
      } else if (this.dynamicData.type === 'image') {
        Image(this.dynamicData.imageUrl)
          .width('100%')
          .height(200)
          .borderRadius(8)
      } else if (this.dynamicData.type === 'video') {
        VideoComponent(this.dynamicData.videoUrl)
      } else if (this.dynamicData.type === 'link') {
        LinkPreview(this.dynamicData.linkUrl, this.dynamicData.content)
      }
      
      // 互动按钮行
      Row() {
        Button({ type: ButtonType.Text }) {
          Text('点赞 ' + this.dynamicData.likeCount)
            .fontSize(14)
        }
        Button({ type: ButtonType.Text }) {
          Text('评论 ' + this.dynamicData.commentCount)
            .fontSize(14)
        }
        Button({ type: ButtonType.Text }) {
          Text('转发 ' + this.dynamicData.shareCount)
            .fontSize(14)
        }
      }
    }
    .padding(16)
    .backgroundColor($r('app.color.background'))
  }
}

// 视频组件
@Component
struct VideoComponent {
  @Prop videoUrl: string
  
  build() {
    Video({ src: this.videoUrl })
      .width('100%')
      .height(240)
      .objectFit(ImageFit.Cover)
      .controls(true)
  }
}

// 链接预览组件
@Component
struct LinkPreview {
  @Prop linkUrl: string
  @Prop linkTitle: string
  
  build() {
    Column() {
      Text(this.linkTitle)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .maxLines(2)
      Text(this.linkUrl)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
    }
    .padding(12)
    .backgroundColor($r('app.color.background_light'))
    .borderRadius(8)
  }
}

@Entry
@Component
export struct DynamicPage {
  @State dynamicList: DynamicData[] = [];
  @State loading: boolean = true;
  @State loadError: string = '';
  @State topInset: number = 24;
  @State bottomInset: number = 8;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.loadDynamics();
    window.getLastWindow(this.context).then((mainWindow: window.Window): void => {
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navigationArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.topInset = px2vp(systemArea.topRect.height);
      this.bottomInset = px2vp(navigationArea.bottomRect.height);
    }).catch((error: BusinessError): void => {
      console.error(`Dynamic page avoid area failed: ${error.code} ${error.message}`);
    });
  }

  private async loadDynamics(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    try {
      // 模拟加载动态数据
      setTimeout(() => {
        this.dynamicList = this.generateMockData();
        this.loading = false;
      }, 1000);
    } catch (error) {
      this.loadError = '加载动态失败';
      console.error('Dynamic page load failed: ' + String(error));
      this.loading = false;
    }
  }

  private generateMockData(): DynamicData[] {
    const mockData: DynamicData[] = [];
    const types: Array<'text' | 'image' | 'video' | 'link'> = ['text', 'image', 'video', 'link'];
    const names = ['用户A', '用户B', '用户C', '用户D', '用户E'];
    
    for (let i = 0; i < 20; i++) {
      const type = types[Math.floor(Math.random() * types.length)];
      const data: DynamicData = {
        id: `dynamic_${i}`,
        type: type,
        userName: names[Math.floor(Math.random() * names.length)],
        userAvatar: `https://picsum.photos/seed/user${i}/40/40.jpg`,
        publishTime: this.formatPublishTime(Date.now() - Math.random() * 86400000),
        content: `这是第${i + 1}条动态内容，类型为${type}`,
        likeCount: Math.floor(Math.random() * 1000),
        commentCount: Math.floor(Math.random() * 100),
        shareCount: Math.floor(Math.random() * 50)
      };
      
      if (type === 'image') {
        data.imageUrl = `https://picsum.photos/seed/dynamic${i}/400/200.jpg`;
      } else if (type === 'video') {
        data.videoUrl = `https://example.com/video${i}.mp4`;
      } else if (type === 'link') {
        data.linkUrl = `https://example.com/link${i}`;
      }
      
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
          Button('重试').onClick(() => this.loadDynamics());
        }
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .width('100%').height('100%');
      } else {
        Scroll() {
          Column() {
            ForEach(this.dynamicList, (item: DynamicData) => {
              DynamicItem({ dynamicData: item });
            }, (item: DynamicData) => item.id);
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: this.topInset + 16, bottom: this.bottomInset + 16 })
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
