/**
 * 等级徽章（Lv0 ~ Lv6）：直接使用素材里的矢量图，样式与 b 站一致。
 *
 * 素材是 1901 × 1024 的横条（含 LV 字样与配色），所以宽度按高度等比算出，
 * 不要在调用处再单独指定宽度，否则会被拉变形。
 */

/** 徽章原始宽高比（viewBox 1901 × 1024） */
const BADGE_RATIO: number = 1901 / 1024;

/** 等级 → 图片资源（0 与负数都落到 Lv0） */
export function levelBadgeRes(level: number): Resource {
  if (level <= 0) {
    return $r('app.media.Lv0');
  }
  if (level === 1) {
    return $r('app.media.Lv1');
  }
  if (level === 2) {
    return $r('app.media.Lv2');
  }
  if (level === 3) {
    return $r('app.media.Lv3');
  }
  if (level === 4) {
    return $r('app.media.Lv4');
  }
  if (level === 5) {
    return $r('app.media.Lv5');
  }
  return $r('app.media.Lv6');
}

@Component
export struct LevelBadge {
  /** 用户等级，超出 0~6 会被夹到区间内 */
  level: number = 0;
  /** 徽章高度（vp），宽度自动按比例算；不能叫 height，会和组件自带的 height() 冲突 */
  badgeHeight: number = 13;

  build() {
    Image(levelBadgeRes(this.level))
      .height(this.badgeHeight)
      .width(this.badgeHeight * BADGE_RATIO)
      .objectFit(ImageFit.Contain)
      .draggable(false)
      .alt($r('app.color.bg_field'))
  }
}
