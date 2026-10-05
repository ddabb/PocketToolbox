import { CoverContentUtil } from '../core/cover/CoverContentUtil';

class PinyinUnit {
  ch: string = '';
  py: string = '';

  constructor(ch: string, py: string) {
    this.ch = ch;
    this.py = py;
  }
}

const PY_CLEAN_RE: RegExp = new RegExp('[^a-zA-Z\u0101\u00e1\u01ce\u00e0\u0113\u00e9\u011b\u00e8\u012b\u00ed\u01d0\u00ec\u014d\u00f3\u01d2\u00f2\u016b\u00fa\u01d4\u00f9\u01d6\u01d8\u01da\u01dc\u00fc\u0144\u0148\u01f9\u0304\u0301\u030c\u0300]', 'g');

function isHan(ch: string): boolean {
  let code: number = ch.charCodeAt(0);
  return code >= 0x4E00 && code <= 0x9FA5;
}

function hasLetter(token: string): boolean {
  return new RegExp('[a-zA-Z]').test(token);
}

@Component
export struct PinyinText {
  @Prop text: string = '';
  @Prop charSize: number = 16;
  @Prop pySize: number = 10;
  @Prop charColor: ResourceColor = $r('app.color.secondary_text');
  @State lines: PinyinUnit[][] = [];

  aboutToAppear(): void {
    this.rebuild();
  }

  private rebuild(): void {
    let rawLines: string[] = this.text.split('\n');
    let result: PinyinUnit[][] = [];
    for (let i = 0; i < rawLines.length; i++) {
      let line: string = rawLines[i];
      if (line.trim() === '') {
        result.push([]);
        continue;
      }
      let syllables: string[] = CoverContentUtil.syllables(CoverContentUtil.autoPinyin(line));
      let chars: string[] = Array.from(line);
      let units: PinyinUnit[] = [];
      let si: number = 0;
      for (let j = 0; j < chars.length; j++) {
        let ch: string = chars[j];
        if (isHan(ch)) {
          let py: string = '';
          while (si < syllables.length && !hasLetter(syllables[si])) {
            si++;
          }
          if (si < syllables.length) {
            py = syllables[si].replace(PY_CLEAN_RE, '');
            si++;
          }
          units.push(new PinyinUnit(ch, py));
        } else if (ch !== ' ' && ch !== '\u3000') {
          if (si < syllables.length && syllables[si] === ch) {
            si++;
          }
          units.push(new PinyinUnit(ch, ''));
        }
      }
      result.push(units);
    }
    this.lines = result;
  }

  build() {
    Column({ space: 8 }) {
      ForEach(this.lines, (units: PinyinUnit[], li: number) => {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          ForEach(units, (u: PinyinUnit, ci: number) => {
            Column() {
              Text(u.py === '' ? ' ' : u.py)
                .fontSize(this.pySize)
                .fontColor($r('app.color.tertiary_text'))
                .maxLines(1)
              Text(u.ch)
                .fontSize(this.charSize)
                .fontColor(this.charColor)
            }
            .constraintSize({ minWidth: this.charSize })
            .alignItems(HorizontalAlign.Center)
          }, (u: PinyinUnit, ci: number) => li.toString() + '-' + ci.toString() + '-' + u.ch + '-' + u.py)
        }
        .width('100%')
      }, (units: PinyinUnit[], li: number) => li.toString() + '-' + units.length.toString() + '-' + this.text.length.toString())
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
