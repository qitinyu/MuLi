import { UIAbility } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import window from '@ohos.window';

export default class EntryAbility extends UIAbility {
  private contentLoaded: boolean = false;

  onWindowStageCreate(windowStage: window.WindowStage): void {
    if (this.contentLoaded) return;
    this.contentLoaded = true;
    const mainWindow: window.Window = windowStage.getMainWindowSync();
    mainWindow.setWindowLayoutFullScreen(true).catch((error: BusinessError): void => {
      console.error(`Pilihos fullscreen layout failed: ${error.code} ${error.message}`);
    });
    mainWindow.setWindowSystemBarProperties({
      // Keep the fullscreen background continuous under the system bars.
      statusBarColor: '#00000000',
      navigationBarColor: '#00000000',
      isStatusBarLightIcon: true,
      isNavigationBarLightIcon: true
    }).catch((error: BusinessError): void => {
      console.error(`Pilihos system bar setup failed: ${error.code} ${error.message}`);
    });
    // 开屏动画页：停留淡出后 replaceUrl 进入主页
    windowStage.loadContent('pages/SplashPage', (err: BusinessError) => {
      if (err.code) {
        console.error(`Pilihos loadContent failed: ${err.code} ${err.message}`);
      }
    });
  }

  // 前后台状态广播：PlayerScreen 依据它实现"打断接续"
  onForeground(): void {
    AppStorage.setOrCreate('app_in_background', false);
  }

  onBackground(): void {
    AppStorage.setOrCreate('app_in_background', true);
  }
}
