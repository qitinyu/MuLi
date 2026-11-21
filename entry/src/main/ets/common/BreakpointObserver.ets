import { mediaquery, MediaQuery } from '@kit.ArkUI';

/**
 * 断点监听：sm(<600vp) / md(600~840vp) / lg(>840vp)。
 * 与页面架构范式保持一致，用于手机竖屏与平板/折叠展开两种布局分支。
 */
export class BreakpointObserver {
  private mediaQuery: MediaQuery;
  private callback: (breakpoint: string) => void;
  private conditions: Array<string> = [
    '(max-width: 600vp)',
    '(min-width: 600vp) and (max-width: 840vp)',
    '(min-width: 840vp)'
  ];
  private names: Array<string> = ['sm', 'md', 'lg'];
  private listeners: Array<mediaquery.MediaQueryListener> = [];
  private current: string = 'sm';

  constructor(mediaQuery: MediaQuery, callback: (breakpoint: string) => void) {
    this.mediaQuery = mediaQuery;
    this.callback = callback;
  }

  /** 立即求值一次并开始监听。 */
  register(): void {
    for (let i = 0; i < this.conditions.length; i++) {
      const condition: string = this.conditions[i];
      const name: string = this.names[i];
      const listener: mediaquery.MediaQueryListener = this.mediaQuery.matchMediaSync(condition);
      if (listener.matches) {
        this.current = name;
        this.callback(name);
      }
      listener.on('change', (result: mediaquery.MediaQueryResult) => {
        if (result.matches && this.current !== name) {
          this.current = name;
          this.callback(name);
        }
      });
      this.listeners.push(listener);
    }
  }

  /** 取消监听，页面销毁时必须调用。 */
  unregister(): void {
    for (let i = 0; i < this.listeners.length; i++) {
      try {
        this.listeners[i].off('change');
      } catch (err) {
        // 监听已失效，忽略
      }
    }
    this.listeners = [];
  }

  /** 当前断点名。 */
  value(): string {
    return this.current;
  }
}
