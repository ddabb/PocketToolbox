import { generateShareImage, saveImageToAlbum, shareImageViaPanel } from '../../common/utils/ShareImageUtil';

export class ImageExporter {
  static async exportToCache(uiContext: UIContext, componentId: string, prefix: string): Promise<string> {
    return generateShareImage(uiContext, componentId, prefix);
  }

  static async saveToAlbum(uiContext: UIContext, cachePath: string, prefix: string): Promise<void> {
    return saveImageToAlbum(uiContext, cachePath, prefix);
  }

  static share(uiContext: UIContext, cachePath: string): void {
    shareImageViaPanel(uiContext, cachePath);
  }
}
