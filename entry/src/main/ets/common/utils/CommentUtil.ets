import { common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { commentManager } from '@kit.AppGalleryKit';
import { ToastUtil } from './ToastUtil';

export class CommentUtil {
  // 应用内评论弹窗（commentManager）自 6.0.0(20) 起支持，工程 compatibleSdkVersion 已同步升至 20，
  // 可安装设备均具备该能力，无需再做版本守卫；运行时失败仍按三层兜底降级。
  static requestComment(uiContext: UIContext): void {
    let ctx: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
    try {
      commentManager.showCommentDialog(ctx).catch((e: BusinessError) => {
        console.error('[CommentUtil] showCommentDialog failed, code: ' + e.code + ', message: ' + e.message);
        CommentUtil.openAppGalleryReview(uiContext, ctx);
      });
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[CommentUtil] showCommentDialog threw, code: ' + err.code + ', message: ' + err.message);
      CommentUtil.openAppGalleryReview(uiContext, ctx);
    }
  }

  // Deep Linking 拉起应用市场写评论页：详情页 + action=write-review
  private static openAppGalleryReview(uiContext: UIContext, ctx: common.UIAbilityContext): void {
    let want: Want = {
      action: 'ohos.want.action.appdetail',
      uri: 'store://appgallery.huawei.com/app/detail?id=' + ctx.abilityInfo.bundleName + '&action=write-review'
    };
    ctx.startAbility(want).catch((e: BusinessError) => {
      console.error('[CommentUtil] open AppGallery review failed, code: ' + e.code + ', message: ' + e.message);
      ToastUtil.show(uiContext, $r('app.string.comment_open_market_failed'), 1500);
    });
  }
}
