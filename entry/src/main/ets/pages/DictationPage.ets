import { Context } from '@kit.AbilityKit';
import { PoemItem } from '../model/PoetryModels';
import { PoetryViewModel } from '../viewmodel/PoetryViewModel';
import { DictationUtil, DictationSentence, DictationChar } from '../common/utils/DictationUtil';
import { StickinessUtil } from '../common/utils/StickinessUtil';
import { StrUtil } from '../common/utils/StrUtil';
import { ErrorState } from '../components/ErrorState';

function buildDictationPoem(param: Object): PoemItem | null {
  if (!param) {
    return null;
  }
  let rec: Record<string, Object> = param as Record<string, Object>;
  let n: string = (rec['n'] as string) || '';
  let c: string = (rec['c'] as string) || '';
  if (n === '' || c === '') {
    return null;
  }
  return PoetryViewModel.getInstance().parsePoemFromParam(rec);
}

@Builder
export function DictationPageBuilder(param: Object) {
  NavDestination() {
    DictationContent({ poemParam: buildDictationPoem(param) })
  }
  .title($r('app.string.dc_title'))
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct DictationContent {
  @Prop poemParam: PoemItem | null = null;
  @State isLoading: boolean = true;
  @State loadFailed: boolean = false;
  @State fromSeed: boolean = false;
  @State failText: string = '';
  @State poem: PoemItem = new PoemItem();
  @State sentences: DictationSentence[] = [];
  @State currentIdx: number = 0;
  @State inputText: string = '';
  @State judged: boolean = false;
  @State finished: boolean = false;
  @State perfectCount: number = 0;
  @State scorePercent: number = 0;
  private recordedSet: Set<number> = new Set<number>();
  private perfectSet: Set<number> = new Set<number>();
  private uiContext: UIContext = this.getUIContext();

  aboutToAppear(): void {
    this.loadData();
  }

  private loadData(): void {
    let param: PoemItem | null = this.poemParam;
    if (param !== null) {
      this.fromSeed = false;
      this.preparePoem(param);
      return;
    }
    this.fromSeed = true;
    this.isLoading = true;
    this.loadFailed = false;
    setTimeout(() => {
      try {
        let ctx: Context = this.uiContext.getHostContext() as Context;
        let loaded: PoemItem | null = DictationUtil.loadTodayPoem(ctx);
        if (loaded === null) {
          this.enterFail();
          return;
        }
        this.preparePoem(loaded);
      } catch (e) {
        console.error('[Dictation] loadTodayPoem failed: ' + (e as Error).message);
        this.enterFail();
      }
    }, 0);
  }

  private enterFail(): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    this.failText = StrUtil.text(ctx, $r('app.string.dc_no_poem'));
    this.isLoading = false;
    this.loadFailed = true;
  }

  private preparePoem(poem: PoemItem): void {
    let raws: string[] = DictationUtil.splitSentences(poem.c);
    if (raws.length === 0) {
      this.enterFail();
      return;
    }
    let list: DictationSentence[] = [];
    for (let i = 0; i < raws.length; i++) {
      list.push(DictationUtil.buildSentence(raws[i]));
    }
    this.poem = poem;
    this.sentences = list;
    this.currentIdx = 0;
    this.inputText = '';
    this.judged = false;
    this.finished = false;
    this.perfectCount = 0;
    this.scorePercent = 0;
    this.isLoading = false;
    this.loadFailed = false;
  }

  private submitSentence(): void {
    if (this.judged || this.finished || this.sentences.length === 0) {
      return;
    }
    let chars: DictationChar[] = this.curChars();
    let cnt: number = this.blankCountOf(chars);
    let input: string = DictationUtil.filterHan(this.inputText);
    if (input.length !== cnt) {
      return;
    }
    let perfect: boolean = true;
    let k: number = 0;
    for (let i = 0; i < chars.length; i++) {
      if (chars[i].blank) {
        if (input.charAt(k) !== chars[i].ch) {
          perfect = false;
        }
        k++;
      }
    }
    this.judged = true;
    let ctx: Context = this.uiContext.getHostContext() as Context;
    if (!this.recordedSet.has(this.currentIdx)) {
      this.recordedSet.add(this.currentIdx);
      StickinessUtil.recordDictationSentence(ctx, perfect);
    }
    if (perfect) {
      this.perfectSet.add(this.currentIdx);
    } else {
      this.perfectSet.delete(this.currentIdx);
    }
  }

  private retrySentence(): void {
    if (this.sentences.length === 0) {
      return;
    }
    let raw: string = this.sentences[this.currentIdx].raw;
    let rebuilt: DictationSentence = DictationUtil.buildSentence(raw);
    let next: DictationSentence[] = [];
    for (let i = 0; i < this.sentences.length; i++) {
      if (i === this.currentIdx) {
        next.push(rebuilt);
      } else {
        next.push(this.sentences[i]);
      }
    }
    this.sentences = next;
    this.inputText = '';
    this.judged = false;
  }

  private goNext(): void {
    if (this.sentences.length === 0) {
      return;
    }
    if (this.currentIdx + 1 >= this.sentences.length) {
      this.perfectCount = this.perfectSet.size;
      this.scorePercent = Math.round(this.perfectCount * 100 / this.sentences.length);
      this.finished = true;
      return;
    }
    this.currentIdx = this.currentIdx + 1;
    this.inputText = '';
    this.judged = false;
  }

  private playAgain(): void {
    this.recordedSet.clear();
    this.perfectSet.clear();
    this.preparePoem(this.poem);
  }

  private curChars(): DictationChar[] {
    if (this.currentIdx < 0 || this.currentIdx >= this.sentences.length) {
      return [];
    }
    return this.sentences[this.currentIdx].chars;
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
    return this.blankCountOf(this.curChars());
  }

  private blankOrderAt(ci: number): number {
    let chars: DictationChar[] = this.curChars();
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

  private authorLine(): string {
    if (this.poem.a !== '' && this.poem.d !== '') {
      return this.poem.a + ' \u00B7 ' + this.poem.d;
    }
    if (this.poem.a !== '') {
      return this.poem.a;
    }
    return this.poem.d;
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

  build() {
    Column() {
      Column() {
        if (this.isLoading) {
          this.LoadingSection()
        } else if (this.loadFailed) {
          this.FailSection()
        } else if (this.finished) {
          this.FinishSection()
        } else {
          this.PracticeSection()
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
  LoadingSection() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color($r('app.color.poetry_green'))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  FailSection() {
    Column() {
      ErrorState({
        text: this.failText,
        onRetry: () => {
          this.loadData();
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  PracticeSection() {
    Scroll() {
      Column() {
        Text(this.poem.n)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .width('100%')
          .textAlign(TextAlign.Center)

        if (this.authorLine() !== '') {
          Text(this.authorLine())
            .fontSize(13)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 6 })
        }

        if (this.fromSeed) {
          Text($r('app.string.dc_today_poem'))
            .fontSize(11)
            .fontColor($r('app.color.poetry_green'))
            .backgroundColor('#1A2D7D46')
            .borderRadius(10)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .margin({ top: 8 })
        }

        Text($r('app.string.dc_progress', this.currentIdx + 1, this.sentences.length))
          .fontSize(12)
          .fontColor($r('app.color.tertiary_text'))
          .margin({ top: 12 })

        Column() {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
            ForEach(this.curChars(), (dc: DictationChar, ci: number) => {
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
        .margin({ top: 12 })

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

  @Builder
  FinishSection() {
    Column() {
      Text($r('app.string.dc_finish_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))

      Text($r('app.string.dc_finish_score', this.scorePercent))
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.poetry_green'))
        .margin({ top: 20 })

      Text($r('app.string.dc_finish_perfect', this.perfectCount, this.sentences.length))
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
        .margin({ top: 8 })

      if (this.perfectCount === this.sentences.length) {
        Text($r('app.string.dc_all_perfect'))
          .fontSize(13)
          .fontColor($r('app.color.on_accent_text'))
          .backgroundColor($r('app.color.poetry_green'))
          .borderRadius(16)
          .padding({ left: 20, right: 20, top: 8, bottom: 8 })
          .margin({ top: 16 })
      }

      Text($r('app.string.dc_again'))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor($r('app.color.poetry_green'))
        .borderRadius(22)
        .padding({ left: 32, right: 32, top: 10, bottom: 10 })
        .margin({ top: 32 })
        .onClick(() => {
          this.playAgain();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
