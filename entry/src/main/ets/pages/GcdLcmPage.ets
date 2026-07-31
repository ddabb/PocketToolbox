import { pasteboard } from '@kit.BasicServicesKit';

@Builder
export function GcdLcmPageBuilder() {
  NavDestination() {
    GcdLcmContent()
  }
  .title('公约/倍数')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct GcdLcmContent {
  @State num1: string = '';
  @State num2: string = '';
  @State gcd: number = 0;
  @State lcm: number = 0;
  @State showResult: boolean = false;
  @State steps: string[] = [];
  @State gcdFactor1: string = '';
  @State gcdFactor2: string = '';
  @State lcmFormula: string = '';

  private readonly examples: number[][] = [
    [48, 18], [100, 75], [36, 24], [144, 96]
  ];

  aboutToAppear(): void {
    let first: number[] = this.examples[0];
    this.num1 = first[0].toString();
    this.num2 = first[1].toString();
    this.tryCalculate();
  }

  private calculateGCD(a: number, b: number): number {
    let x: number = a;
    let y: number = b;
    while (y !== 0) {
      let temp: number = y;
      y = x % y;
      x = temp;
    }
    return x;
  }

  private generateSteps(a: number, b: number, gcd: number): string[] {
    let result: string[] = [];
    result.push('使用欧几里得算法求 ' + a.toString() + ' 和 ' + b.toString() + ' 的最大公约数');
    let x: number = Math.max(a, b);
    let y: number = Math.min(a, b);
    while (y !== 0) {
      let remainder: number = x % y;
      let quotient: number = Math.floor(x / y);
      if (remainder > 0) {
        result.push(x.toString() + ' ÷ ' + y.toString() + ' = ' + quotient.toString() + ' 余 ' + remainder.toString());
      } else {
        result.push(x.toString() + ' ÷ ' + y.toString() + ' = ' + quotient.toString());
      }
      x = y;
      y = remainder;
    }
    result.push('余数为0，最大公约数为 ' + x.toString());
    result.push('最小公倍数 = (' + a.toString() + ' × ' + b.toString() + ') ÷ ' + x.toString() + ' = ' + ((a * b) / x).toString());
    return result;
  }

  private tryCalculate(): void {
    if (!this.num1 || !this.num2) {
      this.showResult = false;
      return;
    }
    let v1: number = parseInt(this.num1);
    let v2: number = parseInt(this.num2);
    if (isNaN(v1) || isNaN(v2) || v1 < 1 || v2 < 1) {
      this.showResult = false;
      return;
    }
    if (v1 > 999999 || v2 > 999999) {
      this.showResult = false;
      return;
    }
    let g: number = this.calculateGCD(v1, v2);
    let l: number = (v1 * v2) / g;
    this.gcd = g;
    this.lcm = l;
    this.gcdFactor1 = v1.toString() + ' = ' + g.toString() + ' × ' + (v1 / g).toString();
    this.gcdFactor2 = v2.toString() + ' = ' + g.toString() + ' × ' + (v2 / g).toString();
    this.lcmFormula = l.toString() + ' = ' + v1.toString() + ' × ' + v2.toString() + ' ÷ ' + g.toString();
    this.steps = this.generateSteps(v1, v2, g);
    this.showResult = true;
  }

  private useExample(n1: number, n2: number): void {
    this.num1 = n1.toString();
    this.num2 = n2.toString();
    this.tryCalculate();
  }

  private copyResult(): void {
    if (!this.showResult) {
      return;
    }
    let lines: string[] = [];
    lines.push(this.gcdFactor1.split(' = ')[0] + ' 和 ' + this.gcdFactor2.split(' = ')[0]);
    lines.push('最大公约数：' + this.gcd.toString());
    lines.push(this.gcdFactor1);
    lines.push(this.gcdFactor2);
    lines.push('最小公倍数：' + this.lcm.toString());
    lines.push(this.lcmFormula);
    try {
      let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      let pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, lines.join('\n'));
      systemPasteboard.setData(pasteData);
      this.getUIContext().getPromptAction().showToast({ message: '已复制转换结果', duration: 1000 });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '复制失败', duration: 1000 });
    }
  }

  build() {
    Scroll() {
      Column() {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceAround }) {
          ForEach(this.examples, (ex: number[]) => {
            Column() {
              Text(ex[0].toString() + ' 和 ' + ex[1].toString())
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.idiom_blue'))
            }
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(12)
            .margin({ bottom: 8 })
            .shadow({ radius: 2, color: '#1a000000', offsetY: 1 })
            .onClick(() => {
              this.useExample(ex[0], ex[1]);
            })
          }, (ex: number[]) => ex[0].toString() + '_' + ex[1].toString())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 8 })

        Column() {
          Row() {
            Text('A')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width(28)
              .height(28)
              .borderRadius(8)
              .backgroundColor($r('app.color.idiom_blue'))
              .textAlign(TextAlign.Center)
              .margin({ right: 10 })
            TextInput({ text: this.num1, placeholder: '第一个正整数' })
              .type(InputType.Number)
              .inputFilter('^[0-9]*$', () => { return 0; })
              .maxLength(6)
              .layoutWeight(1)
              .fontSize(18)
              .fontColor($r('app.color.primary_text'))
              .backgroundColor(Color.Transparent)
              .caretColor($r('app.color.idiom_blue'))
              .onChange((value: string) => {
                this.num1 = value;
                this.tryCalculate();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .alignItems(VerticalAlign.Center)

          Divider().color($r('app.color.border_color')).margin({ left: 54, right: 16 })

          Row() {
            Text('B')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
              .width(28)
              .height(28)
              .borderRadius(8)
              .backgroundColor('#e74c3c')
              .textAlign(TextAlign.Center)
              .margin({ right: 10 })
            TextInput({ text: this.num2, placeholder: '第二个正整数' })
              .type(InputType.Number)
              .inputFilter('^[0-9]*$', () => { return 0; })
              .maxLength(6)
              .layoutWeight(1)
              .fontSize(18)
              .fontColor($r('app.color.primary_text'))
              .backgroundColor(Color.Transparent)
              .caretColor($r('app.color.idiom_blue'))
              .onChange((value: string) => {
                this.num2 = value;
                this.tryCalculate();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)

        Column() {
          if (this.showResult) {
            Column() {
              Text('最大公约数 (GCD)')
                .fontSize(12)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ bottom: 4 })
              Text(this.gcd.toString())
                .fontSize(36)
                .fontWeight(FontWeight.Bolder)
                .fontColor($r('app.color.idiom_blue'))
              Text(this.gcdFactor1)
                .fontSize(12)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 4 })
              Text(this.gcdFactor2)
                .fontSize(12)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 20, bottom: 16 })
            .backgroundColor($r('app.color.idiom_blue') + '08')
            .borderRadius({ topLeft: 16, topRight: 16 })

            Divider().color($r('app.color.border_color'))

            Column() {
              Text('最小公倍数 (LCM)')
                .fontSize(12)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ bottom: 4 })
              Text(this.lcm.toString())
                .fontSize(36)
                .fontWeight(FontWeight.Bolder)
                .fontColor('#e74c3c')
              Text(this.lcmFormula)
                .fontSize(12)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 4 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 16, bottom: 16 })
            .backgroundColor('#e74c3c08')
            .borderRadius({ bottomLeft: 16, bottomRight: 16 })

            Column() {
              Text('计算过程')
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
              }, (step: string, index: number) => index.toString())
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })

            Button('复制结果')
              .fontSize(13)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.idiom_blue'))
              .borderRadius(8)
              .height(32)
              .padding({ left: 16, right: 16 })
              .margin({ top: 8, bottom: 12 })
              .onClick(() => {
                this.copyResult();
              })
          } else {
            Column() {
              Text('输入两个正整数，实时计算')
                .fontSize(14)
                .fontColor($r('app.color.tertiary_text'))
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 40, bottom: 40 })
          }
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .margin({ top: 12 })
        .clip(true)
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .scrollable(ScrollDirection.Vertical)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }
}
