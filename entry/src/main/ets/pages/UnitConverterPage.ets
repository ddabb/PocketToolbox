import { UnitItem, UnitConverterData, ConverterCategory } from '../model/UnitModels';

@Observed
class UnitValueItem {
  name: string = '';
  value: string = '';

  constructor(name: string, value: string) {
    this.name = name;
    this.value = value;
  }
}

class ConverterParamInfo {
  categoryId: string = '';
  title: string = '';
}

function buildConverterParam(param: Object): ConverterParamInfo {
  let p: Record<string, Object> = param as Record<string, Object>;
  let info: ConverterParamInfo = new ConverterParamInfo();
  info.categoryId = (p['categoryId'] ?? '') as string;
  info.title = (p['title'] ?? '') as string;
  return info;
}

@Builder
export function UnitConverterPageBuilder(param: Object) {
  NavDestination() {
    UnitConverterContent({ convParam: buildConverterParam(param) })
  }
  .title(buildConverterParam(param).title)
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct UnitValueRow {
  @ObjectLink item: UnitValueItem;
  isActive: boolean = false;
  showDivider: boolean = false;
  onValueChange: (value: string) => void = () => {};
  onItemFocus: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text(this.item.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.secondary_text'))
          .width(80)
        TextInput({ text: $$this.item.value, placeholder: '\u8F93\u5165\u6570\u503C' })
          .type(InputType.Normal)
          .inputFilter('^[0-9.\\-]*$', () => {
            return 0;
          })
          .layoutWeight(1)
          .fontSize(15)
          .fontColor($r('app.color.primary_text'))
          .backgroundColor(Color.Transparent)
          .caretColor($r('app.color.idiom_blue'))
          .selectedBackgroundColor($r('app.color.unit_active_bg'))
          .textAlign(TextAlign.End)
          .onFocus(() => {
            this.onItemFocus();
          })
          .onChange((value: string) => {
            let dotCount: number = 0;
            let filtered: string = '';
            for (let i = 0; i < value.length; i++) {
              let ch: string = value[i];
              if (ch === '.') {
                dotCount++;
                if (dotCount > 1) {
                  continue;
                }
              }
              if (ch === '-' && i !== 0) {
                continue;
              }
              filtered += ch;
            }
            let cleaned: string = filtered.replace(/^0+(?=\d)/, '');
            if (cleaned.length === 0 && value.length > 0) {
              cleaned = '0';
            }
            if (cleaned === '-' || cleaned === '-0') {
              cleaned = '-0';
            }
            this.onValueChange(cleaned);
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
struct UnitConverterContent {
  @Prop convParam: ConverterParamInfo = new ConverterParamInfo();
  @State unitValues: UnitValueItem[] = [];
  @State activeUnitIndex: number = -1;
  private category: ConverterCategory | null = null;
  private isTemperature: boolean = false;
  private focusedIndex: number = -1;
  private suppressOnChange: boolean = false;

  aboutToAppear(): void {
    this.category = UnitConverterData.getCategoryById(this.convParam.categoryId);
    if (this.category !== null) {
      this.isTemperature = this.category.isTemperature;
      let items: UnitValueItem[] = [];
      if (this.isTemperature) {
        let units: string[] = UnitConverterData.temperatureUnits;
        for (let i = 0; i < units.length; i++) {
          items.push(new UnitValueItem(units[i], ''));
        }
      } else {
        for (let i = 0; i < this.category.units.length; i++) {
          items.push(new UnitValueItem(this.category.units[i].name, ''));
        }
      }
      this.unitValues = items;
    }
  }

  private onValueChange(changedIndex: number, value: string): void {
    if (this.suppressOnChange) {
      return;
    }
    if (this.focusedIndex >= 0 && changedIndex !== this.focusedIndex) {
      return;
    }
    this.activeUnitIndex = changedIndex;
    this.suppressOnChange = true;

    if (!value || value.length === 0) {
      for (let i = 0; i < this.unitValues.length; i++) {
        this.unitValues[i].value = '';
      }
      this.suppressOnChange = false;
      return;
    }

    let inputValue: number = parseFloat(value);
    if (isNaN(inputValue)) {
      this.unitValues[changedIndex].value = value;
      this.suppressOnChange = false;
      return;
    }

    this.unitValues[changedIndex].value = value;

    if (this.isTemperature) {
      let unitNames: string[] = UnitConverterData.temperatureUnits;
      let baseValue: number = UnitConverterData.temperatureToBase(inputValue, unitNames[changedIndex]);
      for (let i = 0; i < this.unitValues.length; i++) {
        if (i !== changedIndex) {
          let result: number = UnitConverterData.temperatureFromBase(baseValue, unitNames[i]);
          this.unitValues[i].value = UnitConverterData.formatResult(result);
        }
      }
    } else if (this.category !== null) {
      let units: UnitItem[] = this.category.units;
      let baseValue: number = inputValue * units[changedIndex].toBase;
      for (let i = 0; i < this.unitValues.length; i++) {
        if (i !== changedIndex) {
          let result: number = baseValue * units[i].fromBase;
          this.unitValues[i].value = UnitConverterData.formatResult(result);
        }
      }
    }

    this.suppressOnChange = false;
  }

  build() {
    Column() {
      List({ space: 0 }) {
        ForEach(this.unitValues, (item: UnitValueItem, index: number) => {
          ListItem() {
            UnitValueRow({
              item: item,
              isActive: this.activeUnitIndex === index,
              showDivider: index < this.unitValues.length - 1,
              onValueChange: (value: string) => {
                this.onValueChange(index, value);
              },
              onItemFocus: () => {
                this.focusedIndex = index;
              }
            })
          }
        }, (item: UnitValueItem) => item.name)
      }
      .width('100%')
      .layoutWeight(1)
      .borderRadius(12)
      .clip(true)
      .margin({ left: 16, right: 16, top: 8 })

      Scroll() {
        Column() {
          Text('\u5E38\u7528\u53C2\u8003')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .margin({ bottom: 8 })

          if (this.isTemperature) {
            this.ConceptRow('\u6444\u6C0F\u5EA6', '\u51B0\u70B90\u00B0C\uFF0C\u6CB8\u70B9100\u00B0C')
            this.ConceptRow('\u534E\u6C0F\u5EA6', '\u51B0\u70B932\u00B0F\uFF0C\u6CB8\u70B9212\u00B0F')
            this.ConceptRow('\u5F00\u5C14\u6587', '\u7EDD\u5BF9\u96F6\u5EA60K = -273.15\u00B0C')
          } else if (this.category !== null) {
            if (this.category.id === 'length') {
              this.ConceptRow('1\u5343\u7C73', '= 0.621371\u82F1\u91CC')
              this.ConceptRow('1\u7C73', '= 3.28084\u82F1\u5C3A')
              this.ConceptRow('1\u5BF8', '\u2248 3.33\u5398\u7C73')
              this.ConceptRow('1\u6D77\u91CC', '= 1.852\u5343\u7C73')
            } else if (this.category.id === 'area') {
              this.ConceptRow('1\u516C\u9877', '= 10000\u5E73\u65B9\u7C73')
              this.ConceptRow('1\u4EA9', '\u2248 666.67\u5E73\u65B9\u7C73')
              this.ConceptRow('1\u82F1\u4EA9', '\u2248 4046.86\u5E73\u65B9\u7C73')
            } else if (this.category.id === 'weight') {
              this.ConceptRow('1\u5343\u514B', '\u2248 2.20462\u78C5')
              this.ConceptRow('1\u78C5', '\u2248 453.59\u514B')
              this.ConceptRow('1\u76CE\u53F8', '\u2248 28.35\u514B')
            } else if (this.category.id === 'volume') {
              this.ConceptRow('1\u7ACB\u65B9\u7C73', '= 1000\u5347')
              this.ConceptRow('1\u52A0\u4ED1', '\u2248 3.78541\u5347')
              this.ConceptRow('1\u5347', '= 10\u5206\u5347 = 1000\u6BEB\u5347')
            } else if (this.category.id === 'speed') {
              this.ConceptRow('1\u5343\u7C73/\u65F6', '\u2248 0.27778\u7C73/\u79D2')
              this.ConceptRow('1\u82F1\u91CC/\u65F6', '\u2248 1.60934\u5343\u7C73/\u65F6')
              this.ConceptRow('1\u8282', '\u2248 1.852\u5343\u7C73/\u65F6')
            } else if (this.category.id === 'time') {
              this.ConceptRow('1\u5929', '= 24\u5C0F\u65F6 = 86400\u79D2')
              this.ConceptRow('1\u5E74', '\u2248 365\u5929')
              this.ConceptRow('1\u4E16\u7EAA', '= 100\u5E74')
            } else if (this.category.id === 'pressure') {
              this.ConceptRow('1\u6807\u51C6\u5927\u6C14\u538B', '\u2248 101325\u5E15')
              this.ConceptRow('1\u5DF4', '= 100000\u5E15')
              this.ConceptRow('1\u6BEB\u7C73\u6C5E\u67F1', '\u2248 133.322\u5E15')
            } else if (this.category.id === 'energy') {
              this.ConceptRow('1\u5343\u74E6\u65F6', '= 3600\u5343\u7126')
              this.ConceptRow('1\u5361\u8DEF\u91CC', '\u2248 4.184\u7126\u8033')
              this.ConceptRow('1\u82F1\u70ED\u5355\u4F4D', '\u2248 1055.06\u7126\u8033')
            }
          }
        }
        .width('100%')
        .padding(16)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(12)
      }
      .width('100%')
      .margin({ left: 16, right: 16, top: 12, bottom: 16 })
      .scrollable(ScrollDirection.Vertical)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  ConceptRow(title: string, desc: string) {
    Row() {
      Text(title)
        .fontSize(13)
        .fontColor($r('app.color.primary_text'))
        .fontWeight(FontWeight.Medium)
        .width(110)
      Text(desc)
        .fontSize(13)
        .fontColor($r('app.color.secondary_text'))
        .layoutWeight(1)
    }
    .width('100%')
    .margin({ bottom: 4 })
  }
}
