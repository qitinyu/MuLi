import { VideoItem } from '../models/VideoItem';
import { BiliHttpClient } from '../services/BiliHttpClient';
import { AuthService, AuthSession } from '../services/AuthService';
import { WbiService } from '../services/WbiService';
import { FormatUtils } from '../utils/FormatUtils';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import router from '@ohos.router';
import common from '@ohos.app.ability.common';
import window from '@ohos.window';

interface SpaceCardData {
  name: string;
  face: string;
  sign: string;
  level: number;
  followerCount: number;
  likeCount: number;
  videoCount: number;
  followed: boolean;
}

interface SpaceVideo {
  item: VideoItem;
  durationText: string;
}

@Entry
@Component
struct UserSpace {
  @State topInset: number = 0;
  @State loading: boolean = true;
  @State loadingVideos: boolean = false;
  @State loadError: string = '';
  @State profile: SpaceCardData = {
    name: '', face: '', sign: '', level: 0,
    followerCount: 0, likeCount: 0, videoCount: 0, followed: false
  };
  @State videos: SpaceVideo[] = [];
  @State videosPage: number = 1;
  @State hasMoreVideos: boolean = true;
  private mid: number = 0;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    const params: Object | undefined = router.getParams() as Object | undefined;
    if (params !== undefined) {
      const record: Record<string, Object> = params as Record<string, Object>;
      this.mid = Number(record['mid'] ?? 0);
    }
    this.updateSystemInsets();
    this.loadProfile();
    this.loadVideos(true);
  }

  private async updateSystemInsets(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      const systemArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = px2vp(systemArea.topRect.height);
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
      this.profile = {
        name: String(card['name'] ?? '未知用户'),
        face: String(card['face'] ?? ''),
        sign: String(card['sign'] ?? ''),
        level: Number(levelInfo['current_level'] ?? 0),
        followerCount: Number(data['follower'] ?? 0),
        likeCount: Number(data['like_num'] ?? 0),
        videoCount: Number(card['arc_count'] ?? 0),
        followed: Number(card['attribute'] ?? 0) !== 0
      };
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

  private async loadVideos(refresh: boolean): Promise<void> {
    if (this.mid <= 0 || this.loadingVideos) return;
    if (!refresh && !this.hasMoreVideos) return;
    this.loadingVideos = true;
    const nextPage: number = refresh ? 1 : this.videosPage + 1;
    try {
      const signed: string = await WbiService.sign([
        `mid=${this.mid}`,
        `pn=${nextPage}`,
        'ps=25',
        'order=pubdate'
      ]);
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
      this.showToast(on ? `已关注 ${this.profile.name}` : '已取消关注');
    } catch (error) {
      this.showToast(`关注操作失败: ${String(error)}`);
    }
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
        Text(this.profile.name === '' ? 'UP主主页' : this.profile.name)
          .fontSize(20).fontWeight(FontWeight.Medium).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        Button(this.profile.followed ? '已关注' : '关注')
          .height(36).fontSize(14)
          .backgroundColor(this.profile.followed ? '#F1F3F5' : '#F04B55')
          .fontColor(this.profile.followed ? '#59616B' : Color.White)
          .onClick(() => { this.toggleFollow(); });
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: this.topInset + 8, bottom: 8 });

      if (this.loading) {
        Column() {
          LoadingProgress().width(30).height(30).color('#1677A8');
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
          Column({ space: 12 }) {
            Row({ space: 14 }) {
              if (this.profile.face !== '') {
                Image(this.profile.face).width(72).height(72).borderRadius(36).objectFit(ImageFit.Cover);
              } else {
                Image($r('app.media.user_me')).width(72).height(72).borderRadius(36).objectFit(ImageFit.Contain);
              }
              Column({ space: 5 }) {
                Row({ space: 6 }) {
                  Text(this.profile.name).fontSize(19).fontWeight(FontWeight.Bold)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                  Text('LV' + String(this.profile.level)).fontSize(10).fontColor(Color.White)
                    .backgroundColor(this.profile.level >= 6 ? '#E661A0' : this.profile.level >= 4 ? '#1677A8' : '#9AA4AE')
                    .borderRadius(3).padding({ left: 4, right: 4, top: 2, bottom: 2 });
                }
                Text(this.profile.sign === '' ? '这个人很懒，什么都没有留下' : this.profile.sign)
                  .fontSize(12).fontColor('#858C94').maxLines(2).lineHeight(17);
              }.layoutWeight(1).alignItems(HorizontalAlign.Start);
            }.width('100%').alignItems(VerticalAlign.Top);

            Row() {
              Column({ space: 3 }) {
                Text(FormatUtils.formatCount(this.profile.followerCount)).fontSize(17).fontWeight(FontWeight.Bold);
                Text('粉丝').fontSize(11).fontColor('#858C94');
              }.layoutWeight(1);
              Column({ space: 3 }) {
                Text(FormatUtils.formatCount(this.profile.likeCount)).fontSize(17).fontWeight(FontWeight.Bold);
                Text('获赞').fontSize(11).fontColor('#858C94');
              }.layoutWeight(1);
              Column({ space: 3 }) {
                Text(FormatUtils.formatCount(this.profile.videoCount)).fontSize(17).fontWeight(FontWeight.Bold);
                Text('投稿').fontSize(11).fontColor('#858C94');
              }.layoutWeight(1);
            }.width('100%').padding({ top: 10, bottom: 10 })
              .backgroundColor('#FFFFFF').borderRadius(12);

            if (this.videos.length === 0 && !this.loadingVideos) {
              Text('暂无投稿').fontSize(14).fontColor('#8B9199').width('100%')
                .textAlign(TextAlign.Center).padding({ top: 30, bottom: 30 });
            }
            ForEach(this.videos, (spaceVideo: SpaceVideo) => {
              this.spaceVideoCard(spaceVideo);
            }, (spaceVideo: SpaceVideo) => `uv_${spaceVideo.item.id}`);
            if (this.loadingVideos) {
              Row({ space: 8 }) {
                LoadingProgress().width(22).height(22).color('#1677A8');
                Text('正在加载投稿').fontSize(13).fontColor('#8B9199');
              }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 10, bottom: 10 });
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 10, right: 10, bottom: 30 });
        }
        .layoutWeight(1).width('100%').scrollBar(BarState.Off)
        .onDidScroll((_offset: number, _state: ScrollState): void => {
        })
        .onReachEnd((): void => { this.loadVideos(false); });
      }
    }.width('100%').height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor('#F7F8FA')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM]);
  }
}
