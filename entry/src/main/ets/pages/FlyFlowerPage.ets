import { Context } from '@kit.AbilityKit';
import { FlyFlowerUtil, FlyFlowerIndex, FlyFlowerLine, FlyFlowerRoundItem } from '../common/utils/FlyFlowerUtil';
import { StickinessUtil, UserStats } from '../common/utils/StickinessUtil';
import { ToastUtil } from '../common/utils/ToastUtil';
import { VibrateUtil } from '../common/utils/VibrateUtil';

@Builder
export function FlyFlowerPageBuilder() {
  NavDestination() {
    FlyFlowerContent()
  }
  .title($r('app.string.ff_title'))
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct FlyFlowerContent {
  @State index: FlyFlowerIndex | undefined = undefined;
  @State currentChar: string = '';
  @State inputText: string = '';
  @State streak: number = 0;
  @State history: FlyFlowerRoundItem[] = [];
  @State isLoading: boolean = true;
  @State loadFailed: boolean = false;
  @State bestStreak: number = 0;
  @State totalCount: number = 0;
  private usedLines: Set<string> = new Set<string>();
  private uiContext: UIContext = this.getUIContext();

  aboutToAppear(): void {
    this.loadData();
  }

  private loadData(): void {
    this.isLoading = true;
    this.loadFailed = false;
    setTimeout(() => {
      try {
        let ctx: Context = this.uiContext.getHostContext() as Context;
        let idx: FlyFlowerIndex = FlyFlowerUtil.loadIndex(ctx);
        this.index = idx;
        this.currentChar = FlyFlowerUtil.pickChar(idx);
        this.refreshStats(ctx);
        this.isLoading = false;
      } catch (e) {
        console.error('[FlyFlower] loadIndex failed: ' + (e as Error).message);
        this.isLoading = false;
        this.loadFailed = true;
      }
    }, 0);
  }

  private refreshStats(ctx: Context): void {
    let stats: UserStats = StickinessUtil.loadStats(ctx);
    this.bestStreak = stats.flyflowerBest;
    this.totalCount = stats.flyflowerTotal;
  }

  private submitAnswer(): void {
    let idx: FlyFlowerIndex | undefined = this.index;
    if (idx === undefined) {
      return;
    }
    let normalized: string = FlyFlowerUtil.normalize(this.inputText);
    if (normalized.length === 0) {
      return;
    }
    if (normalized.indexOf(this.currentChar) < 0) {
      ToastUtil.show(this.uiContext, $r('app.string.ff_miss_char', this.currentChar), 1500);
      return;
    }
    if (this.usedLines.has(normalized)) {
      ToastUtil.show(this.uiContext, $r('app.string.ff_used'), 1500);
      return;
    }
    let matched: FlyFlowerLine | null = FlyFlowerUtil.matchLine(idx, this.currentChar, normalized);
    if (matched === null) {
      ToastUtil.show(this.uiContext, $r('app.string.ff_not_found'), 1500);
      return;
    }
    VibrateUtil.tap();
    this.streak = this.streak + 1;
    let item: FlyFlowerRoundItem = new FlyFlowerRoundItem();
    item.l = matched.l;
    item.t = matched.t;
    item.a = matched.a;
    this.history.unshift(item);
    this.usedLines.add(matched.l);
    this.inputText = '';
    let ctx: Context = this.uiContext.getHostContext() as Context;
    StickinessUtil.recordFlyFlowerVerse(ctx, this.streak);
    this.refreshStats(ctx);
  }

  private showHint(): void {
    let idx: FlyFlowerIndex | undefined = this.index;
    if (idx === undefined) {
      return;
    }
    let hint: string = FlyFlowerUtil.pickHint(idx, this.currentChar, this.usedLines);
    if (hint.length === 0) {
      return;
    }
    ToastUtil.show(this.uiContext, $r('app.string.ff_hint_toast', hint), 1500);
  }

  private changeChar(): void {
    let idx: FlyFlowerIndex | undefined = this.index;
    if (idx === undefined) {
      return;
    }
    if (this.streak > 0) {
      ToastUtil.show(this.uiContext, $r('app.string.ff_streak_end', this.streak, this.bestStreak), 1500);
    }
    this.streak = 0;
    this.history = [];
    this.usedLines.clear();
    this.inputText = '';
    this.currentChar = FlyFlowerUtil.pickChar(idx);
  }

  build() {
    Column() {
      Column() {
        if (this.isLoading) {
          this.LoadingSection()
        } else if (this.loadFailed) {
          this.FailSection()
        } else {
          this.GameSection()
        }
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: 720 })
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
      Text($r('app.string.ff_loading'))
        .fontSize(16)
        .fontColor($r('app.color.tertiary_text'))
        .margin({ top: 12 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  FailSection() {
    Column() {
      Text($r('app.string.ff_load_fail'))
        .fontSize(16)
        .fontColor($r('app.color.tertiary_text'))
        .margin({ bottom: 16 })
      Text($r('app.string.err_retry'))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.on_accent_text'))
        .backgroundColor($r('app.color.poetry_green'))
        .borderRadius(22)
        .padding({ left: 36, right: 36, top: 10, bottom: 10 })
        .onClick(() => {
          this.loadData();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  GameSection() {
    Column() {
      Row() {
        Column() {
          Text(this.streak.toString())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.idiom_orange'))
          Text($r('app.string.ff_current_streak'))
            .fontSize(11)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)

        Divider()
          .vertical(true)
          .height(30)
          .color($r('app.color.border_color'))

        Column() {
          Text(this.bestStreak.toString())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.poetry_green'))
          Text($r('app.string.ff_best_streak'))
            .fontSize(11)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)

        Divider()
          .vertical(true)
          .height(30)
          .color($r('app.color.border_color'))

        Column() {
          Text(this.totalCount.toString())
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.idiom_blue'))
          Text($r('app.string.ff_total'))
            .fontSize(11)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 14, bottom: 14 })
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(14)
      .margin({ left: 16, right: 16, top: 12 })

      Column() {
        Text(this.currentChar)
          .fontSize(72)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Text($r('app.string.ff_input_hint', this.currentChar))
          .fontSize(13)
          .fontColor($r('app.color.tertiary_text'))
          .margin({ top: 10 })
      }
      .width('100%')
      .padding({ top: 24, bottom: 24 })
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(14)
      .margin({ left: 16, right: 16, top: 12 })
      .alignItems(HorizontalAlign.Center)

      Row({ space: 10 }) {
        TextInput({ placeholder: $r('app.string.ff_input_hint', this.currentChar), text: this.inputText })
          .layoutWeight(1)
          .height(44)
          .fontSize(15)
          .fontColor($r('app.color.primary_text'))
          .placeholderColor($r('app.color.hint_text'))
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(12)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.inputText = value;
          })
          .onSubmit(() => {
            this.submitAnswer();
          })

        Text($r('app.string.ff_submit'))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.on_accent_text'))
          .backgroundColor($r('app.color.poetry_green'))
          .borderRadius(22)
          .padding({ left: 24, right: 24, top: 12, bottom: 12 })
          .onClick(() => {
            this.submitAnswer();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16 })

      Row({ space: 12 }) {
        Text($r('app.string.ff_hint'))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.poetry_green'))
          .backgroundColor($r('app.color.poetry_green') + '18')
          .borderRadius(16)
          .padding({ left: 20, right: 20, top: 8, bottom: 8 })
          .onClick(() => {
            this.showHint();
          })

        Text($r('app.string.ff_change_char'))
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.secondary_text'))
          .backgroundColor($r('app.color.border_color'))
          .borderRadius(16)
          .padding({ left: 20, right: 20, top: 8, bottom: 8 })
          .onClick(() => {
            this.changeChar();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })
      .justifyContent(FlexAlign.Center)

      Scroll() {
        Column() {
          if (this.history.length === 0) {
            Text($r('app.string.ff_empty_history'))
              .fontSize(13)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ top: 40, bottom: 40 })
          } else {
            ForEach(this.history, (item: FlyFlowerRoundItem) => {
              Column() {
                Text(item.l)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.primary_text'))
                  .width('100%')
                Text($r('app.string.ff_source', item.t, item.a))
                  .fontSize(12)
                  .fontColor($r('app.color.tertiary_text'))
                  .width('100%')
                  .margin({ top: 4 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(12)
              .margin({ top: 8 })
            }, (item: FlyFlowerRoundItem) => item.l)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
  }
}
