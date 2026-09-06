import { VideoItem } from '../models/VideoItem';
import { BiliHttpClient } from '../services/BiliHttpClient';
import { AuthService, AuthSession } from '../services/AuthService';
import { FormatUtils } from '../utils/FormatUtils';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';

class FavFolderInfo {
  id: number = 0;
  title: string = '';
  mediaCount: number = 0;
}

class FavMedia {
  aid: number = 0;
  bvid: string = '';
  title: string = '';
  cover: string = '';
  author: string = '';
  playCount: number = 0;
  danmuCount: number = 0;
  duration: number = 0;
}

@Entry
@Component
struct MyFav {
  @State topInset: number = 0;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State folders: FavFolderInfo[] = [];
  @State currentFolderId: number = 0;
  @State medias: FavMedia[] = [];
  @State mediasLoading: boolean = false;
  @State mediasPage: number = 1;
  @State hasMore: boolean = false;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.updateSystemInsets();
    this.loadFolders();
  }

  private async updateSystemInsets(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = px2vp(systemArea.topRect.height);
    } catch (error) {
      console.error('Pilihos my fav inset failed: ' + String(error));
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2500, bottom: 24 });
    } catch (error) {
      console.error(`Pilihos my fav toast failed: ${String(error)}`);
    }
  }

  private cookieValue(): string {
    const session: AuthSession | null = AuthService.currentSession();
    return session === null ? '' : session.cookie;
  }

  private async loadFolders(): Promise<void> {
    const session: AuthSession | null = AuthService.currentSession();
    if (session === null || session.cookie === '') {
      this.loading = false;
      this.loadError = '请先登录后查看收藏';
      return;
    }
    this.loading = true;
    this.loadError = '';
    try {
      const query: Record<string, string> = {};
      query['pn'] = '1';
      query['ps'] = '50';
      query['up_type'] = '0';
      query['mid'] = String(session.uid);
      const result: Record<string, Object> =
        await BiliHttpClient.getJson('/x/v3/fav/folder/created/list', query, session.cookie);
      const code: number = Number(result['code'] ?? -1);
      if (code !== 0) {
        throw new Error(`${code}: ${String(result['message'] ?? '收藏夹获取失败')}`);
      }
      const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
      const list: Object[] = (data['list'] as Object[]) ?? [];
      const folders: FavFolderInfo[] = [];
      list.forEach((raw: Object): void => {
        const record: Record<string, Object> = raw as Record<string, Object>;
        const folder: FavFolderInfo = new FavFolderInfo();
        folder.id = Number(record['id'] ?? 0);
        folder.title = String(record['title'] ?? '');
        folder.mediaCount = Number(record['media_count'] ?? 0);
        if (folder.id > 0) folders.push(folder);
      });
      this.folders = folders;
      if (folders.length > 0) {
        this.currentFolderId = folders[0].id;
        await this.loadMedias(true);
      } else {
        this.medias = [];
      }
    } catch (error) {
      this.loadError = `收藏夹获取失败: ${String(error)}`;
      console.error(`Pilihos my fav folders failed: ${String(error)}`);
    } finally {
      this.loading = false;
    }
  }

  private async loadMedias(refresh: boolean): Promise<void> {
    if (this.currentFolderId <= 0 || this.mediasLoading) return;
    if (!refresh && !this.hasMore) return;
    this.mediasLoading = true;
    const nextPage: number = refresh ? 1 : this.mediasPage + 1;
    try {
      const query: Record<string, string> = {};
      query['media_id'] = String(this.currentFolderId);
      query['pn'] = String(nextPage);
      query['ps'] = '20';
      query['keyword'] = '';
      query['order'] = 'mtime';
      query['type'] = '2';
      query['tid'] = '0';
      const result: Record<string, Object> =
        await BiliHttpClient.getJson('/x/v3/fav/resource/list', query, this.cookieValue());
      const code: number = Number(result['code'] ?? -1);
      if (code !== 0) {
        throw new Error(`${code}: ${String(result['message'] ?? '收藏内容获取失败')}`);
      }
      const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
      const rawList: Object[] = (data['medias'] as Object[]) ?? [];
      const items: FavMedia[] = [];
      rawList.forEach((raw: Object): void => {
        const record: Record<string, Object> = raw as Record<string, Object>;
        if (Number(record['type'] ?? 0) !== 2) return;
        const media: FavMedia = new FavMedia();
        media.aid = Number(record['id'] ?? 0);
        media.bvid = String(record['bvid'] ?? '');
        media.title = String(record['title'] ?? '');
        media.cover = String(record['cover'] ?? '');
        const upper: Record<string, Object> = (record['upper'] ?? {}) as Record<string, Object>;
        media.author = String(upper['name'] ?? '');
        const cntInfo: Record<string, Object> = (record['cnt_info'] ?? {}) as Record<string, Object>;
        media.playCount = Number(cntInfo['play'] ?? 0);
        media.danmuCount = Number(cntInfo['danmaku'] ?? 0);
        media.duration = Number(record['duration'] ?? 0);
        if (media.aid > 0 || media.bvid !== '') items.push(media);
      });
      this.medias = refresh ? items : this.medias.concat(items);
      this.mediasPage = nextPage;
      this.hasMore = Number(data['has_more'] ?? 0) === 1;
    } catch (error) {
      this.showToast(`收藏内容获取失败: ${String(error)}`);
      console.error(`Pilihos my fav medias failed: ${String(error)}`);
    } finally {
      this.mediasLoading = false;
    }
  }

  private selectFolder(folder: FavFolderInfo): void {
    if (this.currentFolderId === folder.id) return;
    this.currentFolderId = folder.id;
    this.medias = [];
    this.hasMore = false;
    this.loadMedias(true);
  }

  private openMedia(media: FavMedia): void {
    const items: VideoItem[] = this.medias.map((entry: FavMedia): VideoItem => {
      return {
        id: entry.aid,
        aid: entry.aid,
        bvid: entry.bvid,
        cid: 0,
        title: entry.title,
        author: entry.author,
        cover: entry.cover,
        viewCount: entry.playCount,
        danmuCount: entry.danmuCount,
        likeCount: 0,
        commentCount: 0,
        followed: false,
        duration: entry.duration,
        playUrl: '',
        placeholder: false,
        publishTime: 0,
        description: '',
        tags: [],
        detailLoaded: false
      };
    });
    const index: number = this.medias.indexOf(media);
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
      console.error('Pilihos my fav play failed: ' + String(error));
    }
  }

  private formatDuration(value: number): string {
    const totalSeconds: number = Math.max(0, Math.floor(value));
    const minutes: number = Math.floor(totalSeconds / 60);
    const seconds: number = totalSeconds % 60;
    return `${minutes}:${String(seconds).padStart(2, '0')}`;
  }

  @Builder
  favMediaCard(media: FavMedia) {
    Row({ space: 12 }) {
      Stack() {
        Image(media.cover).width('100%').height('100%').objectFit(ImageFit.Cover)
          .borderRadius(10);
        Text(this.formatDuration(media.duration))
          .fontSize(11).fontColor(Color.White).backgroundColor('#B0000000')
          .padding({ left: 5, right: 5, top: 3, bottom: 3 }).borderRadius(4)
          .position({ right: 5, bottom: 5 });
      }.width('42%').aspectRatio(16 / 9);
      Column({ space: 7 }) {
        Text(media.title).fontSize(15).fontColor('#20242A').maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        Text(media.author === '' ? '未知用户' : media.author).fontSize(12).fontColor('#8B9199')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        Row({ space: 12 }) {
          Text(FormatUtils.formatCount(media.playCount) + '播放').fontSize(12).fontColor('#8B9199');
          Text(FormatUtils.formatCount(media.danmuCount) + '弹幕').fontSize(12).fontColor('#8B9199');
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .backgroundColor(Color.White)
    .onClick((): void => { this.openMedia(media); });
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Button() {
          Image($r('app.media.fanhui_left')).width(24).height(24);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(48).height(48)
        .backgroundColor(ImmersiveMaterial.fallbackBackground())
        .borderRadius(24)
        .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
        .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
        .onClick(() => { router.back(); });
        Text('我的收藏').fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1);
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: this.topInset + 8, bottom: 8 });

      if (this.loading) {
        Column() {
          LoadingProgress().width(30).height(30).color('#1677A8');
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadError !== '') {
        Column({ space: 10 }) {
          Text(this.loadError).fontSize(14).fontColor('#8B9199').textAlign(TextAlign.Center);
          Button('重新加载').height(36).onClick(() => { this.loadFolders(); });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.folders.length === 0) {
        Column() {
          Text('暂无收藏夹').fontSize(14).fontColor('#8B9199');
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Row({ space: 10 }) {
            ForEach(this.folders, (folder: FavFolderInfo) => {
              Text(`${folder.title} ${folder.mediaCount}`).fontSize(13)
                .fontColor(this.currentFolderId === folder.id ? '#1677A8' : '#59616B')
                .fontWeight(this.currentFolderId === folder.id ? FontWeight.Bold : FontWeight.Normal)
                .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                .backgroundColor(this.currentFolderId === folder.id ? '#E5F3FA' : Color.White)
                .borderRadius(16)
                .onClick((): void => { this.selectFolder(folder); });
            }, (folder: FavFolderInfo) => `fav_${folder.id}`);
          }.padding({ left: 16, right: 16 });
        }.width('100%').height(46)
          .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off);

        if (this.medias.length === 0 && !this.mediasLoading) {
          Column() {
            Text('收藏夹暂无视频').fontSize(14).fontColor('#8B9199');
          }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
        } else {
          Scroll() {
            Column({ space: 10 }) {
              ForEach(this.medias, (media: FavMedia) => {
                this.favMediaCard(media);
              }, (media: FavMedia) => `media_${media.aid}_${media.bvid}`);
              if (this.mediasLoading) {
                Row({ space: 8 }) {
                  LoadingProgress().width(22).height(22).color('#1677A8');
                  Text('正在加载').fontSize(13).fontColor('#8B9199');
                }.width('100%').justifyContent(FlexAlign.Center).padding(10);
              }
            }.width('100%');
          }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
            .onReachEnd((): void => { this.loadMedias(false); });
        }
      }
    }.width('100%').height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#F7F8FA')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }
}
