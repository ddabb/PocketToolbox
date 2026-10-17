/**
 * 生字卡配色面板（1.4.8 M3 样式拆分为版式/配色两页签）：
 * 字色 + 配色方案，状态留在页面，本组件纯展示 + 回调
 */

import { common } from '@kit.AbilityKit';
import { CoverPalette } from '../../model/CoverModels';
import { CharCardCharMode } from '../../core/cover/CharCardTemplates';
import { ChipOption } from '../../core/template/UnifiedTemplateModels';
import { ChipRow } from '../template/ChipRow';
import { PaletteSection } from '../template/PaletteSection';
import { StrUtil } from '../../common/utils/StrUtil';

@Component
export struct CharCardColorEditor {
  @Prop palettes: CoverPalette[] = [];
  @Prop paletteIndex: number = 0;
  @Prop charMode: string = CharCardCharMode.READ;
  onModeSelect: (value: string) => void = () => {
  };
  onPaletteSelect: (index: number) => void = () => {
  };
  private modeOptions: ChipOption[] = [
    ChipOption.of(CharCardCharMode.READ, CharCardCharMode.label(CharCardCharMode.READ)),
    ChipOption.of(CharCardCharMode.TRACE, CharCardCharMode.label(CharCardCharMode.TRACE)),
  ];

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  build() {
    Column({ space: 14 }) {
      ChipRow({
        label: StrUtil.text(this.context(), $r('app.string.char_label_mode')),
        labelColor: $r('app.color.editor_label_text'),
        options: this.modeOptions,
        selected: this.charMode,
        accent: $r('app.color.char_accent_red'),
        chipBg: $r('app.color.editor_chip_bg'),
        chipText: $r('app.color.editor_chip_text'),
        onSelect: (value: string) => {
          this.onModeSelect(value);
        },
      })

      PaletteSection({
        palettes: this.palettes,
        selectedIndex: this.paletteIndex,
        accentColor: $r('app.color.char_accent_red'),
        labelColor: $r('app.color.editor_label_text'),
        onSelect: (idx: number) => {
          this.onPaletteSelect(idx);
        },
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
