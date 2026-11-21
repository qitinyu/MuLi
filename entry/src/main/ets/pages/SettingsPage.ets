import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { MaterialScope } from '../common/Materials';
import { CARD_RADIUS, PAGE_PADDING } from '../common/DesignSpec';
import { Channel, ChannelRegistry } from '../model/ChannelRegistry';
import { AppPrefs } from '../services/AppPrefs';
import { ScrollSignal } from '../common/ScrollSignal';

const ROW_HEIGHT: number = 52;
/** 分区网格每行块数（n*4 块状显示） */
const PARTITION_COLUMNS: number = 4;
const PARTITION_CELL_HEIGHT: number = 44;
const PARTITION_GAP: number = 8;

/**
 * 设置页（二级路由 name = 'settings'，入口在「我的 → 沐哩设置」）。
 *
 * 版式：与全站一致的沉浸标题栏 + 条式竖排分组，一组一张卡，组内每项一行、
 * 行间细分隔线，需要在行内多选的项目点击后在下方就地展开（下拉写法，不用浮层）。
 *
 * 分组：
 * - 外观 / 通用设置：底部隐藏、默认启动页
 * - 播放器：播放质量 · 播放行为 · 过滤词 · 推荐（占位）+ 推荐页卡片布局（即时生效）
 * - 播放页 / List 分区：显示 List、跟随界面移动隐藏、显示分区（4 列块状勾选）
 *
 * 所有改动即时写入 AppStorage（其他页面 @StorageLink 订阅）并落盘 preferences。
 */
@Component
export struct SettingsPage {
  pathStack: NavPathStack | undefined = undefined;
  @StorageLink('muli_bottomHide') bottomHide: boolean = true;
  @StorageLink('muli_startTab') startTab: number = 0;
  @StorageLink('muli_cardLayout') cardLayout: number = 1;
  @StorageLink('muli_listVisible') listVisible: boolean = true;
  @StorageLink('muli_listFollow') listFollow: boolean = true;
  @StorageLink('muli_partitions') partitions: string = '';
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
    }
  }

  // ---------- 分组 ----------

  @Builder
  appearanceGroup() {
    Column() {
      this.toggleRow('底部隐藏', '关闭后，底部栏将常驻页面。', AppPrefs.KEY_BOTTOM_HIDE,
        this.bottomHide, false)
      this.menuRow('默认启动页', '只改每次启动进入哪个版块，不改底部栏入口位置',
        AppPrefs.KEY_START_TAB, AppPrefs.startTabLabel(this.startTab),
        AppPrefs.START_TAB_LABELS, true)
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

          this.sectionLabel('外观 · 通用设置')
          this.appearanceGroup()

          this.sectionLabel('播放器')
          this.playerGroup()

          this.sectionLabel('播放页 · List 分区')
          this.playPageGroup()

          Text('沐哩 MuLi  V2.0.3')
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
        title: { mainTitle: '设置' }
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
