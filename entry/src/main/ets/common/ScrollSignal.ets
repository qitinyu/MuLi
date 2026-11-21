/**
 * 滚动 → 底部栏收起信号。
 *
 * 各页签的 List 在 onScroll 里调 report(scroller)，这里按纵向位移方向判定：
 * 向上滑（内容向上走）收起底部栏，向下滑或回到顶部立即显示。
 * 结果写进 AppStorage，Index 订阅后做高度动画，页面之间不直接耦合。
 */
export class ScrollSignal {
  static readonly KEY_HIDDEN: string = 'muli_barHidden';
  /** 「底部隐藏」关闭时置 false：只记录位移，不再驱动隐藏 */
  static enabled: boolean = true;

  private static lastY: number = -1;
  private static hidden: boolean = false;

  static report(scroller: Scroller): void {
    if (!ScrollSignal.enabled) {
      return;
    }
    let offset: number = 0;
    try {
      offset = scroller.currentOffset().yOffset;
    } catch (err) {
      return;
    }
    if (ScrollSignal.lastY < 0) {
      ScrollSignal.lastY = offset;
      return;
    }
    const delta: number = offset - ScrollSignal.lastY;
    ScrollSignal.lastY = offset;
    if (offset <= 8) {
      ScrollSignal.apply(false);
      return;
    }
    if (delta > 8) {
      ScrollSignal.apply(true);
    } else if (delta < -8) {
      ScrollSignal.apply(false);
    }
  }

  /** 切页签 / 回到顶部时复位，避免新页签继承了上一页的收起状态 */
  static reset(): void {
    ScrollSignal.lastY = -1;
    ScrollSignal.apply(false);
  }

  private static apply(hide: boolean): void {
    if (ScrollSignal.hidden === hide) {
      return;
    }
    ScrollSignal.hidden = hide;
    AppStorage.setOrCreate(ScrollSignal.KEY_HIDDEN, hide);
  }
}
