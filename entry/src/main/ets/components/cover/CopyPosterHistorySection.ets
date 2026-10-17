/**
 * 文案海报最近制作（1.4.8 M2 自 CopyPosterPage 抽离）：
 * 历史缩略图横滑列表 + 清空入口；状态留在页面（historyRecords），本组件纯展示 + 回调
 */
import { common } from '@kit.AbilityKit';
import { CoverHistoryRecord } from '../../model/CoverModels';
import { CopyPosterTemplate } from '../../model/CopyPosterModels';
import { CopyPosterTemplates } from '../../core/cover/CopyPosterTemplates';
import { CoverHistoryStore } from '../../core/cover/CoverHistoryStore';
import { StrUtil } from '../../common/utils/StrUtil';

@Component
export struct CopyPosterHistorySection {
  @Prop historyRecords: CoverHistoryRecord[] = [];
  onRestore: (record: CoverHistoryRecord) => void = () => {
  };
  onClear: () => void = () => {
  };

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private historyLabel(r: CoverHistoryRecord): string {
    let parts: string[] = r.templateId.split('|');
    let t: CopyPosterTemplate = CopyPosterTemplates.getById(parts.length > 0 ? parts[0] : 'T1');
    return StrUtil.text(this.context(), t.name);
  }

  build() {
    if (this.historyRecords.length > 0) {
      Column({ space: 8 }) {
        Row() {
          Text($r('app.string.char_recent'))
            .fontSize(12)
            .fontColor($r('app.color.editor_label_text'))
            .layoutWeight(1)
          Text($r('app.string.char_clear'))
            .fontSize(12)
            .fontColor($r('app.color.editor_label_text'))
            .padding(6)
            .onClick(() => {
              this.onClear();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        List({ space: 10 }) {
          ForEach(this.historyRecords, (r: CoverHistoryRecord) => {
            ListItem() {
              Column({ space: 4 }) {
                Image('file://' + CoverHistoryStore.filePath(this.context(), r.fileName, CoverHistoryStore.DIR_POSTER))
                  .width(64)
                  .height(64)
                  .objectFit(ImageFit.Cover)
                  .borderRadius(4)
                  .border({ width: 1, color: $r('app.color.editor_line') })
                Text(this.historyLabel(r))
                  .fontSize(10)
                  .fontColor($r('app.color.editor_label_text'))
                  .maxLines(1)
              }
              .alignItems(HorizontalAlign.Center)
              .onClick(() => {
                this.onRestore(r);
              })
            }
          }, (r: CoverHistoryRecord) => r.id)
        }
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .height(92)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .padding({ top: 8 })
      .border({ width: { top: 1 }, color: $r('app.color.editor_line') })
    }
  }
}
