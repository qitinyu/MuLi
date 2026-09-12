import { DanmakuItem, DanmakuService } from '../services/DanmakuService';

interface ActiveScrollDanmaku {
  text: string;
  color: string;
  lane: number;
  x: number;
  y: number;
  width: number;
}

interface ActiveStaticDanmaku {
  text: string;
  color: string;
  x: number;
  y: number;
  bornAt: number;
}

const SCROLL_DURATION_MS: number = 9000;
const STATIC_DURATION_MS: number = 4000;
const LANE_HEIGHT: number = 22;

/**
 * 弹幕覆盖层：Canvas 逐帧渲染，按时间轴生成弹幕；
 * 进度跳变（seek）时清空重定位，暂停时冻结画面。
 */
@Component
export struct DanmakuOverlay {
  @Prop @Watch('onCidChanged') cid: number = 0;
  @Prop playing: boolean = true;
  @Prop positionMs: number = 0;
  @Prop speedFactor: number = 1.0;
  @Prop @Watch('onFontSizeChanged') danmakuFontSize: number = 1;
  @Prop @Watch('onOpacityChanged') danmakuOpacity: number = 1;
  @Prop @Watch('onSpeedChanged') danmakuSpeed: number = 1;
  @Prop @Watch('onAreaChanged') danmakuArea: number = 100;
  private settings: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private items: DanmakuItem[] = [];
  private cursor: number = 0;
  private lastPositionMs: number = 0;
  private scrollLanes: (ActiveScrollDanmaku | undefined)[] = [];
  private staticItems: ActiveStaticDanmaku[] = [];
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private timerId: number = -1;
  private lastTickAt: number = 0;

  aboutToAppear(): void {
    this.loadDanmaku();
    this.lastTickAt = Date.now();
    this.timerId = setInterval((): void => { this.tick(); }, 33);
  }

  aboutToDisappear(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private onCidChanged(): void {
    this.loadDanmaku();
  }

  private onFontSizeChanged(): void {
    // Rebuild active items because their measured widths use the old font.
    this.scrollLanes = [];
    this.staticItems = [];
    this.draw();
  }

  private onOpacityChanged(): void {
    this.draw();
  }

  private onSpeedChanged(): void {
  }

  private onAreaChanged(): void {
    // 立即按新的显示区域重建弹道，避免用户点击后要等下一轮弹幕才看到变化。
    this.scrollLanes = [];
    this.staticItems = [];
    this.cursor = this.lowerBound(this.positionMs);
    this.lastPositionMs = this.positionMs;
    this.draw();
  }

  private async loadDanmaku(): Promise<void> {
    this.items = [];
    this.cursor = 0;
    this.scrollLanes = [];
    this.staticItems = [];
    try {
      this.items = await DanmakuService.load(this.cid);
    } catch (error) {
      console.warn(`Pilihos danmaku overlay load failed: ${String(error)}`);
    }
  }

  private laneCount(): number {
    const visibleHeight: number = this.canvasHeight * Math.max(0.2, Math.min(1, this.danmakuArea / 100));
    return Math.max(3, Math.floor(visibleHeight / LANE_HEIGHT) - 2);
  }

  private getFontSizePx(): number {
    // Keep compatibility with the old 0/1/2 values while using a continuous
    // 12-48px range for the current setting.
    if (this.danmakuFontSize === 0) return 12;
    if (this.danmakuFontSize === 1) return 15;
    if (this.danmakuFontSize === 2) return 18;
    return Math.max(40, Math.min(60, this.danmakuFontSize));
  }

  private spawn(item: DanmakuItem): void {
    const fontSize: number = this.getFontSizePx();
    this.settings.font = `${fontSize}px sans-serif`;
    const textWidth: number = this.settings.measureText(item.text).width;
    if (item.mode === 1) {
      const laneCount: number = this.laneCount();
      if (laneCount <= 0) return;
      // 优先复用空闲弹道：弹道尾部与新弹幕保持安全间距
      for (let lane: number = 0; lane < laneCount; lane++) {
        const tail: ActiveScrollDanmaku | undefined = this.scrollLanes[lane];
        if (tail === undefined || tail.x + tail.width <= this.canvasWidth - textWidth - 24) {
          const active: ActiveScrollDanmaku = {
            text: item.text,
            color: `#${item.color.toString(16).padStart(6, '0')}`,
            lane: lane,
            x: this.canvasWidth,
            y: lane * LANE_HEIGHT + LANE_HEIGHT,
            width: textWidth
          };
          if (lane < this.scrollLanes.length) {
            this.scrollLanes[lane] = active;
          } else {
            this.scrollLanes.push(active);
          }
          return;
        }
      }
      // 弹道全忙时丢弃，避免堆积
      return;
    }
    const isTop: boolean = item.mode === 5;
    const visibleHeight: number = this.canvasHeight * Math.max(0.2, Math.min(1, this.danmakuArea / 100));
    const active: ActiveStaticDanmaku = {
      text: item.text,
      color: `#${item.color.toString(16).padStart(6, '0')}`,
      x: Math.max(4, (this.canvasWidth - textWidth) / 2),
      y: isTop ? LANE_HEIGHT : visibleHeight - 6,
      bornAt: Date.now()
    };
    this.staticItems.push(active);
    if (this.staticItems.length > 6) {
      this.staticItems.shift();
    }
  }

  private tick(): void {
    const now: number = Date.now();
    const dtMs: number = Math.min(200, now - this.lastTickAt);
    this.lastTickAt = now;
    if (this.canvasWidth <= 0) return;
    const position: number = this.positionMs;
    if (Math.abs(position - this.lastPositionMs) > 1500) {
      // seek：清空在屏弹幕，重新定位时间轴
      this.scrollLanes = [];
      this.staticItems = [];
      this.cursor = this.lowerBound(position);
      this.lastPositionMs = position;
    } else {
      this.lastPositionMs = position;
      if (this.playing) {
        while (this.cursor < this.items.length && this.items[this.cursor].timeMs <= position) {
          this.spawn(this.items[this.cursor]);
          this.cursor++;
        }
        const speed: number = (this.canvasWidth + 60) / (SCROLL_DURATION_MS / (this.speedFactor * (0.5 + this.danmakuSpeed * 0.5)));
        for (let lane: number = 0; lane < this.scrollLanes.length; lane++) {
          const active: ActiveScrollDanmaku | undefined = this.scrollLanes[lane];
          if (active === undefined) continue;
          active.x -= speed * dtMs;
          if (active.x + active.width < 0) {
            this.scrollLanes[lane] = undefined;
          }
        }
        this.staticItems = this.staticItems.filter(
          (active: ActiveStaticDanmaku): boolean => now - active.bornAt < STATIC_DURATION_MS);
      }
    }
    this.draw();
  }

  private lowerBound(positionMs: number): number {
    let low: number = 0;
    let high: number = this.items.length;
    while (low < high) {
      const mid: number = Math.floor((low + high) / 2);
      if (this.items[mid].timeMs < positionMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  private draw(): void {
    this.settings.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    const fontSize: number = this.getFontSizePx();
    this.settings.font = `${fontSize}px sans-serif`;
    this.settings.textBaseline = 'alphabetic';
    this.settings.shadowColor = '#000000';
    this.settings.shadowBlur = 3;
    this.settings.globalAlpha = this.danmakuOpacity;
    for (let lane: number = 0; lane < this.scrollLanes.length; lane++) {
      const active: ActiveScrollDanmaku | undefined = this.scrollLanes[lane];
      if (active === undefined) continue;
      this.settings.fillStyle = active.color;
      this.settings.fillText(active.text, active.x, active.y);
    }
    for (let index: number = 0; index < this.staticItems.length; index++) {
      const active: ActiveStaticDanmaku = this.staticItems[index];
      this.settings.fillStyle = active.color;
      this.settings.fillText(active.text, active.x, active.y);
    }
    this.settings.shadowBlur = 0;
    this.settings.globalAlpha = 1;
  }

  build() {
    Canvas(this.settings)
      .width('100%').height('100%')
      .hitTestBehavior(HitTestMode.None)
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        this.canvasWidth = Number(newArea.width);
        this.canvasHeight = Number(newArea.height);
      })
  }
}
