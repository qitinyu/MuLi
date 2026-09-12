/**
 * 统一日志工具
 * 提供分级日志输出和用户可见的错误提示
 */

export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
  NONE = 4
}

export class Logger {
  private static level: LogLevel = LogLevel.INFO;
  private static prefix: string = 'Pilihos';

  static setLevel(level: LogLevel): void {
    Logger.level = level;
  }

  static setPrefix(prefix: string): void {
    Logger.prefix = prefix;
  }

  static debug(message: string, ...args: Object[]): void {
    if (Logger.level <= LogLevel.DEBUG) {
      console.debug(`[${Logger.prefix}] ${message}`, ...args);
    }
  }

  static info(message: string, ...args: Object[]): void {
    if (Logger.level <= LogLevel.INFO) {
      console.info(`[${Logger.prefix}] ${message}`, ...args);
    }
  }

  static warn(message: string, ...args: Object[]): void {
    if (Logger.level <= LogLevel.WARN) {
      console.warn(`[${Logger.prefix}] ${message}`, ...args);
    }
  }

  static error(message: string, ...args: Object[]): void {
    if (Logger.level <= LogLevel.ERROR) {
      console.error(`[${Logger.prefix}] ${message}`, ...args);
    }
  }

  /**
   * 将业务错误转换为用户友好的提示信息
   */
  static userMessage(error: string, fallback: string = '操作失败'): string {
    if (error === '') return fallback;
    const text: string = String(error);
    // 常见错误映射
    if (text.includes('网络') || text.includes('network') || text.includes('ECONNREFUSED')) {
      return '网络连接失败，请检查网络后重试';
    }
    if (text.includes('timeout') || text.includes('超时')) {
      return '请求超时，请稍后重试';
    }
    if (text.includes('登录') || text.includes('login') || text.includes('cookie')) {
      return '请先登录后再操作';
    }
    if (text.includes('权限') || text.includes('permission') || text.includes('403')) {
      return '没有操作权限';
    }
    if (text.includes('412') || text.includes('风控')) {
      return '操作频繁，请稍后再试';
    }
    if (text.includes('-412')) {
      return '请求被拦截，请稍后重试';
    }
    if (text.includes('-352')) {
      return '安全验证失败，请稍后重试';
    }
    if (text.includes('播放') || text.includes('play')) {
      return '视频播放失败，请重试';
    }
    return `${fallback}: ${text.substring(0, 100)}`;
  }

  /**
   * 从 BusinessError 中提取错误码
   */
  static errorCode(error: string): string {
    if (error === '') return 'UNKNOWN';
    const text: string = String(error);
    const match: RegExpMatchArray | null = text.match(/(?:code|错误码)\D*(-?\d+)/i);
    if (match !== null) return match[1];
    const leading: RegExpMatchArray | null = text.match(/^(-?\d+)/);
    if (leading !== null) return leading[1];
    return 'UNKNOWN';
  }
}
