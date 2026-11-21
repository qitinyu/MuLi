import { hdsMaterial } from '@kit.UIDesignKit';

/**
 * 材质能力探测。
 * 沉浸光感（IMMERSIVE）只在部分设备/版本上可用，不可用时退回自适应材质，
 * 直接指定 IMMERSIVE 会在不支持的环境里退化为纯色或直接失效。
 */
export class MaterialScope {
  /** 依据系统可用材质类型返回最合适的材质等级。 */
  static detectLevel(): hdsMaterial.MaterialLevel {
    try {
      const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      if (types.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0) {
        return hdsMaterial.MaterialLevel.EXQUISITE;
      }
    } catch (err) {
      // 低版本 SDK 无该接口，按最保守等级处理
    }
    return hdsMaterial.MaterialLevel.SMOOTH;
  }

  /** 依据系统可用材质类型返回最合适的材质类型。 */
  static detectType(): hdsMaterial.MaterialType {
    try {
      const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      if (types.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0) {
        return hdsMaterial.MaterialType.IMMERSIVE;
      }
    } catch (err) {
      // 忽略并按自适应材质处理
    }
    return hdsMaterial.MaterialType.ADAPTIVE;
  }
}
