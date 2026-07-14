import { PoetDetail, PoemItem } from '../model/PoetryModels';
import { PoetryViewModel } from '../viewmodel/PoetryViewModel';

function buildPoetDetail(param: Object): PoetDetail {
  return PoetryViewModel.getInstance().parsePoetDetailFromParam(param as Record<string, Object>);
}

@Builder
export function PoetryDetailPageBuilder(param: Object) {
  NavDestination() {
    PoetryDetailContent({ poetParam: buildPoetDetail(param) })
  }
  .title((param as Record<string, Object>)['name'] as string || '诗人详情')
  .hideTitleBar(false)
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
export struct PoetryDetailContent {
  @Prop poetParam: PoetDetail = new PoetDetail();
  @State searchText: string = '';
  @State displayPoems: PoemItem[] = [];
  navPathStack: NavPathStack = AppStorage.get('AppNavPathStack') as NavPathStack;

  aboutToAppear(): void {
    this.displayPoems = this.poetParam.poems;
    console.info('[PoetryDetail] poet=' + this.poetParam.name + ', dynasty=' + this.poetParam.dynasty +
      ', poems=' + this.poetParam.poems.length.toString());
  }

  private filterPoems(query: string): void {
    if (!query) {
      this.displayPoems = this.poetParam.poems;
      console.info('[PoetryDetail] filter cleared, total=' + this.displayPoems.length.toString());
      return;
    }
    let filtered: PoemItem[] = [];
    for (let i: number = 0; i < this.poetParam.poems.length; i++) {
      let poem: PoemItem = this.poetParam.poems[i];
      if (poem.n.indexOf(query) >= 0 || poem.c.indexOf(query) >= 0) {
        filtered.push(poem);
      }
    }
    this.displayPoems = filtered;
    console.info('[PoetryDetail] filter query=' + query + ', results=' + filtered.length.toString());
  }

  private onPoemTap(poem: PoemItem): void {
    console.info('[PoetryDetail] tap poem=' + poem.n);
    this.navPathStack.pushPathByName('PoemContentPage', poem);
  }

  build() {
    Column() {
      this.PoetHeader()
      this.SearchBar()
      this.PoemList()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  PoetHeader() {
    Column() {
      Text(this.poetParam.name)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.poetry_green'))
      Text(this.poetParam.dynasty)
        .fontSize(14)
        .fontColor($r('app.color.tertiary_text'))
        .margin({ top: 4 })
      if (this.poetParam.desc) {
        Text(this.poetParam.desc)
          .fontSize(13)
          .fontColor($r('app.color.secondary_text'))
          .lineHeight(22)
          .margin({ top: 8 })
          .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.card_background'))
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  SearchBar() {
    Row() {
      TextInput({ placeholder: '搜索诗名...', text: this.searchText })
        .layoutWeight(1)
        .height(36)
        .fontSize(13)
        .fontColor($r('app.color.primary_text'))
        .placeholderColor($r('app.color.hint_text'))
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(18)
        .padding({ left: 16, right: 28 })
        .onChange((value: string) => {
          this.searchText = value;
          this.filterPoems(value);
        })
        .onSubmit(() => {
          this.filterPoems(this.searchText);
        })

      if (this.searchText) {
        Text('\u2715')
          .fontSize(14)
          .fontColor($r('app.color.tertiary_text'))
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .margin({ left: -32 })
          .onClick(() => {
            this.searchText = '';
            this.displayPoems = this.poetParam.poems;
          })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
  }

  @Builder
  PoemList() {
    Column() {
      Row() {
        Text(this.searchText ? '搜索结果' : '作品')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
        Text('(' + this.displayPoems.length.toString() + ')')
          .fontSize(13)
          .fontColor($r('app.color.tertiary_text'))
          .margin({ left: 4 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 6 })
    }

    List({ space: 6 }) {
      if (this.displayPoems.length === 0) {
        ListItem() {
          Text('未找到相关诗词')
            .fontSize(15)
            .fontColor($r('app.color.tertiary_text'))
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 30 })
        }
      }

      ForEach(this.displayPoems, (poem: PoemItem, index: number) => {
        ListItem() {
          Row() {
            Column() {
              Text(poem.n)
                .fontSize(14)
                .fontColor($r('app.color.primary_text'))
                .fontWeight(FontWeight.Medium)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (poem.f) {
                Text(poem.f)
                  .fontSize(11)
                  .fontColor($r('app.color.tertiary_text'))
                  .margin({ top: 2 })
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text('\u203A')
              .fontSize(20)
              .fontColor($r('app.color.hint_text'))
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(10)
          .onClick(() => {
            this.onPoemTap(poem);
          })
        }
      }, (poem: PoemItem, index: number) => poem.n + '_' + index.toString())
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 10, right: 10, top: 2, bottom: 6 })
  }
}
