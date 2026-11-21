import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BiliCookie } from '../services/BiliHttp';
import { AuthService } from '../services/AuthService';

const DOMAIN: number = 0x0001;
const TAG: string = 'MuLi';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'onCreate');
    // 设备指纹与登录态都依赖 preferences，必须在首帧前就绪，否则首批请求会缺 cookie 被风控拦截
    BiliCookie.init(this.context).then(() => {
      // cookie 就绪后再恢复资料快照：restore 依赖 BiliCookie.isLogin() 判断是否该读
      AuthService.bind(this.context);
      if (AuthService.isLogin()) {
        AuthService.loadProfile().then(() => {
          AppStorage.setOrCreate('loginTick', Date.now());
        }).catch(() => {
          // 资料拉取失败不阻塞启动
        });
      }
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'cookie init failed: %{public}s', err.message);
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      this.applyWindowBackground(windowStage);
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    hilog.info(DOMAIN, TAG, 'onConfigurationUpdate: colorMode=%{public}d', newConfig.colorMode ?? -1);
    // 深浅色 / 语言切换后重新对齐窗口底色，避免切换瞬间闪白
    const ctx = this.context;
    try {
      const win = window.getLastWindow(ctx);
      win.then((w: window.Window) => {
        w.setWindowBackgroundColor(this.pageBackgroundColor());
      }).catch(() => {
        // 窗口尚未就绪，忽略
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'sync window background failed');
    }
  }

  /** 把页面底色同步到窗口背景，避免启动与切换时出现底色断层 */
  private applyWindowBackground(windowStage: window.WindowStage): void {
    try {
      const win: window.Window = windowStage.getMainWindowSync();
      win.setWindowBackgroundColor(this.pageBackgroundColor());
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setWindowBackgroundColor failed');
    }
  }

  private pageBackgroundColor(): string {
    try {
      const color: number = this.context.resourceManager.getColorSync($r('app.color.bg_page').id);
      const hex: string = (color & 0xFFFFFF).toString(16);
      return `#${('000000' + hex).slice(-6)}`;
    } catch (err) {
      return '#F5F6F7';
    }
  }
}
