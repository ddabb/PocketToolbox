import { Context } from '@kit.AbilityKit';
import { RawFileUtil } from './RawFileUtil';

export class FlyFlowerLine {
  l: string = '';
  t: string = '';
  a: string = '';
}

export class FlyFlowerIndex {
  version: number = 0;
  chars: string[] = [];
  data: Record<string, FlyFlowerLine[]> = {};
}

export class FlyFlowerRoundItem {
  l: string = '';
  t: string = '';
  a: string = '';
}

export class FlyFlowerUtil {
  private static readonly HINT_LEN: number = 2;
  private static readonly DATA_PATH: string = 'flyflower/lines.json';

  static loadIndex(context: Context): FlyFlowerIndex {
    let raw: Record<string, Object> =
      RawFileUtil.readJson<Record<string, Object>>(context, FlyFlowerUtil.DATA_PATH);
    let index: FlyFlowerIndex = new FlyFlowerIndex();
    index.version = (raw['version'] as number) || 0;
    let rawChars: Object[] = (raw['chars'] as Object[]) || [];
    let chars: string[] = [];
    for (let i = 0; i < rawChars.length; i++) {
      chars.push(rawChars[i] as string);
    }
    index.chars = chars;
    let rawData: Record<string, Object> = (raw['data'] as Record<string, Object>) || {};
    let data: Record<string, FlyFlowerLine[]> = {};
    let keys: string[] = Object.keys(rawData);
    for (let i = 0; i < keys.length; i++) {
      let rawLines: Object[] = (rawData[keys[i]] as Object[]) || [];
      let lines: FlyFlowerLine[] = [];
      for (let j = 0; j < rawLines.length; j++) {
        let obj: Record<string, Object> = rawLines[j] as Record<string, Object>;
        let line: FlyFlowerLine = new FlyFlowerLine();
        line.l = (obj['l'] as string) || '';
        line.t = (obj['t'] as string) || '';
        line.a = (obj['a'] as string) || '';
        lines.push(line);
      }
      data[keys[i]] = lines;
    }
    index.data = data;
    if (index.chars.length === 0) {
      throw new Error('FlyFlower index invalid: empty chars');
    }
    return index;
  }

  static pickChar(index: FlyFlowerIndex): string {
    if (index.chars.length === 0) {
      return '';
    }
    let i: number = Math.floor(Math.random() * index.chars.length);
    return index.chars[i];
  }

  static pickHint(index: FlyFlowerIndex, char: string, used: Set<string>): string {
    let lines: FlyFlowerLine[] | undefined = index.data[char];
    if (lines === undefined || lines.length === 0) {
      return '';
    }
    let candidates: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      if (!used.has(lines[i].l)) {
        candidates.push(lines[i].l);
      }
    }
    if (candidates.length === 0) {
      return '';
    }
    let pick: string = candidates[Math.floor(Math.random() * candidates.length)];
    if (pick.length <= FlyFlowerUtil.HINT_LEN) {
      return pick;
    }
    return pick.substring(0, FlyFlowerUtil.HINT_LEN);
  }

  static normalize(input: string): string {
    let pattern: RegExp = new RegExp('[^\\u4e00-\\u9fa5]', 'g');
    return input.replace(pattern, '');
  }

  static matchLine(index: FlyFlowerIndex, char: string, normalized: string): FlyFlowerLine | null {
    let lines: FlyFlowerLine[] | undefined = index.data[char];
    if (lines === undefined) {
      return null;
    }
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].l === normalized) {
        return lines[i];
      }
    }
    return null;
  }
}
