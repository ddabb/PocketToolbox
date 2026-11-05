import { Context } from '@kit.AbilityKit';
import { ToastUtil } from '../common/utils/ToastUtil';
import { StrUtil } from '../common/utils/StrUtil';
import { DateDiffHistoryUtil, DateDiffRecord } from '../common/utils/DateDiffHistoryUtil';

@Builder
export function DateDiffPageBuilder() {
  NavDestination() {
    DateDiffContent()
  }
  .title($r('app.string.tool_date_diff_title'))
  .backButtonIcon($r('sys.symbol.chevron_left'))
  .menus([])
  .backgroundColor($r('app.color.page_background'))
}

@Component
struct DateDiffContent {
  @State startDate: Date = new Date();
  @State endDate: Date = new Date();
  @State totalDays: number = 0;
  @State breakdownStr: string = '';
  @State weeksStr: string = '';
  @State workdaysStr: string = '';
  @State workdaysNote: string = '';
  @State hoursStr: string = '';
  @State minutesStr: string = '';
  @State history: DateDiffRecord[] = [];
  private readonly MS_PER_DAY: number = 86400000;
  private readonly ACCENT: string = '#06b6d4';
  private readonly ACCENT_END: string = '#f59e0b';

  aboutToAppear(): void {
    let ctx: Context = this.getUIContext().getHostContext() as Context;
    this.history = DateDiffHistoryUtil.load(ctx);
    if (this.history.length > 0) {
      let last: DateDiffRecord = this.history[0];
      let s: Date | null = this.parseDate(last.start);
      let e: Date | null = this.parseDate(last.end);
      if (s !== null && e !== null) {
        this.startDate = s;
        this.endDate = e;
        this.recalc();
        return;
      }
    }
    let now: Date = new Date();
    this.startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    this.endDate = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 30);
    this.recalc();
  }

  private pad(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }

  private formatDate(d: Date): string {
    return d.getFullYear().toString() + '-' + this.pad(d.getMonth() + 1) + '-' + this.pad(d.getDate());
  }

  private parseDate(s: string): Date | null {
    let parts: string[] = s.split('-');
    if (parts.length !== 3) {
      return null;
    }
    let y: number = parseInt(parts[0]);
    let m: number = parseInt(parts[1]);
    let d: number = parseInt(parts[2]);
    if (isNaN(y) || isNaN(m) || isNaN(d)) {
      return null;
    }
    return new Date(y, m - 1, d);
  }

  private groupThousands(n: number): string {
    let s: string = n.toString();
    let out: string = '';
    let count: number = 0;
    for (let i = s.length - 1; i >= 0; i--) {
      out = s.charAt(i) + out;
      count++;
      if (count % 3 === 0 && i > 0) {
        out = ',' + out;
      }
    }
    return out;
  }

  private toUtcMs(d: Date): number {
    return Date.UTC(d.getFullYear(), d.getMonth(), d.getDate());
  }

  private recalc(): void {
    let aMs: number = this.toUtcMs(this.startDate);
    let bMs: number = this.toUtcMs(this.endDate);
    let total: number = Math.round(Math.abs(bMs - aMs) / this.MS_PER_DAY);
    this.totalDays = total;
    let from: Date = aMs <= bMs ? this.startDate : this.endDate;
    let to: Date = aMs <= bMs ? this.endDate : this.startDate;
    let y: number = to.getFullYear() - from.getFullYear();
    let m: number = to.getMonth() - from.getMonth();
    let d: number = to.getDate() - from.getDate();
    if (d < 0) {
      m -= 1;
      d += new Date(to.getFullYear(), to.getMonth(), 0).getDate();
    }
    if (m < 0) {
      y -= 1;
      m += 12;
    }
    let ctx: Context = this.getUIContext().getHostContext() as Context;
    let parts: string[] = [];
    if (y > 0) {
      parts.push(StrUtil.text(ctx, $r('app.string.date_diff_unit_year', y)));
    }
    if (m > 0) {
      parts.push(StrUtil.text(ctx, $r('app.string.date_diff_unit_month', m)));
    }
    if (d > 0 || parts.length === 0) {
      parts.push(StrUtil.text(ctx, $r('app.string.date_diff_unit_day', d)));
    }
    this.breakdownStr = parts.join(' ');
    this.weeksStr = '';
    let weeks: number = Math.floor(total / 7);
    let weekRemain: number = total % 7;
    let weekParts: string[] = [];
    if (weeks > 0) {
      weekParts.push(StrUtil.text(ctx, $r('app.string.date_diff_unit_week', weeks)));
    }
    if (weekRemain > 0 || weekParts.length === 0) {
      weekParts.push(StrUtil.text(ctx, $r('app.string.date_diff_unit_day', weekRemain)));
    }
    this.weeksStr = weekParts.join(' ');
    let workdayCount: number = 0;
    let cursor: number = this.toUtcMs(from);
    for (let i = 0; i < total; i++) {
      cursor += this.MS_PER_DAY;
      let wd: number = new Date(cursor).getUTCDay();
      if (wd !== 0 && wd !== 6) {
        workdayCount++;
      }
    }
    this.workdaysStr = StrUtil.text(ctx, $r('app.string.date_diff_unit_day', workdayCount));
    this.workdaysNote = StrUtil.text(ctx, $r('app.string.date_diff_stat_workdays_note'));
    this.hoursStr = this.groupThousands(total * 24);
    this.minutesStr = this.groupThousands(total * 24 * 60);
  }

  private applyDates(sy: number, sm: number, sd: number, ey: number, em: number, ed: number, record: boolean): void {
    this.startDate = new Date(sy, sm - 1, sd);
    this.endDate = new Date(ey, em - 1, ed);
    this.recalc();
    if (record) {
      let ctx: Context = this.getUIContext().getHostContext() as Context;
      this.history = DateDiffHistoryUtil.record(ctx, this.formatDate(this.startDate), this.formatDate(this.endDate), this.totalDays);
    }
  }

  private openStartPicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(1900, 0, 1),
      end: new Date(2100, 11, 31),
      selected: this.startDate,
      onDateAccept: (value: Date) => {
        this.applyDates(value.getFullYear(), value.getMonth() + 1, value.getDate(),
          this.endDate.getFullYear(), this.endDate.getMonth() + 1, this.endDate.getDate(), true);
      }
    });
  }

  private openEndPicker(): void {
    this.getUIContext().showDatePickerDialog({
      start: new Date(1900, 0, 1),
      end: new Date(2100, 11, 31),
      selected: this.endDate,
      onDateAccept: (value: Date) => {
        this.applyDates(this.startDate.getFullYear(), this.startDate.getMonth() + 1, this.startDate.getDate(),
          value.getFullYear(), value.getMonth() + 1, value.getDate(), true);
      }
    });
  }

  private setStartToday(): void {
    let now: Date = new Date();
    this.applyDates(now.getFullYear(), now.getMonth() + 1, now.getDate(),
      this.endDate.getFullYear(), this.endDate.getMonth() + 1, this.endDate.getDate(), true);
  }

  private setEndToday(): void {
    let now: Date = new Date();
    this.applyDates(this.startDate.getFullYear(), this.startDate.getMonth() + 1, this.startDate.getDate(),
      now.getFullYear(), now.getMonth() + 1, now.getDate(), true);
  }

  private swapDates(): void {
    this.applyDates(this.endDate.getFullYear(), this.endDate.getMonth() + 1, this.endDate.getDate(),
      this.startDate.getFullYear(), this.startDate.getMonth() + 1, this.startDate.getDate(), true);
  }

  private restoreRecord(rec: DateDiffRecord): void {
    let s: Date | null = this.parseDate(rec.start);
    let e: Date | null = this.parseDate(rec.end);
    if (s === null || e === null) {
      return;
    }
    this.applyDates(s.getFullYear(), s.getMonth() + 1, s.getDate(), e.getFullYear(), e.getMonth() + 1, e.getDate(), true);
  }

  private clearHistory(): void {
    let ctx: Context = this.getUIContext().getHostContext() as Context;
    this.history = DateDiffHistoryUtil.clear(ctx);
    ToastUtil.show(this.getUIContext(), $r('app.string.date_diff_cleared'), 1000);
  }

  @Builder
  StatTile(label: ResourceStr, value: string, note: string) {
    Column() {
      Text(label)
        .fontSize(11)
        .fontColor($r('app.color.tertiary_text'))
      Text(value)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.primary_text'))
        .margin({ top: 5 })
        .maxLines(1)
      if (note !== '') {
        Text(note)
          .fontSize(10)
          .fontColor($r('app.color.tertiary_text'))
          .margin({ top: 3 })
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .constraintSize({ minHeight: 78 })
    .padding({ top: 12, bottom: 12 })
    .margin({ left: 5, right: 5 })
    .backgroundColor($r('app.color.page_background'))
    .borderRadius(12)
  }

  @Builder
  QuickChip(label: ResourceStr, onTap: () => void) {
    Text(label)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.ACCENT)
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.ACCENT + '12')
      .borderRadius(14)
      .onClick(() => {
        onTap();
      })
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          Row() {
            Text('A')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.on_accent_text'))
              .width(30)
              .height(30)
              .borderRadius(9)
              .backgroundColor(this.ACCENT)
              .textAlign(TextAlign.Center)
              .margin({ right: 12 })
            Column() {
              Text($r('app.string.date_diff_start_label'))
                .fontSize(11)
                .fontColor($r('app.color.tertiary_text'))
              Text(this.formatDate(this.startDate))
                .fontSize(19)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text($r('app.string.date_diff_edit'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.ACCENT)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor(this.ACCENT + '12')
              .borderRadius(12)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.openStartPicker();
          })

          Divider().color($r('app.color.border_color')).margin({ left: 58, right: 16 })

          Row() {
            Text('B')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.on_accent_text'))
              .width(30)
              .height(30)
              .borderRadius(9)
              .backgroundColor(this.ACCENT_END)
              .textAlign(TextAlign.Center)
              .margin({ right: 12 })
            Column() {
              Text($r('app.string.date_diff_end_label'))
                .fontSize(11)
                .fontColor($r('app.color.tertiary_text'))
              Text(this.formatDate(this.endDate))
                .fontSize(19)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary_text'))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Text($r('app.string.date_diff_edit'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.ACCENT_END)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor(this.ACCENT_END + '12')
              .borderRadius(12)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.openEndPicker();
          })

          Row({ space: 8 }) {
            this.QuickChip($r('app.string.date_diff_today'), () => {
              this.setStartToday();
            })
            this.QuickChip($r('app.string.date_diff_until_today'), () => {
              this.setEndToday();
            })
            this.QuickChip($r('app.string.date_diff_swap'), () => {
              this.swapDates();
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 14 })
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)

        Column() {
          Column() {
            Text($r('app.string.date_diff_total_label'))
              .fontSize(12)
              .fontColor($r('app.color.tertiary_text'))
            Row() {
              Text(this.groupThousands(this.totalDays))
                .fontSize(42)
                .fontWeight(FontWeight.Bolder)
                .fontColor(this.ACCENT)
              Text($r('app.string.date_diff_day_short'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.secondary_text'))
                .margin({ left: 5, bottom: 7 })
            }
            .alignItems(VerticalAlign.Bottom)
            .margin({ top: 4 })
            if (this.totalDays === 0) {
              Text($r('app.string.date_diff_same_day'))
                .fontSize(13)
                .fontColor($r('app.color.secondary_text'))
                .margin({ top: 6 })
            } else {
              Text(this.breakdownStr)
                .fontSize(13)
                .fontColor($r('app.color.secondary_text'))
                .margin({ top: 6 })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 22, bottom: 20 })
          .backgroundColor(this.ACCENT + '10')
          .borderRadius({ topLeft: 16, topRight: 16 })

          Column() {
            Row() {
              this.StatTile($r('app.string.date_diff_stat_weeks'), this.weeksStr, '')
              this.StatTile($r('app.string.date_diff_stat_workdays'), this.workdaysStr, this.workdaysNote)
            }
            .width('100%')
            .margin({ top: 6 })

            Row() {
              this.StatTile($r('app.string.date_diff_stat_hours'), this.hoursStr, '')
              this.StatTile($r('app.string.date_diff_stat_minutes'), this.minutesStr, '')
            }
            .width('100%')
            .margin({ top: 4 })
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 4, bottom: 10 })
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .margin({ top: 12 })
        .clip(true)

        Column() {
          Row() {
            Text($r('app.string.date_diff_history_title'))
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary_text'))
            Blank()
            if (this.history.length > 0) {
              Text($r('app.string.date_diff_history_clear'))
                .fontSize(13)
                .fontColor($r('app.color.danger_red'))
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .onClick(() => {
                  this.clearHistory();
                })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 8, top: 14, bottom: 6 })

          if (this.history.length === 0) {
            Text($r('app.string.date_diff_history_empty'))
              .fontSize(13)
              .fontColor($r('app.color.tertiary_text'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 26, bottom: 30 })
          } else {
            ForEach(this.history, (rec: DateDiffRecord, index: number) => {
              Column() {
                Row() {
                  Column() {
                    Text(rec.start + '  →  ' + rec.end)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.primary_text'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Row() {
                    Text(this.groupThousands(rec.days))
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(this.ACCENT)
                    Text($r('app.string.date_diff_day_short'))
                      .fontSize(11)
                      .fontColor($r('app.color.secondary_text'))
                      .margin({ left: 2 })
                  }
                  .alignItems(VerticalAlign.Bottom)
                  .margin({ left: 10 })
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 11, bottom: 11 })
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  this.restoreRecord(rec);
                })

                if (index < this.history.length - 1) {
                  Divider().color($r('app.color.border_color')).margin({ left: 16, right: 16 })
                }
              }
            }, (rec: DateDiffRecord, index: number) => rec.start + '_' + rec.end + '_' + rec.ts.toString())
          }
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(16)
        .margin({ top: 12 })
        .padding({ bottom: 6 })
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .constraintSize({ maxWidth: 640 })
    .scrollable(ScrollDirection.Vertical)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }
}
