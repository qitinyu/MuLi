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
      // Keep system areas opaque so the app bars cannot bleed or blur through them.
      statusBarColor: '#F7F8FA',
      navigationBarColor: '#00000000',
      isStatusBarLightIcon: true,
      isNavigationBarLightIcon: true
    }).catch((error: BusinessError): void => {
      console.error(`Pilihos system bar setup failed: ${error.code} ${error.message}`);
    });
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        console.error(`Pilihos loadContent failed: ${err.code} ${err.message}`);
      }
    });
  }
}
