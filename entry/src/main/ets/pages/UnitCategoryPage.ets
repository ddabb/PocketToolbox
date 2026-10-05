import { ConverterCategory, UnitConverterData } from '../model/UnitModels';
import { StrUtil } from '../common/utils/StrUtil';

@Builder
export function UnitCategoryPageBuilder(param?: Object) {
  NavDestination() {
    UnitCategoryContent()
  }
  .title($r('app.string.unitcat_title'))
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
  .backgroundColor($r('app.color.page_background'))
}

@Component
struct UnitCategoryContent {
  private getNavPathStack(): NavPathStack {
    return AppStorage.get('AppNavPathStack') as NavPathStack;
  }
  private uiContext: UIContext = this.getUIContext();
  @State categories: ConverterCategory[] = UnitConverterData.getCategories();

  build() {
    Scroll() {
      Column() {
        ForEach(this.categories, (cat: ConverterCategory) => {
          Row() {
            Column() {
              Image($r('app.media.' + cat.icon))
                .width(48)
                .height(48)
                .borderRadius(14)
            }
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
    .constraintSize({ maxWidth: 720 })
    .scrollable(ScrollDirection.Vertical)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  private getSubtitle(cat: ConverterCategory): ResourceStr {
    if (cat.isBase) {
      return $r('app.string.unitcat_base_sub');
    }
    if (cat.isTimezone) {
      return $r('app.string.tool_timezone_sub');
    }
    if (cat.isTemperature) {
      return $r('app.string.unit_temp_subtitle');
    }
    let names: string[] = [];
    let count: number = Math.min(cat.units.length, 4);
    for (let i = 0; i < count; i++) {
      names.push(cat.units[i].name);
    }
    let suffix: string = cat.units.length > 4
      ? StrUtil.text(this.uiContext.getHostContext() as Context, $r('app.string.unitcat_units_more', cat.units.length))
      : '';
    return names.join('、') + suffix;
  }

  private navigateToCategory(cat: ConverterCategory): void {
    let stack: NavPathStack = this.getNavPathStack();
    if (!stack) {
      return;
    }
    if (cat.isBase) {
      stack.pushPathByName('BaseConverterPage', null);
    } else if (cat.isTimezone) {
      stack.pushPathByName('TimezoneConverterPage', null);
    } else {
      let param: Record<string, Object> = {
        'categoryId': cat.id as Object,
        'title': cat.title as Object
      };
      stack.pushPathByName('UnitConverterPage', param);
    }
  }
}
