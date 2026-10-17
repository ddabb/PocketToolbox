/**
 * 文案海报 T12 头像行（1.4.8 M2）：圆角缩略预览（有图 Image / 无图占位）+ 上传/更换 + 移除（有图时）
 * 状态留在页面（content.avatarUri），本组件纯展示 + 回调；预览本身可点（同「上传/更换」）
 */
@Component
export struct CopyPosterAvatarRow {
  @Prop avatarUri: string = '';
  onPick: () => void = () => {
  };
  onRemove: () => void = () => {
  };

  build() {
    Column({ space: 5 }) {
      Text($r('app.string.poster_avatar_label'))
        .fontSize(12)
        .fontColor($r('app.color.editor_label_text'))
      Row({ space: 12 }) {
        if (this.avatarUri !== '') {
          Image('file://' + this.avatarUri)
            .width(40)
            .height(40)
            .borderRadius(8)
            .objectFit(ImageFit.Cover)
            .onClick(() => {
              this.onPick();
            })
        } else {
          Stack() {
            Text('+')
              .fontSize(22)
              .fontWeight(FontWeight.Lighter)
              .fontColor($r('app.color.editor_label_text'))
          }
          .width(40)
          .height(40)
          .borderRadius(8)
          .backgroundColor($r('app.color.editor_input_bg'))
          .onClick(() => {
            this.onPick();
          })
        }
        Text(this.avatarUri !== '' ? $r('app.string.poster_avatar_change') : $r('app.string.poster_avatar_upload'))
          .fontSize(13)
          .fontColor($r('app.color.idiom_blue'))
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .backgroundColor($r('app.color.brand_blue_tint'))
          .borderRadius(14)
          .onClick(() => {
            this.onPick();
          })
        if (this.avatarUri !== '') {
          Text($r('app.string.poster_avatar_remove'))
            .fontSize(13)
            .fontColor($r('app.color.editor_label_text'))
            .padding({ left: 10, right: 10, top: 7, bottom: 7 })
            .borderRadius(14)
            .onClick(() => {
              this.onRemove();
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
