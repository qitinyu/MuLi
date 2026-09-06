@Builder
export function loadingIndicator(label: string, color: string) {
  Row({ space: 8 }) {
    LoadingProgress().width(26).height(26).color(color);
    Text(label).fontSize(14).fontColor(color).textAlign(TextAlign.Center);
  }
  .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center);
}
