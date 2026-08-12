import { UIContext } from '@kit.ArkUI';
import { MarkdownController } from '@luvi/lv-markdown-in';
import { TemplateInfo, Md2PngTemplates } from '../../model/Md2PngModels';

interface FontFileEntry {
  familyName: string;
  fileName: string;
}

export class FontUtil {
  private static registered: Set<string> = new Set<string>();
  private static readonly FONT_FILES: FontFileEntry[] = [
    { familyName: Md2PngTemplates.FONT_SMILEY, fileName: 'font/SmileySans-Oblique.otf' },
    { familyName: Md2PngTemplates.FONT_WENKAI, fileName: 'font/LXGWWenKaiLite-Regular.ttf' },
    { familyName: Md2PngTemplates.FONT_MASHAN, fileName: 'font/MaShanZheng-Regular.ttf' },
    { familyName: Md2PngTemplates.FONT_KUAILE, fileName: 'font/ZCOOLKuaiLe-Regular.ttf' },
    { familyName: Md2PngTemplates.FONT_HUANGYOU, fileName: 'font/ZCOOLQingKeHuangYou-Regular.ttf' },
    { familyName: Md2PngTemplates.FONT_LONGCANG, fileName: 'font/LongCang-Regular.ttf' },
    { familyName: Md2PngTemplates.FONT_MAOMAO, fileName: 'font/LiuJianMaoCao-Regular.ttf' },
    { familyName: Md2PngTemplates.FONT_XIAOWEI, fileName: 'font/ZCOOLXiaoWei-Regular.ttf' },
    { familyName: Md2PngTemplates.FONT_ZHIMANG, fileName: 'font/ZhiMangXing-Regular.ttf' },
    { familyName: Md2PngTemplates.FONT_SOURCE_HAN_SANS, fileName: 'font/SourceHanSansSC-Regular.ttf' },
    { familyName: Md2PngTemplates.FONT_SOURCE_HAN_SERIF, fileName: 'font/SourceHanSerifCN-Regular.otf' },
    { familyName: Md2PngTemplates.FONT_CHILL_CHUNQIU, fileName: 'font/ChillCalligraphyChunQiu_ChenFeng.ttf' },
    { familyName: Md2PngTemplates.FONT_CHILL_ROUND, fileName: 'font/ChillRoundF.ttf' },
    { familyName: Md2PngTemplates.FONT_TSANGER_FEIBAI, fileName: 'font/TsangerFeiBaiW03.ttf' },
    { familyName: Md2PngTemplates.FONT_TSANGER_XWZ, fileName: 'font/TsangerXWZ.ttf' },
  ];

  static registerAll(uiCtx: UIContext): void {
    let font = uiCtx.getFont();
    for (let i = 0; i < FontUtil.FONT_FILES.length; i++) {
      let entry: FontFileEntry = FontUtil.FONT_FILES[i];
      if (FontUtil.registered.has(entry.familyName)) {
        continue;
      }
      try {
        font.registerFont({
          familyName: entry.familyName,
          familySrc: $rawfile(entry.fileName)
        });
        FontUtil.registered.add(entry.familyName);
      } catch (e) {
        console.error('[FontUtil] register failed: ' + entry.familyName + ' ' + (e as Error).message);
      }
    }
  }

  static applyFonts(controller: MarkdownController, tpl: TemplateInfo): void {
    if (tpl.titleFont && tpl.titleFont.length > 0) {
      let titleFonts: [ResourceStr, ResourceStr, ResourceStr, ResourceStr, ResourceStr, ResourceStr] = [
        tpl.titleFont, tpl.titleFont, tpl.titleFont, tpl.titleFont, tpl.titleFont, tpl.titleFont
      ];
      controller.setTitleFontFamily(titleFonts);
    }
    if (tpl.textFont && tpl.textFont.length > 0) {
      controller.setTextFontFamily(tpl.textFont);
    }
  }
}
