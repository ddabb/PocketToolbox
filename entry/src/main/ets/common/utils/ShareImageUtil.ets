import { image } from '@kit.ImageKit';
import { fileIo as fs, WriteOptions, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { IdiomDetailItem } from '../../model/IdiomModels';
import { PoemItem } from '../../model/PoetryModels';
import { XiehouyuItem } from '../../model/XiehouyuModels';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { ToastUtil } from './ToastUtil';

const WEEKDAYS: string[] = ['日', '一', '二', '三', '四', '五', '六'];
const TIANGAN: string[] = ['甲', '乙', '丙', '丁', '戊', '己', '庚', '辛', '壬', '癸'];
const DIZHI: string[] = ['子', '丑', '寅', '卯', '辰', '巳', '午', '未', '申', '酉', '戌', '亥'];
const SHENGXIAO: string[] = ['鼠', '牛', '虎', '兔', '龙', '蛇', '马', '羊', '猴', '鸡', '狗', '猪'];

export class DateInfo {
  dateStr: string = '';
  weekday: string = '';
  ganzhi: string = '';
  shengxiao: string = '';

  constructor() {
    let now: Date = new Date();
    let y: number = now.getFullYear();
    let m: number = now.getMonth() + 1;
    let d: number = now.getDate();
    let w: number = now.getDay();
    this.dateStr = y.toString() + '年' + m.toString() + '月' + d.toString() + '日';
    this.weekday = '星期' + WEEKDAYS[w];
    let gzIdx: number = (y - 4) % 60;
    let tgIdx: number = gzIdx % 10;
    let dzIdx: number = gzIdx % 12;
    this.ganzhi = TIANGAN[tgIdx] + DIZHI[dzIdx] + '年';
    this.shengxiao = SHENGXIAO[dzIdx];
  }

  toMarkdownLine(): string {
    return this.dateStr + ' ' + this.weekday + ' | ' + this.ganzhi;
  }
}

export function buildIdiomMarkdown(item: IdiomDetailItem): string {
  let md: string = '';
  let dateInfo: DateInfo = new DateInfo();
  md += '# **' + item.word + '**\n\n';
  if (item.pinyin) {
    md += '`' + item.pinyin + '`\n\n';
  }
  md += '---\n\n';
  if (item.explanation) {
    md += '> **释义**　' + item.explanation + '\n\n';
  }
  if (item.derivation) {
    md += '> **出处**　' + item.derivation + '\n\n';
  }
  if (item.example) {
    md += '> **例句**　' + item.example + '\n\n';
  }
  md += '---\n\n';
  md += '*解语珠玑　·　成语词典*\n\n';
  md += '*' + dateInfo.toMarkdownLine() + '*\n';
  return md;
}

export function buildPoemMarkdown(item: PoemItem): string {
  let md: string = '';
  let dateInfo: DateInfo = new DateInfo();
  md += '# **' + item.n + '**\n\n';
  let authorLine: string = '';
  if (item.a) {
    authorLine += item.a;
  }
  if (item.d) {
    authorLine += ' \u00B7 ' + item.d;
  }
  if (authorLine) {
    md += '***' + authorLine + '***\n\n';
  }
  if (item.f) {
    md += '`' + item.f + '`\n\n';
  }
  md += item.c + '\n\n';
  md += '---\n\n';
  md += '*诗词鉴赏 · 解语珠玑*\n\n';
  md += '*' + dateInfo.toMarkdownLine() + '*\n';
  return md;
}

export function buildXiehouyuMarkdown(item: XiehouyuItem): string {
  let md: string = '';
  let dateInfo: DateInfo = new DateInfo();
  md += '# **' + item.riddle + '**\n\n';
  md += '***' + item.answer + '***\n\n';
  md += '---\n\n';
  md += '*趣味歇后语 · 解语珠玑*\n\n';
  md += '*' + dateInfo.toMarkdownLine() + '*\n';
  return md;
}

export async function generateShareImage(uiContext: UIContext, componentId: string, prefix: string): Promise<string> {
  try {
    let snapshot = uiContext.getComponentSnapshot();
    let pixelMap: image.PixelMap = await snapshot.get(componentId, { scale: 2, waitUntilRenderFinished: true });
    let packer: image.ImagePacker = image.createImagePacker();
    let packOpts: image.PackingOption = {
      format: 'image/png',
      quality: 100
    };
    let context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
    let dir: string = context.cacheDir;
    let fileName: string = prefix + '_' + Date.now() + '.png';
    let filePath: string = dir + '/' + fileName;
    let file: fs.File = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      await packer.packToFile(pixelMap, file.fd, packOpts);
    } finally {
      try {
        fs.closeSync(file.fd);
      } catch (closeErr) {
        console.error('[ShareUtil] closeSync failed: ' + (closeErr as BusinessError).message);
      }
      packer.release();
      pixelMap.release();
    }
    return file.path;
  } catch (e) {
    console.error('[ShareUtil] generateShareImage failed: ' + (e as BusinessError).message);
    throw e as Error;
  }
}

/**
 * 保存单张 PixelMap 到系统相册（经保存确认弹窗）。
 * 返回 true=已保存；false=用户在弹窗中取消；失败抛出异常。
 */
export async function savePixelMapToAlbum(uiContext: UIContext, pixelMap: image.PixelMap): Promise<boolean> {
  let context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
  let dir: string = context.cacheDir;
  let fileName: string = 'save_tmp_' + Date.now().toString(36) + '.png';
  let filePath: string = dir + '/' + fileName;
  let packer: image.ImagePacker = image.createImagePacker();
  let packOpts: image.PackingOption = { format: 'image/png', quality: 100 };
  let file: fs.File;
  try {
    file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  } catch (e) {
    packer.release();
    console.error('[ShareImage] openSync failed: ' + (e as BusinessError).message);
    return false;
  }
  try {
    await packer.packToFile(pixelMap, file.fd, packOpts);
  } catch (e) {
    console.error('[ShareImage] packToFile failed: ' + (e as BusinessError).message);
    try {
      fs.closeSync(file.fd);
    } catch (_) {
    }
    packer.release();
    return false;
  }
  try {
    fs.closeSync(file.fd);
  } catch (e) {
    console.error('[ShareImage] closeSync failed: ' + (e as BusinessError).message);
  }
  packer.release();
  return await saveFilesToAlbum(uiContext, [filePath]) > 0;
}

/**
 * 批量保存多张沙箱图片文件到系统相册：单次保存确认弹窗处理全部文件。
 * 返回实际保存张数；用户取消返回 0；失败抛出异常。
 */
export async function saveFilesToAlbum(uiContext: UIContext, filePaths: string[]): Promise<number> {
  let context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
  let helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
  if (helper === undefined) {
    console.error('[ShareUtil] saveFilesToAlbum failed: getPhotoAccessHelper returned undefined');
    throw new Error('系统相册服务不可用');
  }
  let srcFileUris: string[] = [];
  let photoCreationConfigs: Array<photoAccessHelper.PhotoCreationConfig> = [];
  for (let i = 0; i < filePaths.length; i++) {
    srcFileUris.push(fileUri.getUriFromPath(filePaths[i]));
    photoCreationConfigs.push({
      fileNameExtension: 'png',
      photoType: photoAccessHelper.PhotoType.IMAGE,
    });
  }
  let desFileUris: Array<string>;
  try {
    desFileUris = await helper.showAssetsCreationDialog(srcFileUris, photoCreationConfigs);
  } catch (e) {
    console.error('[ShareImage] showAssetsCreationDialog failed: ' + (e as BusinessError).message);
    return 0;
  }
  let saved: number = 0;
  if (desFileUris.length > 0) {
    for (let i = 0; i < desFileUris.length && i < filePaths.length; i++) {
      let srcFile: fs.File;
      try {
        srcFile = fs.openSync(filePaths[i], fs.OpenMode.READ_ONLY);
      } catch (e) {
        console.error('[ShareImage] openSync srcFile failed: ' + (e as BusinessError).message);
        continue;
      }
      try {
        let desFile: fs.File;
        try {
          desFile = await fs.open(desFileUris[i], fs.OpenMode.READ_WRITE);
        } catch (e) {
          console.error('[ShareImage] open desFile failed: ' + (e as BusinessError).message);
          try {
            fs.closeSync(srcFile.fd);
          } catch (_) {
          }
          continue;
        }
        try {
          await fs.copyFile(srcFile.fd, desFile.fd);
          saved++;
        } catch (e) {
          console.error('[ShareImage] copyFile failed: ' + (e as BusinessError).message);
        } finally {
          try {
            await fs.close(desFile);
          } catch (e) {
            console.error('[ShareImage] close desFile failed: ' + (e as BusinessError).message);
          }
        }
      } finally {
        try {
          fs.closeSync(srcFile.fd);
        } catch (e) {
          console.error('[ShareImage] closeSync srcFile failed: ' + (e as BusinessError).message);
        }
      }
    }
  }
  return saved;
}

export function shareImageViaPanel(uiContext: UIContext, cachePath: string): void {
  try {
    let context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
    let fileUriStr: string = fileUri.getUriFromPath(cachePath);
    let utdTypeId: string = utd.getUniformDataTypeByFilenameExtension('.png', utd.UniformDataType.IMAGE);
    let shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: utdTypeId,
      uri: fileUriStr,
    });
    let controller: systemShare.ShareController = new systemShare.ShareController(shareData);
    controller.on('dismiss', () => {
      console.info('[ShareUtil] share panel closed');
    });
    controller.show(context, {
      previewMode: systemShare.SharePreviewMode.DETAIL,
      selectionMode: systemShare.SelectionMode.SINGLE,
    });
  } catch (e) {
    let err: BusinessError = e as BusinessError;
    console.error('[ShareUtil] shareViaPanel failed: ' + err.code + ' ' + err.message);
    ToastUtil.show(uiContext, '分享失败', 2000);
  }
}

export function shareGifViaPanel(uiContext: UIContext, cachePath: string): void {
  try {
    let context: common.UIAbilityContext = uiContext.getHostContext() as common.UIAbilityContext;
    let fileUriStr: string = fileUri.getUriFromPath(cachePath);
    let utdTypeId: string = utd.getUniformDataTypeByFilenameExtension('.gif', utd.UniformDataType.IMAGE);
    let shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: utdTypeId,
      uri: fileUriStr,
    });
    let controller: systemShare.ShareController = new systemShare.ShareController(shareData);
    controller.on('dismiss', () => {
      console.info('[ShareUtil] gif share panel closed');
    });
    controller.show(context, {
      previewMode: systemShare.SharePreviewMode.DETAIL,
      selectionMode: systemShare.SelectionMode.SINGLE,
    });
  } catch (e) {
    let err: BusinessError = e as BusinessError;
    console.error('[ShareUtil] shareGifViaPanel failed: ' + err.code + ' ' + err.message);
    ToastUtil.show(uiContext, '分享失败', 2000);
  }
}
