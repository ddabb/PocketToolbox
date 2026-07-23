import { TimezoneCity, TimezoneRegion, TimezoneDataLoader } from '../model/UnitModels';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

class CitySelectItem {
  city: string = '';
  country: string = '';
  offset: number = 0;
  abbr: string = '';
  isSelected: boolean = false;

  constructor(city: string, country: string, offset: number, abbr: string, isSelected: boolean) {
    this.city = city;
    this.country = country;
    this.offset = offset;
    this.abbr = abbr;
    this.isSelected = isSelected;
  }
}

class CityTimeInfo {
  cityName: string = '';
  country: string = '';
  offset: number = 0;
  localDate: string = '';
  localTime: string = '';
  isWorkTime: boolean = false;
  isNight: boolean = false;

  constructor() {}
}

class MeetingCityInfo {
  cityName: string = '';
  localTime: string = '';
  isWorkTime: boolean = false;
  isNight: boolean = false;

  constructor() {}
}

@Builder
export function TimezoneConverterPageBuilder(param?: Object) {
  NavDestination() {
    TimezoneConverterContent()
  }
  .title('时区转换')
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
}

@Component
struct TimezoneConverterContent {
  @State activeTab: number = 0;
  @State baseDate: string = '';
  @State baseTime: string = '';
  @State baseCityName: string = '北京';
  @State selectedCities: string[] = [];
  @State favoriteCities: string[] = [];
  @State meetingCities: string[] = [];
  @State meetingDuration: number = 60;
  @State showCityPicker: boolean = false;
  @State pickerMode: string = 'add';
  @State searchKeyword: string = '';
  @State meetingSuggestion: string = '';
  @State meetingSuggestionType: number = 0;
  @State cityTimeInfos: CityTimeInfo[] = [];
  @State meetingCityInfos: MeetingCityInfo[] = [];
  private allCities: TimezoneCity[] = [];
  private regionGroups: TimezoneRegion[] = [];
  private readonly PREF_NAME: string = 'timezone_prefs';

  aboutToAppear(): void {
    let ctx: common.UIAbilityContext = AppStorage.get('AppHostContext') as common.UIAbilityContext;
    TimezoneDataLoader.load(ctx);
    this.allCities = TimezoneDataLoader.getCities();
    this.regionGroups = TimezoneDataLoader.getRegions();
    this.initTime();
    this.loadPrefs();
  }

  private initTime(): void {
    let now: Date = new Date();
    this.baseDate = this.formatDate(now);
    this.baseTime = this.formatTime(now);
  }

  private formatDate(date: Date): string {
    let y: number = date.getFullYear();
    let m: string = (date.getMonth() + 1).toString().padStart(2, '0');
    let d: string = date.getDate().toString().padStart(2, '0');
    return y.toString() + '-' + m + '-' + d;
  }

  private formatTime(date: Date): string {
    let h: string = date.getHours().toString().padStart(2, '0');
    let min: string = date.getMinutes().toString().padStart(2, '0');
    return h + ':' + min;
  }

  private loadPrefs(): void {
    try {
      let ctx: common.UIAbilityContext = AppStorage.get('AppHostContext') as common.UIAbilityContext;
      let options: preferences.Options = { name: this.PREF_NAME };
      let pref: preferences.Preferences = preferences.getPreferencesSync(ctx, options);
      let fav: preferences.ValueType = pref.getSync('favoriteCities', '["北京","东京","纽约","伦敦"]');
      let sel: preferences.ValueType = pref.getSync('selectedCities', '["东京","纽约","伦敦"]');
      this.favoriteCities = JSON.parse(fav as string) as string[];
      this.selectedCities = JSON.parse(sel as string) as string[];
    } catch (e) {
      this.favoriteCities = ['北京', '东京', '纽约', '伦敦'];
      this.selectedCities = ['东京', '纽约', '伦敦'];
    }
  }

  private savePrefs(): void {
    try {
      let ctx: common.UIAbilityContext = AppStorage.get('AppHostContext') as common.UIAbilityContext;
      let options: preferences.Options = { name: this.PREF_NAME };
      let pref: preferences.Preferences = preferences.getPreferencesSync(ctx, options);
      pref.putSync('favoriteCities', JSON.stringify(this.favoriteCities));
      pref.putSync('selectedCities', JSON.stringify(this.selectedCities));
      pref.flush();
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[Timezone] savePrefs failed: ' + err.message);
    }
  }

  private getCityByName(name: string): TimezoneCity | null {
    return TimezoneDataLoader.getCityByName(name);
  }

  private getOffsetText(offset: number): string {
    if (offset >= 0) {
      return '+' + offset.toString();
    }
    return offset.toString();
  }

  private calculateLocalTime(cityName: string): Date {
    let baseCity: TimezoneCity | null = this.getCityByName(this.baseCityName);
    let targetCity: TimezoneCity | null = this.getCityByName(cityName);
    if (baseCity === null || targetCity === null) {
      return new Date();
    }
    let baseDateTime: Date = new Date(this.baseDate + 'T' + this.baseTime + ':00');
    let offsetDiff: number = targetCity.offset - baseCity.offset;
    return new Date(baseDateTime.getTime() + offsetDiff * 60 * 60 * 1000);
  }

  private isWorkTime(date: Date): boolean {
    let h: number = date.getHours();
    return h >= 9 && h < 18;
  }

  private isNight(date: Date): boolean {
    let h: number = date.getHours();
    return h < 6 || h >= 22;
  }

  private getCityOffset(name: string): number {
    let city: TimezoneCity | null = this.getCityByName(name);
    if (city !== null) {
      return city.offset;
    }
    return 0;
  }

  private recalcCityTimeInfos(): void {
    let infos: CityTimeInfo[] = [];
    for (let i = 0; i < this.selectedCities.length; i++) {
      let cityName: string = this.selectedCities[i];
      let city: TimezoneCity | null = this.getCityByName(cityName);
      let localDate: Date = this.calculateLocalTime(cityName);
      let info: CityTimeInfo = new CityTimeInfo();
      info.cityName = cityName;
      info.country = city !== null ? city.country : '';
      info.offset = city !== null ? city.offset : 0;
      info.localDate = this.formatDate(localDate);
      info.localTime = this.formatTime(localDate);
      info.isWorkTime = this.isWorkTime(localDate);
      info.isNight = this.isNight(localDate);
      infos.push(info);
    }
    this.cityTimeInfos = infos;
  }

  private recalcMeetingCityInfos(): void {
    let infos: MeetingCityInfo[] = [];
    for (let i = 0; i < this.meetingCities.length; i++) {
      let cityName: string = this.meetingCities[i];
      let localDate: Date = this.calculateLocalTime(cityName);
      let info: MeetingCityInfo = new MeetingCityInfo();
      info.cityName = cityName;
      info.localTime = this.formatTime(localDate);
      info.isWorkTime = this.isWorkTime(localDate);
      info.isNight = this.isNight(localDate);
      infos.push(info);
    }
    this.meetingCityInfos = infos;
  }

  private calculateMeetingSuggestion(): void {
    this.recalcMeetingCityInfos();
    if (this.meetingCities.length < 2) {
      this.meetingSuggestion = '请至少添加2个城市';
      this.meetingSuggestionType = 1;
      return;
    }
    let allWork: boolean = true;
    let hasNight: boolean = false;
    for (let i = 0; i < this.meetingCityInfos.length; i++) {
      if (!this.meetingCityInfos[i].isWorkTime) {
        allWork = false;
      }
      if (this.meetingCityInfos[i].isNight) {
        hasNight = true;
      }
    }
    if (allWork) {
      this.meetingSuggestion = '所有城市都在工作时间，非常适合开会！';
      this.meetingSuggestionType = 0;
    } else if (hasNight) {
      this.meetingSuggestion = '有城市处于深夜，建议调整会议时间';
      this.meetingSuggestionType = 2;
    } else {
      this.meetingSuggestion = '部分城市处于非工作时间，请注意协调';
      this.meetingSuggestionType = 1;
    }
  }

  private openCityPicker(mode: string): void {
    this.pickerMode = mode;
    this.searchKeyword = '';
    this.showCityPicker = true;
  }

  private selectCity(cityName: string): void {
    if (this.pickerMode === 'base') {
      this.baseCityName = cityName;
      this.showCityPicker = false;
      this.recalcCityTimeInfos();
    } else if (this.pickerMode === 'add') {
      if (!this.selectedCities.includes(cityName)) {
        let newCities: string[] = [];
        for (let i = 0; i < this.selectedCities.length; i++) {
          newCities.push(this.selectedCities[i]);
        }
        newCities.push(cityName);
        this.selectedCities = newCities;
        this.savePrefs();
      }
      this.showCityPicker = false;
      this.recalcCityTimeInfos();
    } else if (this.pickerMode === 'meeting') {
      if (!this.meetingCities.includes(cityName)) {
        let newCities: string[] = [];
        for (let i = 0; i < this.meetingCities.length; i++) {
          newCities.push(this.meetingCities[i]);
        }
        newCities.push(cityName);
        this.meetingCities = newCities;
        this.calculateMeetingSuggestion();
      }
      this.showCityPicker = false;
    }
  }

  private getFilteredCitiesForRegion(region: TimezoneRegion): CitySelectItem[] {
    let result: CitySelectItem[] = [];
    let keyword: string = this.searchKeyword.toLowerCase();
    let selectedList: string[] = this.pickerMode === 'meeting' ? this.meetingCities : this.selectedCities;
    for (let i = 0; i < region.cities.length; i++) {
      let cityName: string = region.cities[i];
      let city: TimezoneCity | null = this.getCityByName(cityName);
      if (city === null) {
        continue;
      }
      if (keyword.length > 0) {
        if (city.city.toLowerCase().indexOf(keyword) < 0 &&
          city.country.toLowerCase().indexOf(keyword) < 0 &&
          city.abbr.toLowerCase().indexOf(keyword) < 0) {
          continue;
        }
      }
      let isSelected: boolean = selectedList.includes(city.city);
      result.push(new CitySelectItem(city.city, city.country, city.offset, city.abbr, isSelected));
    }
    return result;
  }

  build() {
    Stack() {
      Column() {
        this.TabBar()

        if (this.activeTab === 0) {
          this.ConverterPage()
        } else {
          this.MeetingPage()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))

      if (this.showCityPicker) {
        this.CityPickerModal()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  TabBar() {
    Row() {
      Column() {
        Text('时区转换')
          .fontSize(15)
          .fontWeight(this.activeTab === 0 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.activeTab === 0 ? $r('app.color.idiom_blue') : $r('app.color.tertiary_text'))
      }
      .layoutWeight(1)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.activeTab = 0;
      })

      Column() {
        Text('会议协调')
          .fontSize(15)
          .fontWeight(this.activeTab === 1 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.activeTab === 1 ? $r('app.color.idiom_blue') : $r('app.color.tertiary_text'))
      }
      .layoutWeight(1)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.activeTab = 1;
        this.calculateMeetingSuggestion();
      })
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .margin({ left: 16, right: 16, top: 8 })
  }

  @Builder
  ConverterPage() {
    Scroll() {
      Column() {
        this.BaseTimeCard()

        Text('转换结果')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .width('100%')
          .margin({ left: 16, top: 16, bottom: 8 })

        ForEach(this.cityTimeInfos, (info: CityTimeInfo) => {
          Row() {
            Column() {
              Text((info.isNight ? '\uD83C\uDF19' : info.isWorkTime ? '\u2600\uFE0F' : '\uD83C\uDF06') + ' ' + info.cityName)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))
              Text(info.country + ' UTC' + this.getOffsetText(info.offset))
                .fontSize(12)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Column() {
              Text(info.localTime)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))
              Text(info.localDate)
                .fontSize(12)
                .fontColor($r('app.color.tertiary_text'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.End)

            Column() {
              Text(info.isWorkTime ? '工作时间' : '非工作时间')
                .fontSize(11)
                .fontColor(info.isWorkTime ? '#27ae60' : '#e67e22')
                .backgroundColor((info.isWorkTime ? '#27ae60' : '#e67e22') + '18')
                .borderRadius(8)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            }
            .margin({ left: 8 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor(info.isNight ? '#2c3e50' : info.isWorkTime ? '#f0f7f0' : '#fdf2e9')
          .borderRadius(10)
          .margin({ left: 16, right: 16, top: 6 })
          .alignItems(VerticalAlign.Center)
        }, (info: CityTimeInfo) => info.cityName)

        Row() {
          Button('添加城市')
            .fontSize(14)
            .fontColor($r('app.color.idiom_blue'))
            .backgroundColor($r('app.color.idiom_blue') + '12')
            .borderRadius(20)
            .height(36)
            .onClick(() => {
              this.openCityPicker('add');
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 8, bottom: 16 })

        this.FavoritesSection()
      }
      .width('100%')
      .padding({ bottom: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollable(ScrollDirection.Vertical)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  BaseTimeCard() {
    Column() {
      Row() {
        Text('基准城市')
          .fontSize(13)
          .fontColor($r('app.color.tertiary_text'))
        Blank()
        Text(this.baseCityName + ' UTC' + this.getOffsetText(this.getCityOffset(this.baseCityName)))
          .fontSize(13)
          .fontColor($r('app.color.idiom_blue'))
          .onClick(() => {
            this.openCityPicker('base');
          })
      }
      .width('100%')
      .margin({ bottom: 8 })

      Row() {
        Column() {
          DatePicker({
            start: new Date('2020-01-01'),
            end: new Date('2030-12-31'),
            selected: new Date(this.baseDate + 'T00:00:00')
          })
            .onChange((value: DatePickerResult) => {
              let y: string = (value.year ?? 2024).toString();
              let m: string = ((value.month ?? 0) + 1).toString().padStart(2, '0');
              let d: string = (value.day ?? 1).toString().padStart(2, '0');
              this.baseDate = y + '-' + m + '-' + d;
              this.recalcCityTimeInfos();
            })
        }
        .layoutWeight(1)

        Column() {
          TimePicker({
            selected: new Date('2024-01-01T' + this.baseTime + ':00')
          })
            .onChange((value: TimePickerResult) => {
              let h: string = (value.hour ?? 0).toString().padStart(2, '0');
              let m: string = (value.minute ?? 0).toString().padStart(2, '0');
              this.baseTime = h + ':' + m;
              this.recalcCityTimeInfos();
            })
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .margin({ left: 16, right: 16, top: 8 })
  }

  @Builder
  FavoritesSection() {
    Column() {
      Text('\u2B50 收藏城市')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .margin({ bottom: 8 })

      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(this.favoriteCities, (cityName: string) => {
          Text(cityName)
            .fontSize(13)
            .fontColor($r('app.color.idiom_blue'))
            .backgroundColor($r('app.color.idiom_blue') + '12')
            .borderRadius(8)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .margin({ right: 6, bottom: 6 })
            .onClick(() => {
              if (!this.selectedCities.includes(cityName)) {
                let newCities: string[] = [];
                for (let i = 0; i < this.selectedCities.length; i++) {
                  newCities.push(this.selectedCities[i]);
                }
                newCities.push(cityName);
                this.selectedCities = newCities;
                this.savePrefs();
                this.recalcCityTimeInfos();
              }
            })
        }, (cityName: string) => cityName)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .margin({ left: 16, right: 16 })
  }

  @Builder
  MeetingPage() {
    Scroll() {
      Column() {
        Text('会议时长')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .width('100%')
          .margin({ left: 16, top: 12 })

        Row({ space: 8 }) {
          this.DurationButton(30, '30分钟')
          this.DurationButton(60, '1小时')
          this.DurationButton(90, '1.5小时')
          this.DurationButton(120, '2小时')
        }
        .margin({ left: 16, right: 16, top: 8 })

        Text('参与城市')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary_text'))
          .width('100%')
          .margin({ left: 16, top: 16, bottom: 8 })

        ForEach(this.meetingCities, (cityName: string) => {
          Row() {
            Text(cityName)
              .fontSize(14)
              .fontColor($r('app.color.primary_text'))
              .layoutWeight(1)
            Text('\u00D7')
              .fontSize(16)
              .fontColor($r('app.color.tertiary_text'))
              .onClick(() => {
                let newCities: string[] = [];
                for (let i = 0; i < this.meetingCities.length; i++) {
                  if (this.meetingCities[i] !== cityName) {
                    newCities.push(this.meetingCities[i]);
                  }
                }
                this.meetingCities = newCities;
                this.calculateMeetingSuggestion();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(8)
          .margin({ left: 16, right: 16, top: 4 })
        }, (cityName: string) => cityName)

        Row() {
          Button('添加城市')
            .fontSize(14)
            .fontColor($r('app.color.idiom_blue'))
            .backgroundColor($r('app.color.idiom_blue') + '12')
            .borderRadius(20)
            .height(36)
            .onClick(() => {
              this.openCityPicker('meeting');
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 8 })

        if (this.meetingCities.length >= 2) {
          this.MeetingAnalysis()
        } else {
          Text('请至少添加2个城市')
            .fontSize(13)
            .fontColor($r('app.color.tertiary_text'))
            .margin({ top: 16 })
        }
      }
      .width('100%')
      .padding({ bottom: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollable(ScrollDirection.Vertical)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  DurationButton(value: number, label: string) {
    Button(label)
      .fontSize(13)
      .fontColor(this.meetingDuration === value ? Color.White : $r('app.color.primary_text'))
      .backgroundColor(this.meetingDuration === value ? $r('app.color.idiom_blue') : $r('app.color.card_background'))
      .borderRadius(8)
      .height(32)
      .layoutWeight(1)
      .onClick(() => {
        this.meetingDuration = value;
        this.calculateMeetingSuggestion();
      })
  }

  @Builder
  MeetingAnalysis() {
    Column() {
      Text('时间分析')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .width('100%')
        .margin({ bottom: 8 })

      ForEach(this.meetingCityInfos, (info: MeetingCityInfo) => {
        Row() {
          Text(info.isWorkTime ? '\u2705' : '\u26A0\uFE0F')
            .fontSize(16)
            .margin({ right: 8 })
          Text(info.cityName)
            .fontSize(14)
            .fontColor($r('app.color.primary_text'))
            .layoutWeight(1)
          Text(info.localTime)
            .fontSize(14)
            .fontColor($r('app.color.primary_text'))
            .margin({ right: 8 })
          Text(info.isWorkTime ? '工作时间' : '加班时间')
            .fontSize(11)
            .fontColor(info.isWorkTime ? '#27ae60' : '#e67e22')
            .backgroundColor((info.isWorkTime ? '#27ae60' : '#e67e22') + '18')
            .borderRadius(6)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        }
        .width('100%')
        .margin({ bottom: 6 })
      }, (info: MeetingCityInfo) => info.cityName)

      Row() {
        Text(this.meetingSuggestion)
          .fontSize(13)
          .fontColor(this.meetingSuggestionType === 0 ? '#27ae60' :
            this.meetingSuggestionType === 2 ? '#e74c3c' : '#e67e22')
      }
      .width('100%')
      .padding(12)
      .backgroundColor(this.meetingSuggestionType === 0 ? '#f0f7f0' :
        this.meetingSuggestionType === 2 ? '#fde8e8' : '#fdf2e9')
      .borderRadius(8)
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .margin({ left: 16, right: 16, top: 12 })
  }

  @Builder
  CityPickerModal() {
    Column() {
      Column() {
        Row() {
          Text('选择城市')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.primary_text'))
          Blank()
          Text('\u2715')
            .fontSize(20)
            .fontColor($r('app.color.tertiary_text'))
            .onClick(() => {
              this.showCityPicker = false;
            })
        }
        .width('100%')
        .margin({ bottom: 12 })

        TextInput({ placeholder: '搜索城市', text: this.searchKeyword })
          .width('100%')
          .height(40)
          .fontSize(14)
          .backgroundColor($r('app.color.page_background'))
          .borderRadius(8)
          .padding({ left: 12 })
          .onChange((value: string) => {
            this.searchKeyword = value;
          })

        Scroll() {
          Column() {
            if (this.searchKeyword.length === 0) {
              Text('\u2B50 收藏城市')
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))
                .width('100%')
                .margin({ top: 12, bottom: 8 })

              Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
                ForEach(this.favoriteCities, (name: string) => {
                  Text(name)
                    .fontSize(13)
                    .fontColor($r('app.color.idiom_blue'))
                    .backgroundColor($r('app.color.idiom_blue') + '12')
                    .borderRadius(8)
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .margin({ right: 6, bottom: 6 })
                    .onClick(() => {
                      this.selectCity(name);
                    })
                }, (name: string) => name)
              }
            }

            ForEach(this.regionGroups, (region: TimezoneRegion) => {
              Column() {
                Text(region.name)
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.primary_text'))
                  .width('100%')
                  .margin({ top: 12, bottom: 8 })

                ForEach(this.getFilteredCitiesForRegion(region), (item: CitySelectItem) => {
                  Row() {
                    Text(item.city)
                      .fontSize(14)
                      .fontColor($r('app.color.primary_text'))
                      .layoutWeight(1)
                    Text(item.country + ' UTC' + this.getOffsetText(item.offset))
                      .fontSize(12)
                      .fontColor($r('app.color.tertiary_text'))
                      .margin({ right: 8 })
                    if (item.isSelected) {
                      Text('\u2713')
                        .fontSize(14)
                        .fontColor($r('app.color.idiom_blue'))
                    }
                  }
                  .width('100%')
                  .padding({ top: 10, bottom: 10 })
                  .onClick(() => {
                    this.selectCity(item.city);
                  })
                }, (item: CitySelectItem) => item.city)
              }
            }, (region: TimezoneRegion) => region.name)
          }
        }
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      }
      .width('100%')
      .height('70%')
      .padding(16)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius({ topLeft: 16, topRight: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#99000000')
    .onClick(() => {
      this.showCityPicker = false;
    })
  }
}
