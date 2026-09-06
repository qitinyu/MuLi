import { VideoItem } from '../models/VideoItem';
import { AuthService } from '../services/AuthService';
import { SearchSeason, SearchService, SearchUser } from '../services/SearchService';
import { WbiService } from '../services/WbiService';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';
import { preferences } from '@kit.ArkData';

class SearchTypeItem {
  label: string = '';
  value: string = '';
}

@Entry
@Component
struct SearchPage {
  @State searchText: string = '';
  @State searchLoading: boolean = false;
  @State searchError: string = '';
  @State searchResults: VideoItem[] = [];
  @State searchUsers: SearchUser[] = [];
  @State searchSeasons: SearchSeason[] = [];
  @State searchType: string = 'video';
  @State searchOrder: string = '';
  @State searchHistory: string[] = [];
  @State searchHistoryEnabled: boolean = false;
  @State searched: boolean = false;
  @State topInset: number = 0;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private typeItems: SearchTypeItem[] = SearchPage.buildTypeItems();

  static buildTypeItems(): SearchTypeItem[] {
    const items: SearchTypeItem[] = [];
    const labels: string[] = ['视频', 'UP主', '番剧', '影视'];
    const values: string[] = ['video', 'bili_user', 'media_bangumi', 'media_ft'];
    for (let i = 0; i < labels.length; i++) {
      const item: SearchTypeItem = new SearchTypeItem();
      item.label = labels[i];
      item.value = values[i];
      items.push(item);
    }
    return items;
  }

  aboutToAppear(): void {
    this.updateSystemInsets();
    this.loadSearchSettings();
    // 提前拉取 WBI 签名密钥，避免首次回车搜索等待
    WbiService.warmup();
  }

  private async updateSystemInsets(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
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

  private switchType(value: string): void {
    if (this.searchType === value) return;
    this.searchType = value;
    if (this.searchText.trim() !== '' && this.searched) {
      this.submitVideoSearch(this.searchText);
    }
  }

  private async submitVideoSearch(keyword: string): Promise<void> {
    let value: string = keyword.trim();
    if (value === '') value = this.searchText.trim();
    if (value === '') {
      // 输入框内容未能同步时给出可见反馈，便于定位真机输入问题
      this.showToast('请输入搜索关键词');
      return;
    }
    if (this.searchLoading) return;
    this.searchText = value;
    this.searchLoading = true;
    console.info(`Pilihos search submit: type=${this.searchType}, keyword=${value}`);
    this.searchError = '';
    this.searchResults = [];
    this.searchUsers = [];
    this.searchSeasons = [];
    this.searched = true;
    try {
      const session = AuthService.currentSession();
      const cookie: string = session === null ? '' : session.cookie;
      const batch = await SearchService.search(this.searchType, value, cookie, this.searchOrder);
      this.searchResults = batch.videos;
      this.searchUsers = batch.users;
      this.searchSeasons = batch.seasons;
      if (batch.videos.length + batch.users.length + batch.seasons.length > 0) {
        await this.rememberSearch(value);
      } else {
        this.showToast('没有找到相关内容');
      }
    } catch (error) {
      const detail: string = String(error);
      this.showToast(detail.length > 0 && detail.length <= 40
        ? '搜索失败: ' + detail : '搜索失败，请稍后重试');
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
          pilihosPlayback: {
            results: this.searchResults,
            index: index,
            nonce: `${Date.now()}-${index}`
          }
        }
      });
    } catch (error) {
      console.error('Pilihos search result back failed: ' + String(error));
    }
  }

  private openSeasonDetail(season: SearchSeason): void {
    router.pushUrl({
      url: 'pages/AnimeDetail',
      params: { seasonId: season.seasonId, title: season.title }
    }).catch((error: Object): void => {
      console.error('Pilihos season detail page failed: ' + String(error));
    });
  }

  private formatCount(value: number): string {
    if (value >= 100000000) return `${(value / 100000000).toFixed(2).replace(/\.00$/, '')}亿`;
    if (value >= 10000) return `${(value / 10000).toFixed(1).replace(/\.0$/, '')}万`;
    return `${value}`;
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

  @Builder
  loadingIndicator(label: string, color: string) {
    Row({ space: 8 }) {
      LoadingProgress().width(26).height(26).color(color);
      Text(label).fontSize(14).fontColor(color).textAlign(TextAlign.Center);
    }
    .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center);
  }

  @Builder
  typeTabs() {
    Scroll() {
      Row({ space: 26 }) {
        ForEach(this.typeItems, (item: SearchTypeItem) => {
          Text(item.label).fontSize(16)
            .fontColor(this.searchType === item.value ? '#1677A8' : '#59616B')
            .fontWeight(this.searchType === item.value ? FontWeight.Bold : FontWeight.Normal)
            .onClick((): void => { this.switchType(item.value); });
        }, (item: SearchTypeItem) => `type_${item.value}_${this.searchType === item.value}`);
      }.padding({ left: 24, right: 24 });
    }.width('100%').height(46)
      .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off);
  }

  @Builder
  searchHistoryPanel() {
    if (this.searchHistoryEnabled && this.searchHistory.length > 0) {
      Row() {
        Text('搜索历史').fontSize(17).fontWeight(FontWeight.Medium).fontColor('#20242A').layoutWeight(1);
        Text('清空').fontSize(13).fontColor('#8B9199').onClick(() => { this.clearSearchHistory(); });
      }.width('100%').padding({ left: 18, right: 18, top: 16, bottom: 8 });
      // 注意：这里不能用 Grid——Grid 未设高度会占满整列，把下方结果区压成 0 高度
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.searchHistory, (keyword: string) => {
          Text(keyword).fontSize(keyword.length > 8 ? 12 : 14).fontColor('#59616B')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('31%').textAlign(TextAlign.Center)
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .margin({ right: '2%', bottom: 8 })
            .backgroundColor('#F1F4F6').borderRadius(16)
            .gesture(LongPressGesture({ repeat: false }).onAction(() => {
              this.deleteSearchHistory(keyword);
            }))
            .onClick(() => { this.useSearchHistory(keyword); });
        }, (keyword: string) => keyword);
      }.width('100%').padding({ left: 18, right: 18, bottom: 8 });
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

  @Builder
  userResultCard(user: SearchUser) {
    Row({ space: 12 }) {
      if (user.face !== '') {
        Image(user.face).width(52).height(52).borderRadius(26).objectFit(ImageFit.Cover);
      } else {
        Row().width(52).height(52).borderRadius(26).backgroundColor('#DCE3EF');
      }
      Column({ space: 5 }) {
        Row({ space: 6 }) {
          Text(user.uname === '' ? '未知用户' : user.uname).fontSize(16).fontColor('#20242A')
            .fontWeight(FontWeight.Medium).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
          if (user.liveRoomId > 0) {
            Text('直播中').fontSize(10).fontColor(Color.White)
              .backgroundColor('#E6000044').borderRadius(4)
              .padding({ left: 5, right: 5, top: 2, bottom: 2 });
          }
        }.width('100%');
        Text(user.sign === '' ? '暂无简介' : user.sign).fontSize(12).fontColor('#8B9199')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        Row({ space: 12 }) {
          Text(this.formatCount(user.fans) + ' 粉丝').fontSize(12).fontColor('#8B9199');
          Text(this.formatCount(user.videoCount) + ' 投稿').fontSize(12).fontColor('#8B9199');
          Text('LV' + String(user.level)).fontSize(10).fontColor(Color.White)
            .backgroundColor(user.level >= 6 ? '#E661A0' : user.level >= 4 ? '#1677A8' : '#9AA4AE')
            .borderRadius(3).padding({ left: 3, right: 3, top: 1, bottom: 1 });
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(Color.White)
    .onClick((): void => { router.pushUrl({ url: 'pages/UserSpace', params: { mid: user.mid, name: user.uname } }).catch((error: Object): void => { console.error('Pilihos user space push failed: ' + String(error)); }); });
  }

  @Builder
  seasonResultCard(season: SearchSeason) {
    Row({ space: 12 }) {
      Image(season.cover).width('42%').aspectRatio(3 / 4).objectFit(ImageFit.Cover)
        .borderRadius(10);
      Column({ space: 7 }) {
        Text(season.typeName).fontSize(10).fontColor('#1677A8')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .backgroundColor('#1A1677A8').borderRadius(4)
          .width('100%').textAlign(TextAlign.Start);
        Text(season.title).fontSize(16).fontColor('#20242A').maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        Text(season.indexShow === '' ? '暂无更新信息' : season.indexShow)
          .fontSize(12).fontColor('#8B9199').width('100%');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(Color.White)
    .onClick((): void => { this.openSeasonDetail(season); });
  }

  @Builder
  sortRow() {
    if (this.searchType === 'video' && this.searched) {
      Scroll() {
        Row({ space: 10 }) {
          ForEach(SearchPage.orderItems(), (item: string[]) => {
            Text(item[1]).fontSize(13)
              .fontColor(this.searchOrder === item[0] ? '#1677A8' : '#59616B')
              .fontWeight(this.searchOrder === item[0] ? FontWeight.Bold : FontWeight.Normal)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(this.searchOrder === item[0] ? '#E5F3FA' : Color.White)
              .borderRadius(14)
              .onClick((): void => {
                if (this.searchOrder === item[0]) return;
                this.searchOrder = item[0];
                this.submitVideoSearch(this.searchText);
              });
          }, (item: string[]) => item[0]);
        }.padding({ left: 18, right: 18 });
      }.width('100%').height(40)
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off);
    }
  }

  static orderItems(): string[][] {
    return [['', '默认排序'], ['click', '播放多'], ['pubdate', '最新发布'], ['dm', '弹幕最多']];
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
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
        .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
        .onClick(() => { router.back(); });
        Search({ placeholder: '搜索', value: this.searchText })
          .layoutWeight(1).height(48).backgroundColor(ImmersiveMaterial.fallbackBackground())
          .borderRadius(24).backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
          .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
          .focusable(true)
          .defaultFocus(true)
          .onChange((value: string) => { this.searchText = value; })
          .onSubmit((value: string): void => {
            // 部分真机 onSubmit 回调的 value 可能为空，回退到状态中记录的输入
            const keyword: string = value.trim() !== '' ? value : this.searchText;
            this.submitVideoSearch(keyword);
          });
      }
      .width('100%').padding({ left: 10, right: 10, top: this.topInset + 8, bottom: 8 });
      this.typeTabs();
      this.searchHistoryPanel();
      this.sortRow();
      if (this.searchLoading) {
        Column() {
          this.loadingIndicator('正在搜索...', '#1677A8');
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.searchResults.length > 0) {
        Scroll() {
          Column() {
            ForEach(this.searchResults, (item: VideoItem) => {
              this.searchResultCard(item);
            }, (item: VideoItem) => `${item.id}-${item.bvid}`);
          }.width('100%');
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      } else if (this.searchUsers.length > 0) {
        Scroll() {
          Column() {
            ForEach(this.searchUsers, (user: SearchUser) => {
              this.userResultCard(user);
            }, (user: SearchUser) => `user_${user.mid}`);
          }.width('100%');
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      } else if (this.searchSeasons.length > 0) {
        Scroll() {
          Column() {
            ForEach(this.searchSeasons, (season: SearchSeason) => {
              this.seasonResultCard(season);
            }, (season: SearchSeason) => `season_${season.seasonId}`);
          }.width('100%');
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      } else if (this.searched) {
        Column() {
          Text(this.searchError !== '' ? this.searchError : '没有找到相关内容')
            .fontSize(14).fontColor('#8B9199');
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
