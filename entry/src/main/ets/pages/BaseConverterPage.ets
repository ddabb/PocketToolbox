@Builder
export function BaseConverterPageBuilder(param?: Object) {
  NavDestination() {
    BaseConverterContent()
  }
  .title('进制转换')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct BaseConverterContent {
  @State decimalValue: string = '';
  @State binaryValue: string = '';
  @State octalValue: string = '';
  @State hexValue: string = '';
  @State base64Value: string = '';
  @State base64Decoded: string = '';
  @State activeField: string = '';
  @State errorMsg: string = '';
  private focusedField: string = '';

  private readonly examples: string[][] = [
    ['255', '十进制'],
    ['11111111', '二进制'],
    ['777', '八进制'],
    ['FF', '十六进制']
  ];

  build() {
    Scroll() {
      Column() {
        this.InputField('十进制', 'DEC', $$this.decimalValue)
        this.InputField('二进制', 'BIN', $$this.binaryValue)
        this.InputField('八进制', 'OCT', $$this.octalValue)
        this.InputField('十六进制', 'HEX', $$this.hexValue)
        this.InputField('Base64', 'B64', $$this.base64Value)

        if (this.base64Decoded.length > 0) {
          Column() {
            Text('Base64解码')
              .fontSize(13)
              .fontColor($r('app.color.tertiary_text'))
              .margin({ bottom: 4 })
            Text(this.base64Decoded)
              .fontSize(14)
              .fontColor($r('app.color.primary_text'))
              .width('100%')
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .margin({ left: 16, right: 16, top: 8 })
        }

        if (this.errorMsg.length > 0) {
          Text(this.errorMsg)
            .fontSize(13)
            .fontColor($r('app.color.error_red'))
            .margin({ left: 16, right: 16, top: 8 })
        }

        this.ExamplesSection()
        this.InfoSection()
      }
      .width('100%')
      .padding({ bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .scrollable(ScrollDirection.Vertical)
  }

  @Builder
  InputField(label: string, symbol: string, textBinding: string) {
    Row() {
      Column() {
        Text(symbol)
          .fontSize(11)
          .fontColor($r('app.color.tertiary_text'))
        Text(label)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary_text'))
      }
      .width(64)
      .alignItems(HorizontalAlign.Center)

      TextInput({ text: textBinding, placeholder: '输入' + label + '数值' })
        .layoutWeight(1)
        .fontSize(15)
        .fontColor($r('app.color.primary_text'))
        .backgroundColor(Color.Transparent)
        .textAlign(TextAlign.End)
        .onFocus(() => {
          this.focusedField = label;
        })
        .onChange((value: string) => {
          this.onFieldChange(label, value);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.activeField === label ?
      $r('app.color.unit_active_bg') : $r('app.color.card_background'))
    .borderRadius(label === '十进制' ? 12 : 0)
  }

  private onFieldChange(field: string, value: string): void {
    if (this.focusedField.length > 0 && field !== this.focusedField) {
      return;
    }
    this.activeField = field;
    if (field === '十进制') {
      this.onDecimalChange(value);
    } else if (field === '二进制') {
      this.onBinaryChange(value);
    } else if (field === '八进制') {
      this.onOctalChange(value);
    } else if (field === '十六进制') {
      this.onHexChange(value);
    } else if (field === 'Base64') {
      this.onBase64Change(value);
    }
  }

  @Builder
  ExamplesSection() {
    Column() {
      Text('快速示例')
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
  }

  @Builder
  InfoSection() {
    Column() {
      Text('进制说明')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .margin({ bottom: 8 })

      this.InfoRow('十进制 (DEC)', '使用0-9，10个数字')
      this.InfoRow('二进制 (BIN)', '使用0和1，计算机基础')
      this.InfoRow('八进制 (OCT)', '使用0-7，8个数字')
      this.InfoRow('十六进制 (HEX)', '使用0-9和A-F')
      this.InfoRow('Base64 (B64)', '编码二进制数据为文本')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .margin({ left: 16, right: 16, top: 8, bottom: 16 })
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

  private clearAll(): void {
    this.decimalValue = '';
    this.binaryValue = '';
    this.octalValue = '';
    this.hexValue = '';
    this.base64Value = '';
    this.base64Decoded = '';
    this.errorMsg = '';
  }

  private onDecimalChange(value: string): void {
    if (value.length === 0) {
      this.clearAll();
      return;
    }
    let reg: RegExp = new RegExp('^[0-9]+$');
    if (!reg.test(value)) {
      this.errorMsg = '请输入有效的十进制数字';
      return;
    }
    this.errorMsg = '';
    let num: number = parseInt(value, 10);
    this.decimalValue = value;
    this.binaryValue = num.toString(2);
    this.octalValue = num.toString(8);
    this.hexValue = num.toString(16).toUpperCase();
    this.base64Value = this.numberToBase64(num);
    this.base64Decoded = this.numberToText(num);
  }

  private onBinaryChange(value: string): void {
    if (value.length === 0) {
      this.clearAll();
      return;
    }
    let reg: RegExp = new RegExp('^[01]+$');
    if (!reg.test(value)) {
      this.errorMsg = '请输入有效的二进制数字（0和1）';
      return;
    }
    this.errorMsg = '';
    let num: number = parseInt(value, 2);
    this.decimalValue = num.toString(10);
    this.binaryValue = value;
    this.octalValue = num.toString(8);
    this.hexValue = num.toString(16).toUpperCase();
    this.base64Value = this.numberToBase64(num);
    this.base64Decoded = this.numberToText(num);
  }

  private onOctalChange(value: string): void {
    if (value.length === 0) {
      this.clearAll();
      return;
    }
    let reg: RegExp = new RegExp('^[0-7]+$');
    if (!reg.test(value)) {
      this.errorMsg = '请输入有效的八进制数字（0-7）';
      return;
    }
    this.errorMsg = '';
    let num: number = parseInt(value, 8);
    this.decimalValue = num.toString(10);
    this.binaryValue = num.toString(2);
    this.octalValue = value;
    this.hexValue = num.toString(16).toUpperCase();
    this.base64Value = this.numberToBase64(num);
    this.base64Decoded = this.numberToText(num);
  }

  private onHexChange(value: string): void {
    if (value.length === 0) {
      this.clearAll();
      return;
    }
    let reg: RegExp = new RegExp('^[0-9A-Fa-f]+$');
    if (!reg.test(value)) {
      this.errorMsg = '请输入有效的十六进制数字（0-9, A-F）';
      return;
    }
    this.errorMsg = '';
    let num: number = parseInt(value, 16);
    this.decimalValue = num.toString(10);
    this.binaryValue = num.toString(2);
    this.octalValue = num.toString(8);
    this.hexValue = value.toUpperCase();
    this.base64Value = this.numberToBase64(num);
    this.base64Decoded = this.numberToText(num);
  }

  private onBase64Change(value: string): void {
    if (value.length === 0) {
      this.clearAll();
      return;
    }
    this.base64Value = value;
    try {
      let decoded: string = this.decodeBase64Text(value);
      this.base64Decoded = decoded;
      this.decimalValue = '';
      this.binaryValue = '';
      this.octalValue = '';
      this.hexValue = '';
    } catch (e) {
      this.errorMsg = '无效的Base64字符';
    }
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

  private numberToText(num: number): string {
    if (num === 0) {
      return '\0';
    }
    let bytes: number[] = [];
    let n: number = num;
    while (n > 0) {
      bytes.unshift(n & 0xFF);
      n = Math.floor(n / 256);
    }
    let result: string = '';
    for (let i = 0; i < bytes.length; i++) {
      result += String.fromCharCode(bytes[i]);
    }
    return result;
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

  private useExample(value: string, source: string): void {
    this.clearAll();
    if (source === '十进制') {
      this.focusedField = '十进制';
      this.decimalValue = value;
      this.onDecimalChange(value);
    } else if (source === '二进制') {
      this.focusedField = '二进制';
      this.binaryValue = value;
      this.onBinaryChange(value);
    } else if (source === '八进制') {
      this.focusedField = '八进制';
      this.octalValue = value;
      this.onOctalChange(value);
    } else if (source === '十六进制') {
      this.focusedField = '十六进制';
      this.hexValue = value;
      this.onHexChange(value);
    }
  }
}
