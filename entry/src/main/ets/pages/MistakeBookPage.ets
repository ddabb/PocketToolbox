import { Context } from '@kit.AbilityKit';
import { PoemItem } from '../model/PoetryModels';
import { ReviewStore, SentenceRecord } from '../common/utils/ReviewStore';
import { DictationUtil, DictationSentence, DictationChar } from '../common/utils/DictationUtil';
import { ToastUtil } from '../common/utils/ToastUtil';

@Builder
export function MistakeBookPageBuilder() {
  NavDestination() {
    MistakeBookContent()
  }
  .title($r('app.string.mb_title'))
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct MistakeBookContent {
  @State mode: string = 'list';
  @State mistakes: SentenceRecord[] = [];
  @State practiceIdx: number = 0;
  @State sentence: DictationSentence = new DictationSentence();
  @State inputText: string = '';
  @State judged: boolean = false;
  private uiContext: UIContext = this.getUIContext();

  aboutToAppear(): void {
    this.reloadList();
  }

  private reloadList(): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    this.mistakes = ReviewStore.getMistakes(ctx);
    this.mode = 'list';
  }

  private curRec(): SentenceRecord | null {
    if (this.practiceIdx < 0 || this.practiceIdx >= this.mistakes.length) {
      return null;
    }
    return this.mistakes[this.practiceIdx];
  }

  private buildPoemItem(rec: SentenceRecord): PoemItem {
    let poem: PoemItem = new PoemItem();
    poem.n = rec.poemName;
    poem.a = rec.poemAuthor;
    poem.d = rec.poemDynasty;
    return poem;
  }

  private enterPractice(idx: number): void {
    if (idx < 0 || idx >= this.mistakes.length) {
      return;
    }
    let rec: SentenceRecord = this.mistakes[idx];
    this.practiceIdx = idx;
    this.sentence = DictationUtil.buildSentenceWithBlanks(rec.raw, rec.wrongChars);
    this.inputText = '';
    this.judged = false;
    this.mode = 'practice';
  }

  private submitSentence(): void {
    if (this.judged || this.mode !== 'practice') {
      return;
    }
    let rec: SentenceRecord | null = this.curRec();
    if (rec === null) {
      return;
    }
    let chars: DictationChar[] = this.sentence.chars;
    let cnt: number = this.blankCountOf(chars);
    let input: string = DictationUtil.filterHan(this.inputText);
    if (input.length !== cnt) {
      return;
    }
    let perfect: boolean = true;
    let wrongIdx: number[] = [];
    let k: number = 0;
    for (let i = 0; i < chars.length; i++) {
      if (chars[i].blank) {
        if (input.charAt(k) !== chars[i].ch) {
          perfect = false;
          wrongIdx.push(i);
        }
        k++;
      }
    }
    this.judged = true;
    let ctx: Context = this.uiContext.getHostContext() as Context;
    ReviewStore.recordResult(ctx, this.buildPoemItem(rec), this.sentence.raw, wrongIdx, perfect);
    if (perfect) {
      ToastUtil.show(this.uiContext, $r('app.string.mb_removed'), 1200);
    }
  }

  private retrySentence(): void {
    let rec: SentenceRecord | null = this.curRec();
    if (rec === null) {
      return;
    }
    this.sentence = DictationUtil.buildSentenceWithBlanks(rec.raw, rec.wrongChars);
    this.inputText = '';
    this.judged = false;
  }

  private goNext(): void {
    if (this.practiceIdx + 1 >= this.mistakes.length) {
      this.reloadList();
      return;
    }
    let rec: SentenceRecord = this.mistakes[this.practiceIdx + 1];
    this.practiceIdx = this.practiceIdx + 1;
    this.sentence = DictationUtil.buildSentenceWithBlanks(rec.raw, rec.wrongChars);
    this.inputText = '';
    this.judged = false;
  }

  private blankCountOf(chars: DictationChar[]): number {
    let cnt: number = 0;
    for (let i = 0; i < chars.length; i++) {
      if (chars[i].blank) {
        cnt++;
      }
    }
    return cnt;
  }

  private curBlankCount(): number {
    return this.blankCountOf(this.sentence.chars);
  }

  private blankOrderAt(ci: number): number {
    let chars: DictationChar[] = this.sentence.chars;
    let cnt: number = 0;
    for (let i = 0; i <= ci && i < chars.length; i++) {
      if (chars[i].blank) {
        cnt++;
      }
    }
    return cnt - 1;
  }

  private userCharAt(k: number): string {
    if (k < 0 || k >= this.inputText.length) {
      return '';
    }
    return this.inputText.charAt(k);
  }

  private isBlankCorrect(dc: DictationChar, ci: number): boolean {
    return this.userCharAt(this.blankOrderAt(ci)) === dc.ch;
  }

  private canSubmit(): boolean {
    return !this.judged && this.inputText.length === this.curBlankCount();
  }

  private cellText(dc: DictationChar, ci: number): string {
    if (!dc.blank || this.judged) {
      return dc.ch;
    }
    return this.userCharAt(this.blankOrderAt(ci));
  }

  private cellTextColor(dc: DictationChar, ci: number): ResourceColor {
    if (!dc.blank) {
      return $r('app.color.secondary_text');
    }
    if (this.judged) {
      return this.isBlankCorrect(dc, ci) ? $r('app.color.poetry_green') : $r('app.color.danger_red');
    }
    return $r('app.color.hint_text');
  }

  private cellBorderColor(dc: DictationChar, ci: number): ResourceColor {
    if (!dc.blank) {
      return Color.Transparent;
    }
    if (!this.judged) {
      return $r('app.color.hint_text');
    }
    return this.isBlankCorrect(dc, ci) ? $r('app.color.poetry_green') : $r('app.color.danger_red');
  }

  private cellBgColor(dc: DictationChar): ResourceColor {
    if (!dc.blank) {
      return Color.Transparent;
    }
    return $r('app.color.page_background');
  }

  private isWrongIdx(rec: SentenceRecord, ci: number): boolean {
    for (let i = 0; i < rec.wrongChars.length; i++) {
      if (rec.wrongChars[i] === ci) {
        return true;
      }
    }
    return false;
  }

  private curPoemName(): string {
    let rec: SentenceRecord | null = this.curRec();
    return rec === null ? '' : rec.poemName;
  }

  private curPoemAuthor(): string {
    let rec: SentenceRecord | null = this.curRec();
    return rec === null ? '' : rec.poemAuthor;
  }

  build() {
    Column() {
      Column() {
        if (this.mode === 'practice') {
          this.PracticeSection()
        } else if (this.mistakes.length === 0) {
          this.EmptySection()
        } else {
          this.ListSection()
        }
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: 720 })
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  EmptySection() {
    Column() {
      Text('📝')
        .fontSize(56)
      Text($r('app.string.mb_empty'))
        .fontSize(14)
        .fontColor($r('app.color.tertiary_text'))
        .margin({ top: 16 })
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ListSection() {
    Scroll() {
      Column() {
        ForEach(this.mistakes, (rec: SentenceRecord, idx: number) => {
          Column() {
            Text() {
              ForEach(Array.from(rec.raw), (ch: string, ci: number) => {
                Span(ch)
                  .fontSize(15)
                  .fontColor(this.isWrongIdx(rec, ci) ? $r('app.color.danger_red') : $r('app.color.secondary_text'))
              }, (ch: string, ci: number) => ci.toString() + '-' + ch)
            }
            .width('100%')

            Text($r('app.string.mb_wrong_times', rec.errCount))
              .fontSize(11)
              .fontColor($r('app.color.danger_red'))
              .margin({ top: 6 })

            Row() {
              Text($r('app.string.ff_source', rec.poemName, rec.poemAuthor))
                .fontSize(12)
                .fontColor($r('app.color.tertiary_text'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text($r('app.string.mb_retry'))
                .fontSize(13)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.on_accent_text'))
                .backgroundColor($r('app.color.poetry_green'))
                .borderRadius(12)
                .padding({ left: 14, right: 14, top: 5, bottom: 5 })
                .margin({ left: 10 })
            }
            .width('100%')
            .margin({ top: 10 })
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(14)
          .padding(14)
          .margin({ bottom: 12 })
          .onClick(() => {
            this.enterPractice(idx);
          })
        }, (rec: SentenceRecord) => rec.key + '-' + rec.errCount.toString() + '-' + rec.wrongChars.length.toString())
      }
      .width('100%')
      .padding({ top: 4, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  PracticeSection() {
    Scroll() {
      Column() {
        Text($r('app.string.ff_source', this.curPoemName(), this.curPoemAuthor()))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .width('100%')
          .textAlign(TextAlign.Center)

        Column() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            ForEach(this.sentence.chars, (dc: DictationChar, ci: number) => {
              Column() {
                Text(dc.py)
                  .fontSize(9)
                  .fontColor($r('app.color.tertiary_text'))
                  .height(12)
                  .maxLines(1)
                  .textAlign(TextAlign.Center)
                Text(this.cellText(dc, ci))
                  .fontSize(16)
                  .fontColor(this.cellTextColor(dc, ci))
                  .width(34)
                  .height(34)
                  .textAlign(TextAlign.Center)
                  .borderRadius(8)
                  .backgroundColor(this.cellBgColor(dc))
                  .border({
                    width: dc.blank ? 1.5 : 0,
                    color: this.cellBorderColor(dc, ci),
                    style: dc.blank && this.judged ? BorderStyle.Solid : BorderStyle.Dashed
                  })
              }
              .width(34)
              .alignItems(HorizontalAlign.Center)
              .margin(3)
            }, (dc: DictationChar, ci: number) =>
              ci.toString() + '-' + dc.ch + '-' + (dc.blank ? 'b' : 'n') + '-' +
              (this.judged ? 'j' : 'u') + '-' + this.inputText)
          }
          .width('100%')
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(14)
        .padding(12)
        .margin({ top: 16 })

        TextInput({
          placeholder: $r('app.string.dc_input_hint', this.curBlankCount()),
          text: this.inputText
        })
          .width('100%')
          .height(44)
          .fontSize(16)
          .fontColor($r('app.color.primary_text'))
          .placeholderColor($r('app.color.hint_text'))
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .padding({ left: 16, right: 16 })
          .margin({ top: 16 })
          .enabled(!this.judged)
          .onChange((value: string) => {
            let filtered: string = DictationUtil.filterHan(value);
            let maxLen: number = this.curBlankCount();
            if (filtered.length > maxLen) {
              filtered = filtered.substring(0, maxLen);
            }
            this.inputText = filtered;
          })
          .onSubmit(() => {
            this.submitSentence();
          })

        if (!this.judged) {
          Text($r('app.string.dc_submit'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.canSubmit() ? $r('app.color.on_accent_text') : $r('app.color.tertiary_text'))
            .backgroundColor(this.canSubmit() ? $r('app.color.poetry_green') : $r('app.color.border_color'))
            .borderRadius(16)
            .padding({ left: 32, right: 32, top: 10, bottom: 10 })
            .margin({ top: 16 })
            .onClick(() => {
              this.submitSentence();
            })
        } else {
          Row({ space: 12 }) {
            Text($r('app.string.dc_retry'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.secondary_text'))
              .backgroundColor($r('app.color.border_color'))
              .borderRadius(16)
              .padding({ left: 24, right: 24, top: 10, bottom: 10 })
              .onClick(() => {
                this.retrySentence();
              })
            Text($r('app.string.dc_next'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.on_accent_text'))
              .backgroundColor($r('app.color.poetry_green'))
              .borderRadius(16)
              .padding({ left: 24, right: 24, top: 10, bottom: 10 })
              .onClick(() => {
                this.goNext();
              })
          }
          .margin({ top: 16 })
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .padding({ top: 4, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }
}
