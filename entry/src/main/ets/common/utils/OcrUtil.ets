import { textRecognition } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';

export class OcrUtil {
  static async recognizeLines(pixelMap: image.PixelMap): Promise<string[]> {
    await textRecognition.init();
    try {
      let visionInfo: textRecognition.VisionInfo = { pixelMap: pixelMap };
      let result: textRecognition.TextRecognitionResult =
        await textRecognition.recognizeText(visionInfo);
      let lines: string[] = [];
      let seen: Set<string> = new Set<string>();
      let blocks: Array<textRecognition.TextBlock> = result.blocks || [];
      for (let bi = 0; bi < blocks.length; bi++) {
        let blockLines: Array<textRecognition.TextLine> = blocks[bi].lines || [];
        for (let li = 0; li < blockLines.length; li++) {
          let value: string = (blockLines[li].value || '').trim();
          if (value.length < 2 || value.length > 40) {
            continue;
          }
          if (seen.has(value)) {
            continue;
          }
          seen.add(value);
          lines.push(value);
          if (lines.length >= 20) {
            return lines;
          }
        }
      }
      return lines;
    } catch (e) {
      console.error('[OcrUtil] recognizeText failed: ' + (e as Error).message);
      throw new Error((e as Error).message);
    } finally {
      textRecognition.release().catch((): void => {
      });
    }
  }
}
