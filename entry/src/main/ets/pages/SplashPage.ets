import router from '@ohos.router';

// 开屏动画：Logo 卡片 + 应用名 + 加载指示，底部署名；淡入停留后淡出进入主页
@Entry
@Component
struct SplashPage {
  @State pageOpacity: number = 0;
  @State logoScale: number = 0.86;
  @State exiting: boolean = false;

  aboutToAppear(): void {
    // 淡入（由 .animation 属性驱动 600ms）
    setTimeout((): void => {
      this.pageOpacity = 1;
      this.logoScale = 1;
    }, 30);
    // 停留约 1.9s 后淡出进入主页
    setTimeout((): void => {
      this.exitSplash();
    }, 1900);
  }

  private exitSplash(): void {
    if (this.exiting) return;
    this.exiting = true;
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseIn }, (): void => {
      this.pageOpacity = 0;
    });
    setTimeout((): void => {
      router.replaceUrl({ url: 'pages/Index' }).catch((error: Object): void => {
        console.error(`Pilihos splash to index failed: ${String(error)}`);
      });
    }, 310);
  }

  build() {
    Column() {
      Blank().layoutWeight(1);
      Column({ space: 18 }) {
        // Logo（64×64，与卡片同尺寸）
        Image($r('app.media.app_logo')).width(64).height(64)
          .borderRadius(14)
          .shadow({ radius: 14, color: '#14000000', offsetX: 0, offsetY: 5 })
          .scale({ x: this.logoScale, y: this.logoScale });

        // 副标题
        Text('鸿蒙端Bilibili').fontSize(13).fontColor('#858C94').letterSpacing(2);

        // 加载指示
        LoadingProgress().width(28).height(28).color('#59616B')
          .margin({ top: 14 });
      }
      .alignItems(HorizontalAlign.Center);
      Blank().layoutWeight(1);
      // 底部署名（整行宽度 + 居中）
      Text('Pilihos By YuQi').fontSize(12).fontColor('#9499A0').letterSpacing(2)
        .width('100%').textAlign(TextAlign.Center)
        .padding({ bottom: 46 });
    }
    .width('100%').height('100%')
    .backgroundColor('#F6F7F9')
    .opacity(this.pageOpacity)
    .animation({ duration: 600, curve: Curve.EaseOut });
  }
}
