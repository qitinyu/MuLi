import router from '@ohos.router';
import window from '@ohos.window';
import common from '@ohos.app.ability.common';
import { MessageSidebar } from '../components/Sidebars';

// 消息子页面：独立路由页（返回即回到来源页，天然恢复此前状态）
@Entry
@Component
struct MessagePage {
  @Provide sidebar: number = 0;
  @Provide topInset: number = 0;
  @Provide bottomInset: number = 0;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.updateSystemInsets();
  }

  private async updateSystemInsets(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      const systemArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = px2vp(systemArea.topRect.height);
      const navArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.bottomInset = px2vp(navArea.bottomRect.height);
    } catch (error) {
      console.error('Pilihos message page inset failed: ' + String(error));
    }
  }

  build() {
    Column() {
      MessageSidebar()
    }
    .width('100%').height('100%')
    .backgroundColor('#F5F7F9');
  }
}
