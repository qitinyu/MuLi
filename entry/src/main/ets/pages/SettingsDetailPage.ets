import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { MaterialScope } from '../common/Materials';
import { CARD_RADIUS, PAGE_PADDING } from '../common/DesignSpec';
import { Channel, ChannelRegistry } from '../model/ChannelRegistry';
import { AppPrefs } from '../services/AppPrefs';

const ROW_HEIGHT: number = 52;
/** 分区网格每行块数（n*4 块状显示） */
const PARTITION_COLUMNS: number = 4;
const PARTITION_CELL_HEIGHT: number = 44;
const PARTITION_GAP: number = 8;

/** 二级页分区标识：与路由名一一对应（settings_appearance / settings_player / settings_playpage） */
export const SECTION_APPEARANCE: string = 'appearance';
export const SECTION_PLAYER: string = 'player';
export const SECTION_PLAYPAGE: string = 'playpage';

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
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.materialLevel = MaterialScope.detectLevel();
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

        Text('待建设')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .backgroundColor($r('app.color.bg_field'))
          .borderRadius(8)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(13)
          .fontColor([$r('app.color.text_tertiary')])
      }
      .width('100%')
      .constraintSize({ minHeight: ROW_HEIGHT })
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.toast(`${title}：接口待接入`);
      })

      this.rowDivider(isLast)
    }
    .width('100%')
  }

  private onPick(key: string, index: number): void {
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
    }
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

  @Builder
  playerGroup() {
    Column() {
      this.navRow('播放质量', '清晰度候选与移动网络策略', false)
      this.navRow('播放行为', '自动连播、后台播放、小窗', false)
      this.navRow('过滤词', '标题与弹幕关键词屏蔽', false)
      this.navRow('推荐', '个性化推荐开关（占位）', false)
      this.menuRow('卡片布局', '推荐页即时生效', AppPrefs.KEY_CARD_LAYOUT,
        AppPrefs.cardLayoutLabel(this.cardLayout), AppPrefs.CARD_LAYOUT_LABELS, true)
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(CARD_RADIUS)
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
      Scroll(this.scroller) {
        Column() {
          Row()
            .width('100%')
            .height(64)

          if (this.section === SECTION_PLAYER) {
            this.sectionLabel('播放器')
            this.playerGroup()
          } else if (this.section === SECTION_PLAYPAGE) {
            this.sectionLabel('播放页 · List 分区')
            this.playPageGroup()
          } else {
            this.sectionLabel('外观 · 通用设置')
            this.appearanceGroup()
          }

          Text('沐哩 MuLi  V2.0.7')
            .width('100%')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Center)
            .margin({ top: 24, bottom: 40 })
        }
        .width('100%')
        .padding({ left: PAGE_PADDING, right: PAGE_PADDING })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
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
