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
 * 弹幕设置（总开关 / 显示区域 / 不透明度 / 字号 / 滚动速度，改动由播放页即时应用）。
 */
@Component
export struct PlayerSettingsPanel {
  @Link prefs: PlayerPrefs;
  onChanged: (key: string, value: number | boolean) => void = () => {
  };
  /** 偏好设置里「分享视频」调起系统分享（由播放页注入，面板本身不持有视频信息） */
  onShare: () => void = () => {
  };

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
        this.commitNumber('quality', this.prefs.quality);
        break;
      case 'longPressSpeed':
        this.prefs.longPressSpeed = PlayerPrefs.SPEEDS[index];
        this.commitNumber('longPressSpeed', this.prefs.longPressSpeed);
        break;
      case 'playMode':
        this.prefs.playMode = index;
        this.commitNumber('playMode', index);
        break;
      case 'danmakuArea':
        this.prefs.danmakuArea = PlayerPrefs.DANMAKU_RATIOS[index];
        this.commitNumber('danmakuArea', this.prefs.danmakuArea);
        break;
      case 'danmakuOpacity':
        this.prefs.danmakuOpacity = PlayerPrefs.DANMAKU_RATIOS[index];
        this.commitNumber('danmakuOpacity', this.prefs.danmakuOpacity);
        break;
      case 'danmakuSize':
        this.prefs.danmakuSize = PlayerPrefs.DANMAKU_SIZES[index];
        this.commitNumber('danmakuSize', this.prefs.danmakuSize);
        break;
      case 'danmakuSpeed':
        this.prefs.danmakuSpeed = PlayerPrefs.DANMAKU_SPEEDS[index];
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
  menuRow(title: string, key: string, currentLabel: string, options: Array<string>, hint: string) {
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

        Text(currentLabel)
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
      .bindMenu(this.optionMenu(key, options, currentLabel), {
        placement: Placement.BottomRight
      })
    }
    .width('100%')
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  build() {
    Column() {
      this.sectionTitle('基础')
      this.menuRow('默认清晰度', 'quality',
        PlayerPrefs.QUALITY_LABELS[this.indexOfValue(PlayerPrefs.QUALITIES, this.prefs.quality)],
        PlayerPrefs.QUALITY_LABELS, '切换后重新载入播放地址')
      this.toggleRow('中断继续播放', '被电话 / 切后台等打断后，回到本页自动从原进度接着放',
        'continuePlay', this.prefs.continuePlay)
      this.toggleRow('迷你进度条', '无操作时隐藏播放区界面，只在视频最低边留一条进度条',
        'miniProgress', this.prefs.miniProgress)
      this.toggleRow('快捷手势', '双击 / 滑动 / 长按加速', 'quickGestures', this.prefs.quickGestures)

      this.sectionTitle('播放行为')
      this.menuRow('长按默认倍速', 'longPressSpeed',
        `${PlayerPrefs.SPEEDS[this.indexOfValue(PlayerPrefs.SPEEDS, this.prefs.longPressSpeed)].toFixed(2)}x`,
        PlayerPrefs.SPEEDS.map((speed: number): string => `${speed.toFixed(2)}x`),
        '长按画面任意位置生效，松手恢复')
      this.menuRow('视频播放模式', 'playMode',
        PlayerPrefs.PLAY_MODE_LABELS[this.prefs.playMode],
        PlayerPrefs.PLAY_MODE_LABELS, '播完后的行为')
      this.menuRow('偏好设置', 'preference', '更多操作',
        ['分享视频', '减推视频', '举报视频', '进小黑屋'], '互动接口待接入')

      this.sectionTitle('弹幕设置')
      this.toggleRow('显示弹幕', '关闭后不再拉取与绘制弹幕，只播放画面', 'danmakuOn', this.prefs.danmakuOn)
      this.menuRow('显示区域', 'danmakuArea',
        PlayerPrefs.RATIO_LABELS[this.indexOfValue(PlayerPrefs.DANMAKU_RATIOS, this.prefs.danmakuArea)],
        PlayerPrefs.RATIO_LABELS, '弹幕占画面高度的比例，越小越不挡画面')
      this.menuRow('不透明度', 'danmakuOpacity',
        PlayerPrefs.RATIO_LABELS[this.indexOfValue(PlayerPrefs.DANMAKU_RATIOS, this.prefs.danmakuOpacity)],
        PlayerPrefs.RATIO_LABELS, '调低后弹幕变淡，画面更清楚')
      this.menuRow('弹幕字号', 'danmakuSize',
        PlayerPrefs.SIZE_LABELS[this.indexOfValue(PlayerPrefs.DANMAKU_SIZES, this.prefs.danmakuSize)],
        PlayerPrefs.SIZE_LABELS, '同时影响同屏轨道数量')
      this.menuRow('滚动速度', 'danmakuSpeed',
        PlayerPrefs.SPEED_LABELS[this.indexOfValue(PlayerPrefs.DANMAKU_SPEEDS, this.prefs.danmakuSpeed)],
        PlayerPrefs.SPEED_LABELS, '调快后同一时间屏幕上的弹幕更少')

      Row().height(16)
    }
    .width('100%')
  }
}
