export interface SettingsItem {
  id: string;
  title: string;
  icon?: ResourceStr;
  value?: string;
  subtitle?: string;
}

@ComponentV2
export struct ListItemView {
  @Param itemId: string = '';
  @Param title: string = '';
  @Param icon: ResourceStr = '';
  @Param value: string = '';
  @Param isSelected: boolean = false;
  @Param hasChevron: boolean = true;
  @Param onItemClick: (itemId: string) => void = (_itemId: string) => {};

  build() {
    Row() {
      if (this.icon) {
        Image(this.icon)
          .width(32)
          .height(32)
          .margin({ right: 12 })
      }

      Row() {
        Text(this.title)
          .fontSize(16)
          .flexGrow(1)
          .fontColor('#E6000000')
          .fontWeight(this.isSelected ? 600 : 500)
      }
      .flexGrow(1)
      .justifyContent(FlexAlign.Start)

      Blank()
      if (this.value) {
        Text(this.value)
          .fontSize(14)
          .fontColor('#99000000')
          .margin({ right: 8 })
      }
      if (this.hasChevron) {
        Image($r('app.media.jinxin_right'))
          .width(20)
          .height(20)
          .fillColor('#34000000')
      }
    }
    .width('100%')
    .height(52)
    .onClick(() => {
      this.onItemClick(this.itemId);
    })
    .backgroundColor(this.isSelected ? '#E6EEFE' : Color.Transparent)
    .borderRadius(12)
    .padding({ left: 12, right: 12 })
  }
}
