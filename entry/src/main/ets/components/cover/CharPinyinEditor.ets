/**
 * 生字卡拼音编辑器（1.4.8 M3 自 CharCardPage 抽离）：逐字读音 chips + 候选选项式修正
 * 替代旧版手输带调拼音（手输体验差）：点击文字展开该字候选读音，点选即改
 * 汉字按序消费音节（与 CharCardPreview.rowPinyinSlots 一致），非汉字无读音不可编辑
 * 无多音字（且无手动修正）时整块隐藏：拼音预览已足够，修正控件无的放矢
 * 1.5.0 M1：A1 候选行尾「应用到全部」次级 chip（同字批量修正，覆盖语义 §9-1，
 *           N=同字出现数实时计数明示影响范围）；A2 correctable chip 下缘红标（可修正视觉提示）
 */

import { CoverContentUtil } from '../../core/cover/CoverContentUtil';

const HAN_RE: RegExp = new RegExp('[\\u4e00-\\u9fff]');

@Component
export struct CharPinyinEditor {
  /** 当前卡片字串（单字模式清洗后 / 句子模式分词字串） */
  @Prop @Watch('onSourceChanged') charsText: string = '';
  /** 空白分隔音节串（仅汉字音节） */
  @Prop pinyinText: string = '';
  /** 存在手动修正时显示「恢复自动」 */
  @Prop locked: boolean = false;
  onApply: (hanziIndex: number, value: string) => void = () => {
  };
  /** 同字批量修正（1.5.0 M1-A1）：ch 全部出现位音节统一替换为 syllable（§9-1 覆盖语义） */
  onApplyAll: (ch: string, syllable: string) => void = () => {
  };
  onReset: () => void = () => {
  };
  /** 当前选中字下标（charsText 内），-1 未选 */
  @State editIndex: number = -1;

  private onSourceChanged(): void {
    this.editIndex = -1;
  }

  private chars(): string[] {
    return Array.from(this.charsText);
  }

  private syllables(): string[] {
    return CoverContentUtil.syllables(this.pinyinText);
  }

  private isHanzi(ch: string): boolean {
    return HAN_RE.test(ch);
  }

  /** 第 idx 字之前的汉字个数（即该字（若为汉字）的音节下标） */
  private hanziIndexBefore(idx: number): number {
    let chars: string[] = this.chars();
    let n: number = 0;
    for (let i = 0; i < idx && i < chars.length; i++) {
      if (HAN_RE.test(chars[i])) {
        n++;
      }
    }
    return n;
  }

  /** 第 idx 字的音节（非汉字或越界返回空） */
  private syllableAt(idx: number): string {
    let chars: string[] = this.chars();
    if (idx < 0 || idx >= chars.length || !HAN_RE.test(chars[idx])) {
      return '';
    }
    let sys: string[] = this.syllables();
    let hi: number = this.hanziIndexBefore(idx);
    return hi < sys.length ? sys[hi] : '';
  }

  /** 第 idx 字候选读音：当前值置顶保底，后接多音字候选 */
  private candidatesFor(idx: number): string[] {
    let chars: string[] = this.chars();
    if (idx < 0 || idx >= chars.length) {
      return [];
    }
    let current: string = this.syllableAt(idx);
    let cands: string[] = CoverContentUtil.pinyinCandidates(chars[idx]);
    let out: string[] = [];
    if (current !== '' && cands.indexOf(current) < 0) {
      out.push(current);
    }
    for (let i = 0; i < cands.length; i++) {
      out.push(cands[i]);
    }
    return out;
  }

  /** 多音字（候选读音 ≥2）才提供修正选项，单音字无可修正项 */
  private correctable(idx: number): boolean {
    let chars: string[] = this.chars();
    if (idx < 0 || idx >= chars.length || !this.isHanzi(chars[idx])) {
      return false;
    }
    return this.candidatesFor(idx).length >= 2;
  }

  /** M1-A1：ch 在当前字串中的出现次数（批量 chip 实时计数，明示批量影响范围） */
  private occurrenceCount(ch: string): number {
    let chars: string[] = this.chars();
    let n: number = 0;
    for (let i = 0; i < chars.length; i++) {
      if (chars[i] === ch) {
        n++;
      }
    }
    return n;
  }

  /** 音节数与汉字数一致（逐字 chips 可用）；不一致（旧手输历史/编辑中错位）退化为纯文本展示 */
  private aligned(): boolean {
    let chars: string[] = this.chars();
    let n: number = 0;
    for (let i = 0; i < chars.length; i++) {
      if (HAN_RE.test(chars[i])) {
        n++;
      }
    }
    return this.syllables().length === n;
  }

  /** 需要展示修正控件：存在多音字；或已有手动修正（保留「恢复自动」入口） */
  private hasCorrection(): boolean {
    if (this.locked) {
      return true;
    }
    let chars: string[] = this.chars();
    for (let i = 0; i < chars.length; i++) {
      if (this.correctable(i)) {
        return true;
      }
    }
    return false;
  }

  build() {
    if (this.hasCorrection()) {
      Column({ space: 8 }) {
        Row() {
          Text($r('app.string.char_pinyin_edit_hint'))
            .fontSize(12)
            .fontColor($r('app.color.editor_label_text'))
            .layoutWeight(1)
          if (this.locked) {
            Text($r('app.string.char_pinyin_auto'))
              .fontSize(12)
              .fontColor($r('app.color.char_accent_red'))
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.char_accent_tint'))
              .borderRadius(12)
              .onClick(() => {
                this.onReset();
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.aligned()) {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.chars(), (ch: string, idx: number) => {
              Column({ space: 2 }) {
                Text(ch)
                  .fontSize(15)
                  .fontColor(this.editIndex === idx ? $r('app.color.on_accent_text') :
                    $r('app.color.editor_chip_text'))
                Text(this.isHanzi(ch) ? this.syllableAt(idx) : '\u00A0')
                  .fontSize(10)
                  .maxFontSize(10)
                  .minFontSize(7)
                  .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
                  .fontColor(this.editIndex === idx ? $r('app.color.on_accent_text') :
                    $r('app.color.editor_label_text'))
                  .maxLines(1)
              }
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .borderRadius(8)
              .backgroundColor(this.editIndex === idx ? $r('app.color.char_accent_red') :
                $r('app.color.editor_input_bg'))
              // M1-A2：correctable chip 下缘红标（可修正视觉提示），非 correctable 无边框
              .border(this.correctable(idx) ?
                { width: { bottom: 2 }, color: $r('app.color.char_accent_red') } :
                { width: 0 })
              .opacity(this.isHanzi(ch) ? 1 : 0.55)
              .margin({ right: 6, bottom: 6 })
              .onClick(() => {
                if (this.correctable(idx)) {
                  this.editIndex = this.editIndex === idx ? -1 : idx;
                }
              })
            }, (ch: string, idx: number) => ch + idx.toString() + this.editIndex.toString() + this.pinyinText)
          }
          .width('100%')

          if (this.editIndex >= 0 && this.isHanzi(this.chars()[this.editIndex])) {
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(this.candidatesFor(this.editIndex), (cand: string) => {
                Text(cand)
                  .fontSize(13)
                  .fontColor(cand === this.syllableAt(this.editIndex) ? $r('app.color.on_accent_text') :
                    $r('app.color.char_accent_red'))
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(cand === this.syllableAt(this.editIndex) ?
                    $r('app.color.char_accent_red') : $r('app.color.char_accent_tint'))
                  .borderRadius(13)
                  .margin({ right: 4, bottom: 4 })
                  .onClick(() => {
                    this.onApply(this.hanziIndexBefore(this.editIndex), cand);
                  })
              }, (cand: string, ci: number) => cand + ci.toString() + this.editIndex.toString() + this.pinyinText)

              // M1-A1：候选行尾「应用到全部」次级 chip（当前字读音推广到全部同字，覆盖语义）
              Text($r('app.string.pinyin_apply_all', this.syllableAt(this.editIndex),
                this.chars()[this.editIndex], this.occurrenceCount(this.chars()[this.editIndex])))
                .fontSize(12)
                .fontColor($r('app.color.char_accent_red'))
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor($r('app.color.char_accent_tint'))
                .borderRadius(13)
                .margin({ right: 4, bottom: 4 })
                .onClick(() => {
                  this.onApplyAll(this.chars()[this.editIndex], this.syllableAt(this.editIndex));
                })
            }
            .width('100%')
          }
        } else {
          Text(this.pinyinText)
            .fontSize(12)
            .fontColor($r('app.color.editor_label_text'))
            .maxLines(2)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }
}
