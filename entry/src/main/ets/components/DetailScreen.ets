import { VideoItem } from '../models/VideoItem';
import { VideoComment } from '../services/ReplyService';
import { FormatUtils } from '../utils/FormatUtils';
import { loadingIndicator } from '../utils/CommonBuilders';

@Component
export struct DetailScreen {
  @BuilderParam videoArea: () => void = this.emptyArea;
  @Link episodeListVisible: boolean;
  @Consume verticalExpanded: boolean;
  @Consume videoWeight: number;
  @Consume pendingResumeMs: number;
  @Consume videos: VideoItem[];
  @Consume currentIndex: number;
  @Consume detailSection: number;
  @Consume detailExpanded: boolean;
  @Consume detailLoading: boolean;
  @Consume detailError: string;
  @Consume topInset: number;
  @Consume bottomInset: number;
  @Consume danmakuText: string;
  @Consume danmakuEnabled: boolean;
  @Consume showCommentInput: boolean;
  @Consume commentInputText: string;
  @Consume comments: VideoComment[];
  @Consume commentTotal: number;
  @Consume commentLoading: boolean;
  @Consume commentError: string;
  @Consume commentHasMore: boolean;
  @Consume expandedCommentId: number;
  @Consume subReplies: VideoComment[];
  @Consume subLoading: boolean;
  @Consume subHasMore: boolean;
  @Consume playbackCurrentMs: number;
  @Consume playbackControlsVisible: boolean;
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
  onFollowAuthor: (on: boolean) => void = (on: boolean): void => {};
  onFollowGroup: () => void = (): void => {};
  onSetPlayMode: (mode: number) => void = (mode: number): void => {};
  onShowControls: () => void = (): void => {};
  onToggleControls: () => void = (): void => {};
  @State followMenuVisible: boolean = false;
  onOpenLandscape: () => void = (): void => {};

  @Builder
  emptyArea() {
  }

  private currentAspect(): number {
    return FormatUtils.currentAspect(this.videos[this.currentIndex]);
  }

  @Builder
  detailAction(label: string, iconName: string, active: boolean, action: () => void,
    longPress: () => void = (): void => {}) {
    Column({ space: 3 }) {
      if (iconName === 'dianzan') {
        Image($r('app.media.dianzan')).width(24).height(24)
          .opacity(active ? 1 : 0.85);
      } else if (iconName === 'diancai') {
        Image($r('app.media.diancai')).width(24).height(24).opacity(active ? 1 : 0.85);
      } else if (iconName === 'toubi') {
        Image($r('app.media.toubi')).width(24).height(24)
          .opacity(active ? 1 : 0.85);
      } else if (iconName === 'favorites') {
        Image($r('app.media.favorites')).width(24).height(24)
          .opacity(active ? 1 : 0.85);
      } else if (iconName === 'watch_later') {
        Image($r('app.media.watch_later')).width(24).height(24).opacity(active ? 1 : 0.85);
      } else {
        Image($r('app.media.share')).width(24).height(24).opacity(0.85);
      }
      Text(label).fontSize(12).fontColor(active ? '#F04B55' : '#3E4854')
        .fontWeight(active ? FontWeight.Bold : FontWeight.Normal)
        .maxLines(1);
    }.layoutWeight(1).alignItems(HorizontalAlign.Center)
      .onClick(() => { action(); })
      .gesture(LongPressGesture({ repeat: false }).onAction((): void => { longPress(); }));
  }

  @Builder
  verticalActionCount(iconName: string, count: number, active: boolean, action: () => void,
    longPress: () => void = (): void => {}, label: string = '') {
    Column({ space: 3 }) {
      if (iconName === 'dianzan') {
        Image($r('app.media.dianzan')).width(24).height(24)
          .fillColor(active ? '#F04B55' : Color.White);
      } else if (iconName === 'toubi') {
        Image($r('app.media.toubi')).width(24).height(24)
          .fillColor(active ? '#F04B55' : Color.White);
      } else if (iconName === 'favorites') {
        Image($r('app.media.favorites')).width(24).height(24)
          .fillColor(active ? '#F0A24B' : Color.White);
      } else {
        Image($r('app.media.pl')).width(24).height(24).fillColor(Color.White);
      }
      Text(label !== '' ? label : (count > 0 ? FormatUtils.formatCount(count) : '-'))
        .fontSize(9).fontColor(active ? '#F04B55' : '#DDE5EA').maxLines(1);
    }.width(40)
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => { action(); })
      .gesture(LongPressGesture({ repeat: false }).onAction((): void => { longPress(); }));
  }

  @Builder
  verticalPanel() {
    Column({ space: 8 }) {
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
          Text(this.videos[this.currentIndex].author === '' ? '未知UP主' : this.videos[this.currentIndex].author)
            .fontSize(14).fontWeight(FontWeight.Bold).fontColor(Color.White)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
          Text(this.videos[this.currentIndex].authorFans !== undefined
            ? FormatUtils.formatCount(this.videos[this.currentIndex].authorFans) + ' 粉丝' : '')
            .fontSize(10).fontColor('#B8C4CC');
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          .onClick((): void => { this.onDetailAction('openauthor'); });
        this.followBubble(true);
      }.width('100%');
      if (this.videos[this.currentIndex].description !== '') {
        Text(this.videos[this.currentIndex].description)
          .fontSize(12).fontColor('#C7D0D6').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
      }
      Row({ space: 10 }) {
        Stack({ alignContent: Alignment.Start }) {
          TextInput({ placeholder: '发弹幕', text: this.danmakuText })
            .layoutWeight(1).height(34).fontSize(12)
            .fontColor('#E8EEF3').placeholderColor('#8FA3B0')
            .backgroundColor('#2EFFFFFF').borderRadius(17)
            .padding({ left: 34, right: 12 })
            .enabled(this.danmakuEnabled)
            .onChange((value: string) => { this.danmakuText = value; })
            .onSubmit((): void => { this.onSendDanmaku(); });
          Image($r('app.media.dmg')).width(16).height(16)
            .opacity(this.danmakuEnabled ? 1 : 0.4)
            .margin({ left: 10 });
        }
        .layoutWeight(1)
        .gesture(TapGesture().onAction((): void => { this.onDetailAction('comments'); }))
        this.verticalActionCount('dianzan', this.videos[this.currentIndex].likeCount,
          this.videos[this.currentIndex].liked ?? false,
          (): void => { this.onDetailAction('like'); });
        this.verticalActionCount('toubi', this.videos[this.currentIndex].coinCount ?? 0,
          this.videos[this.currentIndex].coined ?? false,
          (): void => { this.onDetailAction('coin'); });
        this.verticalActionCount('favorites', this.videos[this.currentIndex].favoriteCount ?? 0,
          this.videos[this.currentIndex].favored ?? false,
          (): void => { this.onDetailAction('fav'); },
          (): void => { this.onDetailAction('favsheet'); });
        this.verticalActionCount('pl', this.videos[this.currentIndex].commentCount,
          false, (): void => { this.onDetailAction('comments'); }, (): void => {}, '评论');
        this.verticalActionCount('sphsz', 0,
          false, (): void => { this.onDetailAction('settings'); }, (): void => {}, '设置');
      }.width('100%');
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: this.bottomInset + 12 });
  }

  @Builder
  detailTabs() {
    Row() {
      Row({ space: 14 }) {
        Text('简介').fontSize(15)
          .fontColor(this.detailSection === 0 ? '#1677A8' : '#59616B')
          .fontWeight(this.detailSection === 0 ? FontWeight.Bold : FontWeight.Normal)
          .onClick(() => { this.detailSection = 0; });
        Text('评论').fontSize(15)
          .fontColor(this.detailSection === 1 ? '#1677A8' : '#59616B')
          .fontWeight(this.detailSection === 1 ? FontWeight.Bold : FontWeight.Normal)
          .onClick(() => { this.detailSection = 1; this.onLoadComments(true); });
        Text('设置').fontSize(15)
          .fontColor(this.detailSection === 2 ? '#1677A8' : '#59616B')
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
        LongPressGesture({ repeat: false, duration: 350 }),
        PanGesture({ fingers: 1, direction: PanDirection.Vertical })
          .onActionStart((event: GestureEvent): void => {
            this.panStartWeight = this.videoWeight;
          })
          .onActionUpdate((event: GestureEvent): void => {
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
            this.videoWeight = Math.min(8, Math.max(4, weight));
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
  subReplyItem(reply: VideoComment) {
    Row({ space: 8 }) {
      if (reply.avatar !== '') {
        Image(reply.avatar).width(26).height(26).borderRadius(13).objectFit(ImageFit.Cover);
      } else {
        Row().width(26).height(26).borderRadius(13).backgroundColor('#DCE3EF');
      }
      Column({ space: 3 }) {
        Row({ space: 5 }) {
          Text(reply.userName).fontSize(12).fontColor('#59616B').fontWeight(FontWeight.Medium)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '65%' });
          Text('LV' + String(reply.level)).fontSize(8).fontColor(Color.White)
            .backgroundColor(FormatUtils.levelColor(reply.level))
            .borderRadius(3).padding({ left: 3, right: 3, top: 1, bottom: 1 });
        }.width('100%');
        Text(reply.message).fontSize(13).fontColor('#1E252D').lineHeight(19).width('100%');
        Row({ space: 12 }) {
          Text(FormatUtils.formatPublishTime(reply.publishTime)).fontSize(10).fontColor('#A0A6AD');
          Row({ space: 3 }) {
            Image($r('app.media.dianzan')).width(12).height(12);
            Text(FormatUtils.formatCount(reply.likeCount)).fontSize(10).fontColor('#858C94');
          }
        }.width('100%');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }.width('100%').alignItems(VerticalAlign.Top);
  }

  @Builder
  commentItem(comment: VideoComment) {
    Column({ space: 8 }) {
      Row({ space: 10 }) {
        if (comment.avatar !== '') {
          Image(comment.avatar).width(38).height(38).borderRadius(19).objectFit(ImageFit.Cover);
        } else {
          Row().width(38).height(38).borderRadius(19).backgroundColor('#DCE3EF');
        }
        Column({ space: 5 }) {
          Row({ space: 5 }) {
            Text(comment.userName).fontSize(13).fontColor('#59616B').fontWeight(FontWeight.Medium)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '70%' });
            Text('LV' + String(comment.level)).fontSize(9).fontColor(Color.White)
              .backgroundColor(FormatUtils.levelColor(comment.level))
              .borderRadius(3).padding({ left: 3, right: 3, top: 1, bottom: 1 });
          }.width('100%');
          Text(comment.message).fontSize(15).fontColor('#1E252D').lineHeight(22).width('100%');
          Row({ space: 14 }) {
            Text(FormatUtils.formatPublishTime(comment.publishTime)).fontSize(11).fontColor('#A0A6AD');
            Row({ space: 3 }) {
              Image($r('app.media.dianzan')).width(14).height(14)
                ;
              Text(FormatUtils.formatCount(comment.likeCount)).fontSize(11)
                .fontColor(comment.liked ? '#F04B55' : '#858C94');
            }
              .onClick((): void => { this.onLikeComment(comment); });
            Row({ space: 3 }) {
              Image($r('app.media.pl')).width(14).height(14)
                .fillColor(this.expandedCommentId === comment.id ? '#1677A8' : '#858C94');
              Text(FormatUtils.formatCount(comment.replyCount)).fontSize(11)
                .fontColor(this.expandedCommentId === comment.id ? '#1677A8' : '#858C94');
            }
              .onClick((): void => { this.onToggleReplies(comment); });
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
              this.subReplyItem(reply);
            }, (reply: VideoComment) => `sub_${reply.id}`);
            if (this.subHasMore) {
              Text(this.subLoading ? '正在加载...' : '展开更多回复')
                .fontSize(12).fontColor('#1677A8')
                .onClick((): void => { this.onLoadSubReplies(comment.id, false); });
            }
          }
        }
        .width('100%')
        .padding({ left: 48, top: 4, bottom: 4 })
        .alignItems(HorizontalAlign.Start);
      }
    }.width('100%').padding({ top: 10, bottom: 10 })
      .border({ width: { bottom: 1 }, color: '#E9EDF0' });
  }

  @Builder
  commentPanel() {
    Column({ space: 12 }) {
      Row() {
        Text('评论 ' + FormatUtils.formatCount(this.commentTotal > 0
          ? this.commentTotal : this.videos[this.currentIndex].commentCount))
          .fontSize(18).fontWeight(FontWeight.Bold).layoutWeight(1);
        Text('按热度').fontSize(13).fontColor('#858C94');
      }.width('100%').padding({ top: 4, bottom: 6 });
      if (this.commentLoading && this.comments.length === 0) {
        loadingIndicator('正在加载评论', '#1677A8');
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
      Column({ space: 14 }) {
          Row({ space: 12 }) {
            if ((this.videos[this.currentIndex].authorFace ?? '') !== '') {
              Image(this.videos[this.currentIndex].authorFace ?? '')
                .width(52).height(52).borderRadius(26).objectFit(ImageFit.Cover);
            } else {
              Image($r('app.media.user_me')).width(52).height(52).borderRadius(26).objectFit(ImageFit.Contain);
            }
            Column({ space: 4 }) {
              Text(`@${this.videos[this.currentIndex].author}`).fontSize(17);
              Text(`${this.videos[this.currentIndex].authorFans !== undefined
                ? FormatUtils.formatCount(this.videos[this.currentIndex].authorFans) + ' 粉丝' : '粉丝 --'} · ${this.videos[this.currentIndex].authorVideos !== undefined
                ? this.videos[this.currentIndex].authorVideos + ' 投稿' : '投稿 --'}`)
                .fontSize(12).fontColor('#858C94');
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              .onClick((): void => { this.onDetailAction('openauthor'); });
            this.followBubble(false);
          }.width('100%').height(64);
          Row({ space: 8 }) {
            Text(this.videos[this.currentIndex].title).fontSize(19)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1);
            Button() {
              Image($r('app.media.down')).width(17).height(17);
            }
            .type(ButtonType.ROUNDED_RECTANGLE).width(32).height(32)
            .backgroundColor(Color.Transparent).borderRadius(16)
            .onClick(() => { this.detailExpanded = !this.detailExpanded; });
          }.width('100%').alignItems(VerticalAlign.Center);

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
                  .width('100%');
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
              'dianzan', this.videos[this.currentIndex].liked ?? false,
              (): void => { this.onDetailAction('like'); });
            this.detailAction('点踩', 'diancai', false,
              (): void => { this.onDetailAction('dislike'); });
            this.detailAction((this.videos[this.currentIndex].coinCount ?? 0) > 0
              ? FormatUtils.formatCount(this.videos[this.currentIndex].coinCount ?? 0) : '投币',
              'toubi', this.videos[this.currentIndex].coined ?? false,
              (): void => { this.onDetailAction('coin'); });
            this.detailAction((this.videos[this.currentIndex].favoriteCount ?? 0) > 0
              ? FormatUtils.formatCount(this.videos[this.currentIndex].favoriteCount ?? 0) : '收藏',
              'favorites', this.videos[this.currentIndex].favored ?? false,
              (): void => { this.onDetailAction('fav'); },
              (): void => { this.onDetailAction('favsheet'); });
            this.detailAction('再看', 'watch_later', false,
              (): void => { this.onDetailAction('watchlater'); });
            this.detailAction('分享', 'share', false,
              (): void => { this.onDetailAction('share'); });
          }.width('100%').height(64).padding({ top: 12, bottom: 12 })
            .border({ width: { bottom: 1 }, color: '#E5E8EC' });
          ForEach(this.videos, (item: VideoItem) => {
            if (!item.placeholder) {
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
            }
          }, (item: VideoItem) => `related_${item.id}`);
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 14, bottom: this.bottomInset + 30 });
    }.layoutWeight(1).width('100%').scrollBar(BarState.Off).backgroundColor(Color.White);
  }

  @Builder
  commentScroll() {
    Scroll() {
      Column({ space: 14 }) {
        this.commentPanel();
      }.width('100%').alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 14, bottom: this.bottomInset + 30 });
    }.layoutWeight(1).width('100%').scrollBar(BarState.Off).backgroundColor(Color.White);
  }

  @Builder
  playModeChipPage(label: string, mode: number, enabled: boolean) {
    Row({ space: 5 }) {
      Checkbox({ name: 'page_' + label, group: 'page_playmode' })
        .select(this.playMode === mode)
        .selectedColor('#1677A8')
        .enabled(enabled)
        .width(16)
        .height(16)
        .onChange((value: boolean) => {
          if (value) {
            this.onSetPlayMode(mode);
          }
        });
      Text(label).fontSize(13)
        .fontColor(enabled ? (this.playMode === mode ? '#1677A8' : '#1E252D') : '#A4A9AF')
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

  @Builder
  settingsPage() {
    Scroll() {
      Column({ space: 12 }) {
        Text('视频播放').fontSize(16).fontWeight(FontWeight.Bold)
          .width('100%').padding({ left: 4 });
        Row({ space: 6 }) {
          this.playModeChipPage('单集循环', 1, true);
          this.playModeChipPage('随机连播', 2, true);
          this.playModeChipPage('合集循环', 3, false);
        }.width('100%');
        Text('单集循环：播完自动重播本视频；随机连播：竖屏化时播完自动切换下一个推荐视频')
          .fontSize(11).fontColor('#858C94').lineHeight(16)
          .width('100%').padding({ left: 4 });
      }.width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 12, right: 12, top: 14, bottom: this.bottomInset + 30 });
    }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      .backgroundColor('#F7F8FA');
  }

  @Builder
  detailBody() {
    Column() {
      if (this.detailSection === 1) {
        this.commentScroll();
      } else if (this.detailSection === 2) {
        this.settingsPage();
      } else {
        this.detailScroll();
      }
    }.width('100%').layoutWeight(1)
      .gesture(PanGesture({ fingers: 1, direction: PanDirection.Horizontal })
        .onActionEnd((event: GestureEvent): void => {
          if (event.offsetX < -60 && this.detailSection < 2) {
            this.detailSection = this.detailSection + 1;
            if (this.detailSection === 1) this.onLoadComments(true);
          } else if (event.offsetX > 60 && this.detailSection > 0) {
            this.detailSection = this.detailSection - 1;
          }
        }));
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
    }.width(124).padding({ top: 6, bottom: 6 }).backgroundColor('#F7F8FA')
      .borderRadius(10).shadow({ radius: 10, color: '#33000000', offsetX: 0, offsetY: 3 });
  }

  @Builder
  followedMenu() {
    Column({ space: 2 }) {
      Text('取消关注').fontSize(13).fontColor('#1E252D')
        .width('100%').height(34).textAlign(TextAlign.Center)
        .onClick((): void => {
          this.onFollowAuthor(false);
        });
    }.width(124).padding({ top: 6, bottom: 6 }).backgroundColor('#F7F8FA')
      .borderRadius(10).shadow({ radius: 10, color: '#33000000', offsetX: 0, offsetY: 3 });
  }

  @Builder
  followBubble(small: boolean) {
    Row({ space: 4 }) {
      Image($r('app.media.lista')).width(small ? 13 : 15).height(small ? 13 : 15)
        .fillColor((this.videos[this.currentIndex].authorFollowed ?? false) ? '#59616B' : '#1677A8');
      Text((this.videos[this.currentIndex].authorFollowed ?? false) ? '已关注' : '关注')
        .fontSize(small ? 11 : 13)
        .fontColor((this.videos[this.currentIndex].authorFollowed ?? false) ? '#59616B' : '#1677A8');
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
          // 竖屏化：视频容器填满区域（Video Contain 自行居中留黑边），
          // 控制条固定在区域底部；信息面板默认显示，点击视频切换为控制条
          Stack({ alignContent: Alignment.Bottom }) {
            Column() {
              Stack() {
                this.videoArea();
              }
              .width('100%').height('100%')
              .backgroundColor(Color.Black)
            }
            .width('100%').height('100%')
            .backgroundColor(Color.Black);
            // 信息面板：控制条显示期间自动让位隐藏
            if (!this.playbackControlsVisible) {
              this.verticalPanel();
            }
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
          .gesture(PanGesture({ fingers: 1, direction: PanDirection.Vertical })
            .onActionStart((event: GestureEvent): void => {
              this.panStartWeight = this.videoWeight;
            })
            .onActionUpdate((event: GestureEvent): void => {
              if (this.currentAspect() >= 1) return;
              const delta: number = event.offsetY / 64;
              this.videoWeight = Math.min(8, Math.max(4, this.panStartWeight + delta));
            }));
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
          Image($r('app.media.edit')).width(22).height(22).fillColor('#1677A8');
        }
        .type(ButtonType.ROUNDED_RECTANGLE).width(46).height(46)
        .backgroundColor(Color.White).borderRadius(23)
        .shadow({ radius: 8, color: '#25000000', offsetX: 0, offsetY: 2 })
        .position({ right: 14, bottom: this.bottomInset + 96 })
        .onClick(() => { this.showCommentInput = true; });
      }
      if (this.detailSection === 1 && this.showCommentInput && !this.verticalExpanded) {
        Row({ space: 8 }) {
          Button() {
            Image($r('app.media.fanhui_left')).width(18).height(18).fillColor('#59616B');
          }
          .type(ButtonType.ROUNDED_RECTANGLE).width(40).height(40)
          .backgroundColor('#F1F3F5').borderRadius(20)
          .onClick(() => {
            this.showCommentInput = false;
            this.commentInputText = '';
          });
          TextInput({ placeholder: '说点什么...', text: this.commentInputText })
            .layoutWeight(1).height(40).fontSize(14).fontColor('#1E252D')
            .backgroundColor('#F1F3F5').borderRadius(20)
            .defaultFocus(true)
            .onChange((value: string) => { this.commentInputText = value; })
            .onSubmit((): void => { this.onSubmitComment(); });
          Button('发送').height(40).fontSize(14)
            .onClick((): void => { this.onSubmitComment(); });
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: this.bottomInset + 12 })
        .backgroundColor(Color.White)
        .borderRadius({ topLeft: 14, topRight: 14 })
        .shadow({ radius: 10, color: '#1A000000', offsetX: 0, offsetY: -2 })
        .position({ left: 0, right: 0, bottom: 0 });
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
