import { VideoItem } from '../models/VideoItem';
import { VideoComment } from '../services/ReplyService';
import { BiliEmoji, EmojiService } from '../services/EmojiService';
import { AuthSession, AuthService } from '../services/AuthService';
import { EmojiSegment, EmojiText } from '../utils/EmojiText';
import { FormatUtils } from '../utils/FormatUtils';
import { loadingIndicator } from '../utils/CommonBuilders';
import { pasteboard } from '@kit.BasicServicesKit';
import { ImmersiveMaterial } from '../utils/ImmersiveMaterial';
import { MessageService, MentionContact } from '../services/MessageService';

// @切片：文本 + 命中的用户 mid（>0 表示可跳转）
class AtPiece {
  public text: string;
  public mid: number;

  constructor(text: string, mid: number) {
    this.text = text;
    this.mid = mid;
  }
}

@Component
export struct DetailScreen {
  @BuilderParam videoArea: () => void = this.emptyArea;
  @Link episodeListVisible: boolean;
  @State commentRefreshing: boolean = false;
  @State settingsRefreshing: boolean = false;
  @Consume emojiPanelVisible: boolean;
  @State verticalDescExpanded: boolean = false;
  @State chipNonce: number = 0;
  // 键入 @ 的联系人选择面板
  @State atPanelVisible: boolean = false;
  @State atSearchText: string = '';
  @State atContacts: MentionContact[] = [];
  @State atLoading: boolean = false;
  // 本轮手动 @ 过的用户（昵称→uid）：发布后本地渲染超链接兜底
  @State pickedAts: Map<string, number> = new Map<string, number>();
  @State commentMenuVisible: boolean = false;
  @State commentMenuComment: VideoComment | null = null;
  @State textSelectSheetVisible: boolean = false;
  @State textSelectContent: string = '';
  @Consume verticalExpanded: boolean;
  @Consume videoWeight: number;
  @Consume pendingResumeMs: number;
  @Consume @Watch('syncInteractionUI') videos: VideoItem[];
  @Consume relatedVideos: VideoItem[];
  @Consume relatedLoading: boolean;
  @Consume @Watch('syncInteractionUI') currentIndex: number;
  // 互动状态本地镜像：点击即时变色， videos/currentIndex 变化后由 @Watch 校准回真实值
  @State uiLiked: boolean = false;
  @State uiFavored: boolean = false;
  @State uiCoined: boolean = false;
  @Consume detailSection: number;
  @Consume detailExpanded: boolean;
  @Consume detailLoading: boolean;
  @Consume detailError: string;
  @Consume topInset: number;
  @Consume bottomInset: number;
  @Consume keyboardInset: number;
  @Consume authSession: AuthSession | null;
  @Consume danmakuText: string;
  @Consume danmakuEnabled: boolean;
  @Consume danmakuFontSize: number;
  @Consume danmakuOpacity: number;
  @Consume danmakuSpeed: number;
  @Consume danmakuArea: number;
  @Consume defaultSpeed: number;
  @Consume sequentialChain: boolean;
  @Consume emojiLoading: boolean;
  @Consume emojiItems: BiliEmoji[];
  @Consume recentEmojis: string[];
  @Consume @Watch('onCommentInputVisibleChange') showCommentInput: boolean;
  @Consume commentInputText: string;
  @Consume commentReplyTarget: string;
  @Consume comments: VideoComment[];
  @Consume commentTotal: number;
  @Consume commentLoading: boolean;
  @Consume commentError: string;
  @Consume commentHasMore: boolean;
  @Consume commentSort: string;
  @Consume expandedCommentId: number;
  @Consume subReplies: VideoComment[];
  @Consume subLoading: boolean;
  @Consume subHasMore: boolean;
  @Consume playbackCurrentMs: number;
  @Consume playbackDurationMs: number;
  @Consume playbackControlsVisible: boolean;
  @StorageProp('mini_progress_on') miniProgressOn: boolean = false;
  @Consume playMode: number;
  @Consume portraitBadge: boolean;
  private panStartWeight: number = 8;
  onOpenRelated: (item: VideoItem, showComments: boolean) => void =
    (item: VideoItem, showComments: boolean): void => {};
  onLoadComments: (refresh: boolean) => void = (refresh: boolean): void => {};
  onToggleReplies: (comment: VideoComment) => void = (comment: VideoComment): void => {};
  onLoadSubReplies: (rootId: number, refresh: boolean) => void =
    (rootId: number, refresh: boolean): void => {};
  onSubmitComment: () => void = (): void => {};
  onSendDanmaku: () => void = (): void => {};
  onDetailAction: (action: string) => void = (action: string): void => {};
  onLikeComment: (comment: VideoComment) => void = (comment: VideoComment): void => {};
  onOpenUser: (mid: number, name: string) => void = (mid: number, name: string): void => {};
  onToggleCommentSort: () => void = (): void => {};
  onReplyComment: (comment: VideoComment) => void = (comment: VideoComment): void => {};
  onReplySubReply: (rootId: number, reply: VideoComment) => void =
    (rootId: number, reply: VideoComment): void => {};
  onPickEmoji: (emoji: BiliEmoji) => void = (emoji: BiliEmoji): void => {};
  onDeleteComment: (comment: VideoComment) => void = (comment: VideoComment): void => {};
  onHideComment: (comment: VideoComment) => void = (comment: VideoComment): void => {};
  onReportComment: (comment: VideoComment) => void = (comment: VideoComment): void => {};
  onBlockComment: (comment: VideoComment) => void = (comment: VideoComment): void => {};
  onFollowAuthor: (on: boolean) => void = (on: boolean): void => {};
  onFollowGroup: () => void = (): void => {};
  onSetPlayMode: (mode: number) => void = (mode: number): void => {};
  onSetDanmakuFontSize: (size: number) => void = (size: number): void => {};
  onSetDanmakuArea: (area: number) => void = (area: number): void => {};
  onShowControls: () => void = (): void => {};
  onToggleControls: () => void = (): void => {};
  @State followMenuVisible: boolean = false;
  onOpenLandscape: () => void = (): void => {};

  aboutToAppear(): void {
    this.syncInteractionUI();
  }

  // 校准互动镜像到视频真实状态（点赞/投币/收藏服务端失败回退时也会触发）
  private syncInteractionUI(): void {
    const item: VideoItem | undefined = this.videos[this.currentIndex];
    if (item === undefined) return;
    this.uiLiked = item.liked ?? false;
    this.uiFavored = item.favored ?? false;
    this.uiCoined = item.coined ?? false;
  }

  @Builder
  emptyArea() {
  }

  private onCommentInputVisibleChange(): void {
    if (!this.showCommentInput) {
      this.emojiPanelVisible = false;
    }
  }

  private emojiUrlMap(comment: VideoComment | null = null): Map<string, string> {
    const map: Map<string, string> = new Map<string, string>();
    this.emojiItems.forEach((emoji: BiliEmoji): void => {
      map.set(emoji.name, emoji.url);
      map.set(EmojiService.normalizeName(emoji.name), emoji.url);
    });
    if (comment !== null) {
      comment.emotes.forEach((url: string, name: string): void => {
        map.set(name, url);
        map.set(EmojiService.normalizeName(name), url);
      });
    }
    return map;
  }

  private isOwnComment(comment: VideoComment): boolean {
    if (comment.id < 0) return true;
    if (comment.mid <= 0) return false;
    const session: AuthSession | null = this.authSession;
    return session !== null && session.uid !== '' && String(comment.mid) === session.uid;
  }

  private recentEmojiList(): BiliEmoji[] {
    const result: BiliEmoji[] = [];
    this.recentEmojis.forEach((name: string): void => {
      const matched: BiliEmoji | undefined =
        this.emojiItems.find((emoji: BiliEmoji): boolean => emoji.name === name);
      if (matched !== undefined) result.push(matched);
    });
    return result;
  }

  private dismissCommentOverlay(): void {
    this.commentMenuVisible = false;
    this.textSelectSheetVisible = false;
    this.commentMenuComment = null;
  }

  @Builder
  commentRichText(comment: VideoComment, size: number, color: string) {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      ForEach(EmojiText.split(comment.message, this.emojiUrlMap(comment)),
        (seg: EmojiSegment, index: number) => {
          if (seg.url !== '') {
            Image(seg.url).width(size + 5).height(size + 5)
              .objectFit(ImageFit.Contain).margin({ right: 3, top: 1 });
          } else {
            ForEach(this.splitAtMentions(seg.text, comment), (piece: AtPiece) => {
              if (piece.mid > 0) {
                // @用户：蓝色可点，跳转个人主页
                Text(piece.text).fontSize(size).fontColor('#1288FA')
                  .onClick((): void => { this.onOpenUser(piece.mid, piece.text.replace('@', '')); });
              } else {
                Text(piece.text).fontSize(size).fontColor(color);
              }
            }, (piece: AtPiece) => `at_${index}_${piece.text}`)
          }
        }, (seg: EmojiSegment, index: number) => `seg_${index}`)
    }.width('100%');
  }

  // 把文本按 "@昵称" 切片：能匹配到 content.members（昵称→mid）的作为超链接片段
  private splitAtMentions(text: string, comment: VideoComment): AtPiece[] {
    const pieces: AtPiece[] = [];
    if (text === '') return pieces;
    const regex: RegExp = /@[^\s@，,。！？：:；;~～]+/g;
    let lastIndex: number = 0;
    let match: RegExpExecArray | null = regex.exec(text);
    while (match !== null) {
      if (match.index > lastIndex) {
        pieces.push(new AtPiece(text.substring(lastIndex, match.index), 0));
      }
      const name: string = match[0].substring(1);
      const mid: number = comment.ats.get(name) ?? this.pickedAts.get(name) ?? 0;
      pieces.push(new AtPiece(match[0], mid));
      lastIndex = match.index + match[0].length;
      match = regex.exec(text);
    }
    if (lastIndex < text.length) {
      pieces.push(new AtPiece(text.substring(lastIndex), 0));
    }
    return pieces;
  }

  @Builder
  emojiGridItem(emoji: BiliEmoji) {
    GridItem() {
      Image(emoji.url).width(42).height(42).objectFit(ImageFit.Contain);
    }.padding(4)
      .onClick((): void => {
        // 选择表情只追加内容，面板保持打开，支持连续选择。
        this.onPickEmoji(emoji);
      });
  }

  @Builder
  emojiPickerPanel() {
    Column({ space: 8 }) {
      Row() {
        Text('B站表情').fontSize(14).fontWeight(FontWeight.Bold).layoutWeight(1);
        Text('关闭').fontSize(12).fontColor('#1288FA')
          .onClick((): void => { this.emojiPanelVisible = false; });
      }.width('100%');
      if (this.emojiLoading && this.emojiItems.length === 0) {
        Text('正在获取表情包...').fontSize(12).fontColor('#858C94')
          .width('100%').textAlign(TextAlign.Center).padding(16);
      } else if (this.emojiItems.length === 0) {
        Text('暂无可用表情').fontSize(12).fontColor('#858C94')
          .width('100%').textAlign(TextAlign.Center).padding(16);
      } else {
        if (this.recentEmojiList().length > 0) {
          Text('最近使用').fontSize(12).fontColor('#858C94').width('100%');
          Grid() {
            ForEach(this.recentEmojiList(), (emoji: BiliEmoji) => {
              this.emojiGridItem(emoji);
            }, (emoji: BiliEmoji) => `recent_${emoji.name}`)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
          .rowsGap(4).columnsGap(4).width('100%').height(100)
          .scrollBar(BarState.Off).enableScrollInteraction(true);
          Divider().strokeWidth(0.5).color('#E5E8EC');
        }
        Grid() {
          ForEach(this.emojiItems, (emoji: BiliEmoji) => {
            this.emojiGridItem(emoji);
          }, (emoji: BiliEmoji, index: number) => `emoji_${index}_${emoji.name}`)
        }
        .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
        .rowsGap(4).columnsGap(4).width('100%').height(190)
        .scrollBar(BarState.Off);
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 10 })
    .backgroundColor(Color.White)
    .borderRadius({ topLeft: 14, topRight: 14 })
    .shadow({ radius: 10, color: '#1A000000', offsetX: 0, offsetY: -2 })
    .position({ left: 0, right: 0, bottom: this.keyboardInset + this.bottomInset + 62 })
    .zIndex(11);
  }

  @Builder
  commentActionSheet() {
    if (this.commentMenuVisible && this.commentMenuComment !== null) {
      Column()
        .width('100%').height('100%').backgroundColor('#33000000')
        .onClick((): void => { this.dismissCommentOverlay(); });
      Column({ space: 2 }) {
        Text('选词复制').fontSize(14).fontColor('#1E252D')
          .width('100%').height(40).textAlign(TextAlign.Center)
          .onClick((): void => {
            this.textSelectContent = this.commentMenuComment?.message ?? '';
            this.commentMenuVisible = false;
            this.textSelectSheetVisible = true;
          });
        if (this.isOwnComment(this.commentMenuComment)) {
          Divider().strokeWidth(0.5).color('#E9EDF0').width('88%');
          Text('删除评论').fontSize(14).fontColor('#F04B55')
            .width('100%').height(40).textAlign(TextAlign.Center)
            .onClick((): void => {
              const target: VideoComment | null = this.commentMenuComment;
              this.dismissCommentOverlay();
              if (target !== null) this.onDeleteComment(target);
            });
        }
        Divider().strokeWidth(0.5).color('#E9EDF0').width('88%');
        Text('不看该评论').fontSize(14).fontColor('#1E252D')
          .width('100%').height(40).textAlign(TextAlign.Center)
          .onClick((): void => {
            const target: VideoComment | null = this.commentMenuComment;
            this.dismissCommentOverlay();
            if (target !== null) this.onHideComment(target);
          });
        Divider().strokeWidth(0.5).color('#E9EDF0').width('88%');
        Text('举报评论').fontSize(14).fontColor('#1E252D')
          .width('100%').height(40).textAlign(TextAlign.Center)
          .onClick((): void => {
            const target: VideoComment | null = this.commentMenuComment;
            this.dismissCommentOverlay();
            if (target !== null) this.onReportComment(target);
          });
        Divider().strokeWidth(0.5).color('#E9EDF0').width('88%');
        Text('拉黑用户').fontSize(14).fontColor('#1E252D')
          .width('100%').height(40).textAlign(TextAlign.Center)
          .onClick((): void => {
            const target: VideoComment | null = this.commentMenuComment;
            this.dismissCommentOverlay();
            if (target !== null) this.onBlockComment(target);
          });
        Divider().strokeWidth(0.5).color('#E9EDF0').width('88%');
        Text('取消').fontSize(14).fontColor('#858C94')
          .width('100%').height(40).textAlign(TextAlign.Center)
          .onClick((): void => { this.dismissCommentOverlay(); });
      }
      .width('72%')
      .padding({ top: 8, bottom: 8 })
      .backgroundColor(Color.White)
      .borderRadius(14)
      .position({ left: '14%', bottom: this.bottomInset + 24 });
    }
  }

  @Builder
  textSelectSheet() {
    if (this.textSelectSheetVisible) {
      Column()
        .width('100%').height('100%').backgroundColor('#33000000')
        .onClick((): void => { this.dismissCommentOverlay(); });
      Column({ space: 10 }) {
        Text('长按选择文字复制').fontSize(13).fontColor('#858C94').width('100%');
        Text(this.textSelectContent)
          .fontSize(15).fontColor('#1E252D').lineHeight(22)
          .copyOption(CopyOptions.InApp)
          .width('100%');
        Text('关闭').fontSize(14).fontColor('#1288FA')
          .width('100%').textAlign(TextAlign.Center).padding({ top: 6 })
          .onClick((): void => { this.dismissCommentOverlay(); });
      }
      .alignItems(HorizontalAlign.Start)
      .width('86%')
      .padding(16)
      .backgroundColor(Color.White)
      .borderRadius(14)
      .position({ left: '7%', bottom: this.bottomInset + 24 });
    }
  }

  private currentAspect(): number {
    return FormatUtils.currentAspect(this.videos[this.currentIndex]);
  }

  @Builder
  detailAction(label: string, iconName: string, active: boolean, action: () => void,
    longPress: () => void = (): void => {}) {
    if (iconName === 'share') {
      // 分享按钮：点击/长按弹多级菜单（预览头+系统分享+复制链接），菜单带蒙层
      Column({ space: 3 }) {
        Image($r('app.media.share')).width(24).height(24).opacity(0.85);
        Text(label).fontSize(12).fontColor('#3E4854').maxLines(1);
      }.layoutWeight(1).alignItems(HorizontalAlign.Center)
        .onClick(() => { action(); })
        .bindMenu(this.shareSheetMenu(), { placement: Placement.Top })
        .bindContextMenu(this.shareSheetMenu(), ResponseType.LongPress, { placement: Placement.Top });
    } else {
      Column({ space: 3 }) {
        if (iconName === 'dianzan') {
          Image($r('app.media.dianzan')).width(24).height(24)
            .fillColor(active ? '#1288FA' : '#111111')
            .animation({ duration: 180, curve: Curve.EaseOut });
        } else if (iconName === 'diancai') {
          Image($r('app.media.diancai')).width(24).height(24)
            .fillColor(active ? '#1288FA' : '#111111')
            .animation({ duration: 180, curve: Curve.EaseOut });
        } else if (iconName === 'toubi') {
          Image($r('app.media.toubi')).width(24).height(24)
            .opacity(active ? 1 : 0.85);
        } else if (iconName === 'favorites') {
          Image($r('app.media.favorites')).width(24).height(24)
            .opacity(active ? 1 : 0.85);
        } else {
          Image($r('app.media.watch_later')).width(24).height(24).opacity(active ? 1 : 0.85);
        }
        Text(label).fontSize(12).fontColor(active ? '#1288FA' : '#3E4854')
          .fontWeight(active ? FontWeight.Bold : FontWeight.Normal)
          .maxLines(1);
      }.layoutWeight(1).alignItems(HorizontalAlign.Center)
        .onClick(() => { action(); })
        .gesture(LongPressGesture({ repeat: false }).onAction((): void => { longPress(); }));
    }
  }

  // 分享多级菜单：视频预览头 + 系统分享 / 复制链接；点击 bindMenu、长按 bindContextMenu（自带蒙层）
  @Builder
  shareSheetMenu() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        if ((this.videos[this.currentIndex].cover ?? '') !== '') {
          Image(this.videos[this.currentIndex].cover).width(96).height(54)
            .borderRadius(8).objectFit(ImageFit.Cover);
        } else {
          Column() {
            Image($r('app.media.img')).width(28).height(28).opacity(0.5);
          }.width(96).height(54).borderRadius(8).backgroundColor('#E1E6EE')
            .justifyContent(FlexAlign.Center);
        }
        Text(this.videos[this.currentIndex].title).fontSize(13).fontColor('#1E252D')
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
          .lineHeight(18);
      }.width('100%').alignItems(VerticalAlign.Center);
      Divider().color('#1A000000').strokeWidth(0.5);
      Row({ space: 28 }) {
        Column({ space: 4 }) {
          Image($r('app.media.share')).width(22).height(22).fillColor('#1E252D');
          Text('系统分享').fontSize(11).fontColor('#59616B');
        }.onClick(() => { this.onDetailAction('share'); })
        Column({ space: 4 }) {
          Image($r('app.media.copy')).width(22).height(22).fillColor('#1E252D');
          Text('复制链接').fontSize(11).fontColor('#59616B');
        }.onClick(() => { this.copyVideoLink(); })
      }.width('100%').justifyContent(FlexAlign.Center);
    }
    .width(216).padding(12)
    .backgroundColor(ImmersiveMaterial.surfaceBackground(0.94))
    .backgroundBlurStyle(ImmersiveMaterial.blurStyle(), { colorMode: ThemeColorMode.LIGHT })
    .borderRadius(14)
    .border({ width: 1, color: '#35FFFFFF' })
    .shadow({ radius: 10, color: '#33000000', offsetX: 0, offsetY: 3 });
  }

  // 复制视频链接到剪贴板
  private copyVideoLink(): void {
    const item: VideoItem = this.videos[this.currentIndex];
    const link: string = item.bvid !== '' ? `https://www.bilibili.com/video/${item.bvid}/` :
      `https://www.bilibili.com/video/av${item.aid}/`;
    try {
      const pasteData: pasteboard.PasteData =
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, link);
      pasteboard.getSystemPasteboard().setData(pasteData).then((): void => {
        this.promptCopyDone();
      }).catch((error: Object): void => {
        console.error(`Pilihos copy link failed: ${String(error)}`);
      });
    } catch (copyError) {
      console.error(`Pilihos copy link build failed: ${String(copyError)}`);
    }
  }

  private promptCopyDone(): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: '链接已复制',
        duration: 1800,
        bottom: this.bottomInset + 24
      });
    } catch (_error) {
      // 忽略 toast 失败
    }
  }

  @Builder
  verticalActionCount(iconName: string, count: number, active: boolean, action: () => void,
    longPress: () => void = (): void => {}, label: string = '') {
    Column({ space: 3 }) {
      if (iconName === 'dianzan') {
        // 点赞：常态白色（黑底可读），激活填充红色；其余图标激活仍为蓝色
        Image($r('app.media.dianzan')).width(24).height(24)
          .fillColor(active ? '#F04B55' : '#FFFFFF');
      } else if (iconName === 'diancai') {
        Image($r('app.media.diancai')).width(24).height(24)
          .fillColor(active ? '#1288FA' : '#FFFFFF');
      } else if (iconName === 'toubi') {
        Image($r('app.media.toubi')).width(24).height(24)
          .fillColor(active ? '#1288FA' : '#DCEBFA');
      } else if (iconName === 'favorites') {
        // 收藏反馈：激活填充蓝色
        Image($r('app.media.favorites')).width(24).height(24)
          .fillColor(active ? '#1288FA' : Color.White);
      } else if (iconName === 'sphsz') {
        Image($r('app.media.sphsz')).width(24).height(24).fillColor(Color.White);
      } else {
        Image($r('app.media.pl')).width(24).height(24).fillColor(Color.White);
      }
      Text(label !== '' ? label : (count > 0 ? FormatUtils.formatCount(count) : '-'))
        .fontSize(9)
        .fontColor(active ? (iconName === 'dianzan' ? '#F04B55' : '#1288FA') : '#DDE5EA')
        .maxLines(1);
    }.width(40)
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => { action(); })
      .gesture(LongPressGesture({ repeat: false }).onAction((): void => { longPress(); }));
  }

  // 竖屏化视频底部悬浮层：UP 信息 + 简介（弹幕输入行之下不再压视频）
  @Builder
  verticalInfoOverlay() {
    Column({ space: 6 }) {
      Row({ space: 10 }) {
        if ((this.videos[this.currentIndex].authorFace ?? '') !== '') {
          Image(this.videos[this.currentIndex].authorFace ?? '')
            .width(38).height(38).borderRadius(19).objectFit(ImageFit.Cover)
            .onClick((): void => { this.onDetailAction('openauthor'); });
        } else {
          Image($r('app.media.user_me')).width(38).height(38).borderRadius(19).objectFit(ImageFit.Contain)
            .onClick((): void => { this.onDetailAction('openauthor'); });
        }
        Column({ space: 3 }) {
          Row({ space: 0 }) {
            Text(this.videos[this.currentIndex].author === '' ? '未知UP主' : this.videos[this.currentIndex].author)
              .fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.White)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '72%' });
            Image(FormatUtils.levelBadge(this.videos[this.currentIndex].authorLevel ?? 0))
              .width(44).height(24).objectFit(ImageFit.Contain);
          }.width('100%');
          Text(this.videos[this.currentIndex].authorFans !== undefined
            ? FormatUtils.formatCount(this.videos[this.currentIndex].authorFans) + ' 粉丝' : '')
            .fontSize(10).fontColor('#B8C4CC');
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          .onClick((): void => { this.onDetailAction('openauthor'); });
        this.followBubble(true);
      }.width('100%');
      if (this.videos[this.currentIndex].description !== '') {
        Text(this.videos[this.currentIndex].description)
          .fontSize(12).fontColor('#C7D0D6')
          .maxLines(this.verticalDescExpanded ? 12 : 1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          .copyOption(CopyOptions.InApp)
          .onClick((): void => { this.verticalDescExpanded = !this.verticalDescExpanded; });
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8 })
  }

  // 竖屏化底部操作行：弹幕输入 + 互动图标，视频区底部与其顶部对齐；
  // 细进度线画在操作行最底部（系统导航条上方），不遮挡简介悬浮层
  @Builder
  verticalActionBar() {
    Stack({ alignContent: Alignment.Bottom }) {
      Row({ space: 10 }) {
        Stack({ alignContent: Alignment.Start }) {
          TextInput({ placeholder: '发弹幕', text: this.danmakuText })
            .layoutWeight(1).height(38).fontSize(13)
            .fontColor('#E8EEF3').placeholderColor('#8FA3B0')
            .backgroundColor('#2EFFFFFF').borderRadius(17)
            .padding({ left: 34, right: 12 })
            .enabled(this.danmakuEnabled)
            .onChange((value: string) => { this.danmakuText = value; })
            .onSubmit((): void => { this.onSendDanmaku(); });
          // 弹幕开关：开启 dm / 关闭 dmg，逻辑与详情页弹幕输入框右侧开关一致
          Button() {
            Image(this.danmakuEnabled ? $r('app.media.dm') : $r('app.media.dmg'))
              .width(18).height(18)
              .fillColor(this.danmakuEnabled ? Color.White : '#8FA3B0');
          }
          .type(ButtonType.Capsule).width(32).height(32)
          .backgroundColor(Color.Transparent)
          .margin({ left: 4 })
          .onClick((): void => {
            this.danmakuEnabled = !this.danmakuEnabled;
            if (!this.danmakuEnabled) this.danmakuText = '';
          });
        }
        .layoutWeight(1)
        .gesture(TapGesture().onAction((): void => { this.onDetailAction('comments'); }))
        this.verticalActionCount('dianzan', this.videos[this.currentIndex].likeCount,
          this.uiLiked,
          (): void => {
            this.uiLiked = !this.uiLiked;
            this.onDetailAction('like');
          });
        this.verticalActionCount('toubi', this.videos[this.currentIndex].coinCount ?? 0,
          this.uiCoined,
          (): void => { this.onDetailAction('coin'); });
        this.verticalActionCount('favorites', this.videos[this.currentIndex].favoriteCount ?? 0,
          this.uiFavored,
          (): void => {
            // 取消收藏即时反馈；进入收藏面板添加由 videos 监听校准
            if (this.uiFavored) {
              this.uiFavored = false;
            }
            this.onDetailAction('favtoggle');
          });
        this.verticalActionCount('pl', this.videos[this.currentIndex].commentCount,
          false, (): void => { this.onDetailAction('comments'); }, (): void => {}, '评论');
        this.verticalActionCount('sphsz', 0,
          false, (): void => { this.onDetailAction('settings'); }, (): void => {}, '设置');
      }.width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: this.bottomInset + 12 });
      if (this.playbackDurationMs > 0 && this.miniProgressOn
        && !this.playbackControlsVisible) {
        Row() {
          Stack({ alignContent: Alignment.Start }) {
            Row().width('100%').height(3).backgroundColor('#4DFFFFFF').borderRadius(1.5)
            Row().width(this.verticalProgressPercent() + '%').height(3)
              .backgroundColor('#1288FA').borderRadius(1.5)
          }.layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
        .margin({ bottom: 2 })
      }
    }
    .width('100%')
    .backgroundColor(Color.Black)
  }

  // 输入框键入 @：弹出联系人面板（最近联系/搜索）
  private onCommentInputChanged(value: string): void {
    this.commentInputText = value;
    if (value.endsWith('@')) {
      this.atSearchText = '';
      this.atPanelVisible = true;
      this.loadAtContacts('');
    } else if (!value.includes('@')) {
      this.atPanelVisible = false;
    }
  }

  private loadAtContacts(keyword: string): void {
    const session: AuthSession | null = this.authSession ?? AuthService.currentSession();
    if (session === null || session.cookie === '') {
      return;
    }
    this.atLoading = true;
    MessageService.loadMentionContacts(keyword, session.cookie).then((contacts: MentionContact[]): void => {
      this.atContacts = contacts;
    }).catch((_: Error): void => {
      this.atContacts = [];
    }).finally((): void => { this.atLoading = false; });
  }

  // 勾选联系人：替换输入框末尾的 @ 为 @昵称 并关闭面板
  private pickAtContact(contact: MentionContact): void {
    this.pickedAts.set(contact.name, contact.uid);
    if (this.commentInputText.endsWith('@')) {
      this.commentInputText = this.commentInputText.substring(0, this.commentInputText.length - 1)
        + `@${contact.name} `;
    } else {
      this.commentInputText = this.commentInputText + `@${contact.name} `;
    }
    this.atPanelVisible = false;
  }

  @Builder
  atContactPanel() {
    if (this.atPanelVisible) {
      // 全宽悬浮容器承载卡片：position 的 left/right 同时非零会互相冲突导致溢出
      Column() {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Image($r('app.media.serch')).width(18).height(18).fillColor('#858C94');
          TextInput({ placeholder: '输入你想@的人', text: this.atSearchText })
            .layoutWeight(1).height(34).fontSize(13)
            .backgroundColor(Color.Transparent).padding({ left: 0, right: 0 })
            .onChange((value: string): void => {
              this.atSearchText = value;
              this.loadAtContacts(value);
            });
        }
        .width('100%').height(40)
        .padding({ left: 12, right: 12 })
        .backgroundColor('#F1F3F5')
        .borderRadius(18);
        if (this.atLoading) {
          Text('正在加载联系人…').fontSize(12).fontColor('#858C94').width('100%')
            .textAlign(TextAlign.Center).padding({ top: 8, bottom: 8 });
        } else if (this.atContacts.length === 0) {
          Text('暂无可@的联系人').fontSize(12).fontColor('#858C94').width('100%')
            .textAlign(TextAlign.Center).padding({ top: 8, bottom: 8 });
        } else {
          Scroll() {
            Column({ space: 0 }) {
              ForEach(this.atContacts, (contact: MentionContact) => {
                Row({ space: 10 }) {
                  if (contact.face !== '') {
                    Image(contact.face).width(36).height(36).borderRadius(18).objectFit(ImageFit.Cover);
                  } else {
                    Image($r('app.media.user_me')).width(36).height(36).borderRadius(18);
                  }
                  Column({ space: 2 }) {
                    Text(contact.name).fontSize(14).fontColor('#1E252D').maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis });
                    if (contact.fans > 0) {
                      Text(FormatUtils.formatCount(contact.fans) + ' 粉丝')
                        .fontSize(11).fontColor('#858C94');
                    }
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start);
                  // 勾选框仅视觉展示，点击整行即完成插入
                  Checkbox({ name: `at_${contact.uid}` }).select(false)
                    .selectedColor('#1288FA').width(18).height(18)
                    .hitTestBehavior(HitTestMode.None);
                }
                .width('100%').padding({ top: 8, bottom: 8 })
                .onClick((): void => { this.pickAtContact(contact); });
              }, (contact: MentionContact) => `atc_${contact.uid}_${contact.name}`);
            }.width('100%');
          }
          .width('100%').height(240).scrollBar(BarState.Off).align(Alignment.Top);
        }
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#FFFFFF')
      .borderRadius(14)
      .border({ width: 1, color: '#14000000' })
      .shadow({ radius: 12, color: '#26000000', offsetX: 0, offsetY: 4 });
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: this.keyboardInset + 66 })
      .position({ left: 0, right: 0, bottom: 0 })
      .zIndex(25);
    }
  }

  private verticalProgressPercent(): number {
    if (this.playbackDurationMs <= 0) return 0;
    return Math.max(0, Math.min(100, this.playbackCurrentMs / this.playbackDurationMs * 100));
  }

  @Builder
  detailTabs() {
    Row() {
      Row({ space: 14 }) {
        Text('简介').fontSize(15)
          .fontColor(this.detailSection === 0 ? '#1288FA' : '#59616B')
          .fontWeight(this.detailSection === 0 ? FontWeight.Bold : FontWeight.Normal)
          .onClick(() => { this.detailSection = 0; });
        Text('评论').fontSize(15)
          .fontColor(this.detailSection === 1 ? '#1288FA' : '#59616B')
          .fontWeight(this.detailSection === 1 ? FontWeight.Bold : FontWeight.Normal)
          .onClick(() => { this.detailSection = 1; this.onLoadComments(true); });
        Text('设置').fontSize(15)
          .fontColor(this.detailSection === 2 ? '#1288FA' : '#59616B')
          .fontWeight(this.detailSection === 2 ? FontWeight.Bold : FontWeight.Normal)
          .onClick(() => { this.detailSection = 2; });
      }
      .layoutWeight(1)
      .padding({ left: 16 })
      .alignItems(VerticalAlign.Center);
      Button() {
        Image($r('app.media.downput')).width(18).height(18);
      }
      .type(ButtonType.ROUNDED_RECTANGLE).width(40).height(40)
      .backgroundColor(Color.Transparent)
      .borderRadius(20)
      .margin({ right: 14 })
      .onClick(() => {
        this.pendingResumeMs = this.playbackCurrentMs;
        this.verticalExpanded = !this.verticalExpanded;
      })
      .gesture(GestureGroup(GestureMode.Sequence,
        LongPressGesture({ repeat: false, duration: 300 }),
        PanGesture({ fingers: 1, direction: PanDirection.Vertical })
          .onActionStart((event: GestureEvent): void => {
            this.panStartWeight = this.videoWeight;
          })
          .onActionUpdate((event: GestureEvent): void => {
            if (event.offsetY >= 40) {
              if (!this.verticalExpanded) {
                this.pendingResumeMs = this.playbackCurrentMs;
                this.verticalExpanded = true;
              }
              return;
            }
            const weight: number = this.panStartWeight + event.offsetY / 64;
            if (weight >= 8.5) {
              if (!this.verticalExpanded) {
                this.pendingResumeMs = this.playbackCurrentMs;
                this.verticalExpanded = true;
              }
              return;
            }
            if (this.verticalExpanded) {
              this.pendingResumeMs = this.playbackCurrentMs;
              this.verticalExpanded = false;
            }
            this.videoWeight = Math.min(6, Math.max(4, weight));
          })));
      Stack({ alignContent: Alignment.End }) {
        TextInput({ placeholder: '发一条弹幕', text: this.danmakuText })
          .width(150).height(36).fontSize(12).fontColor('#858C94')
          .backgroundColor('#F1F3F5').borderRadius(18)
          .padding({ left: 12, right: 38 })
          .enabled(this.danmakuEnabled)
          .onChange((value: string) => { this.danmakuText = value; })
          .onSubmit((): void => { this.onSendDanmaku(); });
        Button() {
          Image($r('app.media.dmg')).width(20).height(20)
            .opacity(this.danmakuEnabled ? 1 : 0.38);
        }.type(ButtonType.Capsule).width(32).height(32)
          .backgroundColor(Color.Transparent)
          .margin({ right: 3 })
          .onClick(() => {
            this.danmakuEnabled = !this.danmakuEnabled;
            if (!this.danmakuEnabled) this.danmakuText = '';
          });
      }
      .padding({ right: 8 });
    }.width('100%').height(64).backgroundColor(Color.White)
      .border({ width: { bottom: 1 }, color: '#E5E8EC' });
  }

  @Builder
  subReplyItem(reply: VideoComment, rootId: number) {
    Row({ space: 8 }) {
      if (reply.avatar !== '') {
        Image(reply.avatar).width(26).height(26).borderRadius(13).objectFit(ImageFit.Cover)
          .onClick((): void => { this.onOpenUser(reply.mid, reply.userName); });
      } else {
        Row().width(26).height(26).borderRadius(13).backgroundColor('#DCE3EF');
      }
      Column({ space: 3 }) {
        Row({ space: 5 }) {
          Text(reply.userName).fontSize(12).fontColor('#59616B').fontWeight(FontWeight.Medium)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '55%' })
            .onClick((): void => { this.onOpenUser(reply.mid, reply.userName); });
          // 间接回复：A 回复 @B（第三层起不再新开层级，统一 @ 展示）
          if (reply.replyToName !== '') {
            Text(`回复 @${reply.replyToName}`).fontSize(11).fontColor('#858C94')
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1);
          } else {
            Image(FormatUtils.levelBadge(reply.level)).width(40).height(22).objectFit(ImageFit.Contain);
          }
        }.width('100%');
        this.commentRichText(reply, 13, '#1E252D');
        Row({ space: 12 }) {
          Text(FormatUtils.formatPublishTime(reply.publishTime)).fontSize(10).fontColor('#A0A6AD');
          Row({ space: 3 }) {
            Image($r('app.media.dianzan')).width(12).height(12)
              .fillColor(reply.liked ? '#1288FA' : '#858C94');
            Text(FormatUtils.formatCount(reply.likeCount)).fontSize(10)
              .fontColor(reply.liked ? '#1288FA' : '#858C94');
          }
            .onClick((): void => { this.onLikeComment(reply); });
          // 楼中楼回复：root 保持在楼层评论，parent 指向被回复的子评论
          Text('回复').fontSize(10).fontColor('#59616B')
            .onClick((): void => { this.onReplySubReply(rootId, reply); });
        }.width('100%');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }.width('100%').alignItems(VerticalAlign.Top);
  }

  @Builder
  commentItem(comment: VideoComment) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        if (comment.avatar !== '') {
          Image(comment.avatar).width(38).height(38).borderRadius(19).objectFit(ImageFit.Cover)
            .onClick((): void => { this.onOpenUser(comment.mid, comment.userName); });
        } else {
          Row().width(38).height(38).borderRadius(19).backgroundColor('#DCE3EF');
        }
        Column({ space: 5 }) {
          Row({ space: 5 }) {
            Text(comment.userName).fontSize(13).fontColor('#59616B').fontWeight(FontWeight.Medium)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '70%' })
              .onClick((): void => { this.onOpenUser(comment.mid, comment.userName); });
            Image(FormatUtils.levelBadge(comment.level)).width(40).height(22).objectFit(ImageFit.Contain);
          }.width('100%');
          this.commentRichText(comment, 15, '#1E252D');
          Row({ space: 14 }) {
            Text(FormatUtils.formatPublishTime(comment.publishTime)).fontSize(11).fontColor('#A0A6AD');
            Row({ space: 3 }) {
              Image($r('app.media.dianzan')).width(14).height(14)
                .fillColor(comment.liked ? '#1288FA' : '#858C94')
                .animation({ duration: 180, curve: Curve.EaseOut });
              Text(FormatUtils.formatCount(comment.likeCount)).fontSize(11)
          .fontColor(comment.liked ? '#1288FA' : '#858C94');
            }
              .onClick((): void => { this.onLikeComment(comment); });
            Row({ space: 3 }) {
              Image($r('app.media.pl')).width(14).height(14)
                .fillColor(this.expandedCommentId === comment.id ? '#1288FA' : '#858C94');
              Text(FormatUtils.formatCount(comment.replyCount)).fontSize(11)
                .fontColor(this.expandedCommentId === comment.id ? '#1288FA' : '#858C94');
            }
              .onClick((): void => { this.onToggleReplies(comment); });
            Image($r('app.media.reply')).width(14).height(14).fillColor('#858C94')
              .onClick((): void => { this.onReplyComment(comment); });
          }.width('100%');
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      }.width('100%').alignItems(VerticalAlign.Top);
      if (this.expandedCommentId === comment.id) {
        Column({ space: 10 }) {
          if (this.subLoading && this.subReplies.length === 0) {
            loadingIndicator('正在加载回复', '#8B9199');
          } else if (this.subReplies.length === 0) {
            Text('暂无回复').fontSize(12).fontColor('#A0A6AD');
          } else {
            ForEach(this.subReplies, (reply: VideoComment) => {
              this.subReplyItem(reply, comment.id);
            }, (reply: VideoComment) => `sub_${reply.id}`);
            if (this.subHasMore) {
              Text(this.subLoading ? '正在加载...' : '展开更多回复')
                .fontSize(12).fontColor('#1288FA')
                .onClick((): void => { this.onLoadSubReplies(comment.id, false); });
            }
          }
        }
        .width('100%')
        .padding({ left: 48, top: 4, bottom: 4 })
        .alignItems(HorizontalAlign.Start);
      }
    }.width('100%').padding({ top: 10, bottom: 10 })
      .gesture(LongPressGesture({ repeat: false, duration: 500 }).onAction((): void => {
        this.commentMenuComment = comment;
        this.commentMenuVisible = true;
      }))
      .border({ width: { bottom: 1 }, color: '#E9EDF0' });
  }

  @Builder
  commentPanel() {
    Column({ space: 12 }) {
      Row() {
        Text('评论 ' + FormatUtils.formatCount(this.commentTotal > 0
          ? this.commentTotal : this.videos[this.currentIndex].commentCount))
          .fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1);
        Text(this.commentSort === '2' ? '按热度' : '按时间').fontSize(13).fontColor('#1288FA')
          .onClick((): void => { this.onToggleCommentSort(); });
      }.width('100%').padding({ top: 4, bottom: 6 });
      if (this.commentLoading && this.comments.length === 0) {
        loadingIndicator('正在加载评论', '#1288FA');
      } else if (this.commentError !== '' && this.comments.length === 0) {
        Column({ space: 10 }) {
          Text(this.commentError).fontSize(14).fontColor('#858C94');
          Button('重新加载').height(36).onClick(() => { this.onLoadComments(true); });
        }.width('100%').alignItems(HorizontalAlign.Center).padding({ top: 30, bottom: 30 });
      } else if (this.comments.length === 0) {
        Text('还没有评论').fontSize(14).fontColor('#858C94').width('100%')
          .textAlign(TextAlign.Center).padding({ top: 30, bottom: 30 });
      } else {
        ForEach(this.comments, (comment: VideoComment) => {
          this.commentItem(comment);
        }, (comment: VideoComment) => `comment_${comment.id}`);
        if (this.commentHasMore) {
          Button(this.commentLoading ? '正在加载' : '加载更多评论').height(38)
            .width('100%').backgroundColor('#F1F3F5').fontColor('#59616B')
            .onClick(() => { this.onLoadComments(false); });
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  @Builder
  detailScroll() {
    Scroll() {
      Column({ space: 12 }) {
          Row({ space: 10 }) {
            if ((this.videos[this.currentIndex].authorFace ?? '') !== '') {
              Image(this.videos[this.currentIndex].authorFace ?? '')
                .width(44).height(44).borderRadius(22).objectFit(ImageFit.Cover);
            } else {
              Image($r('app.media.user_me')).width(44).height(44).borderRadius(22).objectFit(ImageFit.Contain);
            }
            Column({ space: 2 }) {
              Text(`@${this.videos[this.currentIndex].author}`).fontSize(15);
              Text(`${this.videos[this.currentIndex].authorFans !== undefined
                ? FormatUtils.formatCount(this.videos[this.currentIndex].authorFans) + ' 粉丝' : '粉丝 --'} · ${this.videos[this.currentIndex].authorVideos !== undefined
                ? this.videos[this.currentIndex].authorVideos + ' 投稿' : '投稿 --'}`)
                .fontSize(11).fontColor('#858C94');
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              .onClick((): void => { this.onDetailAction('openauthor'); });
            this.followBubble(false);
          }.width('100%');
          Row({ space: 8 }) {
            Text(this.videos[this.currentIndex].title).fontSize(19)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1);
            Button() {
              Image($r('app.media.down')).width(17).height(17);
            }
            .type(ButtonType.ROUNDED_RECTANGLE).width(32).height(32)
            .backgroundColor(Color.Transparent).borderRadius(16);
          }.width('100%').alignItems(VerticalAlign.Center)
            .onClick((): void => { this.detailExpanded = !this.detailExpanded; });

          if (this.detailExpanded) {
            Column({ space: 8 }) {
              Text(this.videos[this.currentIndex].title)
                .fontSize(18).fontWeight(FontWeight.Medium).lineHeight(25)
                .width('100%');
              if (this.detailLoading) {
                loadingIndicator('正在加载视频详情...', '#59616B');
              } else {
                Text(this.detailError !== '' ? this.detailError :
                  (this.videos[this.currentIndex].description === ''
                    ? '暂无简介' : this.videos[this.currentIndex].description))
                  .fontSize(14).fontColor('#59616B').lineHeight(21)
                  .width('100%')
                  // 长按简介可选中复制（应用内选词）
                  .copyOption(CopyOptions.InApp);
              }
              Text('BV号: ' + (this.videos[this.currentIndex].bvid === ''
                ? '暂无' : this.videos[this.currentIndex].bvid))
                .fontSize(13).fontColor('#858C94').width('100%');
              Text('标签 ' + (this.videos[this.currentIndex].tags.length === 0
                ? '暂无' : this.videos[this.currentIndex].tags.join(' · ')))
                .fontSize(13).fontColor('#858C94').lineHeight(20)
                .width('100%');
            }.width('100%').padding({ top: 2, bottom: 4 })
              .backgroundColor('#F7F8FA').borderRadius(8)
              .padding({ left: 10, right: 10, top: 8, bottom: 8 });
          }
          Row({ space: 18 }) {
            Row({ space: 4 }) {
              Image($r('app.media.bfl')).width(16).height(16);
              Text(FormatUtils.formatCount(this.videos[this.currentIndex].viewCount))
                .fontSize(13).fontColor('#858C94');
            }
            Row({ space: 4 }) {
              Image($r('app.media.dm')).width(16).height(16);
              Text(FormatUtils.formatCount(this.videos[this.currentIndex].danmuCount))
                .fontSize(13).fontColor('#858C94');
            }
            Text('发布于 ' + FormatUtils.formatPublishDate(this.videos[this.currentIndex].publishTime))
              .fontSize(13).fontColor('#858C94');
          }.width('100%').height(28)
            .justifyContent(FlexAlign.Start)
            .alignItems(VerticalAlign.Center);
          Row() {
            this.detailAction(this.videos[this.currentIndex].likeCount > 0
              ? FormatUtils.formatCount(this.videos[this.currentIndex].likeCount) : '点赞',
              'dianzan', this.uiLiked,
              (): void => {
                this.uiLiked = !this.uiLiked;
                this.onDetailAction('like');
              });
        this.detailAction('点踩', 'diancai', this.videos[this.currentIndex].disliked ?? false,
              (): void => { this.onDetailAction('dislike'); });
            this.detailAction((this.videos[this.currentIndex].coinCount ?? 0) > 0
              ? FormatUtils.formatCount(this.videos[this.currentIndex].coinCount ?? 0) : '投币',
              'toubi', this.uiCoined,
              (): void => { this.onDetailAction('coin'); });
            this.detailAction((this.videos[this.currentIndex].favoriteCount ?? 0) > 0
              ? FormatUtils.formatCount(this.videos[this.currentIndex].favoriteCount ?? 0) : '收藏',
              'favorites', this.uiFavored,
              (): void => {
                if (this.uiFavored) {
                  this.uiFavored = false;
                }
                this.onDetailAction('favtoggle');
              });
            this.detailAction('再看', 'watch_later', false,
              (): void => { this.onDetailAction('watchlater'); });
            this.detailAction('分享', 'share', false,
              (): void => { });
          }.width('100%').height(56).padding({ top: 8, bottom: 8 })
            .border({ width: { bottom: 1 }, color: '#E5E8EC' });
          if (this.relatedLoading && this.relatedVideos.length === 0) {
            loadingIndicator('正在加载推荐视频', '#59616B');
          } else if (this.relatedVideos.length === 0) {
            Text('暂无推荐视频').fontSize(13).fontColor('#858C94')
              .width('100%').textAlign(TextAlign.Center).padding({ top: 20, bottom: 20 });
          } else {
            ForEach(this.relatedVideos, (item: VideoItem) => {
              Row({ space: 10 }) {
                Image(item.cover).width(132).height(76).borderRadius(8);
                Column({ space: 5 }) {
                  Text(item.title).fontSize(14).maxLines(2).lineHeight(20);
                  Row({ space: 8 }) {
                    Row({ space: 3 }) {
                      Image($r('app.media.bfl')).width(13).height(13);
                      Text(FormatUtils.formatCount(item.viewCount)).fontSize(11).fontColor('#858C94');
                    }
                    Row({ space: 3 }) {
                      Image($r('app.media.dm')).width(13).height(13);
                      Text(FormatUtils.formatCount(item.danmuCount)).fontSize(11).fontColor('#858C94');
                    }
                    Text(FormatUtils.formatPublishTime(item.publishTime))
                      .fontSize(11).fontColor('#858C94').layoutWeight(1)
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
                  }.width('100%');
                  Row({ space: 6 }) {
                    if (FormatUtils.isPortraitVideo(item, this.portraitBadge)) {
                      Text('竖屏').fontSize(9).fontColor('#E661A0')
                        .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                        .backgroundColor('#1AE661A0').borderRadius(3);
                    }
                    Text(`@${item.author}`).fontSize(11).fontColor('#858C94')
                      .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1);
                  }.width('100%');
                }.layoutWeight(1).alignItems(HorizontalAlign.Start);
              }.width('100%').onClick(() => {
                this.onOpenRelated(item, this.detailSection === 1);
              });
            }, (item: VideoItem) => `related_${item.id}`);
          }
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 14, bottom: this.bottomInset + 30 });
    }.layoutWeight(1).width('100%').scrollBar(BarState.Off).backgroundColor(Color.White);
  }

  @Builder
  commentScroll() {
    Scroll() {
      Column({ space: 18 }) {
        this.commentPanel();
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 14, bottom: this.bottomInset + 30 });
    }.layoutWeight(1).width('100%').scrollBar(BarState.Off).backgroundColor(Color.White);
  }

  @Builder
  defaultSpeedChip(label: string, speed: number) {
    Row({ space: 5 }) {
      Checkbox({ name: 'page_speed_' + label, group: 'page_speed' })
        .select(this.defaultSpeed === speed)
        .selectedColor('#1288FA')
        .width(16)
        .height(16)
        .onChange((value: boolean) => {
          if (value) {
            this.defaultSpeed = speed;
          }
        });
      Text(label).fontSize(13)
        .fontColor(this.defaultSpeed === speed ? '#1288FA' : '#1E252D')
        .fontWeight(this.defaultSpeed === speed ? FontWeight.Bold : FontWeight.Normal);
    }
  }

  // 设置子页统一芯片：Toggle 状态按钮（样式与竖屏化设置面板一致）。
  // chipNonce：偏好设置等动作芯片执行后强制重建，复位 Toggle 视觉状态。
  @Builder
  settingChip(label: string, active: boolean, action: () => void) {
    Toggle({ type: ToggleType.Button, isOn: active }) {
      Text(label)
        .fontSize(13)
        .fontColor(active ? Color.White : '#1E252D')
        .fontWeight(active ? FontWeight.Medium : FontWeight.Normal)
        .textAlign(TextAlign.Center);
    }
    .layoutWeight(1)
    .height(40)
    .selectedColor('#1288FA')
    .id(`sc_${label}_${String(this.chipNonce)}`)
    .onChange((_on: boolean): void => {
      action();
      this.chipNonce++;
    });
  }

  @Builder
  playModeChipPage(label: string, mode: number, enabled: boolean) {
    Row({ space: 5 }) {
      Checkbox({ name: 'page_' + label, group: 'page_playmode' })
        .select(this.playMode === mode)
        .selectedColor('#1288FA')
        .enabled(enabled)
        .width(16)
        .height(16)
        .onChange((value: boolean) => {
          if (value) {
            this.onSetPlayMode(mode);
          }
        });
      Text(label).fontSize(13)
        .fontColor(enabled ? (this.playMode === mode ? '#1288FA' : '#1E252D') : '#A4A9AF')
        .fontWeight(this.playMode === mode ? FontWeight.Medium : FontWeight.Normal);
    }
    .enabled(enabled)
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ top: 8, bottom: 8 })
    .backgroundColor(this.playMode === mode ? '#E5F3FA' : Color.White)
    .borderRadius(14)
    .onClick((): void => {
      if (!enabled) return;
      this.onSetPlayMode(mode);
    });
  }

  private isPortraitCurrentVideo(): boolean {
    return this.currentIndex >= 0 && this.currentIndex < this.videos.length
      && FormatUtils.currentAspect(this.videos[this.currentIndex]) < 1;
  }

  @Builder
  danmakuSizeControl() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        this.danmakuChoice('45', this.danmakuFontSize === 45,
          (): void => { this.onSetDanmakuFontSize(45); });
        this.danmakuChoice('50', this.danmakuFontSize === 50,
          (): void => { this.onSetDanmakuFontSize(50); });
        this.danmakuChoice('55', this.danmakuFontSize === 55,
          (): void => { this.onSetDanmakuFontSize(55); });
        this.danmakuChoice('60', this.danmakuFontSize === 60,
          (): void => { this.onSetDanmakuFontSize(60); });
      }.width('100%');
    }.width('100%').padding({ left: 4, right: 4 });
  }

  @Builder
  danmakuChoice(label: string, selected: boolean, action: () => void) {
    Button() {
      Text(label).fontSize(13).fontColor(selected ? '#1288FA' : '#1E252D')
        .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
        .textAlign(TextAlign.Center);
    }
    .layoutWeight(1)
    .height(40)
    .padding(0)
    .enabled(true)
    .backgroundColor(selected ? '#E5F3FA' : Color.White)
    .borderRadius(8)
    .onClick((): void => { action(); });
  }

  @Builder
  danmakuAreaControl() {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        this.danmakuChoice('25%', this.danmakuArea === 25,
          (): void => { this.onSetDanmakuArea(25); });
        this.danmakuChoice('50%', this.danmakuArea === 50,
          (): void => { this.onSetDanmakuArea(50); });
        this.danmakuChoice('75%', this.danmakuArea === 75,
          (): void => { this.onSetDanmakuArea(75); });
        this.danmakuChoice('100%', this.danmakuArea === 100,
          (): void => { this.onSetDanmakuArea(100); });
      }.width('100%');
    }.width('100%').padding({ left: 4, right: 4 });
  }

  @Builder
  danmakuOpacityChip(label: string, opacity: number) {
    Text(label)
      .fontSize(13)
      .fontColor(this.danmakuOpacity === opacity ? '#1288FA' : '#1E252D')
      .fontWeight(this.danmakuOpacity === opacity ? FontWeight.Medium : FontWeight.Normal)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 8, bottom: 8 })
      .backgroundColor(this.danmakuOpacity === opacity ? '#FFF5ED' : Color.White)
      .borderRadius(14)
      .onClick(() => { this.danmakuOpacity = opacity; });
  }

  @Builder
  danmakuSpeedChip(label: string, speed: number) {
    Text(label)
      .fontSize(13)
      .fontColor(this.danmakuSpeed === speed ? '#1288FA' : '#1E252D')
      .fontWeight(this.danmakuSpeed === speed ? FontWeight.Medium : FontWeight.Normal)
      .textAlign(TextAlign.Center)
      .layoutWeight(1)
      .padding({ top: 8, bottom: 8 })
      .backgroundColor(this.danmakuSpeed === speed ? '#FFF5ED' : Color.White)
      .borderRadius(14)
      .onClick(() => { this.danmakuSpeed = speed; });
  }

  @Builder
  settingsPage() {
    Scroll() {
      Column({ space: 12 }) {
        Text('视频播放').fontSize(16).fontWeight(FontWeight.Bold)
          .width('100%').padding({ left: 4 });
        Row({ space: 6 }) {
          this.playModeChipPage('单集循环', 1, true);
          this.playModeChipPage('随机连播', 2, true);
          this.playModeChipPage(this.isPortraitCurrentVideo() ? '合集顺序' : '停止推荐', 3, true);
        }.width('100%');
        Text(this.isPortraitCurrentVideo()
          ? '单集循环、随机连播或按合集顺序播放'
          : '单集循环、随机播放或播放结束后停止推荐')
          .fontSize(11).fontColor('#858C94').lineHeight(16)
          .width('100%').padding({ left: 4 });

        Text('弹幕设置').fontSize(16).fontWeight(FontWeight.Bold)
          .width('100%').padding({ left: 4, top: 8 });

        Text('字体大小').fontSize(13).fontColor('#858C94')
          .width('100%').padding({ left: 4 });
        this.danmakuSizeControl();

        Text('显示区域').fontSize(13).fontColor('#858C94')
          .width('100%').padding({ left: 4 });
        this.danmakuAreaControl();

        Text('不透明度').fontSize(13).fontColor('#858C94')
          .width('100%').padding({ left: 4 });
        Row({ space: 8 }) {
          this.danmakuOpacityChip('20%', 0.2);
          this.danmakuOpacityChip('50%', 0.5);
          this.danmakuOpacityChip('80%', 0.8);
          this.danmakuOpacityChip('100%', 1);
        }.width('100%');

        Text('滚动速度').fontSize(13).fontColor('#858C94')
          .width('100%').padding({ left: 4 });
        Row({ space: 8 }) {
          this.danmakuSpeedChip('慢', 0.5);
          this.danmakuSpeedChip('中', 1);
          this.danmakuSpeedChip('快', 1.5);
          this.danmakuSpeedChip('极快', 2);
        }.width('100%');
      }.width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12, top: 14, bottom: this.bottomInset + 30 });
    }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      .backgroundColor('#F7F8FA');
  }

  @Builder
  detailBody() {
    Tabs({ index: this.detailSection }) {
      TabContent() {
        this.detailScroll();
      }

      TabContent() {
        Refresh({ refreshing: $$this.commentRefreshing, offset: 56, friction: 80 }) {
          Scroll() {
            Column({ space: 18 }) {
              this.commentPanel();
            }.width('100%').alignItems(HorizontalAlign.Start)
              .padding({ left: 16, right: 16, top: 14, bottom: this.bottomInset + 30 });
          }.layoutWeight(1).width('100%').scrollBar(BarState.Off).backgroundColor(Color.White);
        }.layoutWeight(1).width('100%')
          .onRefreshing(() => {
            this.onLoadComments(true);
            setTimeout(() => { this.commentRefreshing = false; }, 800);
          })
      }

      TabContent() {
        Refresh({ refreshing: $$this.settingsRefreshing, offset: 56, friction: 80 }) {
          Scroll() {
            Column({ space: 12 }) {
              // 与竖屏化设置面板同构：同芯片样式、同分组、同数据源
              Text('视频播放').fontSize(16).fontWeight(FontWeight.Bold)
                .width('100%').padding({ left: 4 });
              Row({ space: 8 }) {
                this.settingChip('单集循环', this.playMode === 1,
                  (): void => { this.onSetPlayMode(1); });
                this.settingChip('随机连播', this.playMode === 2,
                  (): void => { this.onSetPlayMode(2); });
                this.settingChip(this.isPortraitCurrentVideo() ? '合集顺序' : '停止推荐', this.playMode === 3,
                  (): void => { this.onSetPlayMode(3); });
              }.width('100%');
              Text(this.isPortraitCurrentVideo()
                ? '单集循环、随机连播或按合集顺序播放'
                : '单集循环、随机播放或播放结束后停止推荐')
                .fontSize(11).fontColor('#858C94').lineHeight(16)
                .width('100%').padding({ left: 4 });

              Text('长按倍速').fontSize(16).fontWeight(FontWeight.Bold)
                .width('100%').padding({ left: 4, top: 4 });
              Row({ space: 8 }) {
                this.settingChip('0.75x', this.defaultSpeed === 0.75,
                  (): void => { this.defaultSpeed = 0.75; });
                this.settingChip('1.25x', this.defaultSpeed === 1.25,
                  (): void => { this.defaultSpeed = 1.25; });
                this.settingChip('1.50x', this.defaultSpeed === 1.5,
                  (): void => { this.defaultSpeed = 1.5; });
                this.settingChip('2.00x', this.defaultSpeed === 2,
                  (): void => { this.defaultSpeed = 2; });
              }.width('100%');
              Text('长按视频时使用此倍速，普通播放保持 1.0x')
                .fontSize(11).fontColor('#858C94').lineHeight(16)
                .width('100%').padding({ left: 4 });

              Text('偏好设置').fontSize(16).fontWeight(FontWeight.Bold)
                .width('100%').padding({ left: 4, top: 4 });
              Row({ space: 6 }) {
                this.settingChip('不看视频', false,
                  (): void => { this.onDetailAction('videohide'); });
                this.settingChip('分享视频', false,
                  (): void => { this.onDetailAction('videoshare'); });
                this.settingChip('举报视频', false,
                  (): void => { this.onDetailAction('videoreport'); });
                this.settingChip('进小黑屋', false,
                  (): void => { this.onDetailAction('videoblock'); });
              }.width('100%');
              Text('不看视频/举报会把当前视频移出列表；进小黑屋屏蔽该UP主')
                .fontSize(11).fontColor('#858C94').lineHeight(16)
                .width('100%').padding({ left: 4 });

              Text('弹幕设置').fontSize(16).fontWeight(FontWeight.Bold)
                .width('100%').padding({ left: 4, top: 4 });

              Text('字体大小').fontSize(13).fontColor('#858C94')
                .width('100%').padding({ left: 4 });
              Row({ space: 8 }) {
                this.settingChip('45', this.danmakuFontSize === 45,
                  (): void => { this.onSetDanmakuFontSize(45); });
                this.settingChip('50', this.danmakuFontSize === 50,
                  (): void => { this.onSetDanmakuFontSize(50); });
                this.settingChip('55', this.danmakuFontSize === 55,
                  (): void => { this.onSetDanmakuFontSize(55); });
                this.settingChip('60', this.danmakuFontSize === 60,
                  (): void => { this.onSetDanmakuFontSize(60); });
              }.width('100%');

              Text('显示区域').fontSize(13).fontColor('#858C94')
                .width('100%').padding({ left: 4 });
              Row({ space: 8 }) {
                this.settingChip('25%', this.danmakuArea === 25,
                  (): void => { this.onSetDanmakuArea(25); });
                this.settingChip('50%', this.danmakuArea === 50,
                  (): void => { this.onSetDanmakuArea(50); });
                this.settingChip('75%', this.danmakuArea === 75,
                  (): void => { this.onSetDanmakuArea(75); });
                this.settingChip('100%', this.danmakuArea === 100,
                  (): void => { this.onSetDanmakuArea(100); });
              }.width('100%');

              Text('不透明度').fontSize(13).fontColor('#858C94')
                .width('100%').padding({ left: 4 });
              Row({ space: 8 }) {
                this.settingChip('20%', this.danmakuOpacity === 0.2,
                  (): void => { this.danmakuOpacity = 0.2; });
                this.settingChip('50%', this.danmakuOpacity === 0.5,
                  (): void => { this.danmakuOpacity = 0.5; });
                this.settingChip('80%', this.danmakuOpacity === 0.8,
                  (): void => { this.danmakuOpacity = 0.8; });
                this.settingChip('100%', this.danmakuOpacity === 1,
                  (): void => { this.danmakuOpacity = 1; });
              }.width('100%');

              Text('滚动速度').fontSize(13).fontColor('#858C94')
                .width('100%').padding({ left: 4 });
              Row({ space: 8 }) {
                this.settingChip('慢', this.danmakuSpeed === 0.5,
                  (): void => { this.danmakuSpeed = 0.5; });
                this.settingChip('中', this.danmakuSpeed === 1,
                  (): void => { this.danmakuSpeed = 1; });
                this.settingChip('快', this.danmakuSpeed === 1.5,
                  (): void => { this.danmakuSpeed = 1.5; });
                this.settingChip('极快', this.danmakuSpeed === 2,
                  (): void => { this.danmakuSpeed = 2; });
              }.width('100%');
            }.width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 12, right: 12, top: 14, bottom: this.bottomInset + 30 });
          }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
            .backgroundColor('#F7F8FA');
        }.layoutWeight(1).width('100%')
          .onRefreshing(() => {
            setTimeout(() => { this.settingsRefreshing = false; }, 500);
          })
      }
    }
    .width('100%').layoutWeight(1).backgroundColor(Color.White)
    .barHeight(0)
    .gesture(PanGesture({ fingers: 1, direction: PanDirection.Vertical })
      .onActionStart((event: GestureEvent): void => {
        this.panStartWeight = this.videoWeight;
      })
      .onActionUpdate((event: GestureEvent): void => {
        if (this.currentAspect() >= 1) return;
        const delta: number = event.offsetY / 64;
        this.videoWeight = Math.min(6, Math.max(4, this.panStartWeight + delta));
      }))
    .onChange((index: number) => {
      this.detailSection = index;
      if (index === 1) this.onLoadComments(true);
    });
  }

  @Builder
  followOptionsMenu() {
    Column({ space: 2 }) {
      Text('只是关注').fontSize(13).fontColor('#1E252D')
        .width('100%').height(34).textAlign(TextAlign.Center)
        .onClick((): void => {
          this.followMenuVisible = false;
          this.onFollowAuthor(true);
        });
      Text('特别关注').fontSize(13).fontColor('#1E252D')
        .width('100%').height(34).textAlign(TextAlign.Center)
        .onClick((): void => {
          this.followMenuVisible = false;
          this.onFollowAuthor(true);
        });
      Text('设置分组').fontSize(13).fontColor('#1E252D')
        .width('100%').height(34).textAlign(TextAlign.Center)
        .onClick((): void => {
          this.followMenuVisible = false;
          this.onFollowGroup();
        });
    }.width(124).padding({ top: 6, bottom: 6 }).backgroundColor(Color.Transparent);
  }

  @Builder
  followedMenu() {
    Column({ space: 2 }) {
      Text('取消关注').fontSize(13).fontColor('#1E252D')
        .width('100%').height(34).textAlign(TextAlign.Center)
        .onClick((): void => {
          this.onFollowAuthor(false);
        });
    }.width(124).padding({ top: 6, bottom: 6 }).backgroundColor(Color.Transparent);
  }

  @Builder
  followBubble(small: boolean) {
    Row({ space: 4 }) {
      Image($r('app.media.listb')).width(small ? 13 : 15).height(small ? 13 : 15)
        .fillColor((this.videos[this.currentIndex].authorFollowed ?? false) ? '#59616B' : '#1288FA');
      Text((this.videos[this.currentIndex].authorFollowed ?? false) ? '已关注' : '关注')
        .fontSize(small ? 11 : 13)
        .fontColor((this.videos[this.currentIndex].authorFollowed ?? false) ? '#59616B' : '#1288FA');
    }
    .padding({ left: 10, right: 10, top: small ? 4 : 6, bottom: small ? 4 : 6 })
    .backgroundColor((this.videos[this.currentIndex].authorFollowed ?? false) ? '#F1F3F5' : '#E5F3FA')
    .borderRadius(16)
    // 非受控菜单：点击气泡弹出；已关注弹"取消关注"，未关注弹关注方式三选项。
    // 不使用 isShow 受控形式——面板随控制条显隐重建时残留状态会导致菜单乱弹。
    .bindMenu((this.videos[this.currentIndex].authorFollowed ?? false)
      ? this.followedMenu() : this.followOptionsMenu(), {
        placement: Placement.Bottom,
        enableArrow: false,
        showInSubWindow: true
      });
  }

  @Builder
  episodeSheet() {
    Column() {
      Text(this.videos[this.currentIndex].duration > 0 ? '暂无更多选集' : '当前视频无合集')
        .fontSize(14).fontColor('#30363D').width('100%').textAlign(TextAlign.Center)
        .padding({ top: 18, bottom: 24 });
    }.width('100%').padding({ bottom: this.bottomInset + 8 })
      .backgroundColor('#F7F8FA');
  }

  build() {
    Stack() {
      Column() {
        if (this.verticalExpanded) {
          // 竖屏化：视频区在上（底部与弹幕输入行顶部对齐），输入/图标行固定其下；
          // 控制条随视频区底部，UP 信息+简介悬浮在视频底部，点击视频切换为控制条
          Column() {
            Stack({ alignContent: Alignment.Bottom }) {
              Stack() {
                this.videoArea();
              }
              .width('100%').height('100%')
              .backgroundColor(Color.Black)
              // 信息面板：控制条显示期间自动让位隐藏
              if (!this.playbackControlsVisible) {
                this.verticalInfoOverlay();
              }
            }
            .width('100%').layoutWeight(1)
            .backgroundColor(Color.Black);
            this.verticalActionBar();
          }
          .width('100%').layoutWeight(1)
          .backgroundColor(Color.Black);
        } else if (this.currentAspect() < 1) {
          Stack() {
            this.videoArea();
          }
          .width('100%').layoutWeight(this.videoWeight).backgroundColor(Color.Black);
          Column() {
            this.detailTabs();
            this.detailBody();
          }
          .width('100%').layoutWeight(10 - this.videoWeight)
          .backgroundColor(Color.White);
        } else {
          Stack() {
            this.videoArea();
          }
          .width('100%').aspectRatio(this.currentAspect()).backgroundColor(Color.Black);
          this.detailTabs();
          this.detailBody();
        }
      }
      .width('100%').height('100%')
      .padding({ top: this.topInset })
      .backgroundColor(Color.Black);

      if (this.detailSection === 1 && !this.showCommentInput && !this.verticalExpanded) {
        Button() {
          Image($r('app.media.edit')).width(22).height(22).fillColor('#1288FA');
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(46).height(46)
        .backgroundColor(Color.White).borderRadius(23)
        .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
        .position({ right: 14, bottom: this.bottomInset + 96 })
          .onClick(() => { this.showCommentInput = true; });
      }
      if (this.detailSection === 1 && this.showCommentInput && !this.verticalExpanded) {
        Row({ space: 2 }) {
          Button() {
            Image($r('app.media.bqa')).width(20).height(20).fillColor('#59616B');
          }
          .type(ButtonType.Capsule).width(34).height(40).backgroundColor(Color.Transparent)
          .onClick((): void => { this.onDetailAction('commentemoji'); });
          Button() {
            Image($r('app.media.img')).width(20).height(20).fillColor('#59616B');
          }
          .type(ButtonType.Capsule).width(34).height(40).backgroundColor(Color.Transparent)
          .onClick((): void => { this.onDetailAction('commentimage'); });
          Button() {
            Image($r('app.media.copy')).width(20).height(20).fillColor('#59616B');
          }
          .type(ButtonType.Capsule).width(34).height(40).backgroundColor(Color.Transparent)
          .onClick((): void => { this.onDetailAction('commentinsert'); });
          TextInput({ placeholder: this.commentReplyTarget === '' ? '说点什么...' : '回复 ' + this.commentReplyTarget,
            text: this.commentInputText })
            .layoutWeight(1).height(40).fontSize(14).fontColor('#1E252D')
            .backgroundColor('#F1F3F5').borderRadius(20)
            .focusable(true)
            // 编辑器打开即获得焦点；表情面板显示时保留焦点，让系统键盘
            // 继续停留在底部，表情区直接出现在键盘上方，不再二次弹窗。
            .defaultFocus(this.showCommentInput)
            .onChange((value: string) => { this.onCommentInputChanged(value); })
            .onSubmit((): void => { this.onSubmitComment(); });
          Button() {
            Image($r('app.media.send')).width(22).height(22).fillColor('#1288FA');
          }
          .type(ButtonType.Capsule).width(40).height(40)
          .backgroundColor(Color.Transparent)
          .onClick((): void => { this.onSubmitComment(); });
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: this.bottomInset + 12 })
        .backgroundColor(Color.White)
        .borderRadius({ topLeft: 14, topRight: 14 })
        .shadow({ radius: 10, color: '#1A000000', offsetX: 0, offsetY: -2 })
        // 编辑器作为评论区上方的浮层定位，键盘出现时只上移编辑器，不改变视频区布局。
        .position({ left: 0, right: 0, bottom: this.keyboardInset })
        .zIndex(12);
      }
      this.commentActionSheet();
      this.textSelectSheet();
      this.atContactPanel();
      if (this.emojiPanelVisible) {
        Column().width('100%').height('100%').backgroundColor('#33000000')
          .onClick((): void => { this.emojiPanelVisible = false; })
          .zIndex(10);
        this.emojiPickerPanel();
      }
    }
    .width('100%').height('100%')
    .bindSheet($$this.episodeListVisible, this.episodeSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true
    });
  }
}
