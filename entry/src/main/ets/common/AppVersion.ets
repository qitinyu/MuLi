import { bundleManager } from '@kit.AbilityKit';

/**
 * 版本号的单一来源。
 *
 * 真值只有一处：`AppScope/app.json5` 的 `versionName`（版本号变更时改那里即可），
 * 这里读包信息拿；取不到（模拟器 / 包信息异常）才退回内置兜底值。
 * 各页面一律调 `AppVersion.label()`，不要再各自硬编码「V2.x.y」——
 * 之前设置页脚注、关于页、README 三处各写一遍，升版时容易漏。
 */
const FALLBACK: string = '2.1.1';

let cached: string = '';

export class AppVersion {
  /** 纯版本号，如 `2.1.0`（方法名避开内置的 `Function.name`） */
  static value(): string {
    if (cached.length > 0) {
      return cached;
    }
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      cached = info.versionName.length > 0 ? info.versionName : FALLBACK;
    } catch (err) {
      cached = FALLBACK;
    }
    return cached;
  }

  /** 带前缀的展示串，如 `V2.1.0` */
  static label(): string {
    return `V${AppVersion.value()}`;
  }
}
