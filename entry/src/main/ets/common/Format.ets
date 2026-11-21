/**
 * 展示层文本格式化：播放量 / 时长 / 时间 / 计数。
 * 接口返回的数值统一在这里转成中文习惯的短文本（1.2万、3.4亿、昨天、12:05 等）。
 */

/** 计数：9256 → 9256，12345 → 1.2万，123456789 → 1.2亿 */
export function shortCount(value: number): string {
  if (!Number.isFinite(value) || value <= 0) {
    return '0';
  }
  if (value < 10000) {
    return `${Math.floor(value)}`;
  }
  if (value < 100000000) {
    const wan: number = value / 10000;
    return `${trimZero(wan.toFixed(wan < 10 ? 1 : 0))}万`;
  }
  const yi: number = value / 100000000;
  return `${trimZero(yi.toFixed(yi < 10 ? 1 : 0))}亿`;
}

function trimZero(text: string): string {
  if (text.indexOf('.') < 0) {
    return text;
  }
  return text.replace(/\.0+$/, '').replace(/(\.\d*?)0+$/, '$1');
}

/** 视频时长：128 → 02:08，3725 → 1:02:05 */
export function durationText(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return '';
  }
  const total: number = Math.floor(seconds);
  const h: number = Math.floor(total / 3600);
  const m: number = Math.floor((total % 3600) / 60);
  const s: number = total % 60;
  const mm: string = h > 0 ? pad2(m) : `${m}`;
  const ss: string = pad2(s);
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** 发布时间：刚刚 / 5分钟前 / 3小时前 / 昨天 / 3天前 / MM-DD / YYYY-MM-DD */
export function pubTimeText(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return '';
  }
  const now: number = Math.floor(Date.now() / 1000);
  const diff: number = now - Math.floor(seconds);
  if (diff < 60) {
    return '刚刚';
  }
  if (diff < 3600) {
    return `${Math.floor(diff / 60)}分钟前`;
  }
  if (diff < 86400) {
    return `${Math.floor(diff / 3600)}小时前`;
  }
  if (diff < 86400 * 2) {
    return '昨天';
  }
  if (diff < 86400 * 30) {
    return `${Math.floor(diff / 86400)}天前`;
  }
  const date: Date = new Date(Math.floor(seconds) * 1000);
  const month: string = pad2(date.getMonth() + 1);
  const day: string = pad2(date.getDate());
  if (diff < 86400 * 365) {
    return `${month}-${day}`;
  }
  return `${date.getFullYear()}-${month}-${day}`;
}

/** 发布日期（卡片第三行）：只保留年月日，形如 26/11/21 */
export function pubDateText(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return '';
  }
  const date: Date = new Date(Math.floor(seconds) * 1000);
  const year: string = pad2(date.getFullYear() % 100);
  const month: string = pad2(date.getMonth() + 1);
  const day: string = pad2(date.getDate());
  return `${year}/${month}/${day}`;
}

/** 数字千分位：12345 → 12,345 */
export function plainCount(value: number): string {
  if (!Number.isFinite(value) || value <= 0) {
    return '0';
  }
  const text: string = `${Math.floor(value)}`;
  let result: string = '';
  for (let i = 0; i < text.length; i++) {
    const rest: number = text.length - i;
    result += text.charAt(i);
    if (rest > 1 && rest % 3 === 1) {
      result += ',';
    }
  }
  return result;
}