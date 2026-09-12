import { common, Want } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { HdsNavigation } from '@kit.UIDesignKit';
import window from '@ohos.window';
import { SettingsViewModel } from '../components/settings/SettingsViewModel';
import { SettingsItem } from '../components/settings/ListItemView';
import { ListItemView } from '../components/settings/ListItemView';
import { ToggleItemView } from '../components/settings/ToggleItemView';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';

@Entry
@Component
struct Settings {
  @State currentPage: string = 'home';
  @State selectedId: string = '';
  @State topInset: number = 0;
  @State bottomInset: number = 8;
  @State filterEditorVisible: boolean = false;
  @State filterEditorKind: string = 'video';
  @State filterEditorText: string = '';
  @State infoDialogVisible: boolean = false;
  @State infoDialogTitle: string = '';
  @State infoDialogMessage: string = '';
  @State qualityOptions: string[] = ['自动', '清晰360P', '标清480P', '准高清720P', '高清1080P'];
  @State qualityValues: number[] = [0, 16, 32, 64, 80];
  @State qualityIndex: number = 0;
  // viewModel 非观察对象：悬浮窗子项展开依赖本地镜像
  @State pipMasterUi: boolean = false;

  private viewModel: SettingsViewModel = new SettingsViewModel();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private pageStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    this.viewModel.setContext(this.context);
    this.updateSystemInsets();
    this.viewModel.loadAllSettings().then((): void => {
      this.qualityIndex = this.qualityValues.indexOf(this.viewModel.defaultQuality);
      this.pipMasterUi = this.viewModel.pipMasterEnabled;
    });
  }

  private async updateSystemInsets(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navigationArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.topInset = px2vp(systemArea.topRect.height);
      this.bottomInset = px2vp(navigationArea.bottomRect.height);
      mainWindow.on('avoidAreaChange', (data): void => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          this.topInset = px2vp(data.area.topRect.height);
        } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          this.bottomInset = px2vp(data.area.bottomRect.height);
        }
      });
      await mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        isStatusBarLightIcon: true,
        isNavigationBarLightIcon: false
      });
    } catch (error) {
      console.error('Pilihos settings system area failed: ' + String(error));
    }
  }

  private showInfo(title: string, message: string): void {
    this.infoDialogTitle = title;
    this.infoDialogMessage = message;
    this.infoDialogVisible = true;
  }

  private openUrl(url: string): void {
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url
      };
      this.context.startAbility(want).catch((): void => {
        promptAction.showToast({ message: '无法打开链接' });
      });
    } catch (error) {
      console.error('Pilihos external link failed: ' + String(error));
      promptAction.showToast({ message: '无法打开链接' });
    }
  }

  private openFilterEditor(kind: string): void {
    this.filterEditorKind = kind;
    this.filterEditorText = this.viewModel.getFilterWords(kind);
    this.filterEditorVisible = true;
  }

  private async saveFilterEditor(): Promise<void> {
    await this.viewModel.saveFilterWords(this.filterEditorKind, this.filterEditorText);
    this.filterEditorVisible = false;
  }

  private async cycleDefaultQuality(): Promise<void> {
    const nextIndex: number = (this.qualityIndex + 1) % this.qualityValues.length;
    this.qualityIndex = nextIndex;
    this.viewModel.defaultQuality = this.qualityValues[nextIndex];
    await this.viewModel.savePlayerSetting('default_quality', this.qualityValues[nextIndex]);
  }

  onBackPress(): boolean {
    if (this.infoDialogVisible) {
      this.infoDialogVisible = false;
      return true;
    }
    if (this.filterEditorVisible) {
      this.filterEditorVisible = false;
      return true;
    }
    if (this.currentPage !== 'home') {
      this.currentPage = 'home';
      return true;
    }
    return false;
  }

  build() {
    Column() {
      // 子页为状态驱动（currentPage），不再包 HdsNavigation——其自带导航层会吞掉自定义返回按钮的点击
      this.settingsSurface()
    }
    .width('100%').height('100%');
  }

  @Builder
  settingsSurface() {
    Stack() {
      Column() {
      // 页面头部（考虑状态栏高度）
      Row() {
        if (this.currentPage !== 'home') {
          Button() {
            Image($r('app.media.fanhui_left')).width(24).height(24);
          }
          .type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
          .backgroundColor(Color.Transparent)
          .onClick(() => { this.currentPage = 'home'; });
        }
        Text(this.getPageTitle())
          .fontSize(20).fontWeight(FontWeight.Bold)
          .layoutWeight(1);
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .margin({ top: this.topInset })
      .alignItems(VerticalAlign.Center)

      // 内容区域
      if (this.currentPage === 'home') {
        this.homePage()
      } else if (this.currentPage === 'appearance') {
        this.appearancePage()
      } else if (this.currentPage === 'player') {
        this.playerPage()
      } else if (this.currentPage === 'search') {
        this.searchPage()
      } else if (this.currentPage === 'advanced') {
        this.advancedPage()
      } else if (this.currentPage === 'about') {
        this.aboutPage()
      }

      // 底部安全区
      Column().height(this.bottomInset)
    }
    .width('100%').height('100%')
    .backgroundColor('#F1F3F5');

      // 过滤词编辑弹窗
      if (this.filterEditorVisible) {
        this.filterEditorOverlay()
      }
      // 信息弹窗
      if (this.infoDialogVisible) {
        this.infoDialog()
      }
    }
    .width('100%').height('100%')
  }

  private getPageTitle(): string {
    switch (this.currentPage) {
      case 'appearance': return '外观';
      case 'player': return '播放器';
      case 'search': return '搜索';
      case 'advanced': return '系统特性';
      case 'about': return '关于';
      default: return '设置';
    }
  }

  @Builder
  homePage() {
    Scroll() {
      Column({ space: 12 }) {
        // 外观设置卡片
        this.categoryCard('外观', '主题、布局与显示方式', $r('app.media.bc'), 'appearance')
        // 播放器设置卡片
        this.categoryCard('播放器', '播放质量、弹幕与推荐页行为', $r('app.media.qp'), 'player')
        // 搜索设置卡片
        this.categoryCard('搜索', '搜索历史记忆与搜索结果设置', $r('app.media.serch'), 'search')
        // 系统特性卡片
        this.categoryCard('系统特性', 'API 26 专属能力与材质兼容设置', $r('app.media.send'), 'advanced')
        // 关于卡片
        this.categoryCard('关于', '应用信息、版本日志与开源链接', $r('app.media.fanju'), 'about')
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  @Builder
  categoryCard(title: string, subtitle: string, icon: Resource, page: string) {
    Row({ space: 14 }) {
      Image(icon)
        .width(36).height(36)
      Column({ space: 4 }) {
        Text(title).fontSize(17).fontWeight(FontWeight.Medium).fontColor('#E6000000');
        Text(subtitle).fontSize(13).fontColor('#99000000');
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Image($r('app.media.jinxin_right')).width(20).height(20).fillColor('#34000000');
    }
    .width('100%')
    .height(72)
    .padding({ left: 16, right: 16 })
    .backgroundColor('#FFFFFF')
    .backgroundBlurStyle(ImmersiveMaterial.blurStyle())
    .systemMaterial(ImmersiveMaterial.getRegular() ?? undefined)
    .borderRadius(16)
    .onClick(() => { this.currentPage = page; });
  }

  @Builder
  appearancePage() {
    Scroll() {
      Column({ space: 12 }) {
        Text('外观').fontSize(14).fontColor('#99000000').width('100%').padding({ left: 4 })
        Column() {
          ToggleItemView({
            title: '底部常驻',
            subtitle: '关闭后，HDS 底部栏会随列表滑动自动隐藏',
            isEnabled: this.viewModel.bottomBarPinned,
            onToggle: (value: boolean) => {
              this.viewModel.bottomBarPinned = value;
              this.viewModel.saveAppearanceSetting('bottom_bar_pinned', value);
            }
          })
          Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
          ToggleItemView({
            title: '竖屏提示',
            subtitle: '视频卡片在播放量/弹幕量后展示竖屏标记',
            isEnabled: this.viewModel.portraitBadgeEnabled,
            onToggle: (value: boolean) => {
              this.viewModel.portraitBadgeEnabled = value;
              this.viewModel.saveAppearanceSetting('portrait_badge', value);
            }
          })
          Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
          ToggleItemView({
            title: '自动横屏',
            subtitle: '开启后不受系统控制即可自动横屏',
            isEnabled: this.viewModel.autoRotateEnabled,
            onToggle: (value: boolean) => {
              this.viewModel.autoRotateEnabled = value;
              this.viewModel.saveAppearanceSetting('auto_rotate_enabled', value);
            }
          })
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle())
        .systemMaterial(ImmersiveMaterial.getRegular() ?? undefined)
        .borderRadius(16)
        .padding(4)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  @Builder
  playerPage() {
    Scroll() {
      Column({ space: 12 }) {
        // 播放质量
        Text('播放质量').fontSize(14).fontColor('#99000000').width('100%').padding({ left: 4 })
        Column() {
          ListItemView({
            itemId: 'quality',
            title: '默认清晰度',
            value: this.qualityOptions[this.qualityIndex],
            isSelected: false,
            hasChevron: true,
            onItemClick: () => { this.cycleDefaultQuality(); }
          })
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle())
        .systemMaterial(ImmersiveMaterial.getRegular() ?? undefined)
        .borderRadius(16)
        .padding(4)

        // 播放行为：打断接续（生效）+ 后台悬浮窗（占位，功能暂未实现）
        Text('播放行为').fontSize(14).fontColor('#99000000').width('100%').padding({ left: 4 })
        Column() {
          ToggleItemView({
            title: '打断接续',
            subtitle: '视频因为切换软件或被其他因素打断播放，重新回到软件时继续播放',
            isEnabled: this.viewModel.interruptResumeEnabled,
            onToggle: (value: boolean) => {
              this.viewModel.interruptResumeEnabled = value;
              this.viewModel.savePlayerBehaviorSetting('interrupt_resume', value);
            }
          })
          Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
          ToggleItemView({
            title: '无UI进度条显示',
            subtitle: '开启后，任意视频播放区UI隐藏时，底部只显示进度条',
            isEnabled: this.viewModel.miniProgressEnabled,
            onToggle: (value: boolean) => {
              this.viewModel.miniProgressEnabled = value;
              this.viewModel.savePlayerBehaviorSetting('mini_progress_on', value);
            }
          })
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle())
        .systemMaterial(ImmersiveMaterial.getRegular() ?? undefined)
        .borderRadius(16)
        .padding(4)

        Text('后台悬浮窗').fontSize(14).fontColor('#99000000').width('100%').padding({ left: 4 })
        Column() {
          ToggleItemView({
            title: '后台悬浮窗',
            subtitle: '此为总开关，开启后设置悬浮窗子功能',
            isEnabled: this.viewModel.pipMasterEnabled,
            onToggle: (value: boolean) => {
              this.viewModel.pipMasterEnabled = value;
              this.pipMasterUi = value;
              this.viewModel.savePlayerBehaviorSetting('pip_master', value);
            }
          })
          if (this.pipMasterUi) {
            Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
            ToggleItemView({
              title: '手动悬浮窗',
              subtitle: '在任意视频播放区右上角显示手动悬浮窗按钮，点击视频区后台悬浮',
              isEnabled: this.viewModel.pipManualEnabled,
              onToggle: (value: boolean) => {
                this.viewModel.pipManualEnabled = value;
                this.viewModel.savePlayerBehaviorSetting('pip_manual', value);
              }
            })
            Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
            ToggleItemView({
              title: '自动悬浮窗',
              subtitle: '进入任意视频播放页退出上一级页面视频自动后台悬浮',
              isEnabled: this.viewModel.pipAutoEnabled,
              onToggle: (value: boolean) => {
                this.viewModel.pipAutoEnabled = value;
                this.viewModel.savePlayerBehaviorSetting('pip_auto', value);
              }
            })
          }
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle())
        .systemMaterial(ImmersiveMaterial.getRegular() ?? undefined)
        .borderRadius(16)
        .padding(4)

        // 过滤词设置
        Text('过滤词').fontSize(14).fontColor('#99000000').width('100%').padding({ left: 4 })
        Column() {
          this.filterCard('视频过滤词', this.viewModel.videoFilterSummary, 'video')
          Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
          this.filterCard('弹幕过滤词', this.viewModel.danmakuFilterSummary, 'danmaku')
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle())
        .systemMaterial(ImmersiveMaterial.getRegular() ?? undefined)
        .borderRadius(16)
        .padding(4)

        Text('视频快捷操作').fontSize(14).fontColor('#99000000').width('100%').padding({ left: 4 })
        Column() {
          ToggleItemView({
            title: '视频快捷操作',
            subtitle: '开启后即可长按对视频进行快捷操作',
            isEnabled: this.viewModel.videoQuickActionsEnabled,
            onToggle: (value: boolean) => {
              this.viewModel.videoQuickActionsEnabled = value;
              this.viewModel.savePlayerSetting('video_quick_actions', value);
            }
          })
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle())
        .systemMaterial(ImmersiveMaterial.getRegular() ?? undefined)
        .borderRadius(16)
        .padding(4)

        // 推荐设置
        Text('推荐').fontSize(14).fontColor('#99000000').width('100%').padding({ left: 4 })
        Column() {
          ToggleItemView({
            title: '推荐页刷新保留',
            subtitle: '下拉刷新将保留刷新前的内容',
            isEnabled: this.viewModel.keepRefreshContent,
            onToggle: (value: boolean) => {
              this.viewModel.keepRefreshContent = value;
              this.viewModel.savePlayerSetting('keep_refresh_content', value);
            }
          })
          Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
          ToggleItemView({
            title: '自动展开简介区',
            subtitle: '开启后将自动展开视频简介区',
            isEnabled: this.viewModel.autoExpandDescription,
            onToggle: (value: boolean) => {
              this.viewModel.autoExpandDescription = value;
              this.viewModel.savePlayerSetting('auto_expand_description', value);
            }
          })
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle())
        .systemMaterial(ImmersiveMaterial.getRegular() ?? undefined)
        .borderRadius(16)
        .padding(4)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  @Builder
  filterCard(title: string, summary: string, kind: string) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(title).fontSize(16).fontColor('#E6000000');
        Text('[' + summary + ']').fontSize(12).fontColor('#1288FA').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Button() {
        Image($r('app.media.edit')).width(18).height(18).fillColor('#1288FA');
      }
      .type(ButtonType.ROUNDED_RECTANGLE).width(34).height(34)
      .backgroundColor('#1A1288FA').borderRadius(17)
      .onClick(() => { this.openFilterEditor(kind); });
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 14 })
    .onClick(() => { this.openFilterEditor(kind); });
  }

  @Builder
  searchPage() {
    Scroll() {
      Column({ space: 12 }) {
        Text('搜索').fontSize(14).fontColor('#99000000').width('100%').padding({ left: 4 })
        Column() {
          ToggleItemView({
            title: '搜索历史记忆',
            subtitle: '开启后将记忆搜索历史',
            isEnabled: this.viewModel.searchHistoryEnabled,
            onToggle: (value: boolean) => {
              this.viewModel.searchHistoryEnabled = value;
              this.viewModel.saveSearchSetting('history_enabled', value);
            }
          })
          Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
          ToggleItemView({
            title: '搜索联想词',
            subtitle: '开启后键入关键词可触发联想词',
            isEnabled: this.viewModel.searchSuggestEnabled,
            onToggle: (value: boolean) => {
              this.viewModel.searchSuggestEnabled = value;
              this.viewModel.saveSearchSetting('suggest_enabled', value);
            }
          })
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle())
        .systemMaterial(ImmersiveMaterial.getRegular() ?? undefined)
        .borderRadius(16)
        .padding(4)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  @Builder
  advancedPage() {
    Scroll() {
      Column({ space: 12 }) {
        Text('系统特性').fontSize(14).fontColor('#99000000').width('100%').padding({ left: 4 })
        Column() {
          ToggleItemView({
            title: 'API 26 高级能力',
            subtitle: '控制 API 26 专属能力；界面材质会按设备版本自动适配',
            isEnabled: this.viewModel.advancedMasterEnabled,
            onToggle: (value: boolean) => {
              this.viewModel.advancedMasterEnabled = value;
              this.viewModel.saveAdvancedSetting('master', value);
            }
          })
          if (this.viewModel.isApi26Supported()) {
            Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
            ToggleItemView({
              title: '增强播放器',
              subtitle: '支持自定义 HTTP 头部，提升视频加载兼容性',
              isEnabled: this.viewModel.advancedPlayerEnabled,
              onToggle: (value: boolean) => {
                this.viewModel.advancedPlayerEnabled = value;
                this.viewModel.saveAdvancedSetting('player', value);
              }
            })
            Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
            ToggleItemView({
              title: 'HUKS 会话式加密',
              subtitle: '使用新版密钥库会话 API，提升安全性',
              isEnabled: this.viewModel.advancedHuksEnabled,
              onToggle: (value: boolean) => {
                this.viewModel.advancedHuksEnabled = value;
                this.viewModel.saveAdvancedSetting('huks', value);
              }
            })
            Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
            ToggleItemView({
              title: 'WebView Cookie 管理',
              subtitle: '使用新版 Cookie 管理器获取登录凭证',
              isEnabled: this.viewModel.advancedWebCookieEnabled,
              onToggle: (value: boolean) => {
                this.viewModel.advancedWebCookieEnabled = value;
                this.viewModel.saveAdvancedSetting('webCookie', value);
              }
            })
            Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
            ToggleItemView({
              title: '沉浸光感',
              subtitle: '开启后界面元素使用毛玻璃模糊材质效果',
              isEnabled: this.viewModel.advancedImmersiveEnabled,
              onToggle: (value: boolean) => {
                this.viewModel.advancedImmersiveEnabled = value;
                this.viewModel.saveAdvancedSetting('immersive', value);
              }
            })
          }
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle())
        .systemMaterial(ImmersiveMaterial.getRegular() ?? undefined)
        .borderRadius(16)
        .padding(4)

        if (!this.viewModel.isApi26Supported()) {
          Row() {
            Text('当前设备 API 版本为 ' + this.viewModel.getDeviceApiLevel() +
              '，不支持 API 26 高级功能。')
              .fontSize(13).fontColor('#99000000').layoutWeight(1);
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  @Builder
  aboutPage() {
    Scroll() {
      Column({ space: 12 }) {
        // 应用信息
        Column({ space: 8 }) {
          Image($r('app.media.app_logo')).width(80).height(80).borderRadius(16);
          Text('Pilihos').fontSize(22).fontWeight(FontWeight.Bold);
          Text('Version 1.0.8.0').fontSize(14).fontColor('#99000000');
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: 20, bottom: 16 })

        // 关于信息
        Text('关于').fontSize(14).fontColor('#99000000').width('100%').padding({ left: 4 })
        Column() {
          ListItemView({
            itemId: 'about_app',
            title: '软件说明',
            value: 'Pilihos',
            isSelected: false,
            hasChevron: true,
            onItemClick: () => { this.showInfo('软件说明', 'Pilihos 是B站鸿蒙移植版，开源无广，纯净高效。'); }
          })
          Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
          ListItemView({
            itemId: 'about_privacy',
            title: '隐私政策',
            value: '',
            isSelected: false,
            hasChevron: true,
            onItemClick: () => { this.showInfo('隐私政策', '应用仅在登录和请求服务时使用必要数据。'); }
          })
          Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
          ListItemView({
            itemId: 'about_license',
            title: '软件协议',
            value: 'MIT',
            isSelected: false,
            hasChevron: true,
            onItemClick: () => { this.showInfo('软件协议', '本软件采用 MIT 开源协议'); }
          })
          Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
          ListItemView({
            itemId: 'about_changelog',
            title: '版本日志',
            value: 'v1.0.8.0',
            isSelected: false,
            hasChevron: true,
            onItemClick: () => {
              this.showInfo('版本日志',
                'v1.0.8.0' +
                  '\n底栏材质回退浅色毛玻璃' +
                  '\n竖屏化视频真居中+面板联动' +
                  '\n面板关注改简介区同款气泡' +
                  '\n竖屏底栏/互动回显修复' +
                  '\n完整更新日志请访问 Pilihos Wiki-https://github.com/qitinyu/Pilihos/wiki/');
            }
          })
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle())
        .systemMaterial(ImmersiveMaterial.getRegular() ?? undefined)
        .borderRadius(16)
        .padding(4)

        // 链接
        Text('链接').fontSize(14).fontColor('#99000000').width('100%').padding({ left: 4 })
        Column() {
          ListItemView({
            itemId: 'about_feedback',
            title: '用户反馈',
            value: '',
            isSelected: false,
            hasChevron: true,
            onItemClick: () => { this.openUrl('https://github.com/qitinyu/Pilihos/discussions/'); }
          })
          Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
          ListItemView({
            itemId: 'about_github',
            title: '开源链接',
            value: '',
            isSelected: false,
            hasChevron: true,
            onItemClick: () => { this.openUrl('https://github.com/qitinyu/Pilihos'); }
          })
          Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
          ListItemView({
            itemId: 'about_release',
            title: '软件更新',
            value: '',
            isSelected: false,
            hasChevron: true,
            onItemClick: () => { this.openUrl('https://github.com/qitinyu/Pilihos/releases'); }
          })
          Divider().strokeWidth(0.5).color('#1A000000').margin({ left: 52, right: 8 })
          ListItemView({
            itemId: 'about_upstream',
            title: '上游仓库',
            value: '',
            isSelected: false,
            hasChevron: true,
            onItemClick: () => { this.openUrl('https://github.com/dev4harmony/PiliPlus'); }
          })
        }
        .width('100%')
        .backgroundColor('#FFFFFF')
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle())
        .systemMaterial(ImmersiveMaterial.getRegular() ?? undefined)
        .borderRadius(16)
        .padding(4)

        Text('\u00A92026 pilihos by YuQi')
          .fontSize(12)
          .fontColor('#99000000')
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 16 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  @Builder
  filterEditorOverlay() {
    if (this.filterEditorVisible) {
      Stack() {
        Column().width('100%').height('100%').backgroundColor('#66000000')
          .onClick(() => { this.filterEditorVisible = false; });
        Column({ space: 12 }) {
          Text(this.filterEditorKind === 'video' ? '视频过滤词' : '弹幕过滤词')
            .fontSize(17).fontWeight(FontWeight.Bold).fontColor('#E6000000').width('100%');
          Text('键入关键词和分隔符并保存，示例样式为：xx|xx，可以一行多个。')
            .fontSize(12).fontColor('#99000000').width('100%');
          TextArea({ text: this.filterEditorText, placeholder: '示例：xx|xx' })
            .width('100%').height(150)
            .backgroundColor('#F1F3F5').borderRadius(8)
            .padding(10)
            .defaultFocus(true)
            .onChange((value: string) => { this.filterEditorText = value; });
          Row({ space: 10 }) {
            Button('取消')
              .layoutWeight(1).height(40)
              .backgroundColor('#F1F3F5').fontColor('#59616B')
              .onClick(() => { this.filterEditorVisible = false; });
            Button('保存')
              .layoutWeight(1).height(40)
              .backgroundColor('#1288FA').fontColor(Color.White)
              .onClick((): void => { this.saveFilterEditor(); });
          }.width('100%');
        }
        .width('88%')
        .padding(16)
        .backgroundColor(Color.White)
        .borderRadius(14)
        .shadow({ radius: 16, color: '#33000000', offsetX: 0, offsetY: 4 })
      }
      .width('100%').height('100%')
      .alignContent(Alignment.Center);
    }
  }

  @Builder
  infoDialog() {
    Stack() {
      Column()
        .width('100%').height('100%')
        .backgroundColor('#66000000')
        .onClick(() => { this.infoDialogVisible = false; });
      Column({ space: 14 }) {
        Text(this.infoDialogTitle).fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor('#E6000000').width('100%');
        Scroll() {
          Text(this.infoDialogMessage)
            .fontSize(15).fontColor('#3E4854')
            .lineHeight(24)
            .textAlign(TextAlign.Start)
            .width('100%');
        }
        .width('100%').height(260).scrollBar(BarState.Auto);
        Button('知道了')
          .width('100%').height(42)
          .fontColor('#1288FA').backgroundColor('#E9F4F8')
          .onClick(() => { this.infoDialogVisible = false; });
      }
      .width('86%').padding(20)
      .backgroundColor(Color.White).borderRadius(12)
      .shadow({ radius: 18, color: '#40000000', offsetX: 0, offsetY: 6 });
    }
    .width('100%').height('100%')
    .alignContent(Alignment.Center);
  }
}
