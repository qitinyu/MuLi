import router from '@ohos.router';
import { common, Want } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';
import window from '@ohos.window';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import { AdvancedFeatures } from '../utils/AdvancedFeatures';
import { FilterWords } from '../utils/FilterWords';
import { PlaybackService } from '../services/PlaybackService';

@Entry
@Component
struct Settings {
  @State showAbout: boolean = false;
  @State childPage: string = '';
  @State keepRefreshContent: boolean = false;
  @State defaultQuality: number = 0;
  @State floatBallSwapped: boolean = false;
  @State topTabsMerged: boolean = false;
  @State searchHistoryEnabled: boolean = false;
  @State infoDialogVisible: boolean = false;
  @State infoDialogTitle: string = '';
  @State infoDialogMessage: string = '';
  @State topInset: number = 0;
  @State bottomInset: number = 8;

  // 高级功能开关状态
  @State advancedMasterEnabled: boolean = false;
  @State advancedImmersiveEnabled: boolean = true;
  @State advancedPlayerEnabled: boolean = true;
  @State advancedHuksEnabled: boolean = true;
  @State advancedWebCookieEnabled: boolean = true;
  @State advancedSegmentEnabled: boolean = true;
  @State bottomBarPinned: boolean = true;
  @State portraitBadgeEnabled: boolean = true;
  @State filterEditorVisible: boolean = false;
  @State filterEditorKind: string = 'video';
  @State filterEditorText: string = '';
  @State videoFilterSummary: string = '';
  @State danmakuFilterSummary: string = '';

  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.updateSystemInsets();
    this.loadPlayerSettings();
    this.loadAppearanceSettings();
    this.loadSearchSettings();
    this.loadAdvancedSettings();
    this.loadFilterSummaries();
  }

  private async loadFilterSummaries(): Promise<void> {
    await FilterWords.load(this.context);
    this.refreshFilterSummaries();
  }

  private refreshFilterSummaries(): void {
    const videoWords: string[] = FilterWords.getWords('video');
    const danmakuWords: string[] = FilterWords.getWords('danmaku');
    this.videoFilterSummary = videoWords.length > 0
      ? videoWords.join('|') : '未设置';
    this.danmakuFilterSummary = danmakuWords.length > 0
      ? danmakuWords.join('|') : '未设置';
  }

  private openFilterEditor(kind: string): void {
    this.filterEditorKind = kind;
    this.filterEditorText = FilterWords.getWords(kind).join('|');
    this.filterEditorVisible = true;
  }

  private async saveFilterEditor(): Promise<void> {
    await FilterWords.save(this.context, this.filterEditorKind, this.filterEditorText);
    this.refreshFilterSummaries();
    this.filterEditorVisible = false;
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
        statusBarColor: '#F7F8FA',
        navigationBarColor: '#00000000',
        isStatusBarLightIcon: true,
        isNavigationBarLightIcon: false
      });
    } catch (error) {
      console.error('Pilihos settings system area failed: ' + String(error));
    }
  }

  private async loadAppearanceSettings(): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_ui');
      this.floatBallSwapped = store.getSync('float_ball_swapped', false) as boolean;
      this.topTabsMerged = store.getSync('top_tabs_merged', false) as boolean;
      this.bottomBarPinned = store.getSync('bottom_bar_pinned', true) as boolean;
      this.portraitBadgeEnabled = store.getSync('portrait_badge', true) as boolean;
    } catch (error) {
      console.error('Pilihos appearance settings load failed: ' + String(error));
    }
  }

  private async setBottomBarPinned(value: boolean): Promise<void> {
    this.bottomBarPinned = value;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_ui');
      store.putSync('bottom_bar_pinned', value);
      store.flushSync();
    } catch (error) {
      console.error('Pilihos appearance settings save failed: ' + String(error));
    }
  }

  private async setPortraitBadge(value: boolean): Promise<void> {
    this.portraitBadgeEnabled = value;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_ui');
      store.putSync('portrait_badge', value);
      store.flushSync();
    } catch (error) {
      console.error('Pilihos appearance settings save failed: ' + String(error));
    }
  }

  private async setFloatBallSwapped(value: boolean): Promise<void> {
    this.floatBallSwapped = value;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_ui');
      store.putSync('float_ball_swapped', value);
      store.flushSync();
    } catch (error) {
      console.error('Pilihos appearance settings save failed: ' + String(error));
    }
  }

  private async setTopTabsMerged(value: boolean): Promise<void> {
    this.topTabsMerged = value;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_ui');
      store.putSync('top_tabs_merged', value);
      store.flushSync();
    } catch (error) {
      console.error('Pilihos top tabs setting save failed: ' + String(error));
    }
  }

  private async loadAdvancedSettings(): Promise<void> {
    await AdvancedFeatures.loadSettings(this.context);
    this.advancedMasterEnabled = AdvancedFeatures.isMasterEnabled();
    this.advancedImmersiveEnabled = AdvancedFeatures.isImmersiveMaterialEnabled();
    this.advancedPlayerEnabled = AdvancedFeatures.isEnhancedPlayerEnabled();
    this.advancedHuksEnabled = AdvancedFeatures.isHuksSessionEnabled();
    this.advancedWebCookieEnabled = AdvancedFeatures.isWebCookieManagerEnabled();
    this.advancedSegmentEnabled = AdvancedFeatures.isSegmentButtonEnabled();
  }

  private async setAdvancedMaster(enabled: boolean): Promise<void> {
    this.advancedMasterEnabled = enabled;
    AdvancedFeatures.setMasterEnabled(enabled);
    await AdvancedFeatures.saveSettings(this.context);
  }

  private async setAdvancedImmersive(enabled: boolean): Promise<void> {
    this.advancedImmersiveEnabled = enabled;
    AdvancedFeatures.setImmersiveMaterialEnabled(enabled);
    await AdvancedFeatures.saveSettings(this.context);
  }

  private async setAdvancedPlayer(enabled: boolean): Promise<void> {
    this.advancedPlayerEnabled = enabled;
    AdvancedFeatures.setEnhancedPlayerEnabled(enabled);
    await AdvancedFeatures.saveSettings(this.context);
  }

  private async setAdvancedHuks(enabled: boolean): Promise<void> {
    this.advancedHuksEnabled = enabled;
    AdvancedFeatures.setHuksSessionEnabled(enabled);
    await AdvancedFeatures.saveSettings(this.context);
  }

  private async setAdvancedWebCookie(enabled: boolean): Promise<void> {
    this.advancedWebCookieEnabled = enabled;
    AdvancedFeatures.setWebCookieManagerEnabled(enabled);
    await AdvancedFeatures.saveSettings(this.context);
  }

  private async setAdvancedSegment(enabled: boolean): Promise<void> {
    this.advancedSegmentEnabled = enabled;
    AdvancedFeatures.setSegmentButtonEnabled(enabled);
    await AdvancedFeatures.saveSettings(this.context);
  }

  private async loadPlayerSettings(): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_player');
      this.keepRefreshContent = store.getSync('keep_refresh_content', false) as boolean;
      this.defaultQuality = store.getSync('default_quality', 0) as number;
    } catch (error) {
      console.error('Pilihos player settings load failed: ' + String(error));
    }
  }

  private qualityLabel(value: number): string {
    if (value === 0) return '自动';
    return PlaybackService.qualityLabel(value);
  }

  private async cycleDefaultQuality(): Promise<void> {
    const options: number[] = [0, 80, 64, 32, 16];
    const index: number = options.indexOf(this.defaultQuality);
    const next: number = options[(index + 1) % options.length];
    this.defaultQuality = next;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_player');
      store.putSync('default_quality', next);
      store.flushSync();
    } catch (error) {
      console.error('Pilihos player quality save failed: ' + String(error));
    }
  }

  private async setKeepRefreshContent(value: boolean): Promise<void> {
    this.keepRefreshContent = value;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_player');
      store.putSync('keep_refresh_content', value);
      store.flushSync();
    } catch (error) {
      console.error('Pilihos player settings save failed: ' + String(error));
    }
  }

  private async loadSearchSettings(): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_search');
      this.searchHistoryEnabled = store.getSync('history_enabled', false) as boolean;
    } catch (error) {
      console.error('Pilihos search settings load failed: ' + String(error));
    }
  }

  private async setSearchHistoryEnabled(value: boolean): Promise<void> {
    this.searchHistoryEnabled = value;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_search');
      store.putSync('history_enabled', value);
      store.flushSync();
    } catch (error) {
      console.error('Pilihos search settings save failed: ' + String(error));
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

  private goBack(): void {
    if (this.infoDialogVisible) {
      this.infoDialogVisible = false;
      return;
    }
    if (this.showAbout) {
      this.showAbout = false;
      return;
    }
    if (this.childPage !== '') {
      this.childPage = '';
      return;
    }
    router.back();
  }

  onBackPress(): boolean {
    if (this.infoDialogVisible) {
      this.infoDialogVisible = false;
      return true;
    }
    if (this.showAbout) {
      this.showAbout = false;
      return true;
    }
    if (this.childPage !== '') {
      this.childPage = '';
      return true;
    }
    return false;
  }

  build() {
    Stack() {
      if (this.showAbout) {
        this.aboutPage();
      } else if (this.childPage === 'player') {
        this.playerPage();
      } else if (this.childPage === 'appearance') {
        this.appearancePage();
      } else if (this.childPage === 'advanced') {
        this.advancedPage();
      } else if (this.childPage === 'search') {
        this.searchPage();
      } else {
        this.settingsPage();
      }
      if (this.infoDialogVisible) {
        this.infoDialog();
      }
      this.filterEditorOverlay();
    }
    .alignContent(Alignment.TopStart)
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
          .fontColor('#1E252D').width('100%');
        Scroll() {
          Text(this.infoDialogMessage)
            .fontSize(15).fontColor('#3E4854')
            .lineHeight(24)
            .textAlign(TextAlign.Start)
            .width('100%')
            .textOverflow({ overflow: TextOverflow.Clip });
        }
        .width('100%').height(260).scrollBar(BarState.Auto);
        Button('知道了')
          .width('100%').height(42)
          .fontColor('#1677A8').backgroundColor('#E9F4F8')
          .onClick(() => { this.infoDialogVisible = false; });
      }
      .width('86%').padding(20)
      .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(12)
      .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
      .shadow({ radius: 18, color: '#40000000', offsetX: 0, offsetY: 6 });
    }
    .width('100%').height('100%')
    .alignContent(Alignment.Center);
  }

  @Builder
  pageHeader(title: string) {
    Row({ space: 10 }) {
      Button() {
        Image($r('app.media.fanhui_left')).width(24).height(24);
      }
      .type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
      .backgroundColor(Color.Transparent)
      .onClick(() => { this.goBack(); });
      Text(title).fontSize(22).fontWeight(FontWeight.Medium).layoutWeight(1);
    }
    .width('100%')
    .padding({ left: 12, right: 18, top: this.topInset + 24, bottom: 12 });
  }

  @Builder
  settingsPage() {
    Column() {
      this.pageHeader('设置');
      Scroll() {
        Column({ space: 10 }) {
          this.settingsCategoryCard('外观', '主题、布局与显示方式', 'appearance');
          this.settingsCategoryCard('播放器', '播放质量、弹幕与推荐页行为', 'player');
          this.settingsCategoryCard('搜索', '搜索历史记忆与搜索结果设置', 'search');
          this.settingsCategoryCard('系统特性', 'API 26 专属能力与材质兼容设置', 'advanced');
          this.settingsCategoryCard('关于', '应用信息、版本日志与开源链接', 'about');
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 6, bottom: this.bottomInset + 18 })
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start);
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart);
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#F7F8FA')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  @Builder
  settingsCategoryCard(title: string, detail: string, page: string) {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(title).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#1E252D');
        Text(detail).fontSize(13).fontColor('#858C94');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Image($r('app.media.jinxin_right')).width(20).height(20);
    }
    .width('100%').height(86)
    .padding({ left: 18, right: 16 })
      .backgroundColor(Color.White).borderRadius(10)
      .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
    .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 })
    .onClick(() => {
      if (page === 'about') this.showAbout = true;
      else this.childPage = page;
    });
  }

  @Builder
  appearancePage() {
    Column() {
      this.pageHeader('外观');
      Scroll() {
        Column({ space: 10 }) {
          this.settingsCard('主题', '跟随系统', false);
          Row({ space: 12 }) {
            Column({ space: 5 }) {
              Text('首页布局 - 底部常驻').fontSize(16).fontColor('#1E252D');
              Text('关闭后，底部栏会间歇性隐藏：向下滚动屏幕时自动隐藏，向上滚动或停止操作时自动弹出')
                .fontSize(12).fontColor('#858C94').maxLines(3);
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            Toggle({ type: ToggleType.Switch, isOn: this.bottomBarPinned })
              .selectedColor('#1677A8')
              .onChange((value: boolean) => { this.setBottomBarPinned(value); });
          }.width('100%').padding({ left: 16, right: 14, top: 10, bottom: 10 })
            .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(10)
            .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
            .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 });
          Row({ space: 12 }) {
            Column({ space: 5 }) {
              Text('竖屏提示').fontSize(16).fontColor('#1E252D');
              Text('所有视频均可显示：视频卡片在播放量/弹幕量后展示竖屏标记（仅竖屏比例视频显示）')
                .fontSize(12).fontColor('#858C94').maxLines(3);
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            Toggle({ type: ToggleType.Switch, isOn: this.portraitBadgeEnabled })
              .selectedColor('#1677A8')
              .onChange((value: boolean) => { this.setPortraitBadge(value); });
          }.width('100%').padding({ left: 16, right: 14, top: 10, bottom: 10 })
            .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(10)
            .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
            .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 });
          Row({ space: 12 }) {
            Column({ space: 5 }) {
              Text('悬浮球互换').fontSize(16).fontColor('#1E252D');
              Text('开启后，两侧的迷你栏位置互换').fontSize(12).fontColor('#858C94');
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            Toggle({ type: ToggleType.Switch, isOn: this.floatBallSwapped })
              .selectedColor('#1677A8')
              .onChange((value: boolean) => { this.setFloatBallSwapped(value); });
          }.width('100%').height(76).padding({ left: 16, right: 14, top: 10, bottom: 10 })
            .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(10)
            .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
            .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 });
          Row({ space: 12 }) {
            Column({ space: 5 }) {
              Text('顶栏合并').fontSize(16).fontColor('#1E252D');
              Text('开启后顶部栏子标签气泡合并').fontSize(12).fontColor('#858C94');
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            Toggle({ type: ToggleType.Switch, isOn: this.topTabsMerged })
              .selectedColor('#1677A8')
              .onChange((value: boolean) => { this.setTopTabsMerged(value); });
          }.width('100%').height(76).padding({ left: 16, right: 14, top: 10, bottom: 10 })
            .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(10)
            .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
            .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 });
        }.width('100%').padding({ left: 18, right: 18, top: 6, bottom: this.bottomInset + 18 })
          .alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Start);
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
        .align(Alignment.TopStart);
    }.width('100%').height('100%').justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start).backgroundColor('#F7F8FA')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  @Builder
  playerPage() {
    Column() {
      this.pageHeader('播放器');
      Scroll() {
        Column({ space: 10 }) {
          Row({ space: 12 }) {
            Column({ space: 5 }) {
              Text('播放质量').fontSize(16).fontColor('#1E252D');
              Text('点击切换默认清晰度，下次打开视频时生效')
                .fontSize(12).fontColor('#858C94').maxLines(2);
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            Text(this.qualityLabel(this.defaultQuality)).fontSize(14).fontColor('#1677A8')
              .fontWeight(FontWeight.Medium);
          }.width('100%').height(76).padding({ left: 16, right: 14, top: 10, bottom: 10 })
            .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(10)
            .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
            .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 })
            .onClick(() => { this.cycleDefaultQuality(); });
          this.filterCard('视频过滤词', this.videoFilterSummary,
            '键入筛选词，相关视频不会出现在你的动态/推荐等版块。示例：xx|xx，可一行多个。', 'video');
          this.filterCard('弹幕过滤词', this.danmakuFilterSummary,
            '键入筛选词，命中关键词的弹幕将不会显示。示例：xx|xx，可一行多个。', 'danmaku');
          Row({ space: 12 }) {
            Column({ space: 5 }) {
              Text('推荐页刷新保留').fontSize(16).fontColor('#1E252D');
              Text('开启功能后，下拉刷新将保留刷新前的内容')
                .fontSize(12).fontColor('#858C94').maxLines(2);
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            Toggle({ type: ToggleType.Switch, isOn: this.keepRefreshContent })
              .selectedColor('#1677A8')
              .onChange((value: boolean) => { this.setKeepRefreshContent(value); });
          }.width('100%').height(76).padding({ left: 16, right: 14, top: 10, bottom: 10 })
            .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(10)
            .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
            .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 });
        }.width('100%').padding({ left: 18, right: 18, top: 6, bottom: this.bottomInset + 18 })
          .alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Start);
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
        .align(Alignment.TopStart);
    }.width('100%').height('100%').justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start).backgroundColor('#F7F8FA')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  @Builder
  searchPage() {
    Column() {
      this.pageHeader('搜索');
      Scroll() {
        Column({ space: 10 }) {
          Row({ space: 12 }) {
            Column({ space: 5 }) {
              Text('搜索历史记忆').fontSize(16).fontColor('#1E252D');
              Text('开启后将记忆搜索历史').fontSize(12).fontColor('#858C94');
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            Toggle({ type: ToggleType.Switch, isOn: this.searchHistoryEnabled })
              .selectedColor('#1677A8')
              .onChange((value: boolean) => { this.setSearchHistoryEnabled(value); });
          }.width('100%').height(76).padding({ left: 16, right: 14, top: 10, bottom: 10 })
            .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(10)
            .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
            .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 });
        }.width('100%').padding({ left: 18, right: 18, top: 6, bottom: this.bottomInset + 18 })
          .alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Start);
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }.width('100%').height('100%').backgroundColor('#F7F8FA');
  }

  @Builder
  filterCard(title: string, summary: string, hint: string, kind: string) {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Row({ space: 6 }) {
          Text(title).fontSize(16).fontColor('#1E252D');
          Text('[' + summary + ']').fontSize(11).fontColor('#1677A8')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1);
        }.width('100%');
        Text(hint).fontSize(11).fontColor('#858C94').maxLines(2);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Button() {
        Image($r('app.media.edit')).width(18).height(18).fillColor('#1677A8');
      }
      .type(ButtonType.ROUNDED_RECTANGLE).width(34).height(34)
      .backgroundColor('#1A1677A8').borderRadius(17)
      .onClick((): void => { this.openFilterEditor(kind); });
    }.width('100%').padding({ left: 16, right: 14, top: 10, bottom: 10 })
      .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(10)
      .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
      .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 })
      .alignItems(VerticalAlign.Center)
      .onClick((): void => { this.openFilterEditor(kind); });
  }

  @Builder
  filterEditorOverlay() {
    if (this.filterEditorVisible) {
      Stack() {
        Column().width('100%').height('100%').backgroundColor('#66000000')
          .onClick(() => { this.filterEditorVisible = false; });
        Column({ space: 12 }) {
          Text(this.filterEditorKind === 'video' ? '视频过滤词' : '弹幕过滤词')
            .fontSize(17).fontWeight(FontWeight.Bold).fontColor('#1E252D').width('100%');
          Text('键入关键词和分隔符并保存，示例样式为：xx|xx，可以一行多个；单独一个筛选词没有字数上限。')
            .fontSize(12).fontColor('#858C94').width('100%');
          TextArea({ text: this.filterEditorText, placeholder: '示例：xx|xx\n可一行多个，回车换行' })
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
              .backgroundColor('#1677A8').fontColor(Color.White)
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
  advancedPage() {
    Column() {
      this.pageHeader('系统特性');
      Scroll() {
        Column({ space: 10 }) {
          Column({ space: 6 }) {
            Row({ space: 10 }) {
              Column({ space: 5 }) {
                Text('API 26 高级能力').fontSize(16).fontColor('#1E252D');
                Text('控制 API 26 专属能力；界面材质会按设备版本自动适配')
                  .fontSize(12).fontColor('#858C94').maxLines(2);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              Toggle({ type: ToggleType.Switch, isOn: this.advancedMasterEnabled })
                .selectedColor('#1677A8')
                .onChange((value: boolean) => { this.setAdvancedMaster(value); });
            }.width('100%').alignItems(VerticalAlign.Center);
          }.width('100%').padding({ left: 16, right: 14, top: 12, bottom: 12 })
            .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(10)
            .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
            .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 });

          if (AdvancedFeatures.isApi26Supported()) {
            this.advancedToggleCard('增强播放器', '支持自定义 HTTP 头部，提升视频加载兼容性', this.advancedPlayerEnabled,
              (value: boolean) => { this.setAdvancedPlayer(value); });
            this.advancedToggleCard('HUKS 会话式加密', '使用新版密钥库会话 API，提升安全性', this.advancedHuksEnabled,
              (value: boolean) => { this.setAdvancedHuks(value); });
            this.advancedToggleCard('WebView Cookie 管理', '使用新版 Cookie 管理器获取登录凭证', this.advancedWebCookieEnabled,
              (value: boolean) => { this.setAdvancedWebCookie(value); });
          }

          if (!AdvancedFeatures.isApi26Supported()) {
            Row({ space: 8 }) {
              Text('当前设备 API 版本为 ' + AdvancedFeatures.getDeviceApiLevel() +
                '，不支持 API 26 高级功能。')
                .fontSize(13).fontColor('#858C94').layoutWeight(1);
            }.width('100%').padding({ left: 16, right: 14, top: 12, bottom: 12 })
              .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(10)
              .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
              .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 });
          }
        }.width('100%').padding({ left: 18, right: 18, top: 6, bottom: this.bottomInset + 18 })
          .alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.Start);
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
        .align(Alignment.TopStart);
    }.width('100%').height('100%').justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start).backgroundColor('#F7F8FA')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  @Builder
  advancedToggleCard(title: string, detail: string, isOn: boolean, onChange: (value: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 5 }) {
        Text(title).fontSize(16).fontColor('#1E252D');
        Text(detail).fontSize(12).fontColor('#858C94').maxLines(2);
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor('#1677A8')
        .onChange((value: boolean) => { onChange(value); });
    }.width('100%').height(76).padding({ left: 16, right: 14, top: 10, bottom: 10 })
      .backgroundColor(ImmersiveMaterial.fallbackBackground()).borderRadius(10)
      .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
      .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 });
  }

  @Builder
  settingsCard(title: string, detail: string, openAbout: boolean) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(title).fontSize(16).fontColor('#1E252D');
        Text(detail).fontSize(12).fontColor('#858C94');
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start);
      Image($r('app.media.jinxin_right')).width(18).height(18);
    }
    .width('100%').height(64)
    .padding({ left: 16, right: 14 })
    .backgroundColor(ImmersiveMaterial.fallbackBackground())
    .borderRadius(10)
    .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
    .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 })
    .onClick(() => {
      if (openAbout) this.showAbout = true;
    });
  }

  @Builder
  aboutPage() {
    Column() {
      this.pageHeader('关于 Pilihos');
      Scroll() {
        Column({ space: 10 }) {
          Column({ space: 8 }) {
            Image($r('app.media.app_logo')).width(112).height(112).borderRadius(22);
            Text('Pilihos').fontSize(28).fontWeight(FontWeight.Bold);
            Text('Version 1.0.6.5').fontSize(15).fontColor('#646A73');
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 18, bottom: 10 });

          Row({ space: 10 }) {
            this.aboutInfoCard('软件说明', 'Pilihos 是B站鸿蒙移植版,开源无广,纯净高效。');
            this.aboutInfoCard('隐私政策', '应用仅在登录和请求服务时使用必要数据。');
          }.width('100%').justifyContent(FlexAlign.SpaceBetween);
          Row({ space: 10 }) {
            this.aboutInfoCard('软件协议', '本软件采用 MIT 开源协议');
            this.aboutInfoCard('版本日志',
              'v1.0.6.5\n' +
              '1. 底栏材质回退浅色毛玻璃\n' +
              '2. 竖屏化视频真居中+面板联动\n' +
              '3. 面板关注改简介区同款气泡\n' +
              'v1.0.6.4 竖屏底栏/互动回显修复\n' +
              '完整更新日志(Pilihos Wiki]https://github.com/qitinyu/Pilihos/wiki/)');
          }.width('100%').justifyContent(FlexAlign.SpaceBetween);

          this.aboutLinkCard('用户反馈', 'https://github.com/qitinyu/Pilihos/discussions/');
          this.aboutLinkCard('开源链接', 'https://github.com/qitinyu/Pilihos');
          this.aboutLinkCard('软件更新', 'https://github.com/qitinyu/Pilihos/releases');
          this.aboutLinkCard('上游仓库', 'https://github.com/dev4harmony/PiliPlus');
          Text('\u00A92026 pilihos by YuQi')
            .fontSize(12).fontColor('#858C94')
            .width('100%').textAlign(TextAlign.Center)
            .margin({ top: 18, bottom: 8 });
        }
        .width('100%')
        .padding({ left: 18, right: 18, bottom: this.bottomInset + 18 });
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart);
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor('#F8F7FF')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }

  @Builder
  aboutInfoCard(label: string, message: string) {
    Row() {
      Text(label).fontSize(15).fontColor('#1E252D').layoutWeight(1);
      Image($r('app.media.jinxin_right')).width(17).height(17);
    }
    .width('100%').height(56)
    .layoutWeight(1)
    .padding({ left: 18, right: 14 })
    .backgroundColor(ImmersiveMaterial.fallbackBackground())
    .borderRadius(10)
    .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
    .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 })
    .onClick(() => { this.showInfo(label, message); });
  }

  @Builder
  aboutLinkCard(label: string, url: string) {
    Row({ space: 8 }) {
      Text(label).fontSize(17).fontColor('#1E252D').layoutWeight(1);
      Text('浏览器打开').fontSize(13).fontColor('#646A73');
      Image($r('app.media.jinxin_right')).width(17).height(17);
    }
    .width('100%').height(56)
    .padding({ left: 18, right: 14 })
    .backgroundColor(ImmersiveMaterial.fallbackBackground())
    .borderRadius(10)
    .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
    .shadow({ radius: 4, color: '#16000000', offsetX: 0, offsetY: 1 })
    .onClick(() => { this.openUrl(url); });
  }
}
