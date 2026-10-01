import { pasteboard } from '@kit.BasicServicesKit';
import { Context } from '@kit.AbilityKit';
import { ToastUtil } from '../common/utils/ToastUtil';
import { StrUtil } from '../common/utils/StrUtil';

@Observed
class BaseValueItem {
  id: string = '';
  name: ResourceStr = '';
  symbol: string = '';
  value: string = '';

  constructor(id: string, name: ResourceStr, symbol: string, value: string) {
    this.id = id;
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
  .title($r('app.string.basec_title'))
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

        TextInput({ text: $$this.item.value, placeholder: $r('app.string.basec_input_placeholder') })
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
  @State errorMsg: ResourceStr = '';
  private focusedIndex: number = -1;
  private suppressOnChange: boolean = false;

  private readonly examples: string[][] = [
    ['255', 'dec'],
    ['11111111', 'bin'],
    ['777', 'oct'],
    ['FF', 'hex']
  ];

  private copyAllResults(): void {
    let hasValue: boolean = false;
    for (let i = 0; i < this.baseValues.length; i++) {
      if (this.baseValues[i].value.length > 0) {
        hasValue = true;
        break;
      }
    }
    if (!hasValue) {
      return;
    }
    let ctx: Context = this.getUIContext().getHostContext() as Context;
    let lines: string[] = [];
    for (let i = 0; i < this.baseValues.length; i++) {
      if (this.baseValues[i].value.length > 0) {
        lines.push(StrUtil.text(ctx, $r('app.string.basec_copy_line',
          StrUtil.text(ctx, this.baseValues[i].name), this.baseValues[i].value)));
      }
    }
    try {
      let systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      let pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, lines.join('\n'));
      systemPasteboard.setData(pasteData);
      ToastUtil.show(this.getUIContext(), $r('app.string.gcd_copy_success'), 1000);
    } catch (e) {
      ToastUtil.show(this.getUIContext(), $r('app.string.sudoku_copy_failed'), 1000);
    }
  }

  aboutToAppear(): void {
    this.baseValues = [
      new BaseValueItem('dec', $r('app.string.basec_radix_dec'), 'DEC', ''),
      new BaseValueItem('bin', $r('app.string.basec_radix_bin'), 'BIN', ''),
      new BaseValueItem('oct', $r('app.string.basec_radix_oct'), 'OCT', ''),
      new BaseValueItem('hex', $r('app.string.basec_radix_hex'), 'HEX', ''),
      new BaseValueItem('b64', 'Base64', 'B64', '')
    ];
  }

  private radixName(baseId: string): ResourceStr {
    if (baseId === 'dec') {
      return $r('app.string.basec_radix_dec');
    }
    if (baseId === 'bin') {
      return $r('app.string.basec_radix_bin');
    }
    if (baseId === 'oct') {
      return $r('app.string.basec_radix_oct');
    }
    if (baseId === 'hex') {
      return $r('app.string.basec_radix_hex');
    }
    return 'Base64';
  }

  private getDecimalNum(inputValue: string, baseId: string): number {
    if (inputValue.length === 0) {
      return NaN;
    }
    if (baseId === 'dec') {
      let reg: RegExp = new RegExp('^[0-9]+$');
      if (!reg.test(inputValue)) {
        return NaN;
      }
      return parseInt(inputValue, 10);
    } else if (baseId === 'bin') {
      let reg: RegExp = new RegExp('^[01]+$');
      if (!reg.test(inputValue)) {
        return NaN;
      }
      return parseInt(inputValue, 2);
    } else if (baseId === 'oct') {
      let reg: RegExp = new RegExp('^[0-7]+$');
      if (!reg.test(inputValue)) {
        return NaN;
      }
      return parseInt(inputValue, 8);
    } else if (baseId === 'hex') {
      let reg: RegExp = new RegExp('^[0-9A-Fa-f]+$');
      if (!reg.test(inputValue)) {
        return NaN;
      }
      return parseInt(inputValue, 16);
    }
    return NaN;
  }

  private validateInput(value: string, baseId: string): ResourceStr {
    if (value.length === 0) {
      return '';
    }
    if (baseId === 'dec') {
      let reg: RegExp = new RegExp('^[0-9]+$');
      if (!reg.test(value)) {
        return $r('app.string.basec_err_dec');
      }
    } else if (baseId === 'bin') {
      let reg: RegExp = new RegExp('^[01]+$');
      if (!reg.test(value)) {
        return $r('app.string.basec_err_bin');
      }
    } else if (baseId === 'oct') {
      let reg: RegExp = new RegExp('^[0-7]+$');
      if (!reg.test(value)) {
        return $r('app.string.basec_err_oct');
      }
    } else if (baseId === 'hex') {
      let reg: RegExp = new RegExp('^[0-9A-Fa-f]+$');
      if (!reg.test(value)) {
        return $r('app.string.basec_err_hex');
      }
    } else if (baseId === 'b64') {
      try {
        this.decodeBase64Text(value);
      } catch (e) {
        return $r('app.string.basec_err_b64');
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

    let baseId: string = this.baseValues[changedIndex].id;
    let validationMsg: ResourceStr = this.validateInput(value, baseId);
    this.errorMsg = validationMsg;

    if (!value || value.length === 0) {
      for (let i = 0; i < this.baseValues.length; i++) {
        this.baseValues[i].value = '';
      }
      this.suppressOnChange = false;
      return;
    }

    if (validationMsg !== '') {
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

    if (baseId === 'b64') {
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
      let num: number = this.getDecimalNum(value, baseId);
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
          }, (item: BaseValueItem) => item.id)
        }
        .width('100%')
        .borderRadius(12)
        .clip(true)
        .margin({ left: 16, right: 16, top: 8 })
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

        Row() {
          Text($r('app.string.basec_copy_all'))
            .fontSize(13)
            .fontColor($r('app.color.idiom_blue'))
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 4, bottom: 4 })
        .onClick(() => {
          this.copyAllResults();
        })

        if (this.errorMsg !== '') {
          Text(this.errorMsg)
            .fontSize(13)
            .fontColor($r('app.color.error_red'))
            .margin({ left: 16, right: 16, top: 4 })
        }

        Column() {
          Text($r('app.string.basec_examples_title'))
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
                Text(this.radixName(ex[1]))
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
          Text($r('app.string.basec_info_title'))
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .margin({ bottom: 8 })

          this.InfoRow($r('app.string.basec_info_dec_title'), $r('app.string.basec_info_dec_desc'))
          this.InfoRow($r('app.string.basec_info_bin_title'), $r('app.string.basec_info_bin_desc'))
          this.InfoRow($r('app.string.basec_info_oct_title'), $r('app.string.basec_info_oct_desc'))
          this.InfoRow($r('app.string.basec_info_hex_title'), $r('app.string.basec_info_hex_desc'))
          this.InfoRow('Base64 (B64)', $r('app.string.basec_info_b64_desc'))
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
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  InfoRow(title: ResourceStr, desc: ResourceStr) {
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
      if (this.baseValues[i].id === source) {
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

    if (source === 'b64') {
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
