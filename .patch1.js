const fs = require('fs');
const p = 'entry/src/main/ets/components/DetailScreen.ets';
let s = fs.readFileSync(p, 'utf8');

// A) 展开分支：视频容器填满区域（Contain 自居中），控制条固定区域底部；点击切换控制条
const oldExpanded = `        if (this.verticalExpanded) {
          // 竖屏化：视频居中显示（竖屏视频按高度定宽/横屏视频按宽度定高），
          // 信息面板默认显示；点击视频隐藏面板并展示播放控制条
          Stack({ alignContent: Alignment.Bottom }) {
            Column() {
              if (this.currentAspect() < 1) {
                Stack() {
                  this.videoArea();
                }
                .height('100%')
                .aspectRatio(this.currentAspect())
                .backgroundColor(Color.Black)
              } else {
                Stack() {
                  this.videoArea();
                }
                .width('100%')
                .aspectRatio(this.currentAspect())
                .backgroundColor(Color.Black)
              }
            }
            .width('100%').height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .backgroundColor(Color.Black)
            .onClick((): void => {
              this.onShowControls();
            });
            // 信息面板：控制条显示期间自动让位隐藏
            if (!this.playbackControlsVisible) {
              this.verticalPanel();
            }
          }
          .width('100%').layoutWeight(1)
          .backgroundColor(Color.Black);
        } else if (this.currentAspect() < 1) {`;
const newExpanded = `        if (this.verticalExpanded) {
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
            .backgroundColor(Color.Black)
            .onClick((): void => {
              this.onToggleControls();
            });
            // 信息面板：控制条显示期间自动让位隐藏
            if (!this.playbackControlsVisible) {
              this.verticalPanel();
            }
          }
          .width('100%').layoutWeight(1)
          .backgroundColor(Color.Black);
        } else if (this.currentAspect() < 1) {`;
if (!s.includes(oldExpanded)) { console.error('expanded not found'); process.exit(1); }
s = s.replace(oldExpanded, newExpanded);

// B) 非展开竖屏分支的视频点击也改为切换
s = s.replace(`          .width('100%').layoutWeight(this.videoWeight).backgroundColor(Color.Black)
          .onClick((): void => { this.onShowControls(); });`,
`          .width('100%').layoutWeight(this.videoWeight).backgroundColor(Color.Black)
          .onClick((): void => { this.onToggleControls(); });`);
s = s.replace(`          .width('100%').aspectRatio(this.currentAspect()).backgroundColor(Color.Black)
          .onClick((): void => { this.onShowControls(); });`,
`          .width('100%').aspectRatio(this.currentAspect()).backgroundColor(Color.Black)
          .onClick((): void => { this.onToggleControls(); });`);

// C) 评论悬浮按钮与输入条：竖屏化时隐藏
s = s.replace('      if (this.detailSection === 1 && !this.showCommentInput) {',
  '      if (this.detailSection === 1 && !this.showCommentInput && !this.verticalExpanded) {');
s = s.replace('      if (this.detailSection === 1 && this.showCommentInput) {',
  '      if (this.detailSection === 1 && this.showCommentInput && !this.verticalExpanded) {');

// D) 回调：onToggleControls
s = s.replace('  onShowControls: () => void = (): void => {};',
  '  onShowControls: () => void = (): void => {};\n  onToggleControls: () => void = (): void => {};');

// F) 竖屏面板收藏图标支持长按进收藏夹面板
s = s.replace(`  @Builder
  verticalActionCount(iconName: string, count: number, active: boolean, action: () => void) {`,
`  @Builder
  verticalActionCount(iconName: string, count: number, active: boolean, action: () => void,
    longPress: () => void = (): void => {}) {`);
s = s.replace(`    }.width(52)
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => { action(); });
  }`,
`    }.width(52)
      .alignItems(HorizontalAlign.Center)
      .onClick((): void => { action(); })
      .gesture(LongPressGesture({ repeat: false }).onAction((): void => { longPress(); }));
  }`);
s = s.replace(`        this.verticalActionCount('favorites', this.videos[this.currentIndex].favoriteCount ?? 0,
          this.videos[this.currentIndex].favored ?? false,
          (): void => { this.onDetailAction('fav'); });`,
`        this.verticalActionCount('favorites', this.videos[this.currentIndex].favoriteCount ?? 0,
          this.videos[this.currentIndex].favored ?? false,
          (): void => { this.onDetailAction('fav'); },
          (): void => { this.onDetailAction('favsheet'); });`);
fs.writeFileSync(p, s);
console.log('detail screen ok');
