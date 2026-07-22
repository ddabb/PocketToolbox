import { ConverterCategory, UnitConverterData } from '../model/UnitModels';

@Builder
export function UnitCategoryPageBuilder(param?: Object) {
  NavDestination() {
    UnitCategoryContent()
  }
  .title('单位转换')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct UnitCategoryContent {
  navPathStack: NavPathStack = AppStorage.get('AppNavPathStack') as NavPathStack;
  @State categories: ConverterCategory[] = UnitConverterData.getCategories();

  build() {
    Scroll() {
      Column() {
        ForEach(this.categories, (cat: ConverterCategory) => {
          Row() {
            Column() {
              Text(cat.icon)
                .fontSize(28)
            }
            .width(48)
            .height(48)
            .borderRadius(14)
            .backgroundColor(cat.color + '18')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .margin({ right: 12 })

            Column() {
              Text(cat.title)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))
              Text(this.getSubtitle(cat))
                .fontSize(12)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)

            Text('\u203A')
              .fontSize(18)
              .fontColor($r('app.color.hint_text'))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(12)
          .margin({ bottom: 8 })
          .onClick(() => {
            this.navigateToCategory(cat);
          })
        }, (cat: ConverterCategory) => cat.id)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .scrollable(ScrollDirection.Vertical)
  }

  private getSubtitle(cat: ConverterCategory): string {
    if (cat.isBase) {
      return '二进制、八进制、十六进制、Base64';
    }
    if (cat.isTimezone) {
      return '全球城市时区对照与会议协调';
    }
    if (cat.isTemperature) {
      return '摄氏度、华氏度、开尔文等';
    }
    let names: string[] = [];
    let count: number = Math.min(cat.units.length, 4);
    for (let i = 0; i < count; i++) {
      names.push(cat.units[i].name);
    }
    let suffix: string = cat.units.length > 4 ? '等' + cat.units.length.toString() + '个单位' : '';
    return names.join('、') + suffix;
  }

  private navigateToCategory(cat: ConverterCategory): void {
    if (cat.isBase) {
      this.navPathStack.pushPathByName('BaseConverterPage', null);
    } else if (cat.isTimezone) {
      this.navPathStack.pushPathByName('TimezoneConverterPage', null);
    } else {
      let param: Record<string, Object> = {
        'categoryId': cat.id as Object,
        'title': cat.title as Object
      };
      this.navPathStack.pushPathByName('UnitConverterPage', param);
    }
  }
}
