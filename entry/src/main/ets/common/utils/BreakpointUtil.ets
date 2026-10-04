import { mediaquery } from '@kit.ArkUI';

/** 统一断点：SM ≤600vp（手机）/ MD 600~840vp（折叠屏展开）/ LG ≥840vp（平板） */
export enum ScreenBreakpoint {
  SM = 'sm',
  MD = 'md',
  LG = 'lg'
}

/** 断点观察者：start 注册媒体查询监听并立即回调当前断点，stop 注销；页面在 aboutToAppear/aboutToDisappear 配对使用 */
export class BreakpointObserver {
  static readonly MD_MIN_VP: number = 600;
  static readonly LG_MIN_VP: number = 840;

  private mdListener: mediaquery.MediaQueryListener | null = null;
  private lgListener: mediaquery.MediaQueryListener | null = null;
  private onChange: (bp: ScreenBreakpoint) => void = () => {};
  current: ScreenBreakpoint = ScreenBreakpoint.SM;

  start(ui: UIContext, onChange: (bp: ScreenBreakpoint) => void): void {
    this.stop();
    this.onChange = onChange;
    let md: mediaquery.MediaQueryListener =
      ui.getMediaQuery().matchMediaSync('(min-width: ' + BreakpointObserver.MD_MIN_VP + 'vp)');
    let lg: mediaquery.MediaQueryListener =
      ui.getMediaQuery().matchMediaSync('(min-width: ' + BreakpointObserver.LG_MIN_VP + 'vp)');
    this.mdListener = md;
    this.lgListener = lg;
    this.current = BreakpointObserver.calc(md.matches, lg.matches);
    md.on('change', (result: mediaquery.MediaQueryResult) => {
      this.update(result.matches, lg.matches);
    });
    lg.on('change', (result: mediaquery.MediaQueryResult) => {
      this.update(md.matches, result.matches);
    });
    onChange(this.current);
  }

  stop(): void {
    if (this.mdListener !== null) {
      this.mdListener.off('change');
      this.mdListener = null;
    }
    if (this.lgListener !== null) {
      this.lgListener.off('change');
      this.lgListener = null;
    }
  }

  private update(md: boolean, lg: boolean): void {
    let next: ScreenBreakpoint = BreakpointObserver.calc(md, lg);
    if (next !== this.current) {
      this.current = next;
      this.onChange(next);
    }
  }

  private static calc(md: boolean, lg: boolean): ScreenBreakpoint {
    if (lg) {
      return ScreenBreakpoint.LG;
    }
    return md ? ScreenBreakpoint.MD : ScreenBreakpoint.SM;
  }
}
