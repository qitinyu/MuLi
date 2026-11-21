import { PAGE_PADDING } from '../common/DesignSpec';

/**
 * 列表的状态占位：加载中 / 失败重试 / 空数据。
 * 三个页面（推荐、热门、直播、动态）共用同一套视觉，避免每个页面各写一遍。
 */
@Component
export struct StateView {
  /** 'loading' | 'error' | 'empty' | 'idle' */
  @Prop kind: string = 'idle';
  @Prop message: string = '';
  @Prop hint: string = '';
  onRetry: () => void = () => {
  };

  build() {
    Column({ space: 10 }) {
      if (this.kind === 'loading') {
        LoadingProgress()
          .width(30)
          .height(30)
          .color($r('app.color.brand_primary'))
        Text(this.message.length > 0 ? this.message : '加载中')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
      } else if (this.kind === 'error') {
        SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
          .fontSize(30)
          .fontColor([$r('app.color.text_tertiary')])
        Text(this.message.length > 0 ? this.message : '加载失败')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
        if (this.hint.length > 0) {
          Text(this.hint)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Center)
        }
        Row() {
          Text('重试')
            .fontSize(14)
            .fontColor($r('app.color.text_on_brand'))
            .padding({ left: 22, right: 22, top: 8, bottom: 8 })
            .backgroundColor($r('app.color.brand_primary'))
            .borderRadius(18)
        }
        .margin({ top: 4 })
        .onClick(() => {
          this.onRetry();
        })
      } else if (this.kind === 'empty') {
        SymbolGlyph($r('sys.symbol.inbox'))
          .fontSize(30)
          .fontColor([$r('app.color.text_tertiary')])
        Text(this.message.length > 0 ? this.message : '暂时没有内容')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
        if (this.hint.length > 0) {
          Text(this.hint)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Center)
        }
      }
    }
    .width('100%')
    .padding({ left: PAGE_PADDING * 2, right: PAGE_PADDING * 2, top: 80, bottom: 60 })
    .justifyContent(FlexAlign.Center)
  }
}

/** 列表底部加载指示（上拉翻页时显示） */
@Component
export struct ListFooter {
  @Prop text: string = '加载中';
  @Prop showProgress: boolean = true;

  build() {
    Row({ space: 8 }) {
      if (this.showProgress) {
        LoadingProgress()
          .width(18)
          .height(18)
          .color($r('app.color.text_tertiary'))
      }
      Text(this.text)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
  }
}