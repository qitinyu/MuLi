import { VideoItem } from '../models/VideoItem';
import { SearchService } from '../services/SearchService';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import { preferences } from '@kit.ArkData';

@Entry
@Component
struct SearchPage {
  @State searchText: string = '';
  @State searchLoading: boolean = false;
  @State searchError: string = '';
  @State searchResults: VideoItem[] = [];
  @State searchHistory: string[] = [];
  @State searchHistoryEnabled: boolean = false;
  @State searched: boolean = false;
  @State topInset: number = 0;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.updateSystemInsets();
    this.loadSearchSettings();
  }

  private async updateSystemInsets(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const navigationArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.topInset = px2vp(systemArea.topRect.height);
      mainWindow.on('avoidAreaChange', (data): void => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          this.topInset = px2vp(data.area.topRect.height);
        }
      });
    } catch (error) {
      console.error('Pilihos search page inset update failed: ' + String(error));
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2500,
        bottom: 24
      });
    } catch (error) {
      console.error(`Pilihos search toast failed: ${String(error)}`);
    }
  }

  private async submitVideoSearch(keyword: string): Promise<void> {
    const value: string = keyword.trim();
    if (value === '' || this.searchLoading) return;
    this.searchText = value;
    this.searchLoading = true;
    this.searchError = '';
    this.searchResults = [];
    this.searched = true;
    try {
      const results: VideoItem[] = await SearchService.searchVideo(value);
      if (results.length === 0) {
        this.showToast('没有找到相关视频');
        return;
      }
      this.searchResults = results;
      await this.rememberSearch(value);
    } catch (error) {
      this.showToast('搜索失败，请稍后重试');
      console.error(`Pilihos video search failed: ${String(error)}`);
    } finally {
      this.searchLoading = false;
    }
  }

  private async loadSearchSettings(): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_search');
      this.searchHistoryEnabled = store.getSync('history_enabled', false) as boolean;
      const saved: string = store.getSync('history', '') as string;
      this.searchHistory = saved === '' ? [] : saved.split('|').filter((item: string): boolean => item !== '');
    } catch (error) {
      console.error(`Pilihos search settings load failed: ${String(error)}`);
    }
  }

  private async rememberSearch(keyword: string): Promise<void> {
    if (!this.searchHistoryEnabled) return;
    const updated: string[] = [keyword].concat(this.searchHistory.filter((item: string): boolean => item !== keyword)).slice(0, 12);
    this.searchHistory = updated;
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_search');
      store.putSync('history', updated.join('|'));
      store.flushSync();
    } catch (error) {
      console.error(`Pilihos search history save failed: ${String(error)}`);
    }
  }

  private async deleteSearchHistory(keyword: string): Promise<void> {
    this.searchHistory = this.searchHistory.filter((item: string): boolean => item !== keyword);
    await this.saveSearchHistory();
  }

  private async clearSearchHistory(): Promise<void> {
    this.searchHistory = [];
    await this.saveSearchHistory();
  }

  private async saveSearchHistory(): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_search');
      store.putSync('history', this.searchHistory.join('|'));
      store.flushSync();
    } catch (error) {
      console.error(`Pilihos search history save failed: ${String(error)}`);
    }
  }

  private useSearchHistory(keyword: string): void {
    this.searchText = keyword;
    this.submitVideoSearch(keyword);
  }

  private openSearchResult(item: VideoItem): void {
    const index: number = this.searchResults.indexOf(item);
    if (index < 0) return;
    try {
      router.back({
        url: 'pages/Index',
        params: {
          pilihosSearch: {
            results: this.searchResults,
            index: index
          }
        }
      });
    } catch (error) {
      console.error('Pilihos search result back failed: ' + String(error));
    }
  }

  private formatPlaybackTime(valueMs: number): string {
    const totalSeconds: number = Math.max(0, Math.floor(valueMs / 1000));
    const hours: number = Math.floor(totalSeconds / 3600);
    const minutes: number = Math.floor((totalSeconds % 3600) / 60);
    const seconds: number = totalSeconds % 60;
    const minuteText: string = String(minutes).padStart(2, '0');
    const secondText: string = String(seconds).padStart(2, '0');
    if (hours > 0) return String(hours).padStart(2, '0') + ':' + minuteText + ':' + secondText;
    return minuteText + ':' + secondText;
  }

  private formatCount(value: number): string {
    if (value >= 100000000) return `${(value / 100000000).toFixed(2).replace(/\.00$/, '')}亿`;
    if (value >= 1000000) return `${(value / 100000).toFixed(2).replace(/\.00$/, '')}万`;
    if (value >= 1000) return `${(value / 1000).toFixed(1).replace(/\.0$/, '')}千`;
    return `${value}`;
  }

  @Builder
  loadingIndicator(label: string, color: string) {
    Row({ space: 8 }) {
      LoadingProgress().width(26).height(26).color(color);
      Text(label).fontSize(14).fontColor(color).textAlign(TextAlign.Center);
    }
    .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center);
  }

  @Builder
  searchHistoryPanel() {
    if (this.searchHistoryEnabled && this.searchHistory.length > 0) {
      Row() {
        Text('搜索历史').fontSize(17).fontWeight(FontWeight.Medium).fontColor('#20242A').layoutWeight(1);
        Text('清空').fontSize(13).fontColor('#8B9199').onClick(() => { this.clearSearchHistory(); });
      }.width('100%').padding({ left: 18, right: 18, top: 16, bottom: 8 });
      Grid() {
        ForEach(this.searchHistory, (keyword: string) => {
          GridItem() {
            Text(keyword).fontSize(keyword.length > 8 ? 12 : 14).fontColor('#59616B')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%').textAlign(TextAlign.Center)
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .backgroundColor('#F1F4F6').borderRadius(16)
              .gesture(LongPressGesture({ repeat: false }).onAction(() => {
                this.deleteSearchHistory(keyword);
              }))
              .onClick(() => { this.useSearchHistory(keyword); });
          }
        }, (keyword: string) => keyword);
      }.columnsTemplate('1fr 1fr 1fr').columnsGap(8).rowsGap(8)
        .width('100%').padding({ left: 18, right: 18, bottom: 8 });
    }
  }

  @Builder
  searchResultCard(item: VideoItem) {
    Row({ space: 12 }) {
      Stack() {
        Image(item.cover).width('100%').height('100%').objectFit(ImageFit.Cover)
          .borderRadius(10);
        Text(this.formatPlaybackTime(item.duration * 1000))
          .fontSize(11).fontColor(Color.White).backgroundColor('#B0000000')
          .padding({ left: 5, right: 5, top: 3, bottom: 3 }).borderRadius(4)
          .position({ right: 5, bottom: 5 });
      }.width('42%').aspectRatio(16 / 9);
      Column({ space: 7 }) {
        Text(item.title).fontSize(16).fontColor('#20242A').maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        Text(item.author === '' ? '未知用户' : item.author).fontSize(12).fontColor('#8B9199')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        Row({ space: 12 }) {
          Text(this.formatCount(item.viewCount) + '播放').fontSize(12).fontColor('#8B9199');
          Text(this.formatCount(item.danmuCount) + '弹幕').fontSize(12).fontColor('#8B9199');
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(Color.White)
    .onClick((): void => { this.openSearchResult(item); });
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button() {
          Image($r('app.media.fanhui_left')).width(24).height(24);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(48).height(48)
        .backgroundColor(ImmersiveMaterial.fallbackBackground())
        .borderRadius(24)
        .systemMaterial(ImmersiveMaterial.thin())
        .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
        .onClick(() => { router.back(); });
        Search({ placeholder: '搜索视频', value: this.searchText })
          .layoutWeight(1).height(48).backgroundColor(ImmersiveMaterial.fallbackBackground())
          .borderRadius(24).systemMaterial(ImmersiveMaterial.thin())
          .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
          .focusable(true)
          .defaultFocus(true)
          .onChange((value: string) => { this.searchText = value; })
          .onSubmit((value: string): void => {
            this.submitVideoSearch(value);
          });
      }
      .width('100%').padding({ left: 10, right: 10, top: this.topInset + 8, bottom: 8 });
      this.searchHistoryPanel();
      if (this.searchResults.length > 0 && !this.searchLoading) {
        Scroll() {
          Row({ space: 28 }) {
            Text('视频 ' + (this.searchResults.length >= 20 ? '20+' : String(this.searchResults.length)))
              .fontSize(16).fontColor('#1677A8').fontWeight(FontWeight.Bold);
            Text('番剧').fontSize(16).fontColor('#59616B');
            Text('影视').fontSize(16).fontColor('#59616B');
            Text('直播间').fontSize(16).fontColor('#59616B');
            Text('用户').fontSize(16).fontColor('#59616B');
          }.padding({ left: 24, right: 24 });
        }.width('100%').height(48).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off);
        Scroll() {
          Row({ space: 25 }) {
            Text('默认排序').fontSize(15).fontColor('#1677A8').fontWeight(FontWeight.Bold);
            Text('播放多').fontSize(15).fontColor('#59616B');
            Text('新发布').fontSize(15).fontColor('#59616B');
            Text('弹幕多').fontSize(15).fontColor('#59616B');
            Text('收藏多').fontSize(15).fontColor('#59616B');
          }.padding({ left: 24, right: 24 });
        }.width('100%').height(42).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off);
        Scroll() {
          Column() {
            ForEach(this.searchResults, (item: VideoItem) => {
              this.searchResultCard(item);
            }, (item: VideoItem) => `${item.id}-${item.bvid}`);
          }.width('100%');
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      } else if (this.searchLoading) {
        Column() {
          this.loadingIndicator('正在搜索视频...', '#1677A8');
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.searchError !== '') {
        Text(this.searchError).fontSize(14).fontColor('#8B9199').margin({ top: 18 });
      } else if (this.searched) {
        Column() {
          Text('没有找到相关视频').fontSize(14).fontColor('#8B9199');
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Column() {
          Text('输入关键词开始搜索').fontSize(14).fontColor('#8B9199');
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      }
    }.width('100%').height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#F7F8FA')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }
}
