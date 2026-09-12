import { VideoItem } from '../models/VideoItem';
import { BiliHttpClient } from '../services/BiliHttpClient';
import { AuthService, AuthSession } from '../services/AuthService';
import { WbiService } from '../services/WbiService';
import { FormatUtils } from '../utils/FormatUtils';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import { InteractionService } from '../services/InteractionService';
import { systemShare } from '@kit.ShareKit';
import window from '@ohos.window';

interface SpaceCardData {
  name: string;
  face: string;
  sign: string;
  level: number;
  followerCount: number;
  followingCount: number;
  likeCount: number;
  videoCount: number;
  followed: boolean;
  mutual: boolean;
  vipStatus: number;
  vipType: number;
}

// UP 主动态（space_history 老接口结构）
class SpaceDynItem {
  dynId: string = '';
  content: string = '';
  pic: string = '';
  bvid: string = '';
  aid: number = 0;
  title: string = '';
  timeText: string = '';
}

interface SpaceVideo {
  item: VideoItem;
  durationText: string;
}

@Entry
@Component
struct UserSpace {
  @State topInset: number = 0;
  @State bottomInset: number = 0;
  @State loading: boolean = true;
  @State loadingVideos: boolean = false;
  @State loadError: string = '';
  @State profile: SpaceCardData = {
    name: '', face: '', sign: '', level: 0,
    followerCount: 0, followingCount: 0, likeCount: 0, videoCount: 0,
    followed: false, mutual: false, vipStatus: 0, vipType: 0
  };
  @State videos: SpaceVideo[] = [];
  @State videosPage: number = 1;
  @State isSelf: boolean = false;
  @State spaceTab: number = 0; // 0=主页 1=动态 2=投稿
  // UP 主页搜索（向左展开）与更多菜单
  @State spaceSearchVisible: boolean = false;
  @State spaceSearchInput: string = '';
  @State spaceSearchKeyword: string = '';
  @State moreSheetVisible: boolean = false;
  @State blacklisted: boolean = false;
  // UP 主动态
  @State spaceDynItems: SpaceDynItem[] = [];
  @State spaceDynLoading: boolean = false;
  @State spaceDynLoaded: boolean = false;
  // 上滑吸顶：滚动越过信息区后固定 tab 栏（仅保留返回/搜索/更多图标）
  @State spaceScrollOffset: number = 0;
  private spaceInfoHeight: number = 380;
  @State hasMoreVideos: boolean = true;
  private mid: number = 0;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    const params: Object | undefined = router.getParams() as Object | undefined;
    if (params !== undefined) {
      const record: Record<string, Object> = params as Record<string, Object>;
      this.mid = Number(record['mid'] ?? 0);
    }
    // 自己的主页：不显示关注/私信按钮
    const session: AuthSession | null = this.session();
    this.isSelf = session !== null && Number(session.uid) === this.mid;
    this.updateSystemInsets();
    this.loadProfile();
    this.loadVideos(true);
  }

  private async updateSystemInsets(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = px2vp(systemArea.topRect.height);
      const navArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.bottomInset = px2vp(navArea.bottomRect.height);
    } catch (error) {
      console.error('Pilihos user space inset failed: ' + String(error));
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2500, bottom: 24 });
    } catch (error) {
      console.error(`Pilihos user space toast failed: ${String(error)}`);
    }
  }

  private session(): AuthSession | null {
    return AuthService.currentSession();
  }

  private async loadProfile(): Promise<void> {
    if (this.mid <= 0) {
      this.loadError = 'UP主信息缺失';
      this.loading = false;
      return;
    }
    this.loading = true;
    this.loadError = '';
    try {
      const query: Record<string, string> = {};
      query['mid'] = String(this.mid);
      query['photo'] = 'true';
      const result: Record<string, Object> =
        await BiliHttpClient.getJson('/x/web-interface/card', query, this.cookieValue());
      const code: number = Number(result['code'] ?? -1);
      if (code !== 0) throw new Error(String(result['message'] ?? 'UP主信息获取失败'));
      const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
      const card: Record<string, Object> = (data['card'] ?? {}) as Record<string, Object>;
      const levelInfo: Record<string, Object> = (card['level_info'] ?? {}) as Record<string, Object>;
      let attr: number = Number(card['attribute'] ?? -1);
      // card.attribute 缺失/为 0 时（登录态）用专属关系接口确认，避免误报未关注
      if (attr < 2 && this.cookieValue() !== '') {
        try {
          const relQuery: Record<string, string> = {};
          relQuery['fid'] = String(this.mid);
          const relResult: Record<string, Object> =
            await BiliHttpClient.getJson('/x/relation', relQuery, this.cookieValue());
          if (Number(relResult['code'] ?? -1) === 0) {
            const relData: Record<string, Object> = (relResult['data'] ?? {}) as Record<string, Object>;
            const relAttr: number = Number(relData['attribute'] ?? -1);
            if (relAttr >= 0) attr = relAttr;
          }
        } catch (relationError) {
          console.warn(`Pilihos user space relation confirm failed: ${String(relationError)}`);
        }
      }
      this.profile = {
        name: String(card['name'] ?? '未知用户'),
        face: String(card['face'] ?? ''),
        sign: String(card['sign'] ?? ''),
        level: Number(levelInfo['current_level'] ?? 0),
        followerCount: Number(data['follower'] ?? 0),
        followingCount: 0,
        likeCount: Number(data['like_num'] ?? 0),
        videoCount: Number(card['arc_count'] ?? 0),
        // attribute 语义：2=已关注，6=互相关注（0/缺失=未关注，登录态下再用 /x/relation 确认）
        followed: attr === 2 || attr === 6,
        mutual: attr === 6,
        vipStatus: Number(card['vipStatus'] ?? 0),
        vipType: Number(card['vipType'] ?? 0)
      };
      // 关注数补拉（card 不含 following）
      try {
        const statQuery: Record<string, string> = {};
        statQuery['mid'] = String(this.mid);
        const statResult: Record<string, Object> =
          await BiliHttpClient.getJson('/x/relation/stat', statQuery, this.cookieValue());
        if (Number(statResult['code'] ?? -1) === 0) {
          const statData: Record<string, Object> = (statResult['data'] ?? {}) as Record<string, Object>;
          this.profile.followingCount = Number(statData['following'] ?? 0);
        }
      } catch (_statError) {
        // 静默：关注数缺失不影响页面
      }
    } catch (error) {
      this.loadError = `UP主信息获取失败: ${String(error)}`;
      console.error(`Pilihos user space profile failed: ${String(error)}`);
    } finally {
      this.loading = false;
    }
  }

  private cookieValue(): string {
    const session: AuthSession | null = this.session();
    return session === null ? '' : session.cookie;
  }

  private async loadVideos(refresh: boolean, keyword: string = this.spaceSearchKeyword): Promise<void> {
    if (this.mid <= 0 || this.loadingVideos) return;
    if (!refresh && !this.hasMoreVideos) return;
    this.loadingVideos = true;
    const nextPage: number = refresh ? 1 : this.videosPage + 1;
    try {
      const pairs: string[] = [
        `mid=${this.mid}`,
        `pn=${nextPage}`,
        'ps=25',
        'order=pubdate'
      ];
      if (keyword !== '') {
        pairs.push(`keyword=${keyword}`);
      }
      const signed: string = await WbiService.sign(pairs);
      const result: Record<string, Object> =
        await BiliHttpClient.getJsonQuery('/x/space/wbi/arc/search', signed, this.cookieValue());
      const code: number = Number(result['code'] ?? -1);
      if (code === -404) {
        this.hasMoreVideos = false;
        if (refresh) this.videos = [];
        return;
      }
      if (code !== 0) throw new Error(String(result['message'] ?? '投稿获取失败'));
      const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
      const list: Record<string, Object> = (data['list'] ?? {}) as Record<string, Object>;
      const vlist: Object[] = (list['vlist'] as Object[]) ?? [];
      const items: SpaceVideo[] = [];
      vlist.forEach((raw: Object): void => {
        const record: Record<string, Object> = raw as Record<string, Object>;
        const aid: number = Number(record['aid'] ?? 0);
        const bvid: string = String(record['bvid'] ?? '');
        if (aid <= 0 && bvid === '') return;
        items.push({
          item: {
            id: aid > 0 ? aid : 1,
            aid: aid,
            bvid: bvid,
            cid: 0,
            title: String(record['title'] ?? ''),
            author: String(record['author'] ?? this.profile.name),
            cover: String(record['pic'] ?? ''),
            viewCount: Number(record['play'] ?? 0),
            danmuCount: Number(record['video_review'] ?? 0),
            likeCount: 0,
            commentCount: 0,
            followed: false,
            duration: UserSpace.parseLength(String(record['length'] ?? '')),
            playUrl: '',
            placeholder: false,
            publishTime: Number(record['created'] ?? 0),
            description: String(record['description'] ?? ''),
            tags: [],
            detailLoaded: false
          },
          durationText: String(record['length'] ?? '')
        });
      });
      if (refresh) {
        this.videos = items;
        this.profile.videoCount = Number(data['page'] !== undefined
          ? ((data['page'] as Record<string, Object>)['count'] ?? this.profile.videoCount)
          : this.profile.videoCount);
      } else {
        this.videos = this.videos.concat(items);
      }
      this.videosPage = nextPage;
      this.hasMoreVideos = items.length >= 25;
    } catch (error) {
      this.showToast(`投稿获取失败: ${String(error)}`);
      console.error(`Pilihos user space videos failed: ${String(error)}`);
    } finally {
      this.loadingVideos = false;
    }
  }

  private static parseLength(value: string): number {
    const parts: string[] = value.split(':');
    if (parts.length === 2) return Number(parts[0]) * 60 + Number(parts[1]);
    if (parts.length === 3) return Number(parts[0]) * 3600 + Number(parts[1]) * 60 + Number(parts[2]);
    return 0;
  }

  // UP 主动态：space_history 老接口（host_uid + need_top）
  private async loadSpaceDynamics(): Promise<void> {
    if (this.mid <= 0 || this.spaceDynLoading) return;
    this.spaceDynLoading = true;
    try {
      const query: Record<string, string> = {};
      query['host_uid'] = String(this.mid);
      query['need_top'] = '1';
      const result: Record<string, Object> = await BiliHttpClient.getJsonHost(
        'api.vc.bilibili.com', '/dynamic_svr/v1/dynamic_svr/space_history', query,
        this.cookieValue());
      const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
      const cards: Object[] = ((data['cards'] ?? []) as Object[]);
      const items: SpaceDynItem[] = [];
      cards.forEach((cardRaw: Object): void => {
        try {
          const card: Record<string, Object> = cardRaw as Record<string, Object>;
          const desc: Record<string, Object> = (card['desc'] ?? {}) as Record<string, Object>;
          const dynId: string = String(desc['dynamic_id'] ?? '');
          const timestamp: number = Number(desc['timestamp'] ?? 0);
          const cardData: Record<string, Object> =
            JSON.parse(String(card['card'] ?? '{}')) as Record<string, Object>;
          const dyn: SpaceDynItem = new SpaceDynItem();
          dyn.dynId = dynId;
          dyn.timeText = timestamp > 0 ? this.formatDynTime(timestamp) : '';
          const itemType: number = Number(desc['type'] ?? 0);
          if (itemType === 8) {
            // 视频动态
            dyn.content = String(cardData['title'] ?? '');
            dyn.pic = String(cardData['pic'] ?? '');
            dyn.bvid = String(cardData['bvid'] ?? '');
            dyn.aid = Number(cardData['aid'] ?? 0);
            dyn.title = dyn.content;
          } else if (itemType === 4) {
            // 纯文本动态
            const item: Record<string, Object> = (cardData['item'] ?? {}) as Record<string, Object>;
            dyn.content = String(item['content'] ?? '');
          } else if (itemType === 64) {
            // 专栏
            dyn.content = String(cardData['title'] ?? '');
          } else {
            dyn.content = '[转发或特殊动态]';
          }
          if (dyn.content !== '') items.push(dyn);
        } catch (rowError) {
          console.warn(`Pilihos space dynamic parse failed: ${String(rowError)}`);
        }
      });
      this.spaceDynItems = items;
      this.spaceDynLoaded = true;
    } catch (error) {
      console.error(`Pilihos space dynamics failed: ${String(error)}`);
      this.showToast(`动态加载失败: ${String(error)}`);
    } finally {
      this.spaceDynLoading = false;
    }
  }

  private formatDynTime(timestamp: number): string {
    const date: Date = new Date(timestamp * 1000);
    const pad = (value: number): string => String(value).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  }

  private submitSpaceSearch(): void {
    this.spaceSearchKeyword = this.spaceSearchInput.trim();
    this.videosPage = 1;
    this.hasMoreVideos = true;
    this.videos = [];
    this.spaceTab = 2;
    this.loadVideos(true, this.spaceSearchKeyword);
  }

  // 更多菜单：分享主页 / 进入黑屋 / 举报用户
  private shareSpaceHome(): void {
    try {
      const sharedData: systemShare.SharedData = new systemShare.SharedData({
        utd: 'general.url',
        uri: `https://space.bilibili.com/${this.mid}`
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(sharedData);
      controller.show(this.context, { selectionMode: systemShare.SelectionMode.SINGLE })
        .catch((error: BusinessError): void => {
          this.showToast(`分享失败 [错误码: ${String(error.code)}]`);
        });
    } catch (shareError) {
      this.showToast(`分享失败: ${String(shareError)}`);
    }
  }

  // 拉黑/取消拉黑：relation/modify act 5/6
  private async toggleBlacklist(): Promise<void> {
    const session: AuthSession | null = this.session();
    if (session === null || session.cookie === '' || session.csrf === '') {
      this.showToast('请先登录');
      return;
    }
    try {
      const block: boolean = !this.blacklisted;
      const form: Record<string, string> = {};
      form['fid'] = String(this.mid);
      form['act'] = block ? '5' : '6';
      form['re_src'] = '11';
      form['csrf'] = session.csrf;
      const result: Record<string, Object> =
        await BiliHttpClient.postForm('/x/relation/modify', form, session.cookie);
      if (Number(result['code'] ?? -1) !== 0) {
        throw new Error(String(result['message'] ?? '操作失败'));
      }
      this.blacklisted = block;
      this.moreSheetVisible = false;
      this.showToast(block ? '已拉黑该用户' : '已取消拉黑');
    } catch (error) {
      this.showToast(`拉黑操作失败: ${String(error)}`);
    }
  }

  private async toggleFollow(): Promise<void> {
    const session: AuthSession | null = this.session();
    if (session === null || session.cookie === '' || session.csrf === '') {
      this.showToast('请先登录后再关注');
      return;
    }
    const on: boolean = !this.profile.followed;
    try {
      const form: Record<string, string> = {};
      form['fid'] = String(this.mid);
      form['act'] = on ? '1' : '2';
      form['re_src'] = '11';
      form['csrf'] = session.csrf;
      const result: Record<string, Object> =
        await BiliHttpClient.postForm('/x/relation/modify', form, session.cookie);
      const code: number = Number(result['code'] ?? -1);
      if (code !== 0) throw new Error(`${code}: ${String(result['message'] ?? '操作失败')}`);
      this.profile.followed = on;
      if (!on) this.profile.mutual = false;
      this.showToast(on ? `已关注 ${this.profile.name}` : '已取消关注');
    } catch (error) {
      this.showToast(`关注操作失败: ${String(error)}`);
    }
  }

  // 关注方式菜单（与视频区三选项一致）
  @Builder
  followOptionsMenu() {
    Column({ space: 2 }) {
      Text('只是关注').fontSize(13).fontColor('#1E252D')
        .width(124).height(34).textAlign(TextAlign.Center)
        .onClick((): void => { this.toggleFollow(); });
      Text('特别关注').fontSize(13).fontColor('#1E252D')
        .width(124).height(34).textAlign(TextAlign.Center)
        .onClick((): void => { this.toggleFollow(); });
      Text('设置分组').fontSize(13).fontColor('#1E252D')
        .width(124).height(34).textAlign(TextAlign.Center)
        .onClick((): void => { this.showToast('分组管理开发中，敬请期待'); });
    }.padding({ top: 6, bottom: 6 }).backgroundColor(Color.Transparent);
  }

  @Builder
  unfollowMenu() {
    Column({ space: 2 }) {
      Text('取消关注').fontSize(13).fontColor('#1E252D')
        .width(124).height(34).textAlign(TextAlign.Center)
        .onClick((): void => { this.toggleFollow(); });
    }.padding({ top: 6, bottom: 6 }).backgroundColor(Color.Transparent);
  }

  @Builder
  unblockMenu() {
    Column({ space: 2 }) {
      Text('取消拉黑').fontSize(13).fontColor('#1E252D')
        .width(124).height(34).textAlign(TextAlign.Center)
        .onClick((): void => { this.toggleBlacklist(); });
    }.padding({ top: 6, bottom: 6 }).backgroundColor(Color.Transparent);
  }

  // 更多操作底部弹窗：分享主页 / 进入黑屋 / 举报用户
  @Builder
  moreSheet() {
    Column({ space: 0 }) {
      Row() {
        Text('分享主页').fontSize(15).fontColor('#1E252D').layoutWeight(1);
      }
      .width('100%').padding({ left: 18, right: 18, top: 16, bottom: 16 })
      .onClick((): void => {
        this.moreSheetVisible = false;
        this.shareSpaceHome();
      });
      Divider().strokeWidth(0.5).color('#1A000000');
      Row() {
        Text(this.blacklisted ? '取消拉黑' : '进入黑屋')
          .fontSize(15).fontColor(this.blacklisted ? '#1E252D' : '#C51D2A').layoutWeight(1);
      }
      .width('100%').padding({ left: 18, right: 18, top: 16, bottom: 16 })
      .onClick((): void => {
        this.toggleBlacklist();
      });
      Divider().strokeWidth(0.5).color('#1A000000');
      Row() {
        Text('举报用户').fontSize(15).fontColor('#1E252D').layoutWeight(1);
      }
      .width('100%').padding({ left: 18, right: 18, top: 16, bottom: this.bottomInset + 16 })
      .onClick((): void => {
        this.moreSheetVisible = false;
        router.pushUrl({
          url: 'pages/WebBrowser',
          params: { url: 'https://www.bilibili.com/appeal/', title: '举报用户' }
        }).catch((_error: Object): void => { });
      });
    }
    .width('100%').alignItems(HorizontalAlign.Start);
  }

  private openVideo(spaceVideo: SpaceVideo): void {
    const index: number = this.videos.indexOf(spaceVideo);
    if (index < 0) return;
    const items: VideoItem[] = this.videos.map((entry: SpaceVideo): VideoItem => entry.item);
    try {
      router.back({
        url: 'pages/Index',
        params: {
          pilihosPlayback: {
            results: items,
            index: index,
            nonce: `${Date.now()}-${index}`
          }
        }
      });
    } catch (error) {
      console.error('Pilihos user space play failed: ' + String(error));
    }
  }

  @Builder
  spaceVideoCard(spaceVideo: SpaceVideo) {
    Row({ space: 12 }) {
      Stack() {
        Image(spaceVideo.item.cover).width('100%').height('100%').objectFit(ImageFit.Cover)
          .borderRadius(10);
        Text(spaceVideo.durationText)
          .fontSize(11).fontColor(Color.White).backgroundColor('#B0000000')
          .padding({ left: 5, right: 5, top: 3, bottom: 3 }).borderRadius(4)
          .position({ right: 5, bottom: 5 });
      }.width('42%').aspectRatio(16 / 9);
      Column({ space: 7 }) {
        Text(spaceVideo.item.title).fontSize(16).fontColor('#20242A').maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        Row({ space: 12 }) {
          Text(FormatUtils.formatCount(spaceVideo.item.viewCount) + '播放')
            .fontSize(12).fontColor('#8B9199');
          Text(FormatUtils.formatCount(spaceVideo.item.danmuCount) + '弹幕')
            .fontSize(12).fontColor('#8B9199');
          Text(FormatUtils.formatPublishTime(spaceVideo.item.publishTime))
            .fontSize(12).fontColor('#8B9199');
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(Color.White)
    .onClick((): void => { this.openVideo(spaceVideo); });
  }

  // 主页 tab 的两列视频缩略卡
  @Builder
  spaceGridCard(spaceVideo: SpaceVideo) {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Image(spaceVideo.item.cover === '' ? $r('app.media.img') : spaceVideo.item.cover)
          .width('100%').aspectRatio(1.6).objectFit(ImageFit.Cover).borderRadius(8);
        Text(spaceVideo.durationText).fontSize(10).fontColor(Color.White)
          .backgroundColor('#B0000000').padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .borderRadius(4).margin(6);
      }.width('100%');
      Text(spaceVideo.item.title).fontSize(13).fontColor('#20242A')
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(18).width('100%');
    }
    .alignItems(HorizontalAlign.Start)
    .onClick((): void => { this.openSpaceVideo(spaceVideo); });
  }

  private openSpaceVideo(spaceVideo: SpaceVideo): void {
    router.pushUrl({
      url: 'pages/HotDetail',
      params: { hotItem: spaceVideo.item }
    }).catch((error: Object): void => {
      console.error('Pilihos space video open failed: ' + String(error));
    });
  }

  @Builder
  spaceTabBar() {
    Row() {
      this.spaceTabItem('主页', 0);
      this.spaceTabItem('动态', 1);
      this.spaceTabItem('投稿', 2);
    }.width('100%').height(42)
      .border({ width: { bottom: 1 }, color: '#E5E8EC' });
  }

  @Builder
  spaceTabItem(label: string, index: number) {
    Column({ space: 4 }) {
      Text(label).fontSize(15)
        .fontColor(this.spaceTab === index ? '#1288FA' : '#59616B')
        .fontWeight(this.spaceTab === index ? FontWeight.Bold : FontWeight.Normal);
      Row().width(28).height(3).borderRadius(1.5)
        .backgroundColor(this.spaceTab === index ? '#1288FA' : Color.Transparent);
    }.layoutWeight(1)
      .onClick((): void => {
        this.spaceTab = index;
        // 动态 tab：拉取该 UP 的动态
        if (index === 1 && !this.spaceDynLoaded && !this.spaceDynLoading) {
          this.loadSpaceDynamics();
        }
      });
  }

  @Builder
  spaceStat(value: string, label: string) {
    Column({ space: 3 }) {
      Text(value).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#20242A');
      Text(label).fontSize(11).fontColor('#858C94');
    }.layoutWeight(1).alignItems(HorizontalAlign.Center);
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
    Column() {
      // 顶部横幅：UP 头像铺底虚化承载（space 接口未提供 banner 图）
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.profile.face !== '') {
          Image(this.profile.face).width('100%').height(190).objectFit(ImageFit.Cover)
            .blur(46);
        } else {
          Column().width('100%').height(190)
            .linearGradient({ angle: 135, colors: [['#59B0E8', 0], ['#3E7BC0', 1]] });
        }
        Row() {
          Button() {
            Image($r('app.media.fanhui_left')).width(24).height(24).fillColor(Color.White);
          }
          .type(ButtonType.ROUNDED_RECTANGLE).width(42).height(42)
          .backgroundColor('#33000000').borderRadius(21)
          .onClick(() => { router.back(); });
          Blank();
          Button() {
            Image($r('app.media.serch')).width(20).height(20).fillColor(Color.White);
          }
          .type(ButtonType.ROUNDED_RECTANGLE).width(42).height(42)
          .backgroundColor('#33000000').borderRadius(21)
          .margin({ right: 10 })
          .onClick(() => { this.spaceSearchVisible = !this.spaceSearchVisible; });
          Button() {
            Image($r('app.media.more')).width(20).height(20).fillColor(Color.White);
          }
          .type(ButtonType.ROUNDED_RECTANGLE).width(42).height(42)
          .backgroundColor('#33000000').borderRadius(21)
          .onClick(() => { this.moreSheetVisible = true; });
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: this.topInset + 8 });
      }.width('100%').height(190);

      // 主页内搜索：展开后键入关键词搜索该UP主的投稿
      if (this.spaceSearchVisible) {
        Row({ space: 8 }) {
          TextInput({ placeholder: '搜索该UP主的视频', text: this.spaceSearchInput })
            .layoutWeight(1).height(36).fontSize(13)
            .backgroundColor('#FFFFFF').borderRadius(18)
            .onChange((value: string) => { this.spaceSearchInput = value; })
            .onSubmit((): void => { this.submitSpaceSearch(); });
          Button('搜索').height(34).fontSize(13)
            .backgroundColor('#1288FA')
            .onClick((): void => { this.submitSpaceSearch(); });
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 });
      }

      // 头像 + 三列统计（头像上移压住横幅）
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          if (this.profile.face !== '') {
            Image(this.profile.face).width(92).height(92).borderRadius(46)
              .objectFit(ImageFit.Cover)
              .border({ width: 3, color: Color.White });
          } else {
            Image($r('app.media.user_me')).width(92).height(92).borderRadius(46)
              .border({ width: 3, color: Color.White });
          }
          Image(FormatUtils.levelBadge(this.profile.level)).width(26).height(16)
            .objectFit(ImageFit.Contain)
            .backgroundColor(Color.White).borderRadius(8)
            .margin({ bottom: 2 });
        }.width(92).height(92).margin({ top: -34 });

        Row() {
          this.spaceStat(FormatUtils.formatCount(this.profile.followerCount), '粉丝');
          Row().width(1).height(28).backgroundColor('#E5E8EC');
          this.spaceStat(FormatUtils.formatCount(this.profile.followingCount), '关注');
          Row().width(1).height(28).backgroundColor('#E5E8EC');
          this.spaceStat(FormatUtils.formatCount(this.profile.likeCount), '获赞');
        }.layoutWeight(1);
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 6, bottom: 4 })
      .alignItems(VerticalAlign.Bottom);

      // 私信 + 关注按钮（自己的主页不显示；关注减宽靠右，拉黑态显示"取消拉黑"）
      if (!this.isSelf) {
        Row({ space: 12 }) {
          Blank().layoutWeight(1);
          Button() {
            Image($r('app.media.hf')).width(22).height(22).fillColor('#3E4854');
          }
          .type(ButtonType.ROUNDED_RECTANGLE).width(52).height(36)
          .backgroundColor('#FFFFFF').borderRadius(18)
          .border({ width: 1, color: '#E5E8EC' })
          .onClick((): void => {
            router.pushUrl({
              url: 'pages/ChatPage',
              params: { mid: this.mid, name: this.profile.name, face: this.profile.face }
            }).catch((_error: Object): void => { });
          });
          Button(this.blacklisted ? '取消拉黑'
            : (this.profile.mutual ? '互相关注'
              : (this.profile.followed ? '已关注' : '关注')))
            .height(36).fontSize(14)
            .width(96)
            .padding(0)
            .backgroundColor(this.blacklisted ? '#F1F3F5'
              : (this.profile.followed ? '#F1F3F5' : '#E5F3FA'))
            .fontColor(this.blacklisted ? '#59616B'
              : (this.profile.followed ? '#59616B' : '#1288FA'))
            .bindMenu(!this.blacklisted && (this.profile.followed || this.profile.mutual)
              ? this.unfollowMenu() : (!this.blacklisted ? this.followOptionsMenu() : this.unblockMenu()),
              { placement: Placement.Bottom });
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 4 });
      }

      // 昵称 + 签名 + UID
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(this.profile.name).fontSize(20).fontWeight(FontWeight.Bold).fontColor('#20242A')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          Image(FormatUtils.levelBadge(this.profile.level)).width(48).height(26).objectFit(ImageFit.Contain);
          if (this.profile.vipType === 2) {
            // 年度大会员标识
            Text('年度大会员').fontSize(10).fontColor('#E6B422')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('#33E6B422').borderRadius(8);
          } else if (this.profile.vipStatus > 0) {
            Text('大会员').fontSize(10).fontColor('#E6B422')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .backgroundColor('#33E6B422').borderRadius(8);
          }
        }
        if (this.profile.sign !== '') {
          Text(this.profile.sign).fontSize(13).fontColor('#3E4854').lineHeight(19).width('100%');
        }
        Text(`UID： ${this.mid}`).fontSize(12).fontColor('#9499A0').width('100%');
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 });

      this.spaceTabBar();

      if (this.loading) {
        Column() {
          LoadingProgress().width(30).height(30).color('#1288FA');
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadError !== '') {
        Column({ space: 10 }) {
          Text(this.loadError).fontSize(14).fontColor('#8B9199');
          Button('重新加载').height(36).onClick(() => {
            this.loadProfile();
            this.loadVideos(true);
          });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column() {
            if (this.spaceTab === 0) {
              // 主页：视频预览两列 + 图文占位
              Row({ space: 6 }) {
                Text('视频').fontSize(16).fontWeight(FontWeight.Bold);
                Text(String(this.profile.videoCount)).fontSize(13).fontColor('#9499A0');
                Blank();
                if (this.videos.length > 0) {
                  Text('查看更多').fontSize(13).fontColor('#9499A0')
                    .onClick((): void => { this.spaceTab = 2; });
                }
              }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 8 });
              if (this.videos.length === 0 && !this.loadingVideos) {
                Text('暂无投稿').fontSize(13).fontColor('#8B9199').width('100%')
                  .textAlign(TextAlign.Center).padding({ top: 24, bottom: 24 });
              }
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(this.videos.slice(0, 6), (spaceVideo: SpaceVideo) => {
                  Column() {
                    this.spaceGridCard(spaceVideo);
                  }
                  .width('48%')
                  .margin({ right: '2%', bottom: 12 });
                }, (spaceVideo: SpaceVideo) => `grid_${spaceVideo.item.id}`);
              }.width('100%').padding({ left: 12, right: 4 });
              Text('图文')
                .fontSize(16).fontWeight(FontWeight.Bold)
                .width('100%').padding({ left: 16, top: 8, bottom: 8 });
              Text('暂无图文').fontSize(13).fontColor('#8B9199').width('100%')
                .textAlign(TextAlign.Center).padding({ top: 16, bottom: 16 });
            } else if (this.spaceTab === 1) {
              // 该 UP 的动态（space_history）
              if (this.spaceDynLoading) {
                Column() {
                  LoadingProgress().width(26).height(26).color('#1288FA');
                }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 24 });
              } else if (this.spaceDynItems.length === 0) {
                Text('暂无动态').fontSize(13).fontColor('#8B9199').width('100%')
                  .textAlign(TextAlign.Center).padding({ top: 24, bottom: 24 });
              } else {
                ForEach(this.spaceDynItems, (dyn: SpaceDynItem) => {
                  Column({ space: 8 }) {
                    Row({ space: 8 }) {
                      if (this.profile.face !== '') {
                        Image(this.profile.face).width(34).height(34).borderRadius(17)
                          .objectFit(ImageFit.Cover);
                      } else {
                        Image($r('app.media.user_me')).width(34).height(34).borderRadius(17);
                      }
                      Column({ space: 2 }) {
                        Text(this.profile.name).fontSize(13).fontWeight(FontWeight.Medium)
                          .fontColor('#1E252D');
                        Text(dyn.timeText).fontSize(10).fontColor('#9499A0');
                      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
                    }.width('100%');
                    if (dyn.content !== '') {
                      Text(dyn.content).fontSize(14).fontColor('#1E252D').lineHeight(20)
                        .width('100%');
                    }
                    if (dyn.pic !== '' && dyn.bvid !== '') {
                      Stack({ alignContent: Alignment.BottomEnd }) {
                        Image(dyn.pic).width('100%').height(150).objectFit(ImageFit.Cover)
                          .borderRadius(8);
                        if (dyn.title !== '') {
                          Text(dyn.title).fontSize(11).fontColor(Color.White)
                            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                            .padding({ left: 6, right: 6, bottom: 4 })
                            .backgroundColor('#99000000');
                        }
                      }.width('100%')
                        .onClick((): void => {
                          const dynVideo: VideoItem = {
                            id: dyn.aid, aid: dyn.aid, bvid: dyn.bvid, cid: 0,
                            title: dyn.title, author: this.profile.name,
                            authorMid: this.mid, cover: dyn.pic,
                            viewCount: 0, danmuCount: 0, likeCount: 0, commentCount: 0,
                            followed: false, duration: 0, playUrl: '', placeholder: false,
                            publishTime: 0, description: '', tags: [], detailLoaded: false
                          };
                          router.pushUrl({
                            url: 'pages/HotDetail',
                            params: { hotItem: dynVideo }
                          }).catch((_error: Object): void => { });
                        });
                    }
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor('#FFFFFF')
                  .borderRadius(12);
                }, (dyn: SpaceDynItem) => `sdyn_${dyn.dynId}`);
              }
            } else {
              Column({ space: 12 }) {
                if (this.videos.length === 0 && !this.loadingVideos) {
                  Text('暂无投稿').fontSize(14).fontColor('#8B9199').width('100%')
                    .textAlign(TextAlign.Center).padding({ top: 30, bottom: 30 });
                }
                ForEach(this.videos, (spaceVideo: SpaceVideo) => {
                  this.spaceVideoCard(spaceVideo);
                }, (spaceVideo: SpaceVideo) => `uv_${spaceVideo.item.id}`);
                if (this.loadingVideos) {
                  Row({ space: 8 }) {
                    LoadingProgress().width(22).height(22).color('#1288FA');
                    Text('正在加载投稿').fontSize(13).fontColor('#8B9199');
                  }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 10, bottom: 10 });
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 10, right: 10, bottom: 30 });
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start);
        }
        .layoutWeight(1).width('100%').scrollBar(BarState.Off)
        .align(Alignment.Top)
        .onDidScroll((offset: number, _state: ScrollState): void => {
          // 记录滚动位置驱动 tab 栏吸顶
          this.spaceScrollOffset = offset;
        })
        .onReachEnd((): void => { this.loadVideos(false); });
      }
    }.width('100%').height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#F7F8FA')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .bindSheet($$this.moreSheetVisible, this.moreSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false
      });

      // 上滑吸顶栏：越过信息区后固定，仅保留返回/搜索/更多图标 + 页签
      if (this.spaceScrollOffset >= this.spaceInfoHeight) {
        Column() {
          Row({ space: 8 }) {
            Button() {
              Image($r('app.media.fanhui_left')).width(22).height(22);
            }
            .type(ButtonType.ROUNDED_RECTANGLE).width(36).height(36)
            .backgroundColor(Color.Transparent)
            .onClick(() => { router.back(); });
            Row() {
              this.spaceTabItem('主页', 0);
              this.spaceTabItem('动态', 1);
              this.spaceTabItem('投稿', 2);
            }.layoutWeight(1).height(36);
            Button() {
              Image($r('app.media.serch')).width(18).height(18).fillColor('#3E4854');
            }
            .type(ButtonType.ROUNDED_RECTANGLE).width(36).height(36)
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.spaceSearchVisible = !this.spaceSearchVisible; });
            Button() {
              Image($r('app.media.more')).width(18).height(18).fillColor('#3E4854');
            }
            .type(ButtonType.ROUNDED_RECTANGLE).width(36).height(36)
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.moreSheetVisible = true; });
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 2, bottom: 2 });
        }
        .width('100%')
        .padding({ top: this.topInset })
        .backgroundColor('#F7F8FA')
        .border({ width: { bottom: 1 }, color: '#E5E8EC' })
        .zIndex(40);
      }
    }.width('100%').height('100%');
  }
}
