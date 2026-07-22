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
        TextInput({ text: $$this.item.value, placeholder: '输入数值' })
          .type(InputType.Number)
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
    if (this.focusedIndex >= 0 && changedIndex !== this.focusedIndex) {
      return;
    }
    this.activeUnitIndex = changedIndex;

    if (!value || value.length === 0) {
      for (let i = 0; i < this.unitValues.length; i++) {
        this.unitValues[i].value = '';
      }
      return;
    }

    let inputValue: number = parseFloat(value);
    if (isNaN(inputValue)) {
      return;
    }

    this.unitValues[changedIndex].value = value;

    if (this.isTemperature) {
      let baseValue: number = UnitConverterData.temperatureToBase(inputValue, this.unitValues[changedIndex].name);
      for (let i = 0; i < this.unitValues.length; i++) {
        if (i !== changedIndex) {
          let result: number = UnitConverterData.temperatureFromBase(baseValue, this.unitValues[i].name);
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
  }

  build() {
    Column() {
      List({ space: 0 }) {
        ForEach(this.unitValues, (item: UnitValueItem, index: number) => {
          ListItem() {
            Column() {
              UnitValueRow({
                item: item,
                isActive: this.activeUnitIndex === index,
                onValueChange: (value: string) => {
                  this.onValueChange(index, value);
                },
                onItemFocus: () => {
                  this.focusedIndex = index;
                }
              })
              if (index < this.unitValues.length - 1) {
                Divider()
                  .color($r('app.color.border_color'))
                  .margin({ left: 16, right: 16 })
              }
            }
            .width('100%')
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
          Text('常用参考')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
            .width('100%')
            .margin({ bottom: 8 })

          if (this.isTemperature) {
            this.ConceptRow('摄氏度', '冰点0\u00B0C，沸点100\u00B0C')
            this.ConceptRow('华氏度', '冰点32\u00B0F，沸点212\u00B0F')
            this.ConceptRow('开尔文', '绝对零度0K = -273.15\u00B0C')
          } else if (this.category !== null) {
            if (this.category.id === 'length') {
              this.ConceptRow('1千米', '= 0.621371英里')
              this.ConceptRow('1米', '= 3.28084英尺')
              this.ConceptRow('1寸', '\u2248 3.33厘米')
              this.ConceptRow('1海里', '= 1.852千米')
            } else if (this.category.id === 'area') {
              this.ConceptRow('1公顷', '= 10000平方米')
              this.ConceptRow('1亩', '\u2248 666.67平方米')
              this.ConceptRow('1英亩', '\u2248 4046.86平方米')
            } else if (this.category.id === 'weight') {
              this.ConceptRow('1千克', '\u2248 2.20462磅')
              this.ConceptRow('1磅', '\u2248 453.59克')
              this.ConceptRow('1盎司', '\u2248 28.35克')
            } else if (this.category.id === 'volume') {
              this.ConceptRow('1立方米', '= 1000升')
              this.ConceptRow('1加仑', '\u2248 3.78541升')
              this.ConceptRow('1升', '= 10分升 = 1000毫升')
            } else if (this.category.id === 'speed') {
              this.ConceptRow('1千米/时', '\u2248 0.27778米/秒')
              this.ConceptRow('1英里/时', '\u2248 1.60934千米/时')
              this.ConceptRow('1节', '\u2248 1.852千米/时')
            } else if (this.category.id === 'time') {
              this.ConceptRow('1天', '= 24小时 = 86400秒')
              this.ConceptRow('1年', '\u2248 365天')
              this.ConceptRow('1世纪', '= 100年')
            } else if (this.category.id === 'pressure') {
              this.ConceptRow('1标准大气压', '\u2248 101325帕')
              this.ConceptRow('1巴', '= 100000帕')
              this.ConceptRow('1毫米汞柱', '\u2248 133.322帕')
            } else if (this.category.id === 'energy') {
              this.ConceptRow('1千瓦时', '= 3600千焦')
              this.ConceptRow('1卡路里', '\u2248 4.184焦耳')
              this.ConceptRow('1英热单位', '\u2248 1055.06焦耳')
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
