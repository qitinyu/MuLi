import { common } from '@kit.AbilityKit';
import { PlayerPrefs } from '../services/PlayerPrefs';

const ROW_HEIGHT: number = 50;

/**
 * 播放设置（信息区「设置」tab 的内联内容页）。
 *
 * 形态说明（V2.0.4）：
 * - 不使用侧边栏 / 遮罩浮层，直接作为视频下方的内容区向下铺开，随页面一起滚动；
 * - 每个设置项一行，需要多选的行点击后在**行下方就地展开**选项列表（手风琴式向下写法），
 *   与旧版播放器的下拉菜单逻辑一致，但方向朝下、不再浮空。
 *
 * 分组：基础（清晰度 / 续播 / 迷你进度条 / 手势）、播放行为（长按倍速 / 播放模式 / 偏好）、
 * 弹幕设置（总开关 / 过滤词 / 显示区域 / 不透明度 / 字号 / 滚动速度，改动由播放页即时应用）。
 *
 * 边界（V2.1.0）：应用级设置（竖屏视频展示、推荐视频过滤词）只留在「我的 - 设置 - 播放页」，
 * 播放区设置面板不再重复出现，避免同一个开关两处入口、状态互相打架。
 */
@Component
export struct PlayerSettingsPanel {
  @Link prefs: PlayerPrefs;
  onChanged: (key: string, value: number | boolean | string) => void = () => {
  };
  /** 偏好设置里「分享视频」调起系统分享（由播放页注入，面板本身不持有视频信息） */
  onShare: () => void = () => {
  };
  /** 弹幕过滤词输入框是否展开 */
  @State filterEditing: boolean = false;
  @State filterDraft: string = '';
  /**
   * 档位 / 过滤词的本地镜像。
   * prefs 是 @Link 到普通类实例，改内部字段不会触发刷新（只有整体赋值才会），
   * 所以展示用的值必须放在 @State 里，改完当场回显。
   */
  @State qualityValue: number = 0;
  @State filterDanmakuValue: string = '';
  /** 其余下拉行的当前档位：同理，选中后必须有个 @State 变化，右侧文案才会跟着换 */
  @State playModeValue: number = 2;
  @State speedValue: number = 2;
  @State danmakuAreaValue: number = 1;
  @State danmakuOpacityValue: number = 1;
  @State danmakuSizeValue: number = 18;
  @State danmakuSpeedValue: number = 1;

  aboutToAppear(): void {
    this.qualityValue = this.prefs.quality;
    this.filterDanmakuValue = this.prefs.filterDanmaku;
    this.playModeValue = this.prefs.playMode;
    this.speedValue = this.prefs.longPressSpeed;
    this.danmakuAreaValue = this.prefs.danmakuArea;
    this.danmakuOpacityValue = this.prefs.danmakuOpacity;
    this.danmakuSizeValue = this.prefs.danmakuSize;
    this.danmakuSpeedValue = this.prefs.danmakuSpeed;
  }

  /**
   * 下拉行当前档位下标 / 右侧文案。
   *
   * 做成「按 key 从 @State 里现算」的方法，而不是在 build 里算好当参数传给 @Builder——
   * @Builder 的值传参不具备响应式，选中后右侧文案不会变（曾实测：模式已切到「停止推荐」，
   * 行内仍显示「随机连播」）。在 Builder 内部读 @State 才会参与刷新。
   */
  private menuIndex(key: string): number {
    switch (key) {
      case 'quality':
        return this.indexOfValue(PlayerPrefs.QUALITIES, this.qualityValue);
      case 'longPressSpeed':
        return this.indexOfValue(PlayerPrefs.SPEEDS, this.speedValue);
      case 'playMode':
        return Math.max(0, Math.min(PlayerPrefs.PLAY_MODE_LABELS.length - 1, this.playModeValue));
      case 'danmakuArea':
        return this.indexOfValue(PlayerPrefs.DANMAKU_RATIOS, this.danmakuAreaValue);
      case 'danmakuOpacity':
        return this.indexOfValue(PlayerPrefs.DANMAKU_RATIOS, this.danmakuOpacityValue);
      case 'danmakuSize':
        return this.indexOfValue(PlayerPrefs.DANMAKU_SIZES, this.danmakuSizeValue);
      case 'danmakuSpeed':
        return this.indexOfValue(PlayerPrefs.DANMAKU_SPEEDS, this.danmakuSpeedValue);
      default:
        return -1;
    }
  }

  private menuLabel(key: string): string {
    const index: number = this.menuIndex(key);
    switch (key) {
      case 'quality':
        return PlayerPrefs.QUALITY_LABELS[index];
      case 'longPressSpeed':
        return `${PlayerPrefs.SPEEDS[index].toFixed(2)}x`;
      case 'playMode':
        return PlayerPrefs.PLAY_MODE_LABELS[index];
      case 'danmakuArea':
      case 'danmakuOpacity':
        return PlayerPrefs.RATIO_LABELS[index];
      case 'danmakuSize':
        return PlayerPrefs.SIZE_LABELS[index];
      case 'danmakuSpeed':
        return PlayerPrefs.SPEED_LABELS[index];
      case 'preference':
        return '更多操作';
      default:
        return '';
    }
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private commitNumber(key: string, value: number): void {
    this.prefs.save(this.context(), key, value);
    this.onChanged(key, value);
  }

  private commitBoolean(key: string, value: boolean): void {
    this.prefs.save(this.context(), key, value);
    this.onChanged(key, value);
  }

  private toast(text: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: text, duration: 1600 });
    } catch (err) {
      // 提示失败不影响设置本身
    }
  }

  private indexOfValue(values: Array<number>, value: number): number {
    const index: number = values.indexOf(value);
    return index < 0 ? 0 : index;
  }

  /** 下拉菜单选中回调：key 决定写入哪个字段 */
  private onPick(key: string, index: number): void {
    switch (key) {
      case 'quality':
        this.prefs.quality = PlayerPrefs.QUALITIES[index];
        this.qualityValue = this.prefs.quality;
        this.commitNumber('quality', this.prefs.quality);
        break;
      case 'longPressSpeed':
        this.prefs.longPressSpeed = PlayerPrefs.SPEEDS[index];
        this.speedValue = this.prefs.longPressSpeed;
        this.commitNumber('longPressSpeed', this.prefs.longPressSpeed);
        break;
      case 'playMode':
        this.prefs.playMode = index;
        this.playModeValue = index;
        this.commitNumber('playMode', index);
        break;
      case 'danmakuArea':
        this.prefs.danmakuArea = PlayerPrefs.DANMAKU_RATIOS[index];
        this.danmakuAreaValue = this.prefs.danmakuArea;
        this.commitNumber('danmakuArea', this.prefs.danmakuArea);
        break;
      case 'danmakuOpacity':
        this.prefs.danmakuOpacity = PlayerPrefs.DANMAKU_RATIOS[index];
        this.danmakuOpacityValue = this.prefs.danmakuOpacity;
        this.commitNumber('danmakuOpacity', this.prefs.danmakuOpacity);
        break;
      case 'danmakuSize':
        this.prefs.danmakuSize = PlayerPrefs.DANMAKU_SIZES[index];
        this.danmakuSizeValue = this.prefs.danmakuSize;
        this.commitNumber('danmakuSize', this.prefs.danmakuSize);
        break;
      case 'danmakuSpeed':
        this.prefs.danmakuSpeed = PlayerPrefs.DANMAKU_SPEEDS[index];
        this.danmakuSpeedValue = this.prefs.danmakuSpeed;
        this.commitNumber('danmakuSpeed', this.prefs.danmakuSpeed);
        break;
      case 'preference': {
        if (index === 0) {
          this.onShare();
        } else {
          const labels: Array<string> = ['分享视频', '减推视频', '举报视频', '进小黑屋'];
          this.toast(`${labels[index]} 功能待接入`);
        }
        break;
      }
      default:
        break;
    }
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .width('100%')
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.text_tertiary'))
      .padding({ top: 18, bottom: 6 })
  }

  @Builder
  toggleRow(title: string, hint: string, key: string, checked: boolean) {
    Row() {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
        Text(hint)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .selectedColor($r('app.color.brand_primary'))
        .onChange((value: boolean) => {
          switch (key) {
            case 'continuePlay':
              this.prefs.continuePlay = value;
              break;
            case 'miniProgress':
              this.prefs.miniProgress = value;
              break;
            case 'quickGestures':
              this.prefs.quickGestures = value;
              break;
            case 'danmakuOn':
              this.prefs.danmakuOn = value;
              break;
            default:
              break;
          }
          this.commitBoolean(key, value);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: ROW_HEIGHT })
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  optionMenu(key: string, options: Array<string>, selectedIndex: number) {
    Menu() {
      ForEach(options, (label: string, index: number) => {
        MenuItem({ content: label })
          .selected(index === selectedIndex)
          .onClick(() => {
            this.onPick(key, index);
          })
      }, (label: string, index: number) => `${key}_${index}`)
    }
  }

  @Builder
  menuRow(title: string, key: string, options: Array<string>, hint: string) {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text(title)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          if (hint.length > 0) {
            Text(hint)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.menuLabel(key))
          .fontSize(13)
          .fontColor($r('app.color.brand_primary'))
          .maxLines(1)

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(13)
          .fontColor([$r('app.color.text_tertiary')])
          .margin({ left: 4 })
      }
      .width('100%')
      .constraintSize({ minHeight: ROW_HEIGHT })
      .padding({ top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      // 系统原生菜单（与设置页一致），选中项由 MenuItem.selected 打勾
      .bindMenu(this.optionMenu(key, options, this.menuIndex(key)), {
        placement: Placement.BottomRight
      })
    }
    .width('100%')
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  /** 过滤词摘要：最多显示两个词，再多就折叠成「等 N 个」 */
  private filterSummary(): string {
    const words: Array<string> = PlayerPrefs.keywords(this.filterDanmakuValue);
    if (words.length === 0) {
      return '未设置';
    }
    return words.length > 2 ? `${words[0]}、${words[1]} 等 ${words.length} 个` : words.join('、');
  }

  private applyFilter(): void {
    const text: string = this.filterDraft.trim();
    this.prefs.filterDanmaku = text;
    this.filterDanmakuValue = text;
    this.prefs.save(this.context(), 'filterDanmaku', text);
    this.onChanged('filterDanmaku', text);
    this.filterEditing = false;
    const count: number = PlayerPrefs.keywords(text).length;
    this.toast(count > 0 ? `已保存 ${count} 个过滤词` : '过滤词已清空');
  }

  /** 文本输入式设置行：点一下就在行下方展开输入框（手风琴式，不弹浮层） */
  @Builder
  filterRow(title: string, hint: string) {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text(title)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Text(hint)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(2)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(this.filterSummary())
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .constraintSize({ maxWidth: '38%' })

        SymbolGlyph(this.filterEditing
          ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(13)
          .fontColor([$r('app.color.text_tertiary')])
          .margin({ left: 4 })
      }
      .width('100%')
      .constraintSize({ minHeight: ROW_HEIGHT })
      .padding({ top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (this.filterEditing) {
          this.filterEditing = false;
          return;
        }
        this.filterEditing = true;
        this.filterDraft = this.filterDanmakuValue;
      })

      if (this.filterEditing) {
        Row({ space: 8 }) {
          TextInput({ text: this.filterDraft, placeholder: '关键词用中文逗号隔开，如：广告，剧透' })
            .layoutWeight(1)
            .height(38)
            .fontSize(13)
            .backgroundColor($r('app.color.bg_field'))
            .borderRadius(9)
            .padding({ left: 10, right: 10 })
            .onChange((value: string) => {
              this.filterDraft = value;
            })
          Text('保存')
            .fontSize(13)
            .fontColor($r('app.color.text_on_brand'))
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .backgroundColor($r('app.color.brand_primary'))
            .borderRadius(15)
            .onClick(() => {
              this.applyFilter();
            })
        }
        .width('100%')
        .padding({ bottom: 10 })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  /** 播放质量行：读 @State qualityValue，档位改完当场回显 */
  @Builder
  qualityRow() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('默认清晰度')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
          Text('切换后重新载入播放地址；未登录时服务端可能回落到 720P')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .maxLines(2)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text(PlayerPrefs.QUALITY_LABELS[this.indexOfValue(PlayerPrefs.QUALITIES, this.qualityValue)])
          .fontSize(13)
          .fontColor($r('app.color.brand_primary'))
          .maxLines(1)

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(13)
          .fontColor([$r('app.color.text_tertiary')])
          .margin({ left: 4 })
      }
      .width('100%')
      .constraintSize({ minHeight: ROW_HEIGHT })
      .padding({ top: 8, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .bindMenu(this.optionMenu('quality', PlayerPrefs.QUALITY_LABELS, this.menuIndex('quality')), {
        placement: Placement.BottomRight
      })
    }
    .width('100%')
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  build() {
    Column() {
      this.sectionTitle('基础')
      this.qualityRow()
      this.toggleRow('中断继续播放', '被电话 / 切后台等打断后，回到本页自动从原进度接着放',
        'continuePlay', this.prefs.continuePlay)
      this.toggleRow('迷你进度条', '无操作时隐藏播放区界面，只在视频最低边留一条进度条',
        'miniProgress', this.prefs.miniProgress)
      this.toggleRow('快捷手势', '双击 / 滑动 / 长按加速', 'quickGestures', this.prefs.quickGestures)

      this.sectionTitle('播放行为')
      this.menuRow('长按默认倍速', 'longPressSpeed',
        PlayerPrefs.SPEEDS.map((speed: number): string => `${speed.toFixed(2)}x`),
        '长按画面任意位置生效，松手恢复')
      this.menuRow('视频播放模式', 'playMode', PlayerPrefs.PLAY_MODE_LABELS, '播完后的行为')
      this.menuRow('偏好设置', 'preference',
        ['分享视频', '减推视频', '举报视频', '进小黑屋'], '互动接口待接入')

      this.sectionTitle('弹幕设置')
      this.toggleRow('显示弹幕', '关闭后不再拉取与绘制弹幕，只播放画面', 'danmakuOn', this.prefs.danmakuOn)
      this.filterRow('视频弹幕过滤', '命中关键词的弹幕不会显示')
      this.menuRow('显示区域', 'danmakuArea', PlayerPrefs.RATIO_LABELS,
        '弹幕占画面高度的比例，越小越不挡画面')
      this.menuRow('不透明度', 'danmakuOpacity', PlayerPrefs.RATIO_LABELS,
        '调低后弹幕变淡，画面更清楚')
      this.menuRow('弹幕字号', 'danmakuSize', PlayerPrefs.SIZE_LABELS, '同时影响同屏轨道数量')
      this.menuRow('滚动速度', 'danmakuSpeed', PlayerPrefs.SPEED_LABELS, '调快后同一时间屏幕上的弹幕更少')

      Row().height(16)
    }
    .width('100%')
  }
}
