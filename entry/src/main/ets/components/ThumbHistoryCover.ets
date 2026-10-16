/**
 * ThumbHistoryCover - 「最近制作」全屏历史弹层（词云/文字转图片共用）
 *
 * 由页面通过 bindContentCover 挂载，展示 ThumbHistoryStore 中的记录：
 * 缩略图 + 摘要 + 时间，支持恢复参数与删除单条记录。
 *
 * 接入约定（缺一不可，否则弹层打开期间列表不刷新、退出重进才生效）：
 * 1. 页面侧 bindContentCover 传入的 @Builder 根节点必须是内置 UI 节点（Column）：
 *    Builder 根为自定义组件时该组件会被框架跳过，其状态变量全部失效，只渲染挂载时的值；
 * 2. records 用 @Link 与页面 @State 建立属性级直接双向绑定：@Prop 是挂载时的一次性深拷贝，
 *    页面后续重赋值同步不到弹层内容；@Link 不依赖页面重新渲染，删除/保存后列表实时刷新。
 */
import { ThumbHistoryRecord, ThumbHistoryStore } from '../core/history/ThumbHistoryStore';
import { fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

@Component
export struct ThumbHistoryCover {
  @Link records: ThumbHistoryRecord[];
  @Prop dirName: string = '';
  onRestore: (record: ThumbHistoryRecord) => void = (record: ThumbHistoryRecord) => {};
  onDelete: (record: ThumbHistoryRecord) => void = (record: ThumbHistoryRecord) => {};
  onClose: () => void = () => {};

  private formatTime(ts: number): string {
    let d: Date = new Date(ts);
    let y: number = d.getFullYear();
    let mo: number = d.getMonth() + 1;
    let da: number = d.getDate();
    let hh: number = d.getHours();
    let mi: number = d.getMinutes();
    let moStr: string = mo < 10 ? '0' + mo.toString() : mo.toString();
    let daStr: string = da < 10 ? '0' + da.toString() : da.toString();
    let hhStr: string = hh < 10 ? '0' + hh.toString() : hh.toString();
    let miStr: string = mi < 10 ? '0' + mi.toString() : mi.toString();
    return y.toString() + '-' + moStr + '-' + daStr + ' ' + hhStr + ':' + miStr;
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.history_recent_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Blank()
        Button($r('app.string.history_btn_close'))
          .fontSize(15)
          .fontColor($r('app.color.on_accent_text'))
          .backgroundColor($r('app.color.brand_blue'))
          .borderRadius(20)
          .height(40)
          .padding({ left: 20, right: 20 })
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 16, right: 16, top: 28, bottom: 14 })

      if (this.records.length === 0) {
        Column() {
          Text($r('app.string.history_empty'))
            .fontSize(14)
            .fontColor($r('app.color.tertiary_text'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.records, (record: ThumbHistoryRecord) => {
              Column({ space: 10 }) {
                Row({ space: 12 }) {
                  Image(fileUri.getUriFromPath(ThumbHistoryStore.thumbFilePath(
                    this.getUIContext().getHostContext() as common.Context, this.dirName, record)))
                    .width(88)
                    .height(88)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(10)
                    .backgroundColor($r('app.color.page_background'))
                  Column({ space: 4 }) {
                    Text(record.summary)
                      .fontSize(13)
                      .fontColor($r('app.color.primary_text'))
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(this.formatTime(record.createdAt))
                      .fontSize(11)
                      .fontColor($r('app.color.tertiary_text'))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')

                Row({ space: 8 }) {
                  Button($r('app.string.history_btn_restore'))
                    .fontSize(12)
                    .fontColor($r('app.color.on_accent_text'))
                    .backgroundColor($r('app.color.brand_blue'))
                    .borderRadius(16)
                    .height(32)
                    .layoutWeight(1)
                    .onClick(() => {
                      this.onRestore(record);
                    })
                  Button($r('app.string.history_btn_delete'))
                    .fontSize(12)
                    .fontColor($r('app.color.danger_red'))
                    .backgroundColor($r('app.color.card_background'))
                    .border({ width: 1, color: $r('app.color.danger_red') })
                    .borderRadius(16)
                    .height(32)
                    .layoutWeight(1)
                    .onClick(() => {
                      this.onDelete(record);
                    })
                }
                .width('100%')
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(12)
            }, (record: ThumbHistoryRecord) => record.id)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 24 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollable(ScrollDirection.Vertical)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
