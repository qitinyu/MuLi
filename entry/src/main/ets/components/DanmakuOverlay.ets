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
    return Math.max(3, Math.floor(this.canvasHeight / LANE_HEIGHT) - 2);
  }

  private spawn(item: DanmakuItem): void {
    this.settings.font = '15px sans-serif';
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
    }    const isTop: boolean = item.mode === 5;
    const active: ActiveStaticDanmaku = {
      text: item.text,
      color: `#${item.color.toString(16).padStart(6, '0')}`,
      x: Math.max(4, (this.canvasWidth - textWidth) / 2),
      y: isTop ? LANE_HEIGHT : this.canvasHeight - 6,
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
        const speed: number = (this.canvasWidth + 60) / (SCROLL_DURATION_MS / this.speedFactor);
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
    this.settings.font = '15px sans-serif';
    this.settings.textBaseline = 'alphabetic';
    this.settings.shadowColor = '#000000';
    this.settings.shadowBlur = 3;
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
