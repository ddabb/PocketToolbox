@Observed
class BaseValueItem {
  name: string = '';
  symbol: string = '';
  value: string = '';

  constructor(name: string, symbol: string, value: string) {
    this.name = name;
    this.symbol = symbol;
    this.value = value;
  }
}

@Builder
export function BaseConverterPageBuilder(param?: Object) {
  NavDestination() {
    BaseConverterContent()
  }
  .title('\u8FDB\u5236\u8F6C\u6362')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct BaseValueRow {
  @ObjectLink item: BaseValueItem;
  isActive: boolean = false;
  showDivider: boolean = false;
  onValueChange: (value: string) => void = () => {};
  onItemFocus: () => void = () => {};

  build() {
    Column() {
      Row() {
        Column() {
          Text(this.item.symbol)
            .fontSize(11)
            .fontColor($r('app.color.tertiary_text'))
          Text(this.item.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary_text'))
        }
        .width(64)
        .alignItems(HorizontalAlign.Center)

        TextInput({ text: $$this.item.value, placeholder: '\u8F93\u5165\u6570\u503C' })
          .type(InputType.Normal)
          .layoutWeight(1)
          .fontSize(15)
          .fontColor($r('app.color.primary_text'))
          .backgroundColor(Color.Transparent)
          .textAlign(TextAlign.End)
          .onFocus(() => {
            this.onItemFocus();
          })
          .onChange((value: string) => {
            this.onValueChange(value);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      if (this.showDivider) {
        Divider()
          .color($r('app.color.border_color'))
          .margin({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .backgroundColor(this.isActive ? $r('app.color.unit_active_bg') : $r('app.color.card_background'))
  }
}

@Component
struct BaseConverterContent {
  @State baseValues: BaseValueItem[] = [];
  @State activeBaseIndex: number = -1;
  @State errorMsg: string = '';
  private focusedIndex: number = -1;
  private suppressOnChange: boolean = false;

  private readonly examples: string[][] = [
    ['255', '\u5341\u8FDB\u5236'],
    ['11111111', '\u4E8C\u8FDB\u5236'],
    ['777', '\u516B\u8FDB\u5236'],
    ['FF', '\u5341\u516D\u8FDB\u5236']
  ];

  aboutToAppear(): void {
    this.baseValues = [
      new BaseValueItem('\u5341\u8FDB\u5236', 'DEC', ''),
      new BaseValueItem('\u4E8C\u8FDB\u5236', 'BIN', ''),
      new BaseValueItem('\u516B\u8FDB\u5236', 'OCT', ''),
      new BaseValueItem('\u5341\u516D\u8FDB\u5236', 'HEX', ''),
      new BaseValueItem('Base64', 'B64', '')
    ];
  }

  private getDecimalNum(inputValue: string, baseName: string): number {
    if (inputValue.length === 0) {
      return NaN;
    }
    if (baseName === '\u5341\u8FDB\u5236') {
      let reg: RegExp = new RegExp('^[0-9]+$');
      if (!reg.test(inputValue)) {
        return NaN;
      }
      return parseInt(inputValue, 10);
    } else if (baseName === '\u4E8C\u8FDB\u5236') {
      let reg: RegExp = new RegExp('^[01]+$');
      if (!reg.test(inputValue)) {
        return NaN;
      }
      return parseInt(inputValue, 2);
    } else if (baseName === '\u516B\u8FDB\u5236') {
      let reg: RegExp = new RegExp('^[0-7]+$');
      if (!reg.test(inputValue)) {
        return NaN;
      }
      return parseInt(inputValue, 8);
    } else if (baseName === '\u5341\u516D\u8FDB\u5236') {
      let reg: RegExp = new RegExp('^[0-9A-Fa-f]+$');
      if (!reg.test(inputValue)) {
        return NaN;
      }
      return parseInt(inputValue, 16);
    }
    return NaN;
  }

  private validateInput(value: string, baseName: string): string {
    if (value.length === 0) {
      return '';
    }
    if (baseName === '\u5341\u8FDB\u5236') {
      let reg: RegExp = new RegExp('^[0-9]+$');
      if (!reg.test(value)) {
        return '\u8BF7\u8F93\u5165\u6709\u6548\u7684\u5341\u8FDB\u5236\u6570\u5B57';
      }
    } else if (baseName === '\u4E8C\u8FDB\u5236') {
      let reg: RegExp = new RegExp('^[01]+$');
      if (!reg.test(value)) {
        return '\u8BF7\u8F93\u5165\u6709\u6548\u7684\u4E8C\u8FDB\u5236\u6570\u5B57\uFF080\u548C1\uFF09';
      }
    } else if (baseName === '\u516B\u8FDB\u5236') {
      let reg: RegExp = new RegExp('^[0-7]+$');
      if (!reg.test(value)) {
        return '\u8BF7\u8F93\u5165\u6709\u6548\u7684\u516B\u8FDB\u5236\u6570\u5B57\uFF080-7\uFF09';
      }
    } else if (baseName === '\u5341\u516D\u8FDB\u5236') {
      let reg: RegExp = new RegExp('^[0-9A-Fa-f]+$');
      if (!reg.test(value)) {
        return '\u8BF7\u8F93\u5165\u6709\u6548\u7684\u5341\u516D\u8FDB\u5236\u6570\u5B57\uFF080-9, A-F\uFF09';
      }
    } else if (baseName === 'Base64') {
      try {
        this.decodeBase64Text(value);
      } catch (e) {
        return '\u65E0\u6548\u7684Base64\u5B57\u7B26';
      }
    }
    return '';
  }

  private numberToBase64(num: number): string {
    if (num === 0) {
      return 'AA==';
    }
    let bytes: number[] = [];
    let n: number = num;
    while (n > 0) {
      bytes.unshift(n & 0xFF);
      n = Math.floor(n / 256);
    }
    return this.encodeBase64(bytes);
  }

  private encodeBase64(bytes: number[]): string {
    let chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result: string = '';
    let len: number = bytes.length;
    for (let i = 0; i < len; i += 3) {
      let b0: number = bytes[i];
      let b1: number = (i + 1 < len) ? bytes[i + 1] : 0;
      let b2: number = (i + 2 < len) ? bytes[i + 2] : 0;
      let triplet: number = (b0 << 16) | (b1 << 8) | b2;
      result += chars[(triplet >> 18) & 0x3F];
      result += chars[(triplet >> 12) & 0x3F];
      result += (i + 1 < len) ? chars[(triplet >> 6) & 0x3F] : '=';
      result += (i + 2 < len) ? chars[triplet & 0x3F] : '=';
    }
    return result;
  }

  private decodeBase64Text(input: string): string {
    let chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let cleanInput: string = input.replace(new RegExp('\\s', 'g'), '');
    let bytes: number[] = [];
    for (let i = 0; i < cleanInput.length; i += 4) {
      let a: number = chars.indexOf(cleanInput[i]);
      let b: number = (i + 1 < cleanInput.length) ? chars.indexOf(cleanInput[i + 1]) : 0;
      let c: number = (i + 2 < cleanInput.length && cleanInput[i + 2] !== '=') ?
        chars.indexOf(cleanInput[i + 2]) : 0;
      let d: number = (i + 3 < cleanInput.length && cleanInput[i + 3] !== '=') ?
        chars.indexOf(cleanInput[i + 3]) : 0;
      let triplet: number = (a << 18) | (b << 12) | (c << 6) | d;
      bytes.push((triplet >> 16) & 0xFF);
      if (i + 2 < cleanInput.length && cleanInput[i + 2] !== '=') {
        bytes.push((triplet >> 8) & 0xFF);
      }
      if (i + 3 < cleanInput.length && cleanInput[i + 3] !== '=') {
        bytes.push(triplet & 0xFF);
      }
    }
    let result: string = '';
    for (let i = 0; i < bytes.length; i++) {
      result += String.fromCharCode(bytes[i]);
    }
    return result;
  }

  private onValueChange(changedIndex: number, value: string): void {
    if (this.suppressOnChange) {
      return;
    }
    if (this.focusedIndex >= 0 && changedIndex !== this.focusedIndex) {
      return;
    }
    this.activeBaseIndex = changedIndex;
    this.suppressOnChange = true;

    let baseName: string = this.baseValues[changedIndex].name;
    let validationMsg: string = this.validateInput(value, baseName);
    this.errorMsg = validationMsg;

    if (!value || value.length === 0) {
      for (let i = 0; i < this.baseValues.length; i++) {
        this.baseValues[i].value = '';
      }
      this.suppressOnChange = false;
      return;
    }

    if (validationMsg.length > 0) {
      this.baseValues[changedIndex].value = value;
      for (let i = 0; i < this.baseValues.length; i++) {
        if (i !== changedIndex) {
          this.baseValues[i].value = '';
        }
      }
      this.suppressOnChange = false;
      return;
    }

    this.baseValues[changedIndex].value = value;

    if (baseName === 'Base64') {
      let decoded: string = this.decodeBase64Text(value);
      let num: number = 0;
      for (let i = 0; i < decoded.length; i++) {
        num = num * 256 + decoded.charCodeAt(i);
      }
      this.baseValues[0].value = num.toString(10);
      this.baseValues[1].value = num.toString(2);
      this.baseValues[2].value = num.toString(8);
      this.baseValues[3].value = num.toString(16).toUpperCase();
    } else {
      let num: number = this.getDecimalNum(value, baseName);
      if (isNaN(num)) {
        this.suppressOnChange = false;
        return;
      }
      this.baseValues[0].value = num.toString(10);
      this.baseValues[1].value = num.toString(2);
      this.baseValues[2].value = num.toString(8);
      this.baseValues[3].value = num.toString(16).toUpperCase();
      if (num >= 0) {
        this.baseValues[4].value = this.numberToBase64(num);
      } else {
        this.baseValues[4].value = '';
      }
    }

    this.suppressOnChange = false;
  }

  build() {
    Scroll() {
      Column() {
        List({ space: 0 }) {
          ForEach(this.baseValues, (item: BaseValueItem, index: number) => {
            ListItem() {
              BaseValueRow({
                item: item,
                isActive: this.activeBaseIndex === index,
                showDivider: index < this.baseValues.length - 1,
                onValueChange: (value: string) => {
                  this.onValueChange(index, value);
                },
                onItemFocus: () => {
                  this.focusedIndex = index;
                }
              })
            }
          }, (item: BaseValueItem) => item.name)
        }
        .width('100%')
        .borderRadius(12)
        .clip(true)
        .margin({ left: 16, right: 16, top: 8 })

        if (this.errorMsg.length > 0) {
          Text(this.errorMsg)
            .fontSize(13)
            .fontColor($r('app.color.error_red'))
            .margin({ left: 16, right: 16, top: 4 })
        }

        Column() {
          Text('\u5FEB\u901F\u793A\u4F8B')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .margin({ bottom: 8 })

          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.examples, (ex: string[]) => {
              Column() {
                Text(ex[0])
                  .fontSize(15)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.idiom_blue'))
                Text(ex[1])
                  .fontSize(11)
                  .fontColor($r('app.color.tertiary_text'))
                  .margin({ top: 2 })
              }
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .backgroundColor($r('app.color.idiom_blue') + '12')
              .borderRadius(10)
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.useExample(ex[0], ex[1]);
              })
            }, (ex: string[]) => ex[0] + ex[1])
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .margin({ left: 16, right: 16, top: 12 })

        Column() {
          Text('\u8FDB\u5236\u8BF4\u660E')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .margin({ bottom: 8 })

          this.InfoRow('\u5341\u8FDB\u5236 (DEC)', '\u4F7F\u75280-9\uFF0C10\u4E2A\u6570\u5B57')
          this.InfoRow('\u4E8C\u8FDB\u5236 (BIN)', '\u4F7F\u75280\u548C1\uFF0C\u8BA1\u7B97\u673A\u57FA\u7840')
          this.InfoRow('\u516B\u8FDB\u5236 (OCT)', '\u4F7F\u75280-7\uFF0C8\u4E2A\u6570\u5B57')
          this.InfoRow('\u5341\u516D\u8FDB\u5236 (HEX)', '\u4F7F\u75280-9\u548CA-F')
          this.InfoRow('Base64 (B64)', '\u7F16\u7801\u4E8C\u8FDB\u5236\u6570\u636E\u4E3A\u6587\u672C')
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
        .margin({ left: 16, right: 16, top: 8, bottom: 16 })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .scrollable(ScrollDirection.Vertical)
  }

  @Builder
  InfoRow(title: string, desc: string) {
    Row() {
      Text(title)
        .fontSize(13)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Medium)
        .width(130)
      Text(desc)
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ bottom: 4 })
  }

  private useExample(value: string, source: string): void {
    this.suppressOnChange = true;
    let targetIndex: number = -1;
    for (let i = 0; i < this.baseValues.length; i++) {
      if (this.baseValues[i].name === source) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex < 0) {
      this.suppressOnChange = false;
      return;
    }

    this.activeBaseIndex = targetIndex;
    this.focusedIndex = targetIndex;
    this.baseValues[targetIndex].value = value;

    if (source === 'Base64') {
      let decoded: string = this.decodeBase64Text(value);
      let num: number = 0;
      for (let i = 0; i < decoded.length; i++) {
        num = num * 256 + decoded.charCodeAt(i);
      }
      this.baseValues[0].value = num.toString(10);
      this.baseValues[1].value = num.toString(2);
      this.baseValues[2].value = num.toString(8);
      this.baseValues[3].value = num.toString(16).toUpperCase();
    } else {
      let num: number = this.getDecimalNum(value, source);
      if (!isNaN(num)) {
        this.baseValues[0].value = num.toString(10);
        this.baseValues[1].value = num.toString(2);
        this.baseValues[2].value = num.toString(8);
        this.baseValues[3].value = num.toString(16).toUpperCase();
        if (num >= 0) {
          this.baseValues[4].value = this.numberToBase64(num);
        } else {
          this.baseValues[4].value = '';
        }
      }
    }

    this.suppressOnChange = false;
  }
}
