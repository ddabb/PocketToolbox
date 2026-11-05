import { common } from '@kit.AbilityKit';
import { CopyPosterRatio } from '../../model/CopyPosterModels';
import { CopyPosterTemplates } from '../../core/cover/CopyPosterTemplates';
import { StrUtil } from '../../common/utils/StrUtil';

/**
 * 文案海报比例页签选项卡片：形状示意 + 比例值 + 名称 + 导出尺寸，选中态描边高亮。
 * 自 CopyPosterPage.RatioOptionCard 抽出为独立组件（页面行数护栏 900 阈值，2026-11）。
 */
@Component
export struct CopyPosterRatioCard {
  @Prop kind: string = CopyPosterRatio.SQUARE;
  @Prop selected: boolean = false;
  onSelect: (kind: string) => void = (kind: string) => {};

  /** 比例短文案（卡片主标题）：1:1 / 3:4 / 9:16 */
  private ratioText(): string {
    if (this.kind === CopyPosterRatio.PORTRAIT) { return '3:4'; }
    if (this.kind === CopyPosterRatio.LONG) { return '9:16'; }
    return '1:1';
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  build() {
    Column({ space: 8 }) {
      Column() {
        Text(this.ratioText())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.selected ? $r('app.color.brand_blue') : $r('app.color.editor_chip_text'))
      }
      .width(56)
      .aspectRatio(900 / CopyPosterRatio.designHeight(this.kind))
      .justifyContent(FlexAlign.Center)
      .borderRadius(8)
      .backgroundColor(this.selected ? $r('app.color.brand_blue_tint') : $r('app.color.editor_chip_bg'))
      .border({ width: this.selected ? 1 : 0, color: $r('app.color.brand_blue') })

      Text(StrUtil.text(this.context(), CopyPosterRatio.label(this.kind)))
        .fontSize(12)
        .fontColor(this.selected ? $r('app.color.brand_blue') : $r('app.color.editor_label_text'))
        .maxLines(1)

      Text($r('app.string.char_export_size',
        StrUtil.text(this.context(), CopyPosterRatio.label(this.kind)),
        CopyPosterTemplates.EXPORT_W, CopyPosterRatio.exportHeight(this.kind)))
        .fontSize(10)
        .fontColor($r('app.color.editor_label_text'))
        .maxLines(1)
    }
    .layoutWeight(1)
    .padding({ left: 8, right: 8, top: 12, bottom: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.editor_chip_bg'))
    .border({ width: this.selected ? 2 : 1, color: this.selected ? $r('app.color.brand_blue') : $r('app.color.editor_line') })
    .onClick(() => { this.onSelect(this.kind); })
  }
}
