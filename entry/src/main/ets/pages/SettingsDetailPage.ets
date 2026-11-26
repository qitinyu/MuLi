import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { MaterialScope } from '../common/Materials';
import { CARD_RADIUS, PAGE_PADDING } from '../common/DesignSpec';
import { AppVersion } from '../common/AppVersion';
import { Channel, ChannelRegistry } from '../model/ChannelRegistry';
import { AppPrefs } from '../services/AppPrefs';
import { PlayerPrefs } from '../services/PlayerPrefs';

const ROW_HEIGHT: number = 52;
/** 分区网格每行块数（n*4 块状显示） */
const PARTITION_COLUMNS: number = 4;
const PARTITION_CELL_HEIGHT: number = 44;
const PARTITION_GAP: number = 8;

/** 二级页分区标识：与路由名一一对应（settings_appearance / settings_player / settings_playpage / settings_dynamic） */
export const SECTION_APPEARANCE: string = 'appearance';
export const SECTION_PLAYER: string = 'player';
export const SECTION_PLAYPAGE: string = 'playpage';
/** 播放 → 动态（V2.1.2）：动态页专用的展示项 */
export const SECTION_DYNAMIC: string = 'dynamic';
/** 设置二级页内部跳转的路由名（与 Index.pageMap 对齐） */
export const ROUTE_SETTINGS_DYNAMIC: string = 'settings_dynamic';

/**
 * 设置二级细则页（V2.0.5）。
 *
 * 一级页（SettingsPage）只放三条总览卡片，细则统一进到这里，避免一级页越堆越长。
 * 同一个组件按 section 渲染三套内容，路由上仍是「一个二级页 = 一个 NavPathStack name」，
 * 与全站其它二级页同一套架构（HdsNavDestination + 沉浸标题栏 + 条式分组）。
 *
 * 分组：
 * - appearance：底部隐藏 / 默认启动页 / UP 主过长名称 / 播放区顶部沉浸 / 增量颜色
 * - player：播放质量 · 播放行为 · 过滤词 · 推荐（占位）+ 推荐页卡片布局（即时生效）
 * - playpage：显示 List、跟随界面移动隐藏、显示分区（4 列块状勾选）
 *
 * 所有改动即时写入 AppStorage（其他页面 @StorageLink 订阅）并落盘 preferences。
 */
@Component
export struct SettingsDetailPage {
  pathStack: NavPathStack | undefined = undefined;
  /** 分区：appearance / player / playpage */
  @Prop section: string = SECTION_APPEARANCE;
  @StorageLink('muli_bottomHide') bottomHide: boolean = true;
  @StorageLink('muli_startTab') startTab: number = 0;
  @StorageLink('muli_cardLayout') cardLayout: number = 1;
  @StorageLink('muli_listVisible') listVisible: boolean = true;
  @StorageLink('muli_listFollow') listFollow: boolean = true;
  @StorageLink('muli_partitions') partitions: string = '';
  @StorageLink(AppPrefs.KEY_AUTHOR_NAME_MODE) authorNameMode: number = 0;
  @StorageLink(AppPrefs.KEY_TOP_IMMERSIVE) topImmersive: boolean = true;
  @StorageLink(AppPrefs.KEY_TOP_INSET_COLOR) topInsetColor: number = 0;
  @StorageLink(AppPrefs.KEY_REC_SAVE) recSave: boolean = true;
  @StorageLink(AppPrefs.KEY_REC_COUNT) recCountIndex: number = 0;
  @StorageLink(AppPrefs.KEY_SHOW_VERTICAL) showVertical: boolean = false;
  @StorageLink(AppPrefs.KEY_LIST_TAP_REFRESH) listTapRefresh: boolean = false;
  /** 全局显示 IP 属地（V2.1.2，默认开） */
  @StorageLink(AppPrefs.KEY_SHOW_IP) showIpLocation: boolean = true;
  /** 动态页快捷入口行数（V2.1.2）：0 = 1 行，1 = 2 行 */
  @StorageLink(AppPrefs.KEY_DYN_QUICK_ROWS) dynQuickRows: number = 0;
  /** 播放器偏好（与播放页共用同一个 preferences store，两边改一处即同步） */
  @State quality: number = 0;
  @State filterRecommend: string = '';
  @State filterDanmaku: string = '';
  /** 过滤词编辑浮层：recommend / danmaku */
  @State filterDialogVisible: boolean = false;
  @State filterKey: string = '';
  @State filterDraft: string = '';
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  private scroller: Scroller = new Scroller();
  /** 播放器偏好实例：与播放页共用同一个 preferences store */
  private prefs: PlayerPrefs = new PlayerPrefs();

  aboutToAppear(): void {
    this.materialLevel = MaterialScope.detectLevel();
    PlayerPrefs.load(this.context()).then((prefs: PlayerPrefs) => {
      this.prefs = prefs;
      this.quality = prefs.quality;
      this.filterRecommend = prefs.filterRecommend;
      this.filterDanmaku = prefs.filterDanmaku;
    }).catch(() => {
      // 读取失败按默认档位渲染
    });
  }

  /** 写播放器偏好：与播放页设置面板同一套字段与磁盘 key */
  private savePlayer(key: string, value: number | string): void {
    this.prefs.save(this.context(), key, value);
  }

  /** 打开过滤词编辑浮层 */
  private openFilterEditor(key: string): void {
    this.filterKey = key;
    this.filterDraft = key === 'recommend' ? this.filterRecommend : this.filterDanmaku;
    this.filterDialogVisible = true;
  }

  /** 保存过滤词（中文逗号分隔，原样存，解析交给 PlayerPrefs.keywords） */
  private applyFilterEditor(): void {
    const text: string = this.filterDraft.trim();
    if (this.filterKey === 'recommend') {
      this.filterRecommend = text;
      this.prefs.filterRecommend = text;
      this.savePlayer('filterRecommend', text);
    } else {
      this.filterDanmaku = text;
      this.prefs.filterDanmaku = text;
      this.savePlayer('filterDanmaku', text);
    }
    this.filterDialogVisible = false;
    const count: number = PlayerPrefs.keywords(text).length;
    this.toast(count > 0 ? `已保存 ${count} 个过滤词` : '过滤词已清空');
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text, duration: 1600 });
    } catch (err) {
      // 提示失败不影响设置本身
    }
  }

  private toggle(key: string, value: boolean): void {
    // 先写 AppStorage（@StorageLink 订阅者即时刷新），再落盘
    AppStorage.setOrCreate(key, value);
    AppPrefs.save(this.context(), key, value);
  }

  private pickNumber(key: string, value: number): void {
    AppStorage.setOrCreate(key, value);
    AppPrefs.save(this.context(), key, value);
  }

  /** 分区勾选：至少保留一个，结果按注册表顺序归一后存储 */
  private togglePartition(key: string): void {
    const picked: Array<string> = ChannelRegistry.splitKeys(this.partitions);
    const index: number = picked.indexOf(key);
    if (index >= 0) {
      if (picked.length <= 1) {
        this.toast('至少保留一个分区');
        return;
      }
      picked.splice(index, 1);
    } else {
      picked.push(key);
    }
    const ordered: Array<string> = [];
    for (let i = 0; i < ChannelRegistry.HOME_CHANNELS.length; i++) {
      const channel: Channel = ChannelRegistry.HOME_CHANNELS[i];
      if (picked.indexOf(channel.key) >= 0) {
        ordered.push(channel.key);
      }
    }
    this.partitions = ordered.join(',');
    AppPrefs.save(this.context(), AppPrefs.KEY_PARTITIONS, this.partitions);
  }

  private partitionRows(): number {
    return Math.ceil(ChannelRegistry.count() / PARTITION_COLUMNS);
  }

  /** 二级页标题：按分区取 */
  private pageTitle(): string {
    if (this.section === SECTION_PLAYER) {
      return '播放器';
    }
    if (this.section === SECTION_PLAYPAGE) {
      return '播放页 · List 分区';
    }
    if (this.section === SECTION_DYNAMIC) {
      return '动态';
    }
    return '外观 · 通用设置';
  }

  // ---------- 通用行 ----------

  @Builder
  sectionLabel(text: string) {
    Text(text)
      .width('100%')
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_tertiary'))
      .padding({ left: PAGE_PADDING + 4, top: 18, bottom: 6 })
  }

  @Builder
  rowDivider(isLast: boolean) {
    if (!isLast) {
      Divider()
        .color($r('app.color.divider'))
        .strokeWidth(0.5)
        .margin({ left: 14 })
    }
  }

  @Builder
  toggleRow(title: string, hint: string, key: string, checked: boolean, isLast: boolean) {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text(title)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          if (hint.length > 0) {
            Text(hint)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(2)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: checked })
          .selectedColor($r('app.color.brand_primary'))
          .onChange((value: boolean) => {
            this.toggle(key, value);
          })
      }
      .width('100%')
      .constraintSize({ minHeight: ROW_HEIGHT })
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)

      this.rowDivider(isLast)
    }
    .width('100%')
  }

  /**
   * 下拉选项：交给系统 Menu 渲染（鸿蒙原生菜单样式），不再就地展开。
   * MenuItem 的 selected 会给选中项打系统勾选标记。
   */
  @Builder
  optionMenu(key: string, options: Array<string>, currentLabel: string) {
    Menu() {
      ForEach(options, (label: string, index: number) => {
        MenuItem({ content: label })
          .selected(label === currentLabel)
          .onClick(() => {
            this.onPick(key, index);
          })
      }, (label: string, index: number) => `${key}_${index}`)
    }
  }

  @Builder
  menuRow(title: string, hint: string, key: string, currentLabel: string,
    options: Array<string>, isLast: boolean) {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text(title)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          if (hint.length > 0) {
            Text(hint)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(2)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(currentLabel)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(13)
          .fontColor([$r('app.color.text_tertiary')])
          .margin({ left: 4 })
      }
      .width('100%')
      .constraintSize({ minHeight: ROW_HEIGHT })
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .bindMenu(this.optionMenu(key, options, currentLabel), {
        placement: Placement.BottomRight
      })

      this.rowDivider(isLast)
    }
    .width('100%')
  }

  @Builder
  navRow(title: string, hint: string, isLast: boolean) {
    Column() {
      Row({ space: 6 }) {
        Column({ space: 3 }) {
          Text(title)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          if (hint.length > 0) {
            Text(hint)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(2)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(13)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .width('100%')
      .constraintSize({ minHeight: ROW_HEIGHT })
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.toast(`${title}：详细设置在播放页「设置」中调整`);
      })

      this.rowDivider(isLast)
    }
    .width('100%')
  }

  /**
   * 可跳转行：右侧箭头 + 摘要，点击进入同体系的另一个二级分区（V2.1.2「播放 → 动态」）。
   * 与 navRow 的区别是 navRow 只弹 toast 占位，这里真的会 push。
   */
  @Builder
  linkRow(title: string, hint: string, summary: string, route: string, isLast: boolean) {
    Column() {
      Row({ space: 6 }) {
        Column({ space: 3 }) {
          Text(title)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          if (hint.length > 0) {
            Text(hint)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(2)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (summary.length > 0) {
          Text(summary)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
        }

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(13)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .width('100%')
      .constraintSize({ minHeight: ROW_HEIGHT })
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.goSection(route);
      })

      this.rowDivider(isLast)
    }
    .width('100%')
  }

  /**
   * 播放质量行。
   *
   * 必须写成专用 Builder、在内部直接读 @State quality：
   * @Builder 的「值传参」不具备响应式，把档位文字当参数传进来，改完档位那一行不会刷新。
   */
  @Builder
  qualityRow() {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text('播放质量')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text('档位与播放页设置同步；未登录时服务端可能回落到 720P')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(2)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(PlayerPrefs.QUALITY_LABELS[this.qualityIndex()])
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(13)
          .fontColor([$r('app.color.text_tertiary')])
          .margin({ left: 4 })
      }
      .width('100%')
      .constraintSize({ minHeight: ROW_HEIGHT })
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .bindMenu(this.optionMenu('quality', PlayerPrefs.QUALITY_LABELS,
        PlayerPrefs.QUALITY_LABELS[this.qualityIndex()]), {
        placement: Placement.BottomRight
      })

      this.rowDivider(false)
    }
    .width('100%')
  }

  /** 下拉刷新数目行：同上，内部读 @State，改完立刻刷新 */
  @Builder
  recCountRow() {
    Column() {
      Row() {
        Column({ space: 3 }) {
          Text('下拉刷新数目')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          Text('每次下拉刷新拉取多少条')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(2)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(AppPrefs.recCountLabel(this.recCountIndex))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(13)
          .fontColor([$r('app.color.text_tertiary')])
          .margin({ left: 4 })
      }
      .width('100%')
      .constraintSize({ minHeight: ROW_HEIGHT })
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .bindMenu(this.optionMenu(AppPrefs.KEY_REC_COUNT, AppPrefs.REC_COUNT_LABELS,
        AppPrefs.recCountLabel(this.recCountIndex)), {
        placement: Placement.BottomRight
      })

      this.rowDivider(false)
    }
    .width('100%')
  }

  /** 过滤词当前值：Builder 内部读取，保证保存后立刻回显 */
  private rowValue(key: string): string {
    return key === 'recommend' ? this.filterSummary(this.filterRecommend)
      : this.filterSummary(this.filterDanmaku);
  }

  /** 文本输入型设置行：右侧显示当前值摘要，点击打开编辑浮层 */
  @Builder
  textRow(title: string, hint: string, key: string, isLast: boolean) {
    Column() {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text(title)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
          if (hint.length > 0) {
            Text(hint)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(2)
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.rowValue(key).length > 0 ? this.rowValue(key) : '未设置')
          .fontSize(12)
          .fontColor(this.rowValue(key).length > 0
            ? $r('app.color.text_secondary') : $r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '42%' })

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(13)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .width('100%')
      .constraintSize({ minHeight: ROW_HEIGHT })
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openFilterEditor(key);
      })

      this.rowDivider(isLast)
    }
    .width('100%')
  }

  private onPick(key: string, index: number): void {
    if (key === 'quality') {
      this.quality = PlayerPrefs.QUALITIES[index];
      this.prefs.quality = this.quality;
      this.savePlayer('quality', this.quality);
      return;
    }
    if (key === AppPrefs.KEY_REC_COUNT) {
      this.recCountIndex = index;
      this.pickNumber(AppPrefs.KEY_REC_COUNT, index);
      return;
    }
    if (key === AppPrefs.KEY_START_TAB) {
      this.startTab = index;
      this.pickNumber(AppPrefs.KEY_START_TAB, index);
      if (!AppPrefs.startTabAvailable(index)) {
        this.toast(`${AppPrefs.startTabLabel(index)}版块待建设，启动后进入首页`);
      }
      return;
    }
    if (key === AppPrefs.KEY_CARD_LAYOUT) {
      this.cardLayout = index;
      this.pickNumber(AppPrefs.KEY_CARD_LAYOUT, index);
      return;
    }
    if (key === AppPrefs.KEY_AUTHOR_NAME_MODE) {
      this.authorNameMode = index;
      this.pickNumber(AppPrefs.KEY_AUTHOR_NAME_MODE, index);
      return;
    }
    if (key === AppPrefs.KEY_TOP_INSET_COLOR) {
      this.topInsetColor = index;
      this.pickNumber(AppPrefs.KEY_TOP_INSET_COLOR, index);
      return;
    }
    if (key === AppPrefs.KEY_DYN_QUICK_ROWS) {
      this.dynQuickRows = index;
      this.pickNumber(AppPrefs.KEY_DYN_QUICK_ROWS, index);
    }
  }

  /** 跳转到本页的其它分区（如 播放 → 动态），保证返回栈仍在本设置体系内 */
  private goSection(route: string): void {
    if (this.pathStack === undefined) {
      return;
    }
    this.pathStack.pushPathByName(route, '');
  }

  // ---------- 分组 ----------

  /** 外观 · 通用设置：全局观感与通用行为 */
  @Builder
  appearanceGroup() {
    Column() {
      this.toggleRow('底部隐藏', '关闭后，底部栏将常驻页面。', AppPrefs.KEY_BOTTOM_HIDE,
        this.bottomHide, false)
      this.menuRow('默认启动页', '只改每次启动进入哪个版块，不改底部栏入口位置',
        AppPrefs.KEY_START_TAB, AppPrefs.startTabLabel(this.startTab),
        AppPrefs.START_TAB_LABELS, false)
      this.menuRow('UP 主过长名称', '视频卡里 UP 名超出可见宽度时的处理方式',
        AppPrefs.KEY_AUTHOR_NAME_MODE, AppPrefs.authorNameLabel(this.authorNameMode),
        AppPrefs.AUTHOR_NAME_LABELS, false)
      this.toggleRow('全局显示 IP 属地',
        '关闭后全局不再显示个人及其他用户 IP 属地。',
        AppPrefs.KEY_SHOW_IP, this.showIpLocation, false)
      this.toggleRow('播放区顶部沉浸', '默认沉浸到系统状态栏，关闭后顶部状态栏会添加黑色条作为增量。',
        AppPrefs.KEY_TOP_IMMERSIVE, this.topImmersive, false)
      this.menuRow('增量颜色', '仅在关闭「播放区顶部沉浸」时生效',
        AppPrefs.KEY_TOP_INSET_COLOR, AppPrefs.topInsetLabel(this.topInsetColor),
        AppPrefs.TOP_INSET_LABELS, true)
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
  }

  /**
   * 动态分组（V2.1.2）：从「播放器」二级进二级。
   *
   * 规格要求是「设置-播放增加 `动态` 二级条目，再在其内部添加 `快捷入口行数`」，
   * 所以这里在播放器分组放一个可跳转的 linkRow，真正的开关在 SECTION_DYNAMIC 页里。
   */
  @Builder
  dynamicGroup() {
    Column() {
      this.menuRow('快捷入口行数', '动态页顶部快捷 UP 主一屏显示几行，每行 4 个头像',
        AppPrefs.KEY_DYN_QUICK_ROWS, AppPrefs.dynQuickRowLabel(this.dynQuickRows),
        AppPrefs.DYN_QUICK_ROW_LABELS, true)
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
  }

  /**
   * 播放器分组（V2.1.0）。
   *
   * - 播放质量：档位与播放页设置面板共用 PlayerPrefs.QUALITIES，任一处修改两边同步；
   * - 播放行为：只保留「后台播放 / 小窗」，自动连播由播放模式控制，不再重复一句小字；
   * - 过滤词拆成两条：推荐视频过滤（标题命中即不推荐）、视频弹幕过滤（命中不上屏）；
   * - 卡片布局保持原条目。
   */
  @Builder
  playerGroup() {
    Column() {
      this.qualityRow()
      this.navRow('播放行为', '后台播放、小窗', false)
      this.linkRow('动态', '动态页展示项：快捷入口行数', AppPrefs.dynQuickRowLabel(this.dynQuickRows),
        ROUTE_SETTINGS_DYNAMIC, false)
      this.textRow('推荐视频过滤', '关键词以中文逗号「，」隔开，标题命中的视频不再推荐', 'recommend', false)
      this.textRow('视频弹幕过滤', '关键词以中文逗号「，」隔开，命中的弹幕不会显示', 'danmaku', false)
      this.menuRow('卡片布局', '推荐页即时生效', AppPrefs.KEY_CARD_LAYOUT,
        AppPrefs.cardLayoutLabel(this.cardLayout), AppPrefs.CARD_LAYOUT_LABELS, true)
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
  }

  /** 推荐分组：下拉刷新保存 / 刷新数目 / 视频展示（竖屏化视频混排） */
  @Builder
  recommendGroup() {
    Column() {
      this.toggleRow('下拉刷新内容保存', '关闭后，下拉刷新不再保存前置内容',
        AppPrefs.KEY_REC_SAVE, this.recSave, false)
      this.recCountRow()
      this.toggleRow('竖屏视频展示', '开启后竖屏化视频也会在推荐页其他视频混乱展示，并在播放量数前标注「竖屏」',
        AppPrefs.KEY_SHOW_VERTICAL, this.showVertical, true)
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
  }

  /** 过滤词摘要：超过一行时截断并且数出条数 */
  private filterSummary(text: string): string {
    const words: Array<string> = PlayerPrefs.keywords(text);
    if (words.length === 0) {
      return '';
    }
    return words.length > 2 ? `${words[0]}、${words[1]} 等 ${words.length} 个` : words.join('、');
  }

  private qualityIndex(): number {
    const index: number = PlayerPrefs.QUALITIES.indexOf(this.quality);
    return index < 0 ? 0 : index;
  }

  /** 过滤词编辑浮层：文本输入式，中文逗号分隔 */
  @Builder
  filterEditor() {
    if (this.filterDialogVisible) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.scrim'))
          .onClick(() => {
            this.filterDialogVisible = false;
          })

        Column({ space: 12 }) {
          Text(this.filterKey === 'recommend' ? '推荐视频过滤' : '视频弹幕过滤')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .width('100%')

          Text(this.filterKey === 'recommend'
            ? '标题包含任一关键词的视频将不再出现在播放页推荐中'
            : '正文包含任一关键词的弹幕将不再上屏')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')

          TextInput({ text: this.filterDraft, placeholder: '例如：广告，剧透，标题党' })
            .width('100%')
            .height(44)
            .fontSize(14)
            .padding({ left: 12, right: 12 })
            .backgroundColor($r('app.color.bg_field'))
            .borderRadius(10)
            .onChange((value: string) => {
              this.filterDraft = value;
            })

          Text(`已识别 ${PlayerPrefs.keywords(this.filterDraft).length} 个关键词（用中文逗号隔开）`)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')

          Row({ space: 10 }) {
            Text('清空')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 9, bottom: 9 })
              .backgroundColor($r('app.color.bg_field'))
              .borderRadius(18)
              .onClick(() => {
                this.filterDraft = '';
              })
            Text('保存')
              .fontSize(14)
              .fontColor($r('app.color.text_on_brand'))
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 9, bottom: 9 })
              .backgroundColor($r('app.color.brand_primary'))
              .borderRadius(18)
              .onClick(() => {
                this.applyFilterEditor();
              })
          }
          .width('100%')
        }
        .width('86%')
        .padding(16)
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius(16)
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  partitionGrid() {
    Column() {
      Grid() {
        ForEach(ChannelRegistry.HOME_CHANNELS, (channel: Channel) => {
          GridItem() {
            Column() {
              Text(channel.label)
                .fontSize(13)
                .fontColor(ChannelRegistry.isSelected(this.partitions, channel.key)
                  ? $r('app.color.brand_primary') : $r('app.color.text_secondary'))
                .maxLines(1)
            }
            .width('100%')
            .height(PARTITION_CELL_HEIGHT)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(ChannelRegistry.isSelected(this.partitions, channel.key)
              ? $r('app.color.brand_tint') : $r('app.color.bg_field'))
            .borderRadius(10)
            .border({
              width: ChannelRegistry.isSelected(this.partitions, channel.key) ? 1.5 : 0.5,
              color: ChannelRegistry.isSelected(this.partitions, channel.key)
                ? $r('app.color.brand_primary') : $r('app.color.divider')
            })
            .onClick(() => {
              this.togglePartition(channel.key);
            })
          }
        }, (channel: Channel) => channel.key)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .columnsGap(PARTITION_GAP)
      .rowsGap(PARTITION_GAP)
      .width('100%')
      .height(this.partitionRows() * PARTITION_CELL_HEIGHT + (this.partitionRows() - 1) * PARTITION_GAP)

      Text(`已展示 ${ChannelRegistry.selectedCount(this.partitions)} / ${ChannelRegistry.count()} 个分区，点击方块加边框表示展示`)
        .width('100%')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 10 })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 14 })
  }

  @Builder
  playPageGroup() {
    Column() {
      this.toggleRow('显示 List', '关闭后不再显示 List', AppPrefs.KEY_LIST_VISIBLE,
        this.listVisible, false)
      this.toggleRow('跟随界面移动隐藏', '关闭后上滑界面 List 将保持显示', AppPrefs.KEY_LIST_FOLLOW,
        this.listFollow, false)
      this.toggleRow('点击分区 List 全量刷新', '实验性：开启后点击顶部的分区 List，实现单个分区全量刷新（刷新前内容可能不保存）',
        AppPrefs.KEY_LIST_TAP_REFRESH, this.listTapRefresh, false)

      Row() {
        Text('显示分区')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('4 列块状展示')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 2 })
      .alignItems(VerticalAlign.Center)

      this.partitionGrid()
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Top }) {
        Scroll(this.scroller) {
          Column() {
            Row()
              .width('100%')
              .height(64)

            if (this.section === SECTION_PLAYER) {
              this.sectionLabel('播放器')
              this.playerGroup()
              this.sectionLabel('推荐')
              this.recommendGroup()
            } else if (this.section === SECTION_PLAYPAGE) {
              this.sectionLabel('播放页 · List 分区')
              this.playPageGroup()
            } else if (this.section === SECTION_DYNAMIC) {
              this.sectionLabel('动态')
              this.dynamicGroup()
              this.sectionLabel('提示')
              Text('快捷入口行数会同时影响手机与平板；每行固定 4 个头像，两行即 8 个。')
                .width('100%')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
                .padding({ left: PAGE_PADDING + 4, right: PAGE_PADDING + 4, bottom: 8 })
            } else {
              this.sectionLabel('外观 · 通用设置')
              this.appearanceGroup()
            }

            Text(`沐哩 MuLi  ${AppVersion.label()}`)
              .width('100%')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .textAlign(TextAlign.Center)
              .margin({ top: 24, bottom: 40 })
          }
          .width('100%')
          .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        // 取消垂直居中：内容不足一屏时也从顶部开始排，不再被 Scroll 居中
        .align(Alignment.Top)

        this.filterEditor()
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({
      content: {
        title: { mainTitle: this.pageTitle() }
      },
      style: {
        originalStyle: {
          contentStyle: {
            titleStyle: { mainTitleColor: $r('app.color.text_primary') },
            menuStyle: { iconColor: $r('app.color.text_primary') },
            backIconStyle: { iconColor: $r('app.color.text_primary') }
          }
        },
        scrollEffectStyle: {
          contentStyle: {
            titleStyle: { mainTitleColor: $r('app.color.text_primary') },
            menuStyle: { iconColor: $r('app.color.text_primary') },
            backIconStyle: { iconColor: $r('app.color.text_primary') }
          }
        },
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(64)
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: this.materialLevel
        }
      }
    })
    .hideBackButton(false)
    .bindToScrollable([this.scroller])
    .backgroundColor($r('app.color.bg_page'))
  }
}
