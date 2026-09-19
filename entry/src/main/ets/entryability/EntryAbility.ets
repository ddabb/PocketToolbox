import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0xF0001;
const TAG = 'PocketToolbox';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    this.handleWidgetWant(want);
  }

  // 桌面卡片 router 事件拉起时解析参数；应用已在后台时走 onNewWant
  onNewWant(want: Want): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onNewWant');
    this.handleWidgetWant(want);
  }

  private handleWidgetWant(want: Want): void {
    let rawParams: Object | undefined = want.parameters?.params;
    if (rawParams === undefined) {
      return;
    }
    try {
      let cardParams: Record<string, Object> = JSON.parse(rawParams as string) as Record<string, Object>;
      let openPoem: string = String(cardParams['openPoem'] ?? '');
      if (openPoem) {
        AppStorage.setOrCreate('WidgetOpenPoem', openPoem);
        hilog.info(DOMAIN, TAG, '%{public}s', 'widget openPoem received');
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'parse widget params failed: %{public}s', JSON.stringify(e));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
  }
}