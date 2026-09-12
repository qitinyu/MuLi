export interface EmojiSegment {
  text: string;
  url: string;
}

/**
 * 把含 [表情名] 的评论文本拆分为 文本/表情 片段序列，供图文混排渲染。
 */
export class EmojiText {
  static split(message: string, urlMap: Map<string, string>): EmojiSegment[] {
    const segments: EmojiSegment[] = [];
    const pattern: RegExp = /\[([^\[\]]{1,32})\]/g;
    let cursor: number = 0;
    let matched: RegExpExecArray | null = pattern.exec(message);
    while (matched !== null) {
      if (matched.index > cursor) {
        segments.push({ text: message.substring(cursor, matched.index), url: '' });
      }
      const name: string = matched[1].trim();
      const url: string = urlMap.get(name) ?? '';
      if (url === '') {
        segments.push({ text: matched[0], url: '' });
      } else {
        segments.push({ text: name, url: url });
      }
      cursor = matched.index + matched[0].length;
      matched = pattern.exec(message);
    }
    if (cursor < message.length) {
      segments.push({ text: message.substring(cursor), url: '' });
    }
    if (segments.length === 0) {
      segments.push({ text: message, url: '' });
    }
    return segments;
  }
}
