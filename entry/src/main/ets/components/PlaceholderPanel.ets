/**
 * 空页面占位组件。
 * 框架阶段所有未接入数据的页面统一用它表态：这里是有意留白，不是加载失败。
 */
@Component
export struct PlaceholderPanel {
  @Prop title: string = '空白页面';
  @Prop note: string = '';
  @Prop icon: Resource = $r('sys.symbol.square_grid_2x2');
  @Prop panelHeight: number = 320;

  build() {
    Column({ space: 12 }) {
      SymbolGlyph(this.icon)
        .fontSize(40)
        .fontColor([$r('app.color.text_tertiary')])
        .opacity(0.65)
      Text(this.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
      if (this.note.length > 0) {
        Text(this.note)
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.text_tertiary'))
          .textAlign(TextAlign.Center)
          .maxLines(3)
          .padding({ left: 32, right: 32 })
      }
      Text('框架占位 · 待建设')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        .backgroundColor($r('app.color.bg_field'))
        .borderRadius(10)
    }
    .width('100%')
    .height(this.panelHeight)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
