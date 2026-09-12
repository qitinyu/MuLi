import router from '@ohos.router';
import window from '@ohos.window';
import common from '@ohos.app.ability.common';
import { BiliHttpClient } from '../services/BiliHttpClient';
import { AuthService, AuthSession } from '../services/AuthService';
import { VideoItem } from '../models/VideoItem';
import { FormatUtils } from '../utils/FormatUtils';

// 观看记录 / 稍后再看 条目
class WatchEntry {
  title: string = '';
  cover: string = '';
  author: string = '';
  authorMid: number = 0;
  aid: number = 0;
  bvid: string = '';
  cid: number = 0;
  duration: number = 0;
  progress: number = -1;
  timeText: string = '';
}

// 观看记录（/x/v2/history）与稍后再看（/x/v2/history/watchlater）列表页
@Entry
@Component
struct WatchListPage {
  @State mode: string = 'history';
  @State pageTitle: string = '观看记录';
  @State items: WatchEntry[] = [];
  @State loading: boolean = true;
  @State loadError: string = '';
  @State page: number = 1;
  @State hasMore: boolean = false;
  @State loadingMore: boolean = false;
  @State topInset: number = 0;
  @State bottomInset: number = 0;
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    const params: Object | undefined = router.getParams() as Object | undefined;
    if (params !== undefined) {
      const record: Record<string, Object> = params as Record<string, Object>;
      const mode: string = String(record['mode'] ?? 'history');
      this.mode = mode === 'watchlater' ? 'watchlater' : 'history';
      this.pageTitle = this.mode === 'watchlater' ? '稍后再看' : '观看记录';
    }
    this.updateSystemInsets();
    this.load(true);
  }

  private async updateSystemInsets(): Promise<void> {
    try {
      const mainWindow: window.Window = await window.getLastWindow(this.context);
      const systemArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.topInset = px2vp(systemArea.topRect.height);
      const navArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      this.bottomInset = px2vp(navArea.bottomRect.height);
    } catch (error) {
      console.error('Pilihos watch list inset failed: ' + String(error));
    }
  }

  private session(): AuthSession | null {
    return AuthService.currentSession();
  }

  private cookieValue(): string {
    const session: AuthSession | null = this.session();
    return session === null ? '' : session.cookie;
  }

  private async load(refresh: boolean): Promise<void> {
    if (this.loadingMore) return;
    if (this.cookieValue() === '') {
      this.loadError = '请先登录后查看';
      this.loading = false;
      return;
    }
    if (refresh) {
      this.loading = true;
      this.loadError = '';
      this.page = 1;
    } else {
      this.loadingMore = true;
    }
    try {
      if (this.mode === 'history') {
        const query: Record<string, string> = {};
        query['pn'] = String(this.page);
        query['ps'] = '20';
        const result: Record<string, Object> =
          await BiliHttpClient.getJson('/x/v2/history', query, this.cookieValue());
        if (Number(result['code'] ?? -1) !== 0) {
          throw new Error(String(result['message'] ?? '观看记录加载失败'));
        }
        const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
        const raw: Object[] = ((data['list'] ?? (Array.isArray(data) ? data : [])) as Object[]);
        const entries: WatchEntry[] = [];
        raw.forEach((value: Object): void => {
          try {
            const row: Record<string, Object> = value as Record<string, Object>;
            const history: Record<string, Object> = (row['history'] ?? {}) as Record<string, Object>;
            const entry: WatchEntry = new WatchEntry();
            entry.title = String(row['title'] ?? row['long_title'] ?? '未知视频');
            entry.cover = String(row['pic'] ?? '');
            entry.author = String(row['author'] ?? '');
            entry.authorMid = Number(row['author_mid'] ?? 0);
            entry.aid = Number(history['oid'] ?? 0);
            entry.bvid = String(history['bvid'] ?? '');
            entry.cid = Number(history['cid'] ?? 0);
            entry.duration = Number(row['duration'] ?? 0);
            entry.progress = Number(row['progress'] ?? -1);
            const viewAt: number = Number(row['view_at'] ?? 0);
            entry.timeText = viewAt > 0 ? FormatUtils.formatPublishTime(viewAt) : '';
            if (entry.aid > 0 || entry.bvid !== '') entries.push(entry);
          } catch (rowError) {
            console.warn(`Pilihos history row parse failed: ${String(rowError)}`);
          }
        });
        this.items = refresh ? entries : this.items.concat(entries);
        this.hasMore = entries.length >= 20;
      } else {
        const query: Record<string, string> = {};
        const result: Record<string, Object> =
          await BiliHttpClient.getJson('/x/v2/history/watchlater', query, this.cookieValue());
        if (Number(result['code'] ?? -1) !== 0) {
          throw new Error(String(result['message'] ?? '稍后再看加载失败'));
        }
        const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
        const raw: Object[] = ((data['list'] ?? []) as Object[]);
        const entries: WatchEntry[] = [];
        raw.forEach((value: Object): void => {
          try {
            const row: Record<string, Object> = value as Record<string, Object>;
            const upper: Record<string, Object> = (row['upper'] ?? {}) as Record<string, Object>;
            const entry: WatchEntry = new WatchEntry();
            entry.title = String(row['title'] ?? '未知视频');
            entry.cover = String(row['pic'] ?? '');
            entry.author = String(upper['name'] ?? '');
            entry.authorMid = Number(upper['mid'] ?? 0);
            entry.aid = Number(row['aid'] ?? 0);
            entry.bvid = String(row['bvid'] ?? '');
            entry.cid = Number(row['cid'] ?? 0);
            entry.duration = Number(row['duration'] ?? 0);
            entry.progress = Number(row['progress'] ?? -1);
            const addAt: number = Number(row['add_at'] ?? 0);
            entry.timeText = addAt > 0 ? FormatUtils.formatPublishTime(addAt) : '';
            if (entry.aid > 0 || entry.bvid !== '') entries.push(entry);
          } catch (rowError) {
            console.warn(`Pilihos watchlater row parse failed: ${String(rowError)}`);
          }
        });
        this.items = entries;
        this.hasMore = false;
      }
    } catch (error) {
      this.loadError = `${this.pageTitle}加载失败: ${String(error)}`;
      console.error(`Pilihos watch list failed: ${String(error)}`);
    } finally {
      this.loading = false;
      this.loadingMore = false;
    }
  }

  // 点击条目：组装最小视频对象进入详情页（播放由详情页回传主页）
  private openEntry(entry: WatchEntry): void {
    const video: VideoItem = {
      id: entry.aid,
      aid: entry.aid,
      bvid: entry.bvid,
      cid: entry.cid,
      title: entry.title,
      author: entry.author,
      authorMid: entry.authorMid,
      cover: entry.cover,
      viewCount: 0, danmuCount: 0, likeCount: 0, commentCount: 0,
      followed: false, duration: entry.duration, playUrl: '', placeholder: false,
      publishTime: 0, description: '', tags: [], detailLoaded: false
    };
    router.pushUrl({
      url: 'pages/HotDetail',
      params: { hotItem: video }
    }).catch((error: Object): void => {
      console.error('Pilihos watch entry open failed: ' + String(error));
    });
  }

  private formatSeconds(seconds: number): string {
    const total: number = Math.max(0, Math.floor(seconds));
    const minutes: number = Math.floor(total / 60);
    const secs: number = total % 60;
    return `${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  }

  @Builder
  entryRow(entry: WatchEntry) {
    Row({ space: 10 }) {
      Stack({ alignContent: Alignment.BottomStart }) {
        if (entry.cover !== '') {
          Image(entry.cover).width(128).height(80).borderRadius(8).objectFit(ImageFit.Cover);
        } else {
          Column() {
            Image($r('app.media.img')).width(26).height(26).opacity(0.5);
          }.width(128).height(80).borderRadius(8).backgroundColor('#E1E6EE')
            .justifyContent(FlexAlign.Center);
        }
        if (entry.duration > 0) {
          Text(this.formatSeconds(entry.duration)).fontSize(10).fontColor(Color.White)
            .backgroundColor('#B0000000').padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .borderRadius(3).margin(4);
        }
      }.width(128).height(80);
      Column({ space: 5 }) {
        Text(entry.title).fontSize(14).fontColor('#20242A').maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).lineHeight(19).width('100%');
        Text(entry.author === '' ? '未知UP主' : entry.author).fontSize(11).fontColor('#858C94')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
        Row({ space: 8 }) {
          if (entry.timeText !== '') {
            Text(entry.timeText).fontSize(10).fontColor('#A0A6AD');
          }
          if (this.mode === 'history' && entry.progress > 0) {
            // 观看进度：看完显示"已看完"，否则显示看到的时间点
            Text(entry.progress >= entry.duration && entry.duration > 0
              ? '已看完' : `看到 ${this.formatSeconds(entry.progress)}`)
              .fontSize(10).fontColor('#1288FA');
          }
        }.width('100%');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .onClick((): void => { this.openEntry(entry); });
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Button() {
          Image($r('app.media.fanhui_left')).width(24).height(24);
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(44).height(44)
        .backgroundColor(Color.Transparent)
        .onClick(() => { router.back(); });
        Text(this.pageTitle).fontSize(19).fontWeight(FontWeight.Bold).layoutWeight(1);
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: this.topInset + 6, bottom: 6 });

      if (this.loading) {
        Column() {
          LoadingProgress().width(30).height(30).color('#1288FA');
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.loadError !== '' && this.items.length === 0) {
        Column({ space: 10 }) {
          Text(this.loadError).fontSize(13).fontColor('#C51D2A')
            .width('100%').textAlign(TextAlign.Center);
          Button('重新加载').height(36).fontSize(13)
            .onClick((): void => { this.load(true); });
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else if (this.items.length === 0) {
        Column({ space: 8 }) {
          Text(`暂无${this.pageTitle}`).fontSize(14).fontColor('#8B9199');
          Text(this.mode === 'history' ? '观看过的视频将出现在这里' : '添加到稍后再看的视频将出现在这里')
            .fontSize(11).fontColor('#A0A6AD');
        }.layoutWeight(1).width('100%').justifyContent(FlexAlign.Center);
      } else {
        Scroll() {
          Column({ space: 0 }) {
            ForEach(this.items, (entry: WatchEntry) => {
              this.entryRow(entry);
            }, (entry: WatchEntry, index: number) => `${this.mode}_${entry.bvid}_${entry.aid}_${index}`);
            if (this.loadingMore) {
              Text('正在加载…').fontSize(12).fontColor('#8B9199').width('100%')
                .textAlign(TextAlign.Center).padding({ top: 10, bottom: 10 });
            }
            Column().height(this.bottomInset + 20).width('100%');
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .constraintSize({ minHeight: '100%' });
        }
        .layoutWeight(1).width('100%').scrollBar(BarState.Off)
        .align(Alignment.Top)
        .onReachEnd((): void => {
          if (this.mode === 'history' && this.hasMore && !this.loadingMore) {
            this.page += 1;
            this.load(false);
          }
        });
      }

      Column().height(this.bottomInset).width('100%');
    }
    .width('100%').height('100%')
    .backgroundColor('#F7F8FA');
  }
}
