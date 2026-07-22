import { Context } from '@kit.AbilityKit';
import { RawFileUtil } from '../common/utils/RawFileUtil';

export class UnitItem {
  name: string = '';
  toBase: number = 0;
  fromBase: number = 0;

  constructor(name: string, toBase: number, fromBase: number) {
    this.name = name;
    this.toBase = toBase;
    this.fromBase = fromBase;
  }
}

export class ConverterCategory {
  id: string = '';
  title: string = '';
  icon: string = '';
  color: string = '';
  units: UnitItem[] = [];
  isTemperature: boolean = false;
  isBase: boolean = false;
  isTimezone: boolean = false;

  constructor(id: string, title: string, icon: string, color: string,
    units: UnitItem[], isTemperature: boolean = false, isBase: boolean = false, isTimezone: boolean = false) {
    this.id = id;
    this.title = title;
    this.icon = icon;
    this.color = color;
    this.units = units;
    this.isTemperature = isTemperature;
    this.isBase = isBase;
    this.isTimezone = isTimezone;
  }
}

export class TimezoneCity {
  city: string = '';
  zone: string = '';
  offset: number = 0;
  country: string = '';
  abbr: string = '';
  lat: number = 0;
  lng: number = 0;

  constructor(city: string, zone: string, offset: number, country: string, abbr: string, lat: number = 0, lng: number = 0) {
    this.city = city;
    this.zone = zone;
    this.offset = offset;
    this.country = country;
    this.abbr = abbr;
    this.lat = lat;
    this.lng = lng;
  }
}

export class TimezoneRegion {
  name: string = '';
  cities: string[] = [];

  constructor(name: string, cities: string[]) {
    this.name = name;
    this.cities = cities;
  }
}

export class ConvertedTimeItem {
  city: string = '';
  country: string = '';
  offset: number = 0;
  offsetDiff: number = 0;
  localDate: string = '';
  localTime: string = '';
  isWorkTime: boolean = false;
  isNight: boolean = false;
  isFavorite: boolean = false;
}

export class MeetingResultItem {
  city: string = '';
  country: string = '';
  localTime: string = '';
  isWorkTime: boolean = false;
  isNight: boolean = false;
}

class TimezoneCityRaw {
  city: string = '';
  zone: string = '';
  offset: number = 0;
  country: string = '';
  abbr: string = '';
  lat: number = 0;
  lng: number = 0;
}

class TimezoneRegionRaw {
  name: string = '';
  cities: TimezoneCityRaw[] = [];
}

class TimezoneFileData {
  regions: TimezoneRegionRaw[] = [];
}

export class TimezoneDataLoader {
  private static cities: TimezoneCity[] = [];
  private static regions: TimezoneRegion[] = [];
  private static loaded: boolean = false;

  static load(context: Context): void {
    if (TimezoneDataLoader.loaded) {
      return;
    }
    try {
      let data: TimezoneFileData = RawFileUtil.readJson<TimezoneFileData>(context, 'timezone/timezone_cities.json');
      let allCities: TimezoneCity[] = [];
      let allRegions: TimezoneRegion[] = [];
      for (let i = 0; i < data.regions.length; i++) {
        let regionRaw: TimezoneRegionRaw = data.regions[i];
        let cityNames: string[] = [];
        for (let j = 0; j < regionRaw.cities.length; j++) {
          let c: TimezoneCityRaw = regionRaw.cities[j];
          let city: TimezoneCity = new TimezoneCity(c.city, c.zone, c.offset, c.country, c.abbr, c.lat, c.lng);
          allCities.push(city);
          cityNames.push(c.city);
        }
        allRegions.push(new TimezoneRegion(regionRaw.name, cityNames));
      }
      TimezoneDataLoader.cities = allCities;
      TimezoneDataLoader.regions = allRegions;
      TimezoneDataLoader.loaded = true;
    } catch (e) {
      let errMsg: string = '';
      if (e instanceof Error) {
        errMsg = e.message;
      }
      console.error('[TimezoneData] load failed: ' + errMsg);
      TimezoneDataLoader.cities = [];
      TimezoneDataLoader.regions = [];
    }
  }

  static isLoaded(): boolean {
    return TimezoneDataLoader.loaded;
  }

  static getCities(): TimezoneCity[] {
    return TimezoneDataLoader.cities;
  }

  static getRegions(): TimezoneRegion[] {
    return TimezoneDataLoader.regions;
  }

  static getCityByName(name: string): TimezoneCity | null {
    for (let i = 0; i < TimezoneDataLoader.cities.length; i++) {
      if (TimezoneDataLoader.cities[i].city === name) {
        return TimezoneDataLoader.cities[i];
      }
    }
    return null;
  }
}

export class UnitConverterData {
  private static categories: ConverterCategory[] = [
    new ConverterCategory('length', '长度换算', '\uD83D\uDCF0', '#3498db', [
      new UnitItem('纳米', 1e-9, 1e9),
      new UnitItem('微米', 1e-6, 1e6),
      new UnitItem('毫米', 0.001, 1000),
      new UnitItem('厘米', 0.01, 100),
      new UnitItem('分米', 0.1, 10),
      new UnitItem('米', 1, 1),
      new UnitItem('千米', 1000, 0.001),
      new UnitItem('光年', 9.46073e15, 1.057e-16),
      new UnitItem('英里', 1609.344, 0.000621371),
      new UnitItem('英尺', 0.3048, 3.28084),
      new UnitItem('英寸', 0.0254, 39.3701),
      new UnitItem('码', 0.9144, 1.09361),
      new UnitItem('海里', 1852, 5.39957e-4),
      new UnitItem('丈', 3.33333, 0.3),
      new UnitItem('尺', 0.333333, 3),
      new UnitItem('寸', 0.0333333, 30)
    ]),
    new ConverterCategory('area', '面积换算', '\uD83D\uDDE3\uFE0F', '#9b59b6', [
      new UnitItem('平方毫米', 0.000001, 1000000),
      new UnitItem('平方厘米', 0.0001, 10000),
      new UnitItem('平方分米', 0.01, 100),
      new UnitItem('平方米', 1, 1),
      new UnitItem('平方千米', 1000000, 0.000001),
      new UnitItem('公顷', 10000, 0.0001),
      new UnitItem('亩', 666.666667, 0.0015),
      new UnitItem('平方英尺', 0.092903, 10.7639),
      new UnitItem('平方码', 0.836127, 1.19599),
      new UnitItem('平方英寸', 0.00064516, 1550.0031),
      new UnitItem('英亩', 4046.86, 0.000247105),
      new UnitItem('平方英里', 2589988.11, 3.86102e-7)
    ]),
    new ConverterCategory('weight', '重量换算', '\u2696\uFE0F', '#e67e22', [
      new UnitItem('千克', 1, 1),
      new UnitItem('克', 0.001, 1000),
      new UnitItem('毫克', 0.000001, 1000000),
      new UnitItem('吨', 1000, 0.001),
      new UnitItem('磅', 0.45359237, 2.20462),
      new UnitItem('盎司', 0.02834952, 35.274)
    ]),
    new ConverterCategory('volume', '体积换算', '\uD83E\uDDEA', '#1abc9c', [
      new UnitItem('立方米', 1, 1),
      new UnitItem('升', 0.001, 1000),
      new UnitItem('分升', 0.0001, 10000),
      new UnitItem('毫升', 0.000001, 1000000),
      new UnitItem('加仑', 0.00378541, 264.172)
    ]),
    new ConverterCategory('temperature', '温度换算', '\uD83C\uDF21\uFE0F', '#e74c3c', [], true),
    new ConverterCategory('speed', '速度换算', '\uD83D\uDE80', '#2ecc71', [
      new UnitItem('米/秒', 1, 1),
      new UnitItem('千米/小时', 0.277778, 3.6),
      new UnitItem('英里/小时', 0.44704, 2.23694),
      new UnitItem('节', 0.514444, 1.94384),
      new UnitItem('光速', 299792458, 1 / 299792458)
    ]),
    new ConverterCategory('time', '时间换算', '\u23F0', '#f39c12', [
      new UnitItem('毫秒', 0.001, 1000),
      new UnitItem('秒', 1, 1),
      new UnitItem('分钟', 60, 1 / 60),
      new UnitItem('小时', 3600, 1 / 3600),
      new UnitItem('天', 86400, 1 / 86400),
      new UnitItem('周', 604800, 1 / 604800),
      new UnitItem('月', 2592000, 1 / 2592000),
      new UnitItem('年', 31536000, 1 / 31536000),
      new UnitItem('十年', 315360000, 1 / 315360000),
      new UnitItem('世纪', 3153600000, 1 / 3153600000)
    ]),
    new ConverterCategory('pressure', '压力换算', '\uD83D\uDCC8', '#34495e', [
      new UnitItem('帕斯卡', 1, 1),
      new UnitItem('千帕', 1000, 0.001),
      new UnitItem('兆帕', 1000000, 0.000001),
      new UnitItem('巴', 100000, 0.00001),
      new UnitItem('标准大气压', 101325, 0.00000986923),
      new UnitItem('毫米汞柱', 133.322, 0.00750062),
      new UnitItem('磅每平方英寸', 6894.76, 0.000145038)
    ]),
    new ConverterCategory('energy', '能量换算', '\u26A1', '#8e44ad', [
      new UnitItem('焦耳', 1, 1),
      new UnitItem('千焦', 1000, 0.001),
      new UnitItem('兆焦', 1000000, 0.000001),
      new UnitItem('卡路里', 4.184, 0.239006),
      new UnitItem('千瓦时', 3600000, 2.77778e-7),
      new UnitItem('英热单位', 1055.06, 9.47817e-4),
      new UnitItem('电子伏特', 1.60218e-19, 6.24151e18)
    ]),
    new ConverterCategory('base', '进制转换', '\uD83D\uDD04', '#16a085', [], false, true),
    new ConverterCategory('timezone', '时区转换', '\uD83C\uDF0D', '#2980b9', [], false, false, true)
  ];

  static getCategories(): ConverterCategory[] {
    return UnitConverterData.categories;
  }

  static getCategoryById(id: string): ConverterCategory | null {
    for (let i = 0; i < UnitConverterData.categories.length; i++) {
      if (UnitConverterData.categories[i].id === id) {
        return UnitConverterData.categories[i];
      }
    }
    return null;
  }

  static temperatureToBase(value: number, unit: string): number {
    if (unit === '摄氏度') {
      return value;
    }
    if (unit === '华氏度') {
      return (value - 32) * 5 / 9;
    }
    if (unit === '开尔文') {
      return value - 273.15;
    }
    if (unit === '兰金温标') {
      return (value - 491.67) * 5 / 9;
    }
    if (unit === '列氏温标') {
      return value * 5 / 4;
    }
    if (unit === '牛顿温标') {
      return value * 100 / 33;
    }
    if (unit === '罗默温标') {
      return (value - 7.5) * 40 / 21;
    }
    return value;
  }

  static temperatureFromBase(baseValue: number, unit: string): number {
    if (unit === '摄氏度') {
      return baseValue;
    }
    if (unit === '华氏度') {
      return baseValue * 9 / 5 + 32;
    }
    if (unit === '开尔文') {
      return baseValue + 273.15;
    }
    if (unit === '兰金温标') {
      return baseValue * 9 / 5 + 491.67;
    }
    if (unit === '列氏温标') {
      return baseValue * 4 / 5;
    }
    if (unit === '牛顿温标') {
      return baseValue * 33 / 100;
    }
    if (unit === '罗默温标') {
      return baseValue * 21 / 40 + 7.5;
    }
    return baseValue;
  }

  static temperatureUnits: string[] = ['摄氏度', '华氏度', '开尔文', '兰金温标', '列氏温标', '牛顿温标', '罗默温标'];

  static formatResult(result: number): string {
    if (result === 0) {
      return '0';
    }
    let absResult: number = Math.abs(result);
    let precision: number = absResult >= 1 ? 6 : 8;
    let fixed: string = result.toFixed(precision);
    let parts: string[] = fixed.split('.');
    let intPart: string = parts[0];
    let decPart: string = parts[1];
    let trimmed: string = decPart.replace(/0+$/, '');
    if (trimmed.length === 0) {
      return intPart;
    }
    return intPart + '.' + trimmed;
  }
}
