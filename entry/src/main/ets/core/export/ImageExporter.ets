import { image } from '@kit.ImageKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { generateShareImage, saveImageToAlbum, shareImageViaPanel } from '../../common/utils/ShareImageUtil';

export class ImageExporter {
  static async exportToCache(uiContext: UIContext, componentId: string, prefix: string): Promise<string> {
    return generateShareImage(uiContext, componentId, prefix);
  }

  static async pixelMapToCache(uiContext: UIContext, pixelMap: image.PixelMap, prefix: string): Promise<string> {
    let packer: image.ImagePacker = image.createImagePacker();
    let packOpts: image.PackingOption = {
      format: 'image/png',
      quality: 100
    };
    let arrayBuffer: ArrayBuffer = await packer.packing(pixelMap, packOpts);
    let context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
    let dir: string = context.cacheDir;
    let fileName: string = prefix + '_' + Date.now() + '.png';
    let filePath: string = dir + '/' + fileName;
    let file: fs.File = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, arrayBuffer);
    fs.closeSync(file);
    packer.release();
    return filePath;
  }

  static async saveToAlbum(uiContext: UIContext, cachePath: string, prefix: string): Promise<void> {
    return saveImageToAlbum(uiContext, cachePath, prefix);
  }

  static share(uiContext: UIContext, cachePath: string): void {
    shareImageViaPanel(uiContext, cachePath);
  }
}
