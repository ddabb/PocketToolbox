import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { generateShareImage, savePixelMapToAlbum, shareImageViaPanel } from '../../common/utils/ShareImageUtil';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

export class ImageExporter {
  static async exportToCache(uiContext: UIContext, componentId: string, prefix: string): Promise<string> {
    return generateShareImage(uiContext, componentId, prefix);
  }

  static async pixelMapToCache(uiContext: UIContext, pixelMap: image.PixelMap, prefix: string): Promise<string> {
    let context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
    let dir: string = context.cacheDir;
    let fileName: string = prefix + '_' + Date.now() + '.png';
    let filePath: string = dir + '/' + fileName;
    try {
      let file: fs.File = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      let packer: image.ImagePacker = image.createImagePacker();
      let packOpts: image.PackingOption = {
        format: 'image/png',
        quality: 100
      };
      try {
        await packer.packToFile(pixelMap, file.fd, packOpts);
      } finally {
        try {
          fs.closeSync(file.fd);
        } catch (closeErr) {
          console.error('[ImageExporter] closeSync failed: ' + (closeErr as BusinessError).message);
        }
        packer.release();
      }
    } catch (e) {
      console.error('[ImageExporter] pixelMapToCache failed: ' + (e as BusinessError).message);
      throw e as Error;
    }
    return filePath;
  }

  static async saveToAlbum(uiContext: UIContext, pixelMap: image.PixelMap): Promise<void> {
    return savePixelMapToAlbum(uiContext, pixelMap);
  }

  static share(uiContext: UIContext, cachePath: string): void {
    shareImageViaPanel(uiContext, cachePath);
  }
}
