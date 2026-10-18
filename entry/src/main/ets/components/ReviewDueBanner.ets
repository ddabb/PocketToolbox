/**
 * 1.4.9 M4-B2/B3：复习到期首页提示组件。
 * ReviewDueBanner：到期 N>0 时显示于首页顶部（QuickToolsRow 上方），点击直达 ReviewPage；
 * ReviewDueBadge：挂在首页「每日复习」卡头部的红底角标，点击直达同上（stopPropagation 防卡片冒泡双跳）。
 * 到期数由 Index 持有（@StorageLink ReviewDataVersion 版本泵驱动刷新），此处仅渲染与转发回调。
 */
@Component
export struct ReviewDueBanner {
  @Prop dueCount: number = 0;
  onOpen: () => void = () => {
  };

  build() {
    if (this.dueCount > 0) {
      Row({ space: 6 }) {
        Text('\uD83D\uDCD6')
          .fontSize(14)
        Text($r('app.string.home_review_due_banner', this.dueCount))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_indigo'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('\u203A')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_indigo'))
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.primary_indigo_bg'))
      .borderRadius(12)
      .margin({ left: 16, right: 16, top: 8 })
      .onClick(() => {
        this.onOpen();
      })
    }
  }
}

@Component
export struct ReviewDueBadge {
  @Prop count: number = 0;
  onTap: () => void = () => {
  };

  build() {
    if (this.count > 0) {
      Text($r('app.string.home_review_due_badge', this.count))
        .fontSize(10)
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor($r('app.color.char_accent_red'))
        .borderRadius(8)
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .margin({ right: 6 })
        .onClick(() => {
          this.onTap();
        })
    }
  }
}
