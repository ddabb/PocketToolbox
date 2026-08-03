/**
 * ImageSaveShareBar - 独立的图片保存/分享操作栏组件
 *
 * 与 ShareImageCard 完全解耦，不依赖 Markdown 渲染、Canvas 装饰等逻辑。
 * 仅提供「保存到相册」和「分享」两个操作按钮，适用于词云、文字转图片等
 * 已有 PixelMap 或缓存路径的场景。
 *
 * 使用方式：
 *   ImageSaveShareBar({
 *     accentColor: '#2563eb',
 *     onPmForSave: () => this.renderExportPixelMap(),  // 返回用于保存的 PixelMap
 *     onPmForShare: () => this.renderExportPixelMap(),  // 返回用于分享的 PixelMap
 *   })
 */
import { image } from '@kit.ImageKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

@Component
export struct ImageSaveShareBar {
  /** 主题强调色，用于按钮背景 */
  @Prop accentColor: string = '#2563eb';
  /** 是否正在执行保存/分享操作 */
  @State isBusy: boolean = false;

  /**
   * 调用方提供用于保存到相册的 PixelMap（每次调用返回新实例）。
   * 必须由使用方覆盖，默认空实现会抛异常。
   */
  onPmForSave: () => image.PixelMap = (): image.PixelMap => {
    throw new Error('ImageSaveShareBar: onPmForSave must be overridden');
  };
  /**
   * 调用方提供用于分享的 PixelMap（每次调用返回新实例）。
   * 必须由使用方覆盖，默认空实现会抛异常。
   */
  onPmForShare: () => image.PixelMap = (): image.PixelMap => {
    throw new Error('ImageSaveShareBar: onPmForShare must be overridden');
  };

  /**
   * 将 PixelMap 打包写入缓存目录，返回文件绝对路径。
   * 主线程同步执行，不使用 taskpool（PixelMap 不可跨线程序列化）。
   */
  private async packToCache(pm: image.PixelMap, prefix: string): Promise<string> {
    let uiCtx: UIContext = this.getUIContext();
    let ctx: common.UIAbilityContext = uiCtx.getHostContext() as common.UIAbilityContext;
    let dir: string = ctx.cacheDir;
    let fileName: string = prefix + '_' + Date.now() + '.png';
    let filePath: string = dir + '/' + fileName;
    let file: fs.File = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    let packer: image.ImagePacker = image.createImagePacker();
    let packOpts: image.PackingOption = { format: 'image/png', quality: 100 };
    try {
      await packer.packToFile(pm, file.fd, packOpts);
    } finally {
      fs.closeSync(file.fd);
      packer.release();
    }
    return filePath;
  }

  /**
   * 保存 PixelMap 到系统相册。
   * 使用 photoAccessHelper.showAssetsCreationDialog 让用户选择存储位置。
   */
  private async saveToAlbum(): Promise<void> {
    this.isBusy = true;
    let uiCtx: UIContext = this.getUIContext();
    try {
      let pm: image.PixelMap = this.onPmForSave();
      let ctx: common.UIAbilityContext = uiCtx.getHostContext() as common.UIAbilityContext;
      let dir: string = ctx.cacheDir;
      let tmpName: string = 'img_save_' + Date.now() + '.png';
      let tmpPath: string = dir + '/' + tmpName;
      let file: fs.File = fs.openSync(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      let packer: image.ImagePacker = image.createImagePacker();
      let packOpts: image.PackingOption = { format: 'image/png', quality: 100 };
      try {
        await packer.packToFile(pm, file.fd, packOpts);
      } finally {
        fs.closeSync(file.fd);
        packer.release();
      }
      let helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(ctx);
      let srcUri: string = fileUri.getUriFromPath(tmpPath);
      let srcUris: Array<string> = [srcUri];
      let configs: Array<photoAccessHelper.PhotoCreationConfig> = [{
        fileNameExtension: 'png',
        photoType: photoAccessHelper.PhotoType.IMAGE,
      }];
      let desUris: Array<string> = await helper.showAssetsCreationDialog(srcUris, configs);
      if (desUris.length > 0) {
        let src: fs.File = fs.openSync(tmpPath, fs.OpenMode.READ_ONLY);
        let des: fs.File = await fs.open(desUris[0], fs.OpenMode.READ_WRITE);
        await fs.copyFile(src.fd, des.fd);
        fs.closeSync(src);
        await fs.close(des);
        uiCtx.getPromptAction().showToast({ message: '已保存到相册', duration: 1000 });
      }
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[ImageSaveShareBar] saveToAlbum failed: ' + err.code + ' ' + err.message);
      uiCtx.getPromptAction().showToast({ message: '保存失败', duration: 2000 });
    }
    this.isBusy = false;
  }

  /**
   * 将 PixelMap 打包到缓存后通过系统分享面板分享。
   */
  private async shareViaPanel(): Promise<void> {
    this.isBusy = true;
    let uiCtx: UIContext = this.getUIContext();
    try {
      let pm: image.PixelMap = this.onPmForShare();
      let cachePath: string = await this.packToCache(pm, 'img_share');
      let ctx: common.UIAbilityContext = uiCtx.getHostContext() as common.UIAbilityContext;
      let fileUriStr: string = fileUri.getUriFromPath(cachePath);
      let utdTypeId: string = utd.getUniformDataTypeByFilenameExtension('.png', utd.UniformDataType.IMAGE);
      let shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utdTypeId,
        uri: fileUriStr,
      });
      let controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      controller.on('dismiss', () => {
        console.info('[ImageSaveShareBar] share panel closed');
      });
      controller.show(ctx, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE,
      });
    } catch (e) {
      let err: BusinessError = e as BusinessError;
      console.error('[ImageSaveShareBar] shareViaPanel failed: ' + err.code + ' ' + err.message);
      uiCtx.getPromptAction().showToast({ message: '分享失败', duration: 2000 });
    }
    this.isBusy = false;
  }

  build() {
    Row({ space: 10 }) {
      Button('保存图片')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor(this.accentColor)
        .borderRadius(19)
        .height(38)
        .layoutWeight(1)
        .enabled(!this.isBusy)
        .onClick(async () => {
          await this.saveToAlbum();
        })

      Button('分享')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .backgroundColor(this.accentColor)
        .borderRadius(19)
        .height(38)
        .layoutWeight(1)
        .enabled(!this.isBusy)
        .onClick(() => {
          this.shareViaPanel();
        })
    }
    .width('100%')
  }
}
