import { pasteboard } from '@kit.BasicServicesKit';
import { Context } from '@kit.AbilityKit';
import { ToastUtil } from '../common/utils/ToastUtil';
import { StrUtil } from '../common/utils/StrUtil';

class PrimeFactorItem {
  value: number = 0;
  isPrime: boolean = true;

  constructor(value: number, isPrime: boolean) {
    this.value = value;
    this.isPrime = isPrime;
  }
}

class FactorizeResult {
  factors: PrimeFactorItem[] = [];
  steps: string[] = [];

  constructor(factors: PrimeFactorItem[], steps: string[]) {
    this.factors = factors;
    this.steps = steps;
  }
}

@Builder
export function PrimeFactorPageBuilder() {
  NavDestination() {
    PrimeFactorContent()
  }
  .title($r('app.string.tool_prime_title'))
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
  .backgroundColor($r('app.color.page_background'))
}

@Component
struct PrimeFactorContent {
  @State inputNumber: string = '';
  @State factors: PrimeFactorItem[] = [];
  @State steps: string[] = [];
  @State showResult: boolean = false;
  @State isPrime: boolean = false;
  @State factorExpression: string = '';
  @State displayNumber: string = '';
  @State calcVersion: number = 0;

  private readonly examples: number[] = [60, 100, 360, 1024, 97, 2310];

  aboutToAppear(): void {
    this.inputNumber = this.examples[0].toString();
    this.doFactorize(this.examples[0]);
  }

  private isPrimeNumber(n: number): boolean {
    if (n < 2) {
      return false;
    }
    if (n === 2) {
      return true;
    }
    if (n % 2 === 0) {
      return false;
    }
    for (let i: number = 3; i <= Math.sqrt(n); i += 2) {
      if (n % i === 0) {
        return false;
      }
    }
    return true;
  }

  private primeFactorization(n: number): FactorizeResult {
    const ctx: Context = this.getUIContext().getHostContext() as Context;
    let factors: PrimeFactorItem[] = [];
    let steps: string[] = [];
    let temp: number = n;
    let divisor: number = 2;
    let stepNum: number = 1;

    steps.push(StrUtil.text(ctx, $r('app.string.prime_step_start', n)));

    let count: number = 0;
    let prev: number = temp;
    while (temp % divisor === 0) {
      temp = Math.floor(temp / divisor);
      count++;
    }
    if (count > 0) {
      for (let i: number = 0; i < count; i++) {
        factors.push(new PrimeFactorItem(divisor, true));
      }
      if (count === 1) {
        steps.push(StrUtil.text(ctx, $r('app.string.prime_step_div', stepNum, prev, divisor, temp)));
      } else {
        steps.push(StrUtil.text(ctx, $r('app.string.prime_step_power', stepNum, prev, divisor, count, temp)));
      }
      stepNum++;
    }

    divisor = 3;
    while (temp > 1 && divisor * divisor <= temp) {
      count = 0;
      prev = temp;
      while (temp % divisor === 0) {
        temp = Math.floor(temp / divisor);
        count++;
      }
      if (count > 0) {
        for (let i: number = 0; i < count; i++) {
          factors.push(new PrimeFactorItem(divisor, true));
        }
        if (count === 1) {
          steps.push(StrUtil.text(ctx, $r('app.string.prime_step_div', stepNum, prev, divisor, temp)));
        } else {
          steps.push(StrUtil.text(ctx, $r('app.string.prime_step_power', stepNum, prev, divisor, count, temp)));
        }
        stepNum++;
      }
      divisor += 2;
    }

    if (temp > 1) {
      factors.push(new PrimeFactorItem(temp, true));
      steps.push(StrUtil.text(ctx, $r('app.string.prime_step_remainder', stepNum, temp)));
    }

    let expression: string = '';
    for (let i: number = 0; i < factors.length; i++) {
      if (i > 0) {
        expression += ' × ';
      }
      expression += factors[i].value.toString();
    }
    steps.push(n.toString() + ' = ' + expression);

    return new FactorizeResult(factors, steps);
  }

  private doFactorize(n: number): void {
    this.displayNumber = n.toString();

    if (this.isPrimeNumber(n)) {
      const ctx: Context = this.getUIContext().getHostContext() as Context;
      this.factors = [new PrimeFactorItem(n, true)];
      this.steps = [StrUtil.text(ctx, $r('app.string.prime_is_prime_step', n))];
      this.factorExpression = n.toString();
      this.isPrime = true;
      this.showResult = true;
      this.calcVersion++;
      return;
    }

    let result: FactorizeResult = this.primeFactorization(n);

    let expression: string = '';
    for (let i: number = 0; i < result.factors.length; i++) {
      if (i > 0) {
        expression += ' × ';
      }
      expression += result.factors[i].value.toString();
    }

    this.factors = result.factors;
    this.steps = result.steps;
    this.factorExpression = expression;
    this.isPrime = false;
    this.showResult = true;
    this.calcVersion++;
  }

  private tryCalculate(): void {
    if (!this.inputNumber) {
      this.showResult = false;
      return;
    }
    let n: number = parseInt(this.inputNumber);
    if (isNaN(n) || n < 2) {
      this.showResult = false;
      return;
    }
    this.doFactorize(n);
  }

  private copyResult(): void {
    if (!this.showResult) {
      return;
    }
    let lines: string[] = [];
    lines.push(this.displayNumber + ' = ' + this.factorExpression);
    if (this.steps.length > 1) {
      for (let i: number = 0; i < this.steps.length; i++) {
        lines.push(this.steps[i]);
      }
    }
    try {
      let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      let pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, lines.join('\n'));
      systemPasteboard.setData(pasteData);
      ToastUtil.show(this.getUIContext(), $r('app.string.prime_copy_success'), 1000);
    } catch (e) {
      ToastUtil.show(this.getUIContext(), $r('app.string.sudoku_copy_failed'), 1000);
    }
  }

  build() {
    Scroll() {
      Column() {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceAround }) {
          ForEach(this.examples, (num: number) => {
            Column() {
              Text(num.toString())
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.idiom_blue'))
            }
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .margin({ bottom: 8 })
            .shadow({ radius: 2, color: '#1a000000', offsetY: 1 })
            .onClick(() => {
              this.inputNumber = num.toString();
              this.doFactorize(num);
            })
          }, (num: number) => num.toString())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 8 })

        Column() {
          TextInput({ text: this.inputNumber, placeholder: $r('app.string.prime_input_hint') })
            .type(InputType.Number)
            .inputFilter('^[0-9]*$', () => { return 0; })
            .maxLength(12)
            .width('100%')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .backgroundColor(Color.Transparent)
            .caretColor($r('app.color.idiom_blue'))
            .textAlign(TextAlign.Center)
            .onChange((value: string) => {
              this.inputNumber = value;
              this.tryCalculate();
            })

          Text($r('app.string.prime_range_hint'))
            .fontSize(11)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 4 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 20, bottom: 16 })
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)

        if (this.showResult) {
          Column() {
            Column() {
              Text(this.displayNumber)
                .fontSize(36)
                .fontWeight(FontWeight.Bolder)
                .fontColor($r('app.color.idiom_blue'))

              Text('=')
                .fontSize(24)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 6, bottom: 6 })

              Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
                ForEach(this.factors, (factor: PrimeFactorItem, index: number) => {
                  if (index > 0) {
                    Text('×')
                      .fontSize(16)
                      .fontColor($r('app.color.tertiary_text'))
                      .margin({ left: 2, right: 2 })
                  }
                  Text(factor.value.toString())
                    .fontSize(22)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.on_accent_text'))
                    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .backgroundColor($r('app.color.idiom_blue'))
                    .borderRadius(10)
                    .margin({ bottom: 6 })
                }, (factor: PrimeFactorItem, index: number) => index.toString() + '_' + factor.value.toString() + '_' + this.calcVersion.toString())
              }

              if (this.isPrime) {
                Row() {
                  Text($r('app.string.prime_is_prime_note', this.displayNumber))
                    .fontSize(13)
                    .fontColor($r('app.color.warning_amber'))
                    .fontWeight(FontWeight.Medium)
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .backgroundColor($r('app.color.warning_bg'))
                .borderRadius(10)
                .margin({ top: 8 })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 20, bottom: 16 })
            .backgroundColor($r('app.color.idiom_blue') + '08')

            if (this.steps.length > 1) {
              Column() {
                Text($r('app.string.prime_steps_title'))
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.secondary_text'))
                  .width('100%')
                  .margin({ bottom: 8, top: 4 })
                ForEach(this.steps, (step: string, index: number) => {
                  Row() {
                    Text('•')
                      .fontSize(12)
                      .fontColor($r('app.color.idiom_blue'))
                      .margin({ right: 6 })
                    Text(step)
                      .fontSize(13)
                      .fontColor($r('app.color.primary_text'))
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .margin({ bottom: 4 })
                  .padding({ left: 4 })
                }, (step: string, index: number) => index.toString() + '_' + this.calcVersion.toString())
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
            }

            Button($r('app.string.gcd_copy_result'))
              .fontSize(13)
              .fontColor($r('app.color.on_accent_text'))
              .backgroundColor($r('app.color.idiom_blue'))
              .borderRadius(8)
              .height(32)
              .padding({ left: 16, right: 16 })
              .margin({ top: 8, bottom: 12 })
              .onClick(() => {
                this.copyResult();
              })
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(16)
          .margin({ top: 12 })
          .clip(true)
        }

        Column() {
          Text($r('app.string.prime_what_title'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .margin({ bottom: 8 })
          Text($r('app.string.prime_what_desc'))
            .fontSize(13)
            .fontColor($r('app.color.secondary_text'))
          Text('12 = 2 × 2 × 3')
            .fontSize(14)
            .fontColor($r('app.color.idiom_blue'))
            .fontWeight(FontWeight.Medium)
            .margin({ top: 6 })
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.idiom_blue') + '0a')
            .borderRadius(8)
            .border({ width: 0.5, color: $r('app.color.idiom_blue') + '30', style: BorderStyle.Solid })
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .margin({ top: 12 })
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: 640 })
    .scrollable(ScrollDirection.Vertical)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }
}
