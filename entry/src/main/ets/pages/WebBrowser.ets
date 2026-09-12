import router from '@ohos.router';
import { webview } from '@kit.ArkWeb';
import window from '@ohos.window';
import common from '@ohos.app.ability.common';

// 应用内网页：举报反馈等外部页面的内嵌容器（不再跳系统浏览器）
@Entry
@Component
struct WebBrowser {
  @State url: string = 'https://www.bilibili.com';
  @State title: string = '页面';
  @State topInset: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    const params: Object | undefined = router.getParams() as Object | undefined;
    if (params !== undefined) {
      const record: Record<string, Object> = params as Record<string, Object>;
      const target: string = String(record['url'] ?? '');
      if (target !== '') {
        this.url = target;
      }
      const name: string = String(record['title'] ?? '');
      if (name !== '') {
        this.title = name;
      }
    }
    this.updateSystemInsets();
  }

  private async updateSystemInsets(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      const systemArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = px2vp(systemArea.topRect.height);
    } catch (error) {
      console.error('Pilihos web browser inset failed: ' + String(error));
    }
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Button() {
          Image($r('app.media.fanhui_left')).width(24).height(24);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
        .backgroundColor(Color.Transparent)
        .onClick(() => { router.back(); });
        Text(this.title).fontSize(17).fontWeight(FontWeight.Medium).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: this.topInset + 6, bottom: 6 });

      Web({ src: this.url, controller: this.controller })
        .width('100%').layoutWeight(1)
        .darkMode(WebDarkMode.Off)
        .overScrollMode(OverScrollMode.NEVER);
    }
    .width('100%').height('100%')
    .backgroundColor('#FAFBFC');
  }
}
