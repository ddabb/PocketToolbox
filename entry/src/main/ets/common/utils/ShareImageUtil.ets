import { image } from '@kit.ImageKit';
import { fileIo as fs, WriteOptions } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { IdiomDetailItem } from '../../model/IdiomModels';
import { PoemItem } from '../../model/PoetryModels';
import { XiehouyuItem } from '../../model/XiehouyuModels';

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
    return this.dateStr + ' ' + this.weekday + ' | ' + this.ganzhi + '（' + this.shengxiao + '年）';
  }
}

export function buildIdiomMarkdown(item: IdiomDetailItem): string {
  let md: string = '';
  let dateInfo: DateInfo = new DateInfo();
  md += '> ' + dateInfo.toMarkdownLine() + '\n\n';
  md += '# ' + item.word + '\n\n';
  if (item.pinyin) {
    md += '`' + item.pinyin + '`\n\n';
  }
  if (item.explanation) {
    md += '**释义**\n\n' + item.explanation + '\n\n';
  }
  if (item.derivation) {
    md += '**出处**\n\n' + item.derivation + '\n\n';
  }
  if (item.example) {
    md += '**例句**\n\n' + item.example + '\n\n';
  }
  md += '---\n\n';
  md += '*来自口袋工具箱*\n';
  return md;
}

export function buildPoemMarkdown(item: PoemItem): string {
  let md: string = '';
  let dateInfo: DateInfo = new DateInfo();
  md += '> ' + dateInfo.toMarkdownLine() + '\n\n';
  md += '# ' + item.n + '\n\n';
  let authorLine: string = '';
  if (item.a) {
    authorLine += item.a;
  }
  if (item.d) {
    authorLine += ' \u00B7 ' + item.d;
  }
  if (authorLine) {
    md += '**' + authorLine + '**\n\n';
  }
  if (item.f) {
    md += '`' + item.f + '`\n\n';
  }
  md += item.c + '\n\n';
  md += '---\n\n';
  md += '*来自口袋工具箱*\n';
  return md;
}

export function buildXiehouyuMarkdown(item: XiehouyuItem): string {
  let md: string = '';
  let dateInfo: DateInfo = new DateInfo();
  md += '> ' + dateInfo.toMarkdownLine() + '\n\n';
  md += '# ' + item.riddle + '\n\n';
  md += '**谜底** ' + item.answer + '\n\n';
  md += '---\n\n';
  md += '*来自口袋工具箱*\n';
  return md;
}

export async function generateShareImage(uiContext: UIContext, componentId: string, prefix: string): Promise<string> {
  let snapshot = uiContext.getComponentSnapshot();
  let pixelMap: image.PixelMap = await snapshot.get(componentId);
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
  pixelMap.release();
  return filePath;
}

export async function saveImageToAlbum(uiContext: UIContext, cachePath: string, prefix: string): Promise<void> {
  let docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
  let saveOpts: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
  saveOpts.newFileNames = [prefix + '_' + Date.now() + '.png'];
  let uris: Array<string> = await docPicker.save(saveOpts);
  if (uris.length > 0) {
    let sourceFile: fs.File = fs.openSync(cachePath, fs.OpenMode.READ_ONLY);
    let destFile: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    let buf: ArrayBuffer = new ArrayBuffer(4096);
    let readLen: number = fs.readSync(sourceFile.fd, buf);
    while (readLen > 0) {
      let writeOpts: WriteOptions = { length: readLen };
      fs.writeSync(destFile.fd, buf, writeOpts);
      readLen = fs.readSync(sourceFile.fd, buf);
    }
    fs.closeSync(sourceFile);
    fs.closeSync(destFile);
    uiContext.getPromptAction().showToast({ message: '已保存', duration: 1500 });
  }
}
