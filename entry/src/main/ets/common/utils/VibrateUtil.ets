import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class VibrateUtil {
  static tap(): void {
    VibrateUtil.vibrate(15);
  }

  static success(): void {
    VibrateUtil.vibrate(30);
  }

  static error(): void {
    VibrateUtil.vibrate(50);
  }

  private static vibrate(durationMs: number): void {
    try {
      let effect: vibrator.VibrateTime = { type: 'time', duration: durationMs };
      let attribute: vibrator.VibrateAttribute = { usage: 'touch' };
      vibrator.startVibration(effect, attribute).catch((err: BusinessError) => {
        console.warn('[VibrateUtil] startVibration rejected: ' + err.code.toString() + ' ' + err.message);
      });
    } catch (e) {
      console.warn('[VibrateUtil] startVibration failed: ' + (e as Error).message);
    }
  }
}
