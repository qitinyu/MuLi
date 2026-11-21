/**
 * 首页顶部分区（List）注册表。
 *
 * 全部 16 个分区固定注册在这里，用户在「我的-设置-播放页-List 分区-显示分区」里
 * 以 4 列块状网格勾选需要展示的分区，勾选结果存为逗号分隔的 key 串。
 * 目前只有「推荐」接入了真实接口，其余分区仍是占位内容页。
 */
export class Channel {
  /** 分区唯一键，用于 ForEach key 与选择集存储 */
  key: string;
  /** 分区展示名 */
  label: string;
  /** 占位说明（接入 API 前显示在空页面里） */
  note: string;

  constructor(key: string, label: string, note: string) {
    this.key = key;
    this.label = label;
    this.note = note;
  }
}

export class ChannelRegistry {
  /** 分区全集，顺序即设置网格里的排布顺序（每行 4 个） */
  static readonly HOME_CHANNELS: Array<Channel> = [
    new Channel('recommend', '推荐', '推荐流接入 Pilihos 首页信息流接口'),
    new Channel('bangumi', '番剧', '番剧分区待接入 bangumi 时间表接口'),
    new Channel('cinema', '影视', '影视分区待接入 pgc 索引接口'),
    new Channel('entertainment', '娱乐', '娱乐分区待接入分区动态接口'),
    new Channel('music', '音乐', '音乐分区待接入分区动态接口'),
    new Channel('dance', '舞蹈', '舞蹈分区待接入分区动态接口'),
    new Channel('game', '游戏', '游戏分区待接入分区动态接口'),
    new Channel('knowledge', '知识', '知识分区待接入分区动态接口'),
    new Channel('tech', '科技', '科技分区待接入分区动态接口'),
    new Channel('life', '生活', '生活分区待接入分区动态接口'),
    new Channel('food', '美食', '美食分区待接入分区动态接口'),
    new Channel('animal', '动物', '动物分区待接入分区动态接口'),
    new Channel('kichiku', '鬼畜', '鬼畜分区待接入分区动态接口'),
    new Channel('fashion', '时尚', '时尚分区待接入分区动态接口'),
    new Channel('information', '资讯', '资讯分区待接入分区动态接口'),
    new Channel('craft', '手工', '手工分区待接入分区动态接口')
  ];

  /** 默认展示的分区（推荐 + 七个常见分区，共两行网格） */
  static readonly DEFAULT_KEYS: string =
    'recommend,bangumi,cinema,entertainment,music,game,knowledge,tech';

  /** 分区总数 */
  static count(): number {
    return ChannelRegistry.HOME_CHANNELS.length;
  }

  /** 按索引取分区，越界返回第一项 */
  static at(index: number): Channel {
    if (index < 0 || index >= ChannelRegistry.HOME_CHANNELS.length) {
      return ChannelRegistry.HOME_CHANNELS[0];
    }
    return ChannelRegistry.HOME_CHANNELS[index];
  }

  static defaultKeys(): string {
    return ChannelRegistry.DEFAULT_KEYS;
  }

  /** 把逗号分隔的 key 串拆成数组（空串返回空数组） */
  static splitKeys(keys: string): Array<string> {
    const result: Array<string> = [];
    if (keys === undefined || keys === null || keys.length === 0) {
      return result;
    }
    const segments: Array<string> = keys.split(',');
    for (let i = 0; i < segments.length; i++) {
      const key: string = segments[i].trim();
      if (key.length > 0) {
        result.push(key);
      }
    }
    return result;
  }

  static isSelected(keys: string, key: string): boolean {
    return ChannelRegistry.splitKeys(keys).indexOf(key) >= 0;
  }

  /**
   * 按选择集过滤出要展示的分区。
   * 顺序恒等于注册表顺序（勾选顺序不影响顶部条的排列），全部取消时兜底展示「推荐」，
   * 避免顶部条变成空白后用户无法回到推荐流。
   */
  static selected(keys: string): Array<Channel> {
    const picked: Array<string> = ChannelRegistry.splitKeys(keys);
    const result: Array<Channel> = [];
    for (let i = 0; i < ChannelRegistry.HOME_CHANNELS.length; i++) {
      const channel: Channel = ChannelRegistry.HOME_CHANNELS[i];
      if (picked.indexOf(channel.key) >= 0) {
        result.push(channel);
      }
    }
    if (result.length === 0) {
      result.push(ChannelRegistry.HOME_CHANNELS[0]);
    }
    return result;
  }

  /** 已选数量（用于设置页右侧计数） */
  static selectedCount(keys: string): number {
    return ChannelRegistry.selected(keys).length;
  }
}
