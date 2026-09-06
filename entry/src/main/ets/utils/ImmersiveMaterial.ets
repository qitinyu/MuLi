import { AdvancedFeatures } from './AdvancedFeatures';

/**
 * 沉浸光感材质管理器
 * 统一通过 backgroundBlurStyle 呈现毛玻璃效果（系统 uiMaterial 材质在真机上
 * 渲染过薄或不渲染，导致卡片不可见），白色底衬仅作轻度提亮。
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
   * 组件背景毛玻璃样式：真机稳定渲染的"沉浸光感"实现，
   * 参考系统弹窗/toast 的厚毛玻璃观感
   */
  static blurStyle(): BlurStyle {
    return BlurStyle.COMPONENT_THICK;
  }

  /**
   * 组件背景底衬：材质开启时给轻度白色提亮（避免完全透底），
   * API 24/25 或关闭时用较实的白色替代模糊。
   * @param opacity 透明度 0.0-1.0，默认 0.85
   */
  static fallbackBackground(opacity: number = 1.0): ResourceColor {
    const clamped: number = Math.max(0, Math.min(1, opacity));
    if (ImmersiveMaterial.isAvailable() && ImmersiveMaterial.strength > 0) {
      // 材质负责模糊，底衬只轻度提亮
      const adjusted: number = Math.max(0.25, clamped * 0.35);
      const alpha: string = Math.round(adjusted * 255).toString(16).padStart(2, '0');
      return `#${alpha}FFFFFF`;
    }
    const alpha: string = Math.round(clamped * 255).toString(16).padStart(2, '0');
    return `#${alpha}FFFFFF`;
  }

  /**
   * 深色材质底衬（参考点赞提示气泡的深色半透明观感），
   * 用于首页底部迷你栏与中间页签栏。
   */
  static fallbackBackgroundDark(opacity: number = 1.0): ResourceColor {
    const clamped: number = Math.max(0, Math.min(1, opacity));
    const adjusted: number = Math.max(0.45, clamped * 0.75);
    const alpha: string = Math.round(adjusted * 255).toString(16).padStart(2, '0');
    return `#${alpha}1A1E26`;
  }
}
