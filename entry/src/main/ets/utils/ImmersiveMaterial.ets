import { uiMaterial } from '@kit.ArkUI';
import { AdvancedFeatures } from './AdvancedFeatures';

/**
 * 沉浸光感材质管理器
 * 支持 API 24+ 设备：API26 自动使用系统材质，API24 自动降级为纯色背景
 */
export class ImmersiveMaterial {
  private static strength: number = 1;

  static setStrength(value: number): void {
    ImmersiveMaterial.strength = Math.max(0, Math.min(2, value));
  }

  /**
   * 检查沉浸式材质是否可用
   * 条件：设备系统 API 26 或更高
   */
  static isAvailable(): boolean {
    return AdvancedFeatures.isApi26Supported();
  }

  /**
   * 获取 none 材质（不透明材质）
   * 用于API24/25或关闭高级功能时的底部栏材质
   */
  static none(): uiMaterial.Material {
    return uiMaterial.Material.empty;
  }

  /**
   * 获取 thin 材质
   * 强度设置：
   * - 弱（0）：不透明材质
   * - 中（1）/强（2）：模糊亚克力（真机上 THIN/ULTRA_THIN 过薄会导致内容不可见，统一降为 REGULAR）
   */
  static thin(): uiMaterial.Material {
    // 强度0：不透明材质
    if (ImmersiveMaterial.strength === 0 || !ImmersiveMaterial.isAvailable()) {
      return uiMaterial.Material.empty;
    }

    // 强度1/2：模糊亚克力
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      colorInvert: true,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: Color.White }
    });
  }

  /**
   * 获取 ultraThin 材质
   * 强度设置同 thin：真机上 ULTRA_THIN 材质过薄，统一降为 REGULAR
   */
  static ultraThin(): uiMaterial.Material {
    // 强度0：不透明材质
    if (ImmersiveMaterial.strength === 0 || !ImmersiveMaterial.isAvailable()) {
      return uiMaterial.Material.empty;
    }

    // 强度1/2：模糊亚克力
    return new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.REGULAR,
      colorInvert: true,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: Color.White }
    });
  }

  /**
   * API 24/25 降级方案：获取半透明背景色
   * 当沉浸式材质不可用时，使用此方法获取替代背景
   * @param opacity 透明度 0.0-1.0，默认 0.85
   */
  static fallbackBackground(opacity: number = 1.0): ResourceColor {
    if (ImmersiveMaterial.isAvailable() && ImmersiveMaterial.strength > 0) {
      // API26：系统材质负责模糊，但真机上材质可能渲染过薄，
      // 保留一层白色底衬保证内容始终可见。
      const adjusted: number = Math.max(0.5, opacity * 0.72);
      const alpha: string = Math.round(adjusted * 255).toString(16).padStart(2, '0');
      return `#${alpha}FFFFFF`;
    }

    // API 24/25 或开关关闭或强度为0，使用不透明纯色，避免透明材质穿透。
    const alpha = Math.round(Math.max(0, Math.min(1, opacity)) * 255).toString(16).padStart(2, '0');
    return `#${alpha}FFFFFF`;
  }

  /**
   * 获取阴影样式（API 24/25 降级时使用）
   */
  static fallbackShadow(radius: number = 6): ShadowOptions {
    return {
      radius: radius,
      color: '#25000000',
      offsetX: 0,
      offsetY: 2
    };
  }
}
