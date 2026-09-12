import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { hdsMaterial } from '@kit.UIDesignKit';
import { AdvancedFeatures } from './AdvancedFeatures';

/**
 * 沉浸光感材质管理器
 * 材质策略管理器。
 * 顶部栏、底部栏和侧栏仍然是普通 ArkUI 组件，因此必须同时处理两条路径：
 * API 26 且设备提供系统材质时使用 ImmersiveMaterial；其他设备使用半透明降级层。
 * 系统材质可用时不叠加不透明的 fallback 背景，避免动态光感被覆盖。
 */
export class ImmersiveMaterial {
  private static thinMaterial: uiMaterial.Material | null = null;
  private static regularMaterial: uiMaterial.Material | null = null;
  private static thickMaterial: uiMaterial.Material | null = null;

  /**
   * 检查沉浸式材质是否可用（API 26+）。
   * API 24/25 由调用方使用半透明白色背景降级。
   */
  static isAvailable(): boolean {
    return AdvancedFeatures.isImmersiveMaterialEnabled()
      && deviceInfo.apiAvailable('26.0.0')
      && hdsMaterial.getSystemMaterialTypes().length > 0;
  }

  /**
   * 系统材质表面颜色。材质可用时返回透明，让系统材质直接采样背后的内容；
   * 材质不可用时才返回兼容性背景。
   */
  static surfaceBackground(opacity: number = 0.85): ResourceColor {
    return ImmersiveMaterial.isAvailable() ? Color.Transparent : ImmersiveMaterial.fallbackBackground(opacity);
  }

  private static createMaterial(style: uiMaterial.ImmersiveStyle): uiMaterial.Material {
    return new uiMaterial.ImmersiveMaterial({
      style: style,
      interactive: true,
      lightEffect: { color: undefined }
    });
  }

  /**
   * 获取 THIN 级别材质（轻薄透明，适合搜索框、小面积悬浮工具栏）
   */
  static getThin(): uiMaterial.Material | null {
    if (!ImmersiveMaterial.isAvailable()) return null;
    if (ImmersiveMaterial.thinMaterial === null) {
      ImmersiveMaterial.thinMaterial = ImmersiveMaterial.createMaterial(uiMaterial.ImmersiveStyle.THIN);
    }
    return ImmersiveMaterial.thinMaterial;
  }

  /**
   * 获取 REGULAR 级别材质（标准厚度，适合导航栏、标签栏）
   */
  static getRegular(): uiMaterial.Material | null {
    if (!ImmersiveMaterial.isAvailable()) return null;
    if (ImmersiveMaterial.regularMaterial === null) {
      ImmersiveMaterial.regularMaterial = ImmersiveMaterial.createMaterial(uiMaterial.ImmersiveStyle.REGULAR);
    }
    return ImmersiveMaterial.regularMaterial;
  }

  /**
   * 获取 THICK 级别材质（厚重模糊，适合弹窗、底部面板）
   */
  static getThick(): uiMaterial.Material | null {
    if (!ImmersiveMaterial.isAvailable()) return null;
    if (ImmersiveMaterial.thickMaterial === null) {
      ImmersiveMaterial.thickMaterial = ImmersiveMaterial.createMaterial(uiMaterial.ImmersiveStyle.THICK);
    }
    return ImmersiveMaterial.thickMaterial;
  }

  /**
   * 浅色材质表面：API 24/25 作为降级背景，API 26+ 作为材质叠加层
   */
  static fallbackBackground(opacity: number = 0.85): ResourceColor {
    const clamped: number = Math.max(0, Math.min(1, opacity));
    // Keep a visible surface behind ordinary components; lowering it for a
    // material that the component cannot render produces a washed-out layer.
    const alpha: string = Math.round(clamped * 255).toString(16).padStart(2, '0');
    // Use a cool blue translucent surface for the fallback path so it still
    // reads as light passing through glass when ordinary ArkUI components do
    // not render the HDS system material.
    return `#${alpha}EAF5FF`;
  }

  static blurStyle(): BlurStyle {
    return BlurStyle.COMPONENT_THICK;
  }

  /**
   * 深色材质表面：API 24/25 作为降级背景，API 26+ 作为材质叠加层
   */
  static fallbackBackgroundDark(opacity: number = 0.75): ResourceColor {
    const clamped: number = Math.max(0, Math.min(1, opacity));
    const alpha: string = Math.round(clamped * 255).toString(16).padStart(2, '0');
    return `#${alpha}1A1E26`;
  }
}
