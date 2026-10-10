/**
 * 文案海报模板注册表：首期 4 个模板（T1 暖调标签卡 / T2 纯色简约 / T3 文艺手写 / T4 大字冲击）
 * 设计稿宽 900px；导出 1080x1080（1:1）/ 1080x1440（3:4）
 * 需求文档：docs/文案海报生成器需求文档.md §4
 */
import { CoverPalette } from '../../model/CoverModels';
import { CopyPosterTemplate } from '../../model/CopyPosterModels';
import { CoverFont } from './CoverTemplates';

export class CopyPosterTemplates {
  static readonly DESIGN_W: number = 900;
  static readonly EXPORT_W: number = 1080;
  static readonly MAX_BODY: number = 120;
  static readonly MAX_SIGN: number = 12;
  static readonly MAX_TAG: number = 10;

  static all(): CopyPosterTemplate[] {
    let list: CopyPosterTemplate[] = [];

    // ---------- T1 暖调标签卡（示例图同款） ----------
    list.push(CopyPosterTemplate.of('T1', $r('app.string.poster_tmpl_t1'), 'warm_label',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_rice_paper'), '#FAF6EE', '#D8231A', '#1F1F1F', '#8A7E6E',
          '', '#F0E9DC', '#D8231A'),
        CoverPalette.of($r('app.string.tmpl_pal_warm_cream'), '#F7F3EC', '#B45309', '#292524', '#78716C',
          '', '#EFE6D8', '#B45309'),
        CoverPalette.of($r('app.string.tmpl_pal_celadon'), '#EEF3EE', '#2F6B4F', '#22302A', '#7C8B80',
          '', '#E2ECE4', '#2F6B4F'),
        CoverPalette.of($r('app.string.tmpl_pal_ink_night'), '#1C1917', '#F59E0B', '#F5F5F4', '#A8A29E',
          '', '#292524', '#F59E0B'),
        CoverPalette.of($r('app.string.tmpl_pal_sakura'), '#FDF0F0', '#E11D48', '#3F3F46', '#A1A1AA',
          '', '#FBE2E4', '#E11D48'),
      ],
      [CoverFont.WENKAI, CoverFont.HANI_SANS, CoverFont.XIAO_WEI, CoverFont.SERIF, CoverFont.ROUND],
      { 'body': '欢迎来访公众号「木舟居」', 'sign': '请你喝茶呀', 'tag': 'hi 朋友' }));

    // ---------- T2 纯色简约 ----------
    list.push(CopyPosterTemplate.of('T2', $r('app.string.poster_tmpl_t2'), 'pure_minimal',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_serene_blue'), '#EEF3FA', '#2E6FD6', '#1F2937', '#6B7280',
          '', '#E3EBF6', '#2E6FD6'),
        CoverPalette.of($r('app.string.tmpl_pal_true_red'), '#A72F2B', '#F3C98B', '#FDF6EC', '#E8D5C4',
          '', '#8C2622', '#F3C98B'),
        CoverPalette.of($r('app.string.tmpl_pal_graphite'), '#1C1C1E', '#F59E0B', '#F5F5F4', '#A1A1AA',
          '', '#2C2C2E', '#F59E0B'),
        CoverPalette.of($r('app.string.tmpl_pal_mint'), '#E8F5EE', '#059669', '#1F2937', '#6B7280',
          '', '#D8EEE2', '#059669'),
        CoverPalette.of($r('app.string.tmpl_pal_dusk_blue'), '#1E3A8A', '#DBEAFE', '#FFFFFF', '#BFDBFE',
          '', '#172F6E', '#DBEAFE'),
      ],
      [CoverFont.HANI_SANS, CoverFont.XIAO_WEI, CoverFont.WENKAI, CoverFont.ROUND, CoverFont.SMILEY],
      { 'body': '人生是旷野，不是轨道', 'sign': '—— 解语珠玑', 'tag': '' }));

    // ---------- T3 文艺手写 ----------
    list.push(CopyPosterTemplate.of('T3', $r('app.string.poster_tmpl_t3'), 'handwrite',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_rice_paper'), '#FBF7EF', '#8C6A3F', '#3B2F24', '#9C8E79',
          '', '#F1E9D8', '#8C6A3F'),
        CoverPalette.of($r('app.string.tmpl_pal_celadon'), '#EDF2EA', '#5B7553', '#2E3B2C', '#84917B',
          '', '#E0E8DC', '#5B7553'),
        CoverPalette.of($r('app.string.tmpl_pal_warm_brown'), '#F5EBDD', '#A05C2C', '#4A3322', '#A08D74',
          '', '#EADBC6', '#A05C2C'),
        CoverPalette.of($r('app.string.tmpl_pal_ink_night'), '#20242A', '#D9C8A9', '#EFE8D8', '#A79E8C',
          '', '#2B3038', '#D9C8A9'),
        CoverPalette.of($r('app.string.tmpl_pal_moon_gray'), '#F2F2F0', '#6B7280', '#333333', '#9CA3AF',
          '', '#E6E6E2', '#6B7280'),
      ],
      [CoverFont.MA_SHAN, CoverFont.LONG_CANG, CoverFont.ZHI_MANG, CoverFont.WENKAI, CoverFont.FEI_BAI],
      { 'body': '愿你眼里有光，心中有暖', 'sign': '—— 木舟', 'tag': '' }));

    // ---------- T4 大字冲击 ----------
    list.push(CopyPosterTemplate.of('T4', $r('app.string.poster_tmpl_t4'), 'big_impact',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_vivid_yellow'), '#FFD100', '#1F1F1F', '#1F1F1F', '#4A4A4A',
          '', '#E8BC00', '#1F1F1F'),
        CoverPalette.of($r('app.string.tmpl_pal_true_red'), '#D7263D', '#FFFFFF', '#FFFFFF', '#F5C6CE',
          '', '#B01E31', '#FFFFFF'),
        CoverPalette.of($r('app.string.tmpl_pal_dark_green'), '#0B7A4B', '#E9FBEF', '#F0FFF6', '#B7E8C9',
          '', '#085C38', '#E9FBEF'),
        CoverPalette.of($r('app.string.tmpl_pal_ink_night'), '#0F172A', '#38BDF8', '#F1F5F9', '#94A3B8',
          '', '#1E293B', '#38BDF8'),
        CoverPalette.of($r('app.string.tmpl_pal_cherry_pink'), '#DB2777', '#FDF2F8', '#FDF2F8', '#F9C9DE',
          '', '#B01D5E', '#FDF2F8'),
      ],
      [CoverFont.HUANG_YOU, CoverFont.SMILEY, CoverFont.HANI_SANS, CoverFont.XIAO_WEI, CoverFont.KUAI_LE],
      { 'body': '把热爱做到极致', 'sign': '', 'tag': '' }));

    return list;
  }

  static getById(id: string): CopyPosterTemplate {
    let list: CopyPosterTemplate[] = CopyPosterTemplates.all();
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        return list[i];
      }
    }
    return list[0];
  }
}
