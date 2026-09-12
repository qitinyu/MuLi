@ComponentV2
export struct ToggleItemView {
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param isEnabled: boolean = false;
  @Event onToggle: (value: boolean) => void = () => {};

  build() {
    Row() {
      if (this.subtitle) {
        Column({ space: 4 }) {
          Text(this.title)
            .fontSize(16)
            .fontWeight(500)
            .fontColor('#E6000000')
          Text(this.subtitle)
            .fontSize(12)
            .fontColor('#99000000')
            .maxLines(2)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      } else {
        Text(this.title)
          .fontSize(16)
          .fontWeight(500)
          .fontColor('#E6000000')
          .layoutWeight(1)
      }

      Blank()

      Toggle({ type: ToggleType.Switch, isOn: this.isEnabled })
        .selectedColor('#1288FA')
        .onChange((isOn: boolean) => {
          this.onToggle(isOn);
        })
    }
    .width('100%')
    .height(this.subtitle ? 64 : 52)
    .padding({ left: 12, right: 12 })
  }
}
