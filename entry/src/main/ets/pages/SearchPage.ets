import { VideoItem } from '../models/VideoItem';
import { AuthService } from '../services/AuthService';
import { SearchSeason, SearchService, SearchUser } from '../services/SearchService';
import { InteractionService } from '../services/InteractionService';
import { BiliHttpClient } from '../services/BiliHttpClient';
import { WbiService } from '../services/WbiService';
import { FormatUtils } from '../utils/FormatUtils';
import { FollowState } from '../utils/FollowState';
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
  @State searchLayer: number = 0; // 0=搜索首页层 1=结果层
  @State hotWords: string[] = [];
  @State portraitBadge: boolean = true;
  @State topInset: number = 0;
  @State followMenuUser: SearchUser | null = null;
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

  static orderItems(): string[][] {
    return [['', '默认排序'], ['click', '播放多'], ['pubdate', '最新发布'], ['dm', '弹幕最多']];
  }

  aboutToAppear(): void {
    this.updateSystemInsets();
    this.loadSearchSettings();
    this.loadHotWords();
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

  private async loadHotWords(): Promise<void> {
    try {
      this.hotWords = await SearchService.loadHotSearch();
    } catch (error) {
      console.warn(`Pilihos hot search failed: ${String(error)}`);
    }
  }

  private switchType(value: string): void {
    if (this.searchType === value) return;
    this.searchType = value;
    if (this.searchText.trim() !== '' && this.searched) {
      this.submitVideoSearch(this.searchText);
    }
  }

  private backAction(): void {
    if (this.searchLayer === 1) {
      this.searchLayer = 0;
    } else {
      router.back();
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
    this.searchLayer = 1;
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
        this.loadUserStates();
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

  /**
   * 搜索结果 UP 主状态校准：关注态逐个核对；
   * 开播状态用 get_status_info_by_uids 批量校验（room_id 有值不代表正在直播）
   */
  private async loadLiveStatus(): Promise<void> {
    const mids: number[] = this.searchUsers
      .filter((user: SearchUser): boolean => user.liveRoomId > 0)
      .map((user: SearchUser): number => user.mid);
    if (mids.length === 0) return;
    try {
      const body: Record<string, Object> = {};
      body['uids'] = mids;
      const result: Record<string, Object> = await BiliHttpClient.postJsonHost(
        'api.live.bilibili.com', '/room/v1/Room/get_status_info_by_uids', body, '');
      if (Number(result['code'] ?? -1) !== 0) return;
      const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
      let changed: boolean = false;
      this.searchUsers.forEach((user: SearchUser): void => {
        if (user.liveRoomId <= 0) return;
        const info: Record<string, Object> = (data[String(user.mid)] ?? {}) as Record<string, Object>;
        const live: boolean = Number(info['live_status'] ?? 0) === 1;
        if (live !== user.liveStatus) {
          user.liveStatus = live;
          changed = true;
        }
      });
      if (changed) this.searchUsers = this.searchUsers.slice(0);
    } catch (error) {
      console.warn(`Pilihos live status check failed: ${String(error)}`);
    }
  }
  private async loadUserStates(): Promise<void> {
    this.loadLiveStatus();
    await this.loadUserRelations();
  }

  private async loadUserRelations(): Promise<void> {
    const session = AuthService.currentSession();
    if (session === null || session.cookie === '') return;
    for (let index: number = 0; index < this.searchUsers.length && index < 8; index++) {
      const user: SearchUser = this.searchUsers[index];
      if (user.mid <= 0) continue;
      try {
        const attribute: number = await InteractionService.relationAttribute(user.mid, session.cookie);
        const followed: boolean = attribute === 2 || attribute === 6 || attribute === 128;
        if (followed !== user.followed) {
          user.followed = followed;
          this.searchUsers = this.searchUsers.slice(0);
        }
      } catch (error) {
        // 忽略单个用户状态获取失败
      }
    }
  }

  private async toggleUserFollow(user: SearchUser, special: boolean): Promise<void> {
    const session = AuthService.currentSession();
    if (session === null || session.cookie === '' || session.csrf === '') {
      this.showToast('请先登录后再关注');
      return;
    }
    if (user.followed) {
      // 已关注：点击气泡直接取关
      try {
        await InteractionService.follow(user.mid, false, session.cookie, session.csrf, '11');
        user.followed = false;
        FollowState.setFollowed(user.mid, user.uname, false);
        this.searchUsers = this.searchUsers.slice(0);
        this.showToast('已取消关注');
      } catch (error) {
        this.showToast(`取关失败: ${String(error)}`);
      }
      return;
    }
    try {
      await InteractionService.follow(user.mid, true, session.cookie, session.csrf, '11');
      user.followed = true;
      FollowState.setFollowed(user.mid, user.uname, true);
      this.searchUsers = this.searchUsers.slice(0);
      this.showToast(special ? `已特别关注 ${user.uname}` : `已关注 ${user.uname}`);
    } catch (error) {
      this.showToast(`关注失败: ${String(error)}`);
    }
  }

  private async loadSearchSettings(): Promise<void> {
    try {
      const store: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_search');
      this.searchHistoryEnabled = store.getSync('history_enabled', false) as boolean;
      const saved: string = store.getSync('history', '') as string;
      this.searchHistory = saved === '' ? [] : saved.split('|').filter((item: string): boolean => item !== '');
      const uiStore: preferences.Preferences = await preferences.getPreferences(this.context, 'pilihos_ui');
      this.portraitBadge = uiStore.getSync('portrait_badge', true) as boolean;
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
    return FormatUtils.formatCount(value);
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

  @Builder
  hotPanel() {
    if (this.hotWords.length > 0) {
      Row() {
        Text('热搜').fontSize(17).fontWeight(FontWeight.Medium).fontColor('#20242A').layoutWeight(1);
      }.width('100%').padding({ left: 18, right: 18, top: 16, bottom: 8 });
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.hotWords, (word: string, index: number) => {
          Row({ space: 5 }) {
            Text(String(index + 1)).fontSize(12)
              .fontColor(index < 3 ? '#F04B55' : '#A4A9AF')
              .fontWeight(FontWeight.Bold);
            Text(word).fontSize(14).fontColor('#20242A')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          }
          .constraintSize({ maxWidth: '46%' })
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .margin({ right: 8, bottom: 8 })
          .backgroundColor('#F1F4F6').borderRadius(16)
          .onClick(() => { this.useSearchHistory(word); });
        }, (word: string) => word);
      }.width('100%').padding({ left: 18, right: 18, bottom: 8 });
    }
  }

  @Builder
  searchHistoryPanel() {
    if (this.searchHistoryEnabled && this.searchHistory.length > 0) {
      Row({ space: 10 }) {
        Text('搜索历史').fontSize(17).fontWeight(FontWeight.Medium).fontColor('#20242A');
        Text('清空').fontSize(13).fontColor('#8B9199').onClick(() => { this.clearSearchHistory(); });
        Blank().layoutWeight(1);
      }.width('100%').padding({ left: 18, right: 18, top: 16, bottom: 8 });
      // 注意：这里不能用 Grid——Grid 未设高度会占满整列，把下方内容压成 0 高度
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

  /**
   * 搜索结果视频卡片：样式与推荐流卡片一致
   */
  @Builder
  searchResultCard(item: VideoItem) {
    Column({ space: 6 }) {
      Stack() {
        if (item.cover !== '') {
          Image(item.cover).width('100%').aspectRatio(1.62).objectFit(ImageFit.Cover);
        } else {
          Row().width('100%').aspectRatio(1.62).backgroundColor('#DCE3EF');
        }
      }
      .borderRadius(10)
      .clip(true);
      Text(item.title).fontSize(14).maxLines(2).fontWeight(FontWeight.Medium).lineHeight(22);
      Row() {
        Row({ space: 4 }) {
          Image($r('app.media.bfl')).width(14).height(14);
          Text(this.formatCount(item.viewCount)).fontSize(11).fontColor('#8B9199');
        }.layoutWeight(1);
        Row({ space: 4 }) {
          Image($r('app.media.dm')).width(14).height(14);
          Text(this.formatCount(item.danmuCount)).fontSize(11).fontColor('#8B9199');
        }.layoutWeight(1);
        if (FormatUtils.isPortraitVideo(item, this.portraitBadge)) {
          Text('竖屏').fontSize(10).fontColor('#E661A0')
            .padding({ left: 5, right: 5, top: 2, bottom: 2 })
            .backgroundColor('#1AE661A0').borderRadius(4);
        }
      }.width('100%');
      Row() {
        Text(`@${item.author}`).fontSize(11).fontColor('#8B9199').layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Text(FormatUtils.formatPublishTime(item.publishTime)).fontSize(11).fontColor('#8B9199');
      }.width('100%');
    }
    .padding({ left: 8, right: 8, top: 8, bottom: 8 })
    .backgroundColor(Color.White)
    .borderRadius(12)
    .height(210)
    .onClick((): void => { this.openSearchResult(item); });
  }

  @Builder
  followOptionsMenu(user: SearchUser) {
    Column({ space: 2 }) {
      Text('只是关注').fontSize(13).fontColor('#1E252D')
        .width('100%').height(34).textAlign(TextAlign.Center)
        .onClick((): void => {
          this.followMenuUser = null;
          this.toggleUserFollow(user, false);
        });
      Text('特别关注').fontSize(13).fontColor('#1E252D')
        .width('100%').height(34).textAlign(TextAlign.Center)
        .onClick((): void => {
          this.followMenuUser = null;
          this.toggleUserFollow(user, true);
        });
      Text('设置分组').fontSize(13).fontColor('#1E252D')
        .width('100%').height(34).textAlign(TextAlign.Center)
        .onClick((): void => {
          this.followMenuUser = null;
          this.showToast('分组管理开发中，敬请期待');
        });
    }.width(124).padding({ top: 6, bottom: 6 }).backgroundColor('#F7F8FA')
      .borderRadius(10).shadow({ radius: 10, color: '#33000000', offsetX: 0, offsetY: 3 });
  }

  @Builder
  followBubble(user: SearchUser) {
    Row({ space: 4 }) {
      Image($r('app.media.lista')).width(14).height(14)
        .fillColor(user.followed ? '#59616B' : '#1677A8');
      Text(user.followed ? '已关注' : '关注')
        .fontSize(12)
        .fontColor(user.followed ? '#59616B' : '#1677A8');
    }
    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
    .backgroundColor(user.followed ? '#F1F3F5' : '#E5F3FA')
    .borderRadius(15)
    .bindMenu(this.followMenuUser !== null && this.followMenuUser.mid === user.mid && !user.followed,
      this.followOptionsMenu(user), {
        placement: Placement.Bottom,
        enableArrow: false,
        showInSubWindow: true
      })
    .onClick((): void => {
      if (user.followed) {
        this.toggleUserFollow(user, false);
      } else {
        // 首次关注：先弹出关注方式选择
        this.followMenuUser = user;
      }
    });
  }

  /**
   * UP主结果卡片：徽章紧跟名称、直播头像红框标记、关注气泡
   */
  @Builder
  userResultCard(user: SearchUser) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Stack() {
          if (user.face !== '') {
            Image(user.face).width(52).height(52).borderRadius(26).objectFit(ImageFit.Cover);
          } else {
            Row().width(52).height(52).borderRadius(26).backgroundColor('#DCE3EF');
          }
          if (user.liveStatus) {
            // 正在直播：头像外围红色标记框
            Row()
              .width(58).height(58)
              .border({ width: 2, color: '#F04B55' })
              .borderRadius(29)
          }
        }.width(58).height(58);
        if (user.liveStatus) {
          Text('直播中').fontSize(9).fontColor(Color.White)
            .backgroundColor('#F04B55')
            .padding({ left: 5, right: 5, top: 1, bottom: 1 })
            .borderRadius(4);
        }
      }.alignItems(HorizontalAlign.Center);
      Column({ space: 5 }) {
        Row({ space: 6 }) {
          Text(user.uname === '' ? '未知用户' : user.uname).fontSize(16).fontColor('#20242A')
            .fontWeight(FontWeight.Medium).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '55%' });
          Text('LV' + String(user.level)).fontSize(9).fontColor(Color.White)
            .backgroundColor(user.level >= 6 ? '#E661A0' : user.level >= 4 ? '#1677A8' : '#9AA4AE')
            .borderRadius(3).padding({ left: 3, right: 3, top: 1, bottom: 1 });
          Blank().layoutWeight(1);
          this.followBubble(user);
        }.width('100%');
        Text(user.sign === '' ? '暂无简介' : user.sign).fontSize(12).fontColor('#8B9199')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        Row({ space: 12 }) {
          Text(this.formatCount(user.fans) + ' 粉丝').fontSize(12).fontColor('#8B9199');
          Text(this.formatCount(user.videoCount) + ' 投稿').fontSize(12).fontColor('#8B9199');
        }.width('100%');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(Color.White)
    .onClick((): void => {
      router.pushUrl({ url: 'pages/UserSpace', params: { mid: user.mid, name: user.uname } })
        .catch((error: Object): void => {
          console.error('Pilihos user space push failed: ' + String(error));
        });
    });
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
  resultSection() {
    if (this.searchLoading) {
      Column() {
        this.loadingIndicator('正在搜索...', '#1677A8');
      }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
    } else if (this.searchType === 'video' && this.searchResults.length > 0) {
      Scroll() {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.searchResults, (item: VideoItem) => {
            Column() {
              this.searchResultCard(item);
            }.width('50%')
              .padding({ left: 6, right: 6, bottom: 10 });
          }, (item: VideoItem) => `${item.id}-${item.bvid}`);
        }.width('100%').padding({ top: 4 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    } else if (this.searchResults.length > 0) {
      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.searchResults, (item: VideoItem) => {
            this.searchResultCard(item);
          }, (item: VideoItem) => `full_${item.id}-${item.bvid}`);
        }.width('100%');
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    } else if (this.searchUsers.length > 0) {
      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.searchUsers, (user: SearchUser) => {
            this.userResultCard(user);
          }, (user: SearchUser) => `user_${user.mid}_${user.followed}`);
        }.width('100%');
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    } else if (this.searchSeasons.length > 0) {
      Scroll() {
        Column({ space: 10 }) {
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
        .onClick(() => { this.backAction(); });
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
      .width('100%')
      .padding({ left: 10, right: 10, top: this.topInset + 8, bottom: 8 });

      if (this.searchLayer === 0) {
        // 第一层：搜索栏 + 热搜 + 历史记录
        Scroll() {
          Column() {
            this.hotPanel();
            this.searchHistoryPanel();
          }.width('100%');
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
          .align(Alignment.TopStart);
      } else {
        // 第二层：筛选项 + 搜索结果
        this.typeTabs();
        this.sortRow();
        this.resultSection();
      }
    }.width('100%').height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#F7F8FA')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }
}
