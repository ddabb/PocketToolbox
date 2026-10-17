/**
 * 生字卡版式面板（1.4.8 M3 自 CharCardPage 抽离，样式拆分为版式/配色两页签）：
 * 尺寸 + 格型 + 拼音开关，状态留在页面，本组件纯展示 + 回调
 */

import { common } from '@kit.AbilityKit';
import { CharCardGridType, CharCardSize } from '../../core/cover/CharCardTemplates';
import { ChipOption } from '../../core/template/UnifiedTemplateModels';
import { ChipRow } from '../template/ChipRow';
import { StrUtil } from '../../common/utils/StrUtil';

@Component
export struct CharCardStyleEditor {
  @Prop sizeKind: string = CharCardSize.SQUARE;
  @Prop gridType: string = CharCardGridType.TIAN;
  @Prop pinyinOn: boolean = true;
  onSizeSelect: (value: string) => void = () => {
  };
  onGridSelect: (value: string) => void = () => {
  };
  onPinyinToggle: (value: string) => void = () => {
  };
  private sizeOptions: ChipOption[] = [
    ChipOption.of(CharCardSize.SQUARE, CharCardSize.label(CharCardSize.SQUARE)),
    ChipOption.of(CharCardSize.PRACTICE, CharCardSize.label(CharCardSize.PRACTICE)),
    ChipOption.of(CharCardSize.COVER, CharCardSize.label(CharCardSize.COVER)),
  ];
  private gridOptions: ChipOption[] = [
    ChipOption.of(CharCardGridType.TIAN, CharCardGridType.label(CharCardGridType.TIAN)),
    ChipOption.of(CharCardGridType.MI, CharCardGridType.label(CharCardGridType.MI)),
    ChipOption.of(CharCardGridType.NONE, CharCardGridType.label(CharCardGridType.NONE)),
  ];
  private pinyinOptions: ChipOption[] = [
    ChipOption.of('on', $r('app.string.char_pinyin_show')),
    ChipOption.of('off', $r('app.string.char_pinyin_hide')),
  ];

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  build() {
    Column({ space: 14 }) {
      ChipRow({
        label: StrUtil.text(this.context(), $r('app.string.char_label_size')),
        labelColor: $r('app.color.editor_label_text'),
        options: this.sizeOptions,
        selected: this.sizeKind,
        accent: $r('app.color.char_accent_red'),
        chipBg: $r('app.color.editor_chip_bg'),
        chipText: $r('app.color.editor_chip_text'),
        onSelect: (value: string) => {
          this.onSizeSelect(value);
        },
      })

      ChipRow({
        label: StrUtil.text(this.context(), $r('app.string.char_label_grid')),
        labelColor: $r('app.color.editor_label_text'),
        options: this.gridOptions,
        selected: this.gridType,
        accent: $r('app.color.char_accent_red'),
        chipBg: $r('app.color.editor_chip_bg'),
        chipText: $r('app.color.editor_chip_text'),
        onSelect: (value: string) => {
          this.onGridSelect(value);
        },
      })

      ChipRow({
        label: StrUtil.text(this.context(), $r('app.string.char_label_pinyin')),
        labelColor: $r('app.color.editor_label_text'),
        options: this.pinyinOptions,
        selected: this.pinyinOn ? 'on' : 'off',
        accent: $r('app.color.char_accent_red'),
        chipBg: $r('app.color.editor_chip_bg'),
        chipText: $r('app.color.editor_chip_text'),
        onSelect: (value: string) => {
          this.onPinyinToggle(value);
        },
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
