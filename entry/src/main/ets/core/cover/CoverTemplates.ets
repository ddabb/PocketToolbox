/**
 * 公众号首图模板注册表：5 系列 15 个模板（首版，E1 相册底图放 P1 后续补）
 */
import { CoverPalette, CoverTemplate } from '../../model/CoverModels';

export class CoverFont {
  static readonly HANI_SANS: string = 'SourceHanSansSC';
  static readonly WENKAI: string = 'LXGWWenKai';
  static readonly MA_SHAN: string = 'MaShanZheng';
  static readonly XIAO_WEI: string = 'ZCOOLXiaoWei';
  static readonly HUANG_YOU: string = 'ZCOOLQingKeHuangYou';
  static readonly KUAI_LE: string = 'ZCOOLKuaiLe';
  static readonly SMILEY: string = 'SmileySans-Oblique';
  static readonly LONG_CANG: string = 'LongCang';
  static readonly ZHI_MANG: string = 'ZhiMangXing';
  static readonly MAO_CAO: string = 'LiuJianMaoCao';
  static readonly ROUND: string = 'ChillRound';
  static readonly SERIF: string = 'SourceHanSerifCN';
  static readonly FEI_BAI: string = 'TsangerFeiBai';
  static readonly CHUN_QIU: string = 'ChillCalligraphyChunQiu';

  static label(family: string): string {
    if (family === CoverFont.HANI_SANS) {
      return '思源黑体';
    } else if (family === CoverFont.WENKAI) {
      return '霞鹜文楷';
    } else if (family === CoverFont.MA_SHAN) {
      return '马善政楷书';
    } else if (family === CoverFont.XIAO_WEI) {
      return '站酷小薇';
    } else if (family === CoverFont.HUANG_YOU) {
      return '站酷庆科黄油';
    } else if (family === CoverFont.KUAI_LE) {
      return '站酷快乐体';
    } else if (family === CoverFont.SMILEY) {
      return '得意黑';
    } else if (family === CoverFont.LONG_CANG) {
      return '龙藏体';
    } else if (family === CoverFont.ZHI_MANG) {
      return '智麻行书';
    } else if (family === CoverFont.MAO_CAO) {
      return '柳建毛草';
    } else if (family === CoverFont.ROUND) {
      return '圆润体';
    } else if (family === CoverFont.SERIF) {
      return '思源宋体';
    } else if (family === CoverFont.FEI_BAI) {
      return '仓耳飞白';
    } else if (family === CoverFont.CHUN_QIU) {
      return '春秋楚风';
    }
    return family;
  }
}

export class CoverSeries {
  static readonly ALL: string = 'all';
  static readonly SIMPLE: string = 'simple';
  static readonly CULTURE: string = 'culture';
  static readonly BIG: string = 'big';
  static readonly MAGAZINE: string = 'magazine';
  static readonly PHOTO: string = 'photo';

  static all(): string[] {
    return [CoverSeries.ALL, CoverSeries.SIMPLE, CoverSeries.CULTURE, CoverSeries.BIG,
      CoverSeries.MAGAZINE, CoverSeries.PHOTO];
  }

  static label(series: string): ResourceStr {
    if (series === CoverSeries.ALL) {
      return $r('app.string.tmpl_series_all');
    } else if (series === CoverSeries.SIMPLE) {
      return $r('app.string.tmpl_series_simple');
    } else if (series === CoverSeries.CULTURE) {
      return $r('app.string.tmpl_series_culture');
    } else if (series === CoverSeries.BIG) {
      return $r('app.string.tmpl_series_big');
    } else if (series === CoverSeries.MAGAZINE) {
      return $r('app.string.tmpl_series_magazine');
    } else if (series === CoverSeries.PHOTO) {
      return $r('app.string.tmpl_series_photo');
    }
    return series;
  }
}

export class CoverTemplates {
  static getAll(): CoverTemplate[] {
    let list: CoverTemplate[] = [];
    // ---------- A 系列 · 简约文字 ----------
    list.push(CoverTemplate.of('A1', $r('app.string.tmpl_name_solid'), CoverSeries.SIMPLE, 'a1_center',
      ['title', 'subtitle'], $r('app.string.cover_slot_title'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_serene_blue'), '#EEF3FA', '#2E6FD6', '#1F2937', '#6B7280'),
        CoverPalette.of($r('app.string.tmpl_pal_warm_cream'), '#F7F3EC', '#B45309', '#292524', '#78716C'),
        CoverPalette.of($r('app.string.tmpl_pal_mint'), '#E8F5EE', '#059669', '#1F2937', '#6B7280'),
        CoverPalette.of($r('app.string.tmpl_pal_graphite'), '#1C1C1E', '#F59E0B', '#F5F5F4', '#A1A1AA'),
        CoverPalette.of($r('app.string.tmpl_pal_sakura'), '#FDF0F0', '#E11D48', '#3F3F46', '#A1A1AA'),
      ],
      [CoverFont.HANI_SANS, CoverFont.XIAO_WEI, CoverFont.WENKAI, CoverFont.ROUND, CoverFont.SMILEY],
      '',
      { 'title': '把热爱做到极致', 'subtitle': '每周一更 · 深度长文' }));

    list.push(CoverTemplate.of('A2', $r('app.string.tmpl_name_gradient'), CoverSeries.SIMPLE, 'a2_gradient_left',
      ['title', 'subtitle', 'author'], $r('app.string.cover_slot_title'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_amber'), '#FFF7ED', '#C2410C', '#431407', '#9A3412', '#FED7AA'),
        CoverPalette.of($r('app.string.tmpl_pal_green_hill'), '#D1FAE5', '#047857', '#064E3B', '#047857', '#A7F3D0'),
        CoverPalette.of($r('app.string.tmpl_pal_dusk_blue'), '#1E3A8A', '#DBEAFE', '#FFFFFF', '#BFDBFE', '#3B82F6'),
        CoverPalette.of($r('app.string.tmpl_pal_rose'), '#FDF2F8', '#BE185D', '#500724', '#9D174D', '#FBCFE8'),
        CoverPalette.of($r('app.string.tmpl_pal_ink_night'), '#0F172A', '#38BDF8', '#F1F5F9', '#94A3B8', '#1E293B'),
      ],
      [CoverFont.XIAO_WEI, CoverFont.WENKAI, CoverFont.HANI_SANS, CoverFont.ROUND, CoverFont.HUANG_YOU],
      '',
      { 'title': '人生是旷野', 'subtitle': '不是轨道', 'author': '解语珠玑' }));

    list.push(CoverTemplate.of('A3', $r('app.string.tmpl_name_neon_night'), CoverSeries.SIMPLE, 'a3_neon',
      ['title', 'subtitle', 'author'], $r('app.string.cover_slot_title'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_neon_purple'), '#0F0A1E', '#A855F7', '#C084FC', '#9CA3AF'),
        CoverPalette.of($r('app.string.tmpl_pal_electric_cyan'), '#041F24', '#22D3EE', '#67E8F9', '#94A3B8'),
        CoverPalette.of($r('app.string.tmpl_pal_neon_pink'), '#1A0A14', '#F472B6', '#F9A8D4', '#9CA3AF'),
        CoverPalette.of($r('app.string.tmpl_pal_neon_green'), '#0A1A0A', '#4ADE80', '#86EFAC', '#94A3B8'),
        CoverPalette.of($r('app.string.tmpl_pal_dark_gold'), '#141008', '#FBBF24', '#FCD34D', '#A8A29E'),
      ],
      [CoverFont.HANI_SANS, CoverFont.SMILEY, CoverFont.HUANG_YOU, CoverFont.WENKAI, CoverFont.ROUND],
      '',
      { 'title': '未来已来', 'subtitle': 'THE FUTURE IS NOW', 'author': '解语珠玑' }));

    // ---------- B 系列 · 文化内容 ----------
    list.push(CoverTemplate.of('B1', $r('app.string.tmpl_name_poetic'), CoverSeries.CULTURE, 'b1_poem_vertical',
      ['quote', 'quoteSource', 'author', 'seal'], $r('app.string.cover_slot_title'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_rice_paper'), '#F5F0E6', '#8C6A3F', '#3D3226', '#8C7B66', '', '', '#C0392B'),
        CoverPalette.of($r('app.string.tmpl_pal_pale_cyan'), '#EAF2EF', '#4A7C6F', '#2F4F45', '#6B857C', '', '', '#B03A2E'),
        CoverPalette.of($r('app.string.tmpl_pal_moon_white'), '#F2F4F7', '#5B7A9E', '#2C3E50', '#7F8C9B', '', '', '#B03A2E'),
        CoverPalette.of($r('app.string.tmpl_pal_dusk_purple'), '#EFE9F5', '#6D5B8F', '#3E3554', '#7D7292', '', '', '#A93226'),
        CoverPalette.of($r('app.string.tmpl_pal_ink'), '#1E1E1C', '#D4C5A0', '#EDE6D6', '#A69E8C', '', '', '#C0392B'),
      ],
      [CoverFont.MA_SHAN, CoverFont.WENKAI, CoverFont.ZHI_MANG, CoverFont.LONG_CANG, CoverFont.SERIF],
      'poem',
      { 'quote': '海上生明月', 'quoteSource': '《望月怀远》·张九龄', 'seal': '珠玑' }));

    list.push(CoverTemplate.of('B2', $r('app.string.tmpl_name_idiom'), CoverSeries.CULTURE, 'b2_idiom',
      ['quote', 'subtitle', 'quoteSource'], $r('app.string.cover_slot_title'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_pale_cyan'), '#E8F1F2', '#2C7A7B', '#1D3B3C', '#5E7C7D', '', '', '#C0392B'),
        CoverPalette.of($r('app.string.tmpl_pal_beige'), '#F7F1E3', '#A16207', '#3F3421', '#8A7B5C'),
        CoverPalette.of($r('app.string.tmpl_pal_crimson'), '#FBEBEB', '#B03A2E', '#5C1F1A', '#A1887F'),
        CoverPalette.of($r('app.string.tmpl_pal_indigo'), '#E9EEF6', '#2F4B7C', '#22344F', '#5D7290'),
      ],
      [CoverFont.WENKAI, CoverFont.MA_SHAN, CoverFont.XIAO_WEI, CoverFont.SERIF, CoverFont.ZHI_MANG],
      'idiom',
      { 'quote': '守株待兔', 'subtitle': '比喻死守狭隘经验，不知变通', 'quoteSource': '《韩非子·五蠹》' }));

    list.push(CoverTemplate.of('B3', $r('app.string.tmpl_name_xiehouyu'), CoverSeries.CULTURE, 'b3_xiehouyu',
      ['quote', 'subtitle', 'author'], $r('app.string.cover_slot_title'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_bright_yellow'), '#FDE68A', '#D97706', '#431407', '#92400E'),
        CoverPalette.of($r('app.string.tmpl_pal_warm_orange'), '#FFEDD5', '#EA580C', '#431407', '#9A3412'),
        CoverPalette.of($r('app.string.tmpl_pal_sky_blue'), '#DBEAFE', '#2563EB', '#1E3A5F', '#3B82F6'),
        CoverPalette.of($r('app.string.tmpl_pal_grass_green'), '#DCFCE7', '#16A34A', '#14532D', '#15803D'),
        CoverPalette.of($r('app.string.tmpl_pal_cherry_pink'), '#FCE7F3', '#DB2777', '#500724', '#9D174D'),
      ],
      [CoverFont.HUANG_YOU, CoverFont.KUAI_LE, CoverFont.SMILEY, CoverFont.ROUND, CoverFont.WENKAI],
      'xiehouyu',
      { 'quote': '外甥打灯笼', 'subtitle': '照旧（舅）' }));

    list.push(CoverTemplate.of('B4', $r('app.string.tmpl_name_solar'), CoverSeries.CULTURE, 'b4_solar',
      ['title', 'quote', 'quoteSource', 'issue'], $r('app.string.tmpl_slot_solar_name'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_spring'), '#D1FAE5', '#047857', '#065F46', '#059669', '#A7F3D0', '', '#B03A2E'),
        CoverPalette.of($r('app.string.tmpl_pal_summer'), '#CCFBF1', '#0D9488', '#134E4A', '#0F766E', '#99F6E4', '', '#B03A2E'),
        CoverPalette.of($r('app.string.tmpl_pal_autumn'), '#FFEDD5', '#C2410C', '#431407', '#9A3412', '#FED7AA', '', '#B03A2E'),
        CoverPalette.of($r('app.string.tmpl_pal_winter'), '#E0F2FE', '#0284C7', '#0C4A6E', '#0369A1', '#BAE6FD', '', '#B03A2E'),
        CoverPalette.of($r('app.string.tmpl_pal_plum'), '#FCE7F3', '#BE185D', '#500724', '#9D174D', '#FBCFE8', '', '#B03A2E'),
      ],
      [CoverFont.ZHI_MANG, CoverFont.MA_SHAN, CoverFont.WENKAI, CoverFont.LONG_CANG, CoverFont.XIAO_WEI],
      'poem',
      { 'title': '白露', 'quote': '露从今夜白，月是故乡明', 'quoteSource': '《月夜忆舍弟》·杜甫', 'issue': '' }));

    list.push(CoverTemplate.of('B5', $r('app.string.tmpl_name_grid_card'), CoverSeries.CULTURE, 'b5_grid',
      ['title', 'pinyin'], $r('app.string.tmpl_slot_chars'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_blue_red'), '#2E6FD6', '#2E6FD6', '#000000', '#000000', '', '', '#D8231A'),
        CoverPalette.of($r('app.string.tmpl_pal_cream_red_black'), '#F7F3EC', '#F7F3EC', '#1F2937', '#1F2937', '', '', '#D8231A'),
        CoverPalette.of($r('app.string.tmpl_pal_dark_green_red'), '#14532D', '#14532D', '#D8231A', '#D8231A', '', '', '#F5EFE0'),
        CoverPalette.of($r('app.string.tmpl_pal_dark_red_black'), '#A93226', '#A93226', '#111111', '#111111', '', '', '#F5EFE0'),
      ],
      [CoverFont.WENKAI, CoverFont.MA_SHAN, CoverFont.SERIF],
      '',
      { 'title': '学而时习之', 'pinyin': '' }));

    // ---------- C 系列 · 大字冲击 ----------
    list.push(CoverTemplate.of('C1', $r('app.string.tmpl_name_big_type'), CoverSeries.BIG, 'c1_poster',
      ['title'], $r('app.string.tmpl_slot_big_title'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_true_red'), '#DC2626', '#DC2626', '#FFF7ED', '#FECACA'),
        CoverPalette.of($r('app.string.tmpl_pal_vivid_yellow'), '#FACC15', '#FACC15', '#422006', '#A16207'),
        CoverPalette.of($r('app.string.tmpl_pal_emerald'), '#16A34A', '#16A34A', '#F0FDF4', '#BBF7D0'),
        CoverPalette.of($r('app.string.tmpl_pal_royal_blue'), '#2563EB', '#2563EB', '#EFF6FF', '#BFDBFE'),
        CoverPalette.of($r('app.string.tmpl_pal_pure_black'), '#111111', '#111111', '#FAFAFA', '#A3A3A3'),
      ],
      [CoverFont.HUANG_YOU, CoverFont.SMILEY, CoverFont.KUAI_LE, CoverFont.HANI_SANS, CoverFont.ROUND],
      '',
      { 'title': '深度好文' }));

    list.push(CoverTemplate.of('C2', $r('app.string.tmpl_name_issue_number'), CoverSeries.BIG, 'c2_number',
      ['issue', 'title', 'author'], $r('app.string.cover_slot_title'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_navy'), '#F8FAFC', '#1E3A8A', '#334155', '#94A3B8'),
        CoverPalette.of($r('app.string.tmpl_pal_dark_night'), '#0F172A', '#38BDF8', '#E2E8F0', '#64748B'),
        CoverPalette.of($r('app.string.tmpl_pal_cream'), '#F7F3EC', '#B45309', '#292524', '#A8A29E'),
        CoverPalette.of($r('app.string.tmpl_pal_wine'), '#FDF2F2', '#B91C1C', '#44403C', '#A8A29E'),
      ],
      [CoverFont.HANI_SANS, CoverFont.XIAO_WEI, CoverFont.SMILEY, CoverFont.WENKAI, CoverFont.ROUND],
      '',
      { 'issue': '42', 'title': '产品沉思录', 'author': '解语珠玑' }));

    list.push(CoverTemplate.of('C3', $r('app.string.tmpl_name_question'), CoverSeries.BIG, 'c3_question',
      ['title', 'author'], $r('app.string.tmpl_slot_question_title'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_ink_blue'), '#16213E', '#E94560', '#EAEAEA', '#8892B0'),
        CoverPalette.of($r('app.string.tmpl_pal_charcoal'), '#191919', '#F59E0B', '#F5F5F5', '#737373'),
        CoverPalette.of($r('app.string.tmpl_pal_deep_purple'), '#2D1B4E', '#E879F9', '#F5F3FF', '#8B7BB8'),
        CoverPalette.of($r('app.string.tmpl_pal_dark_green'), '#12291E', '#34D399', '#ECFDF5', '#6B9E85'),
      ],
      [CoverFont.LONG_CANG, CoverFont.ZHI_MANG, CoverFont.MA_SHAN, CoverFont.WENKAI, CoverFont.MAO_CAO],
      '',
      { 'title': '为什么你总是焦虑', 'author': '解语珠玑' }));

    // ---------- D 系列 · 杂志设计 ----------
    list.push(CoverTemplate.of('D1', $r('app.string.tmpl_name_geoblock'), CoverSeries.MAGAZINE, 'd1_geoblock',
      ['title', 'subtitle', 'author'], $r('app.string.cover_slot_title'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_clash_yellow'), '#FAF9F6', '#111111', '#111111', '#57534E', '', '#FACC15'),
        CoverPalette.of($r('app.string.tmpl_pal_clash_blue'), '#F8FAFC', '#FFFFFF', '#FFFFFF', '#DBEAFE', '', '#2563EB'),
        CoverPalette.of($r('app.string.tmpl_pal_clash_red'), '#FAF7F5', '#FFFFFF', '#FFF7ED', '#FECACA', '', '#DC2626'),
        CoverPalette.of($r('app.string.tmpl_pal_clash_green'), '#F7FAF7', '#FFFFFF', '#ECFDF5', '#A7F3D0', '', '#059669'),
        CoverPalette.of($r('app.string.tmpl_pal_mono'), '#FFFFFF', '#FFFFFF', '#FAFAFA', '#A3A3A3', '', '#111111'),
      ],
      [CoverFont.HANI_SANS, CoverFont.XIAO_WEI, CoverFont.WENKAI, CoverFont.ROUND, CoverFont.FEI_BAI],
      '',
      { 'title': '城市漫游指南', 'subtitle': 'VOL.07', 'author': '解语珠玑' }));

    list.push(CoverTemplate.of('D2', $r('app.string.tmpl_name_twocolumn'), CoverSeries.MAGAZINE, 'd2_twocolumn',
      ['title', 'subtitle', 'author', 'issue'], $r('app.string.cover_slot_title'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_red_black'), '#FAF7F2', '#A31621', '#1F1F1F', '#F5EFE6', '', '#A31621'),
        CoverPalette.of($r('app.string.tmpl_pal_navy_blue'), '#F8FAFC', '#1E3A8A', '#1E293B', '#DBEAFE', '', '#1E3A8A'),
        CoverPalette.of($r('app.string.tmpl_pal_forest_green'), '#F5F8F6', '#14532D', '#1F2937', '#D1FAE5', '', '#14532D'),
        CoverPalette.of($r('app.string.tmpl_pal_warm_brown'), '#FAF6F0', '#78350F', '#292524', '#FDE68A', '', '#78350F'),
      ],
      [CoverFont.XIAO_WEI, CoverFont.SERIF, CoverFont.WENKAI, CoverFont.FEI_BAI, CoverFont.ZHI_MANG],
      '',
      { 'author': '珠玑月刊', 'issue': '第 7 期', 'title': '在文字里寻找答案', 'subtitle': '本期关键词：阅读、写作与表达' }));

    list.push(CoverTemplate.of('D3', $r('app.string.tmpl_name_seal'), CoverSeries.MAGAZINE, 'd3_seal',
      ['title', 'subtitle', 'seal', 'author'], $r('app.string.cover_slot_title'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_plain_white'), '#FFFFFF', '#111111', '#1F1F1F', '#6B7280', '', '', '#C0392B'),
        CoverPalette.of($r('app.string.tmpl_pal_cream'), '#F7F3EC', '#3F3421', '#292524', '#8C7B66', '', '', '#B03A2E'),
        CoverPalette.of($r('app.string.tmpl_pal_pale_cyan'), '#EEF4F3', '#2F4F45', '#2C3E36', '#7C8F89', '', '', '#B03A2E'),
        CoverPalette.of($r('app.string.tmpl_pal_moon_gray'), '#F1F2F4', '#3F4756', '#2B3242', '#8B93A3', '', '', '#C0392B'),
      ],
      [CoverFont.WENKAI, CoverFont.MA_SHAN, CoverFont.SERIF, CoverFont.XIAO_WEI, CoverFont.CHUN_QIU],
      '',
      { 'title': '对话创业者', 'subtitle': '第 12 期 · 关于坚持与热爱', 'seal': '珠玑', 'author': '' }));

    // ---------- E 系列 · 图片背景 ----------
    list.push(CoverTemplate.of('E2', $r('app.string.tmpl_name_texture'), CoverSeries.PHOTO, 'e2_texture',
      ['title', 'author'], $r('app.string.cover_slot_title'),
      [
        CoverPalette.of($r('app.string.tmpl_pal_morning_mist'), '#F5F0E6', '#8C6A3F', '#3D3226', '#8C7B66', '#E8DFD0'),
        CoverPalette.of($r('app.string.tmpl_pal_celadon'), '#E8F0EF', '#4A7C6F', '#2F4F45', '#6B857C', '#D3E2DF'),
        CoverPalette.of($r('app.string.tmpl_pal_twilight'), '#2E2A26', '#D4C5A0', '#EDE6D6', '#A69E8C', '#3D372F'),
        CoverPalette.of($r('app.string.tmpl_pal_gray_blue'), '#E7EBF0', '#5B7A9E', '#2C3E50', '#7F8C9B', '#D5DCE4'),
      ],
      [CoverFont.WENKAI, CoverFont.MA_SHAN, CoverFont.SERIF, CoverFont.ZHI_MANG, CoverFont.LONG_CANG],
      '',
      { 'title': '且听风吟', 'author': '解语珠玑' }));

    return list;
  }

  static getById(id: string): CoverTemplate {
    let list: CoverTemplate[] = CoverTemplates.getAll();
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        return list[i];
      }
    }
    return list[0];
  }

  static getBySeries(series: string): CoverTemplate[] {
    if (series === CoverSeries.ALL) {
      return CoverTemplates.getAll();
    }
    let all: CoverTemplate[] = CoverTemplates.getAll();
    let list: CoverTemplate[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].series === series) {
        list.push(all[i]);
      }
    }
    return list;
  }
}
