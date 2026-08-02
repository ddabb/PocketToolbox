import { TimezoneCity, TimezoneRegion, TimezoneDataLoader } from '../model/UnitModels';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { Context, common } from '@kit.AbilityKit';

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
  @State pendingBaseCityName: string = '';
  @State meetingSuggestion: string = '';
  @State meetingSuggestionType: number = 0;
  @State cityTimeInfos: CityTimeInfo[] = [];
  @State meetingCityInfos: MeetingCityInfo[] = [];
  @State calcVersion: number = 0;
  private allCities: TimezoneCity[] = [];
  private regionGroups: TimezoneRegion[] = [];
  private uiContext: UIContext = this.getUIContext();
  private readonly PREF_NAME: string = 'timezone_prefs';

  aboutToAppear(): void {
    this.initTime();
    this.loadPrefs();
    setTimeout(() => {
      this.loadTimezoneData();
    }, 0);
  }

  private loadTimezoneData(): void {
    let ctx: Context = this.uiContext.getHostContext() as Context;
    let ok: boolean = false;
    if (ctx !== null && ctx !== undefined) {
      ok = TimezoneDataLoader.load(ctx);
    }
    if (!ok) {
      let appCtx: common.UIAbilityContext | undefined = AppStorage.get('AppHostContext') as common.UIAbilityContext;
      if (appCtx !== null && appCtx !== undefined) {
        ok = TimezoneDataLoader.reload(appCtx);
      }
    }
    this.allCities = TimezoneDataLoader.getCities();
    this.regionGroups = TimezoneDataLoader.getRegions();
    this.initTime();
    this.recalcCityTimeInfos();
  }

  private initTime(): void {
    let now: Date = new Date();
    let baseCity: TimezoneCity | null = this.getCityByName(this.baseCityName);
    let offset: number = 8;
    if (baseCity !== null) {
      offset = this.getEffectiveOffset(baseCity, now);
    }
    let baseCityTime: Date = new Date(now.getTime() + offset * 60 * 60 * 1000);
    this.baseDate = this.formatDate(baseCityTime);
    this.baseTime = this.formatTime(baseCityTime);
  }

  private formatDate(date: Date): string {
    let y: number = date.getUTCFullYear();
    let m: string = (date.getUTCMonth() + 1).toString().padStart(2, '0');
    let d: string = date.getUTCDate().toString().padStart(2, '0');
    return y.toString() + '-' + m + '-' + d;
  }

  private formatTime(date: Date): string {
    let h: string = date.getUTCHours().toString().padStart(2, '0');
    let min: string = date.getUTCMinutes().toString().padStart(2, '0');
    return h + ':' + min;
  }

  private loadPrefs(): void {
    try {
      let ctx: Context = this.uiContext.getHostContext() as Context;
      if (ctx === null || ctx === undefined) {
        ctx = AppStorage.get('AppHostContext') as common.UIAbilityContext;
      }
      let options: preferences.Options = { name: this.PREF_NAME };
      let pref: preferences.Preferences = preferences.getPreferencesSync(ctx, options);
      let fav: preferences.ValueType = pref.getSync('favoriteCities', '["北京","东京","纽约","伦敦"]');
      let sel: preferences.ValueType = pref.getSync('selectedCities', '["东京","纽约","伦敦"]');
      this.favoriteCities = JSON.parse(fav as string) as string[];
      this.selectedCities = JSON.parse(sel as string) as string[];
    } catch (e) {
      let errMsg: string = '';
      if (e instanceof Error) {
        errMsg = e.message;
      }
      console.error('[Timezone] loadPrefs fallback to defaults, err=' + errMsg);
      this.favoriteCities = ['北京', '东京', '纽约', '伦敦'];
      this.selectedCities = ['东京', '纽约', '伦敦'];
    }
  }

  private savePrefs(): void {
    try {
      let ctx: Context = this.uiContext.getHostContext() as Context;
      if (ctx === null || ctx === undefined) {
        ctx = AppStorage.get('AppHostContext') as common.UIAbilityContext;
      }
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
    let parts: string[] = this.baseDate.split('-');
    let y: number = parseInt(parts[0]);
    let m: number = parseInt(parts[1]) - 1;
    let d: number = parseInt(parts[2]);
    let timeParts: string[] = this.baseTime.split(':');
    let h: number = parseInt(timeParts[0]);
    let min: number = parseInt(timeParts[1]);
    let baseLocalMs: number = Date.UTC(y, m, d, h, min, 0);
    let baseDateObj: Date = new Date(baseLocalMs);
    let baseOffset: number = this.getEffectiveOffset(baseCity, baseDateObj);
    let utcMs: number = baseLocalMs - baseOffset * 60 * 60 * 1000;
    let targetOffset: number = this.getEffectiveOffset(targetCity, new Date(utcMs));
    let targetLocalMs: number = utcMs + targetOffset * 60 * 60 * 1000;
    return new Date(targetLocalMs);
  }

  private isWorkTime(date: Date): boolean {
    let h: number = date.getUTCHours();
    return h >= 9 && h < 18;
  }

  private isNight(date: Date): boolean {
    let h: number = date.getUTCHours();
    return h < 6 || h >= 22;
  }

  private getBaseDateObj(): Date {
    let parts: string[] = this.baseDate.split('-');
    return new Date(Date.UTC(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2])));
  }

  private getNthWeekdayOfMonth(year: number, month: number, weekday: number, n: number): number {
    let firstDay: Date = new Date(Date.UTC(year, month, 1));
    let firstWeekday: number = firstDay.getUTCDay();
    let offset: number = (weekday - firstWeekday + 7) % 7;
    return 1 + offset + (n - 1) * 7;
  }

  private getLastWeekdayOfMonth(year: number, month: number, weekday: number): number {
    let lastDay: Date = new Date(Date.UTC(year, month + 1, 0));
    let lastWeekday: number = lastDay.getUTCDay();
    return lastDay.getUTCDate() - ((lastWeekday - weekday + 7) % 7);
  }

  private isDst(zone: string, date: Date): boolean {
    let year: number = date.getUTCFullYear();
    let month: number = date.getUTCMonth();
    let day: number = date.getUTCDate();
    if (zone.startsWith('America/')) {
      let dstStart: number = this.getNthWeekdayOfMonth(year, 2, 0, 2);
      let dstEnd: number = this.getNthWeekdayOfMonth(year, 10, 0, 1);
      let afterStart: boolean = month > 2 || (month === 2 && day >= dstStart);
      let beforeEnd: boolean = month < 10 || (month === 10 && day < dstEnd);
      return afterStart && beforeEnd;
    }
    if (zone.startsWith('Europe/')) {
      let dstStart: number = this.getLastWeekdayOfMonth(year, 2, 0);
      let dstEnd: number = this.getLastWeekdayOfMonth(year, 9, 0);
      let afterStart: boolean = month > 2 || (month === 2 && day >= dstStart);
      let beforeEnd: boolean = month < 9 || (month === 9 && day < dstEnd);
      return afterStart && beforeEnd;
    }
    return false;
  }

  private getEffectiveOffset(city: TimezoneCity, date: Date): number {
    if (this.isDst(city.zone, date)) {
      return city.offset + 1;
    }
    return city.offset;
  }

  private getCityEffectiveOffset(name: string): number {
    let city: TimezoneCity | null = this.getCityByName(name);
    if (city !== null) {
      return this.getEffectiveOffset(city, this.getBaseDateObj());
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
      info.offset = city !== null ? this.getCityEffectiveOffset(cityName) : 0;
      info.localDate = this.formatDate(localDate);
      info.localTime = this.formatTime(localDate);
      info.isWorkTime = this.isWorkTime(localDate);
      info.isNight = this.isNight(localDate);
      infos.push(info);
    }
    this.cityTimeInfos = infos;
    this.calcVersion++;
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
    if (mode === 'base') {
      this.pendingBaseCityName = this.baseCityName;
    }
    this.showCityPicker = true;
  }

  private confirmBaseCity(): void {
    if (this.pendingBaseCityName.length === 0 || this.pendingBaseCityName === this.baseCityName) {
      this.showCityPicker = false;
      return;
    }
    this.baseCityName = this.pendingBaseCityName;
    this.showCityPicker = false;
    this.recalcCityTimeInfos();
  }

  private selectCity(cityName: string): void {
    if (this.pickerMode === 'base') {
      this.pendingBaseCityName = cityName;
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

  private removeSelectedCity(cityName: string): void {
    let newCities: string[] = [];
    for (let i = 0; i < this.selectedCities.length; i++) {
      if (this.selectedCities[i] !== cityName) {
        newCities.push(this.selectedCities[i]);
      }
    }
    this.selectedCities = newCities;
    this.savePrefs();
    this.recalcCityTimeInfos();
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
      let isSelected: boolean = this.pickerMode === 'base' ?
        city.city === this.pendingBaseCityName : selectedList.includes(city.city);
      result.push(new CitySelectItem(city.city, city.country, this.getCityEffectiveOffset(city.city), city.abbr, isSelected));
    }
    return result;
  }

  private onDateChange(value: DatePickerResult): void {
    let y: string = (value.year ?? 2024).toString();
    let m: string = ((value.month ?? 0) + 1).toString().padStart(2, '0');
    let d: string = (value.day ?? 1).toString().padStart(2, '0');
    this.baseDate = y + '-' + m + '-' + d;
    this.recalcCityTimeInfos();
  }

  private onTimeChange(value: TimePickerResult): void {
    let h: string = (value.hour ?? 0).toString().padStart(2, '0');
    let m: string = (value.minute ?? 0).toString().padStart(2, '0');
    this.baseTime = h + ':' + m;
    this.recalcCityTimeInfos();
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

            Text('\u00D7')
              .fontSize(18)
              .fontColor($r('app.color.hint_text'))
              .margin({ left: 8 })
              .onClick(() => {
                this.removeSelectedCity(info.cityName);
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor(info.isNight ? '#2c3e50' : info.isWorkTime ? '#f0f7f0' : '#fdf2e9')
          .borderRadius(10)
          .margin({ left: 16, right: 16, top: 6 })
          .alignItems(VerticalAlign.Center)
        }, (info: CityTimeInfo) => info.cityName + '_' + this.calcVersion.toString())

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
        Text(this.baseCityName + ' UTC' + this.getOffsetText(this.getCityEffectiveOffset(this.baseCityName)))
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
              this.onDateChange(value);
            })
        }
        .layoutWeight(1)

        Column() {
          TimePicker({
            selected: new Date('2024-01-01T' + this.baseTime + ':00')
          })
            .onChange((value: TimePickerResult) => {
              this.onTimeChange(value);
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
          Text(cityName + ' UTC' + this.getOffsetText(this.getCityEffectiveOffset(cityName)))
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
        }, (cityName: string) => cityName + '_' + this.baseDate)
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
                  Text(name + ' UTC' + this.getOffsetText(this.getCityEffectiveOffset(name)))
                    .fontSize(13)
                    .fontColor(this.pickerMode === 'base' && this.pendingBaseCityName === name ?
                      Color.White : $r('app.color.idiom_blue'))
                    .backgroundColor(this.pickerMode === 'base' && this.pendingBaseCityName === name ?
                      $r('app.color.idiom_blue') : $r('app.color.idiom_blue') + '12')
                    .borderRadius(8)
                    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                    .margin({ right: 6, bottom: 6 })
                    .onClick(() => {
                      this.selectCity(name);
                    })
                }, (name: string) => name + '_' + this.baseDate + '_' + (this.pickerMode === 'base' && this.pendingBaseCityName === name ? '1' : '0'))
              }
            }

            if (this.regionGroups.length === 0) {
              Column() {
                Text('\u26A0\uFE0F 城市数据加载失败')
                  .fontSize(14)
                  .fontColor('#e74c3c')
                  .margin({ top: 24, bottom: 8 })
                Text('请尝试重新进入页面或重启应用')
                  .fontSize(12)
                  .fontColor($r('app.color.tertiary_text'))
              }
              .width('100%')
              .margin({ top: 16 })
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
                      .fontColor(item.isSelected ? $r('app.color.idiom_blue') : $r('app.color.primary_text'))
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
                  .backgroundColor(item.isSelected && this.pickerMode === 'base' ? $r('app.color.idiom_blue') + '12' : Color.Transparent)
                  .borderRadius(8)
                  .onClick(() => {
                    this.selectCity(item.city);
                  })
                }, (item: CitySelectItem) => item.city + '_' + this.baseDate + '_' + (item.isSelected ? '1' : '0'))
              }
            }, (region: TimezoneRegion) => region.name)
          }
        }
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

        if (this.pickerMode === 'base') {
          Row() {
            Button('取消')
              .fontSize(14)
              .fontColor($r('app.color.tertiary_text'))
              .backgroundColor($r('app.color.page_background'))
              .borderRadius(20)
              .height(40)
              .layoutWeight(1)
              .onClick(() => {
                this.showCityPicker = false;
              })
            Button('确定')
              .fontSize(14)
              .fontColor(Color.White)
              .backgroundColor($r('app.color.idiom_blue'))
              .borderRadius(20)
              .height(40)
              .layoutWeight(1)
              .onClick(() => {
                this.confirmBaseCity();
              })
          }
          .width('100%')
          .margin({ top: 12 })
        }
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
