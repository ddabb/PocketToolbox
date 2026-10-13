/**
 * 文案海报模板注册表：21 个模板（T1 暖调标签卡 / T2 纯色简约 / T3 文艺手写 / T4 大字冲击 / T5 LCD 像素屏
 *   / T6 CRT 终端屏 / T7 霓虹灯招牌 / T8 掌机游戏机 / T9 复古车票 / T10 翻牌显示屏
 *   / T11 复古报纸 / T12 聊天气泡 / T13 黑胶唱片 / T14 电影字幕卡 / T15 公告栏启事
 *   / T16 二十四节气卡 / T17 节日祝福卡 / T18 红包对联风
 *   / T19 撕纸拼贴 / T20 竖排标点 / T21 层叠色块，均为大字金句类）
 * 设计稿宽 900px；导出 1080x1080（1:1）/ 1080x1440（3:4）/ 1080x1920（9:16 长图）
 * supportsPinyin=false 的固定构图模板（T9/T10/T13/T14/T15/T16/T18）隐藏注音开关（1.4.4 待确认 4 默认：允许隐藏）
 * 需求文档：docs/文案海报生成器需求文档.md §4；T5-T10 参照 docs/页面渲染失败问题排查.html 及 docs/文案海报候选_*.html；
 *   T11-T15 参照 docs/文案海报候选2_总览.html（复古报纸/聊天气泡/黑胶唱片/电影字幕卡/公告栏启事）；
 *   T16-T18 参照 docs/文案海报候选_二十四节气卡.html / 文案海报候选_节日祝福卡.html / 文案海报候选_红包对联风.html
 * 分类导航见 model/CopyPosterModels.ets 的 CopyPosterCategories（1.4.5 优化新增）
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
  static readonly MAX_WATERMARK: number = 12;

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
      { 'body': '欢迎来访公众号「随身工具宝」', 'sign': '请你喝茶呀', 'tag': 'hi 朋友' }));

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

    // ---------- T5 LCD 像素屏（功能机斜拍风，参照 docs/页面渲染失败问题排查.html） ----------
    // 配色字段约定：bg=舞台底色 accent=辉光色 title=框内文字(恒深色) sub=屏上状态文字 block=LCD文本框底(恒浅灰) grid=屏幕面板底色
    list.push(CopyPosterTemplate.of('T5', $r('app.string.poster_tmpl_t5'), 'lcd_pixel',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_night_glow'), '#000000', '#9EC9FF', '#111111', '#D8E4F5',
          '', '#C9C9C9', '#05070B'),
        CoverPalette.of($r('app.string.tmpl_pal_jade_lcd'), '#000A06', '#86EFAC', '#111111', '#D9FFE9',
          '', '#C9C9C9', '#03120A'),
        CoverPalette.of($r('app.string.tmpl_pal_amber_lcd'), '#120C02', '#FCD34D', '#111111', '#FFF3D6',
          '', '#C9C9C9', '#140D02'),
        CoverPalette.of($r('app.string.tmpl_pal_warm_desk'), '#E5DFD3', '#7BA7D9', '#111111', '#D8E4F5',
          '', '#C9C9C9', '#05070B'),
        CoverPalette.of($r('app.string.tmpl_pal_neon_magenta'), '#08030D', '#F0ABFC', '#111111', '#FBE4FF',
          '', '#C9C9C9', '#0F0618'),
      ],
      [CoverFont.SERIF, CoverFont.HANI_SANS, CoverFont.WENKAI, CoverFont.XIAO_WEI, CoverFont.ROUND],
      {
        'body': '欢迎来访公众号「随身工具宝」，木木请你喝茶呀。今天测试六十字内容，看屏幕会不会自动撑高，功能机像素屏效果仍然保持，斜着拍的感觉也要在。一二三四五六七八九十。',
        'sign': '',
        'tag': 'pinyin'
      }));

    // ---------- T6 CRT 终端屏（米色复古显示器 + 荧光屏） ----------
    // 配色字段约定：bg=舞台底色 accent=荧光辉光 title=正文亮荧光 sub=暗荧光 block=机壳米色 grid=屏幕底色
    list.push(CopyPosterTemplate.of('T6', $r('app.string.poster_tmpl_t6'), 'crt_terminal',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_emerald_phosphor'), '#050805', '#3AFF90', '#3AFF90', '#7DFFB9',
          '', '#D3CCBC', '#06180C'),
        CoverPalette.of($r('app.string.tmpl_pal_amber_terminal'), '#0A0702', '#FFB000', '#FFC94D', '#FFD98A',
          '', '#D3CCBC', '#140E02'),
        CoverPalette.of($r('app.string.tmpl_pal_ice_glow'), '#030710', '#6BD5FF', '#9FE4FF', '#C9F0FF',
          '', '#C9CDD6', '#04121E'),
        CoverPalette.of($r('app.string.tmpl_pal_rose_ray'), '#0C0306', '#FF5C7A', '#FF8FA3', '#FFC2CD',
          '', '#D3CCBC', '#170409'),
        CoverPalette.of($r('app.string.tmpl_pal_paper_white'), '#0A0A0A', '#E8E8E8', '#F5F5F5', '#C9C9C9',
          '', '#3A3D42', '#131313'),
      ],
      [CoverFont.SERIF, CoverFont.HANI_SANS, CoverFont.SMILEY, CoverFont.WENKAI, CoverFont.ROUND],
      { 'body': '欢迎来访公众号「随身工具宝」', 'sign': '请你喝茶呀', 'tag': 'quote' }));

    // ---------- T7 霓虹灯招牌（夜墙灯管） ----------
    // 配色字段约定：bg/bg2=夜空渐变 accent=主灯管色 title=灯管亮芯 sub=标签灯管色 block=边框灯管色
    list.push(CopyPosterTemplate.of('T7', $r('app.string.poster_tmpl_t7'), 'neon_sign',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_pink_haze'), '#0B1020', '#FF4FD8', '#FFFFFF', '#FFD9F6',
          '#04060C', '#3CE8FF', ''),
        CoverPalette.of($r('app.string.tmpl_pal_cyan_flame'), '#071018', '#3CE8FF', '#FFFFFF', '#DFFAFF',
          '#030608', '#FF4FD8', ''),
        CoverPalette.of($r('app.string.tmpl_pal_gold_purple'), '#100B18', '#FFD166', '#FFFFFF', '#FFE9B8',
          '#060410', '#B388FF', ''),
        CoverPalette.of($r('app.string.tmpl_pal_lime_light'), '#08120A', '#A3FF6B', '#FFFFFF', '#D9FFC2',
          '#030805', '#FF6B9D', ''),
        CoverPalette.of($r('app.string.tmpl_pal_ice_nocturne'), '#080D1A', '#6BB8FF', '#FFFFFF', '#CCE4FF',
          '#040710', '#FF9DE2', ''),
      ],
      [CoverFont.HANI_SANS, CoverFont.HUANG_YOU, CoverFont.ROUND, CoverFont.XIAO_WEI, CoverFont.KUAI_LE],
      { 'body': '欢迎来访公众号「随身工具宝」', 'sign': '请你喝茶呀', 'tag': 'hi 朋友' }));

    // ---------- T8 掌机游戏机（橄榄绿点阵屏 + 像素对话框） ----------
    // 配色字段约定：bg=舞台底色 accent/title=点阵屏墨色 sub=屏上暗墨 block=机身壳色 grid=LCD 底色
    list.push(CopyPosterTemplate.of('T8', $r('app.string.poster_tmpl_t8'), 'handheld_console',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_classic_gray'), '#0B0C10', '#1F2D16', '#1F2D16', '#3A4A2C',
          '', '#4A4D56', '#9BB069'),
        CoverPalette.of($r('app.string.tmpl_pal_clear_purple'), '#0D0A12', '#1F2D16', '#1F2D16', '#3A4A2C',
          '', '#7C5BA6', '#9BB069'),
        CoverPalette.of($r('app.string.tmpl_pal_berry_pink'), '#100710', '#1F2D16', '#1F2D16', '#3A4A2C',
          '', '#A14A6A', '#9BB069'),
        CoverPalette.of($r('app.string.tmpl_pal_mint_teal'), '#061011', '#1F2D16', '#1F2D16', '#3A4A2C',
          '', '#3F8E85', '#9BB069'),
        CoverPalette.of($r('app.string.tmpl_pal_amber_shell'), '#100D04', '#1F2D16', '#1F2D16', '#3A4A2C',
          '', '#C9A23F', '#9BB069'),
      ],
      [CoverFont.HANI_SANS, CoverFont.SMILEY, CoverFont.WENKAI, CoverFont.KUAI_LE, CoverFont.ROUND],
      { 'body': '欢迎来访公众号「随身工具宝」', 'sign': '请你喝茶呀', 'tag': 'POCKET-8' }));

    // ---------- T9 复古车票（票纸 + 撕票线 + 邮戳） ----------
    // 配色字段约定：bg=舞台底色 accent=印章红 title=票面墨色 sub=票面浅墨 block=票纸颜色 grid=分隔线色
    list.push(CopyPosterTemplate.of('T9', $r('app.string.poster_tmpl_t9'), 'vintage_ticket',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_classic_red_seal'), '#171208', '#C44A3A', '#2E281D', '#6B5C40',
          '', '#F2E8D2', '#C8B794'),
        CoverPalette.of($r('app.string.tmpl_pal_indigo_seal'), '#0D0F14', '#3A4E8C', '#2A2E3A', '#6E7484',
          '', '#F0EDDE', '#BCC0CE'),
        CoverPalette.of($r('app.string.tmpl_pal_pine_postmark'), '#0D110C', '#3E6B4F', '#26301F', '#5F6E52',
          '', '#F2EFDF', '#B9C4AC'),
        CoverPalette.of($r('app.string.tmpl_pal_coffee_paper'), '#15100A', '#8B5A2B', '#33291A', '#77664A',
          '', '#EADFC4', '#C4B394'),
        CoverPalette.of($r('app.string.tmpl_pal_midnight_gold'), '#101014', '#D4AF37', '#E8E4D8', '#9A968A',
          '', '#2E3138', '#4A4E57'),
      ],
      [CoverFont.SERIF, CoverFont.FEI_BAI, CoverFont.WENKAI, CoverFont.XIAO_WEI, CoverFont.MA_SHAN],
      { 'body': '欢迎来访公众号「随身工具宝」', 'sign': '请你喝茶呀', 'tag': '随身工具宝' }, false));

    // ---------- T10 翻牌显示屏（车站翻牌板，逐字模块） ----------
    // 配色字段约定：bg=舞台底色 accent=琥珀标签/署名 title=翻牌字色 sub=暗灰 dash block=底板颜色 grid=翻牌模块底色
    list.push(CopyPosterTemplate.of('T10', $r('app.string.poster_tmpl_t10'), 'split_flap',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_classic_platform'), '#08090B', '#E8B84B', '#F5EFDC', '#5A5F68',
          '', '#1B1D20', '#363A40'),
        CoverPalette.of($r('app.string.tmpl_pal_subway_blue'), '#060A12', '#FFD166', '#EAF2FF', '#55617A',
          '', '#16233C', '#2C3E5C'),
        CoverPalette.of($r('app.string.tmpl_pal_signal_green'), '#060B07', '#7CFF9E', '#EAFBEF', '#4A6B55',
          '', '#12241A', '#2A4A38'),
        CoverPalette.of($r('app.string.tmpl_pal_station_red'), '#0E0708', '#FF9E7A', '#FFF0E8', '#6B4A44',
          '', '#2B1618', '#4E2C2E'),
        CoverPalette.of($r('app.string.tmpl_pal_steel_slate'), '#07090C', '#8FD4FF', '#F0F6FC', '#4A5560',
          '', '#1A2129', '#34404C'),
      ],
      [CoverFont.HANI_SANS, CoverFont.SMILEY, CoverFont.SERIF, CoverFont.ROUND, CoverFont.WENKAI],
      { 'body': '欢迎来访公众号「随身工具宝」', 'sign': '请你喝茶呀', 'tag': '文案站' }, false));

    // ---------- T11 复古报纸（老报纸头版，参照 docs/文案海报候选_复古报纸.html） ----------
    // 配色字段约定：bg=纸色 accent=号外红章 title=标题墨 sub=次要墨 block=亮纸色 grid=分隔线色
    list.push(CopyPosterTemplate.of('T11', $r('app.string.poster_tmpl_t11'), 'vintage_news',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_aged_press'), '#EDE3CB', '#C0392B', '#2B2317', '#6E5F44',
          '', '#F4ECD8', '#B4A382'),
        CoverPalette.of($r('app.string.tmpl_pal_morning_paper'), '#F4F1E8', '#1F4E79', '#1A1A18', '#6B6860',
          '', '#FBF9F2', '#C9C4B4'),
        CoverPalette.of($r('app.string.tmpl_pal_evening_edition'), '#E8D9B5', '#8C2F2A', '#33291A', '#77664A',
          '', '#F0E4C6', '#BFA878'),
        CoverPalette.of($r('app.string.tmpl_pal_ink_reprint'), '#1C1A17', '#E8B84B', '#EFE8D8', '#9A9285',
          '', '#26231F', '#4A443A'),
        CoverPalette.of($r('app.string.tmpl_pal_rose_gazette'), '#F3E4E0', '#B03A5B', '#3A2430', '#8A6570',
          '', '#F9ECE9', '#CFA3AC'),
      ],
      [CoverFont.SERIF, CoverFont.FEI_BAI, CoverFont.MA_SHAN, CoverFont.WENKAI, CoverFont.XIAO_WEI],
      { 'body': '欢迎来访公众号「随身工具宝」', 'sign': '请你喝茶呀', 'tag': '随身日报' }));

    // ---------- T12 聊天气泡（微信式对话，参照 docs/文案海报候选_聊天气泡.html） ----------
    // 配色字段约定：bg=聊天区底色 accent=我方气泡色 title=正文墨色 sub=次要文字 block=对方气泡色 grid=顶栏底色
    list.push(CopyPosterTemplate.of('T12', $r('app.string.poster_tmpl_t12'), 'chat_bubbles',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_wechat_green'), '#EDEDED', '#95EC69', '#191919', '#8A8A8A',
          '', '#FFFFFF', '#E4E4E4'),
        CoverPalette.of($r('app.string.tmpl_pal_midnight_chat'), '#15181D', '#2E5C4A', '#E8EAF0', '#7A8290',
          '', '#23272E', '#1B1F26'),
        CoverPalette.of($r('app.string.tmpl_pal_bubblegum_pink'), '#FBE9EF', '#F9A8C9', '#4A2434', '#B08A98',
          '', '#FFFFFF', '#F6DCE7'),
        CoverPalette.of($r('app.string.tmpl_pal_business_blue'), '#EDF1F8', '#7FA9EE', '#1F2A44', '#8A94A6',
          '', '#FFFFFF', '#E2E8F4'),
        CoverPalette.of($r('app.string.tmpl_pal_cream_talk'), '#F3EBDD', '#E8B84B', '#3A2E1A', '#A08D6A',
          '', '#FFF8EC', '#EADFC8'),
      ],
      [CoverFont.HANI_SANS, CoverFont.SMILEY, CoverFont.KUAI_LE, CoverFont.ROUND, CoverFont.WENKAI],
      { 'body': '欢迎来访公众号「随身工具宝」', 'sign': '请你喝茶呀', 'tag': '随身工具宝' }));

    // ---------- T13 黑胶唱片（聚光灯唱片 + 曲目单，参照 docs/文案海报候选_黑胶唱片.html） ----------
    // 配色字段约定：bg=舞台底色 accent=中心标签色 title=曲目文字 sub=次要文字 block=标签文字色 grid=唱片纹色
    list.push(CopyPosterTemplate.of('T13', $r('app.string.poster_tmpl_t13'), 'vinyl_record',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_retro_orange_label'), '#14100C', '#E8833A', '#F2E8D8', '#8A7C68',
          '', '#241708', '#1C1A18'),
        CoverPalette.of($r('app.string.tmpl_pal_blue_jazz'), '#0C1016', '#3A6EA5', '#E8EEF6', '#7A8698',
          '', '#F0F4FA', '#15181D'),
        CoverPalette.of($r('app.string.tmpl_pal_midnight_vinyl'), '#0A0A0C', '#1C1C22', '#EFEFEA', '#7A7A80',
          '', '#EFEFEA', '#16161A'),
        CoverPalette.of($r('app.string.tmpl_pal_rose_label'), '#161014', '#D96A8B', '#F6E8EC', '#9A7E88',
          '', '#2A1218', '#1A1418'),
        CoverPalette.of($r('app.string.tmpl_pal_emerald_groove'), '#0A1210', '#2F8E6B', '#E6F2EC', '#7E968A',
          '', '#0C1F16', '#121A16'),
      ],
      [CoverFont.SERIF, CoverFont.XIAO_WEI, CoverFont.HANI_SANS, CoverFont.WENKAI, CoverFont.MA_SHAN],
      { 'body': '欢迎来访公众号「随身工具宝」', 'sign': '请你喝茶呀', 'tag': 'POCKET LP' }, false));

    // ---------- T14 电影字幕卡（影院片头卡，参照 docs/文案海报候选_电影字幕卡.html） ----------
    // 配色字段约定：bg/bg2=夜幕渐变 accent=金线 title=字幕银 sub=次要文字 block=胶片条色 grid=片孔色
    list.push(CopyPosterTemplate.of('T14', $r('app.string.poster_tmpl_t14'), 'cinema_card',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_midnight_premiere'), '#07070B', '#C9A55C', '#ECE8E0', '#8A867C',
          '#101018', '#15151C', '#040406'),
        CoverPalette.of($r('app.string.tmpl_pal_sepia_film'), '#171210', '#D9A868', '#F0E4D0', '#9A8870',
          '#241C14', '#2A2018', '#0C0806'),
        CoverPalette.of($r('app.string.tmpl_pal_cool_blue_ray'), '#060A12', '#7FB4E8', '#E8F0F8', '#7E92A8',
          '#0C1420', '#121A26', '#03060C'),
        CoverPalette.of($r('app.string.tmpl_pal_rose_premiere'), '#120A0E', '#E8A0B4', '#F6ECF0', '#A08690',
          '#1E1218', '#221820', '#080406'),
        CoverPalette.of($r('app.string.tmpl_pal_neon_green_reel'), '#081008', '#7CE87C', '#ECF6EC', '#86A086',
          '#0E1A0E', '#142014', '#030803'),
      ],
      [CoverFont.SERIF, CoverFont.HANI_SANS, CoverFont.SMILEY, CoverFont.XIAO_WEI, CoverFont.ROUND],
      { 'body': '欢迎来访公众号「随身工具宝」', 'sign': '请你喝茶呀', 'tag': 'POCKET 电影' }, false));

    // ---------- T15 公告栏启事（软木板图钉便签，参照 docs/文案海报候选_公告栏启事.html） ----------
    // 配色字段约定：bg=软木底色 accent=图钉/红线色 title=便签墨色 sub=次要墨色 block=便签纸色 grid=木框色
    list.push(CopyPosterTemplate.of('T15', $r('app.string.poster_tmpl_t15'), 'cork_notice',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_classic_cork'), '#B58A5F', '#C0392B', '#3A2E20', '#7A6A4E',
          '', '#F6EFDE', '#6E4A2A'),
        CoverPalette.of($r('app.string.tmpl_pal_blue_pin'), '#C4A484', '#2E6FD6', '#2E2A22', '#7E7460',
          '', '#F8F4E8', '#5F4A32'),
        CoverPalette.of($r('app.string.tmpl_pal_cream_notes'), '#D8C5A5', '#B03A5B', '#3A3026', '#8A7C64',
          '', '#FFFBEF', '#8A6A44'),
        CoverPalette.of($r('app.string.tmpl_pal_midnight_chalk'), '#1E2430', '#E8B84B', '#EDEAE2', '#8A92A0',
          '', '#262D3D', '#11141C'),
        CoverPalette.of($r('app.string.tmpl_pal_kraft_paper'), '#A98A5F', '#2F8E6B', '#33281A', '#6E5C42',
          '', '#EFE3C6', '#5E4426'),
      ],
      [CoverFont.MA_SHAN, CoverFont.LONG_CANG, CoverFont.WENKAI, CoverFont.FEI_BAI, CoverFont.ZHI_MANG],
      { 'body': '欢迎来访公众号「随身工具宝」', 'sign': '请你喝茶呀', 'tag': '寻物启事' }, false));

    // ---------- T16 二十四节气卡（竖排主文案 + 节气名/印章/节气歌，参照 docs/文案海报候选_二十四节气卡.html） ----------
    // 配色字段约定：bg=纸色 accent=印章红 title=主文案墨 sub=次要文字 block=节气名色 grid=边框线色
    list.push(CopyPosterTemplate.of('T16', $r('app.string.poster_tmpl_t16'), 'solar_term',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_rice_seal'), '#F3ECDA', '#B03A2E', '#2E2A22', '#8C6A3F',
          '', '#3B4A3F', '#C9BC9C'),
        CoverPalette.of($r('app.string.tmpl_pal_celadon_term'), '#E8EFE8', '#C0392B', '#2C3530', '#6E7F72',
          '', '#2F6B4F', '#B8C8BA'),
        CoverPalette.of($r('app.string.tmpl_pal_ink_term'), '#1F1E1A', '#C0392B', '#EFE6D0', '#9C8E79',
          '', '#EFE6D0', '#4A453B'),
        CoverPalette.of($r('app.string.tmpl_pal_rouge_term'), '#F6EBE4', '#B03A5B', '#33261F', '#A0786A',
          '', '#8C3A4E', '#DCC2B4'),
        CoverPalette.of($r('app.string.tmpl_pal_xiang_paper'), '#F5EBD8', '#8C6A3F', '#3A2E1A', '#A08D6A',
          '', '#6E5230', '#D8C5A0'),
      ],
      [CoverFont.SERIF, CoverFont.XIAO_WEI, CoverFont.WENKAI, CoverFont.FEI_BAI, CoverFont.MA_SHAN],
      { 'body': '春风如贵客，一到便繁华', 'sign': '随身工具宝', 'tag': '立春' }, false));

    // ---------- T17 节日祝福卡（圆月星点几何 + 居中祝福，参照 docs/文案海报候选_节日祝福卡.html） ----------
    // 配色字段约定：bg/bg2=夜空渐变 accent=月色 title=祝福文字 sub=次要文字 block=云色 grid=星点色
    list.push(CopyPosterTemplate.of('T17', $r('app.string.poster_tmpl_t17'), 'festival_greet',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_midmoon_night'), '#0B1026', '#F2E2B6', '#F6EFD9', '#D2E0FA',
          '#1B2B52', '#D2E0FA', '#F2E2B6'),
        CoverPalette.of($r('app.string.tmpl_pal_spring_red'), '#8C0B0F', '#F4D07C', '#FCE9BF', '#F4D07C',
          '#C0181B', '#FF9E7A', '#FCE9BF'),
        CoverPalette.of($r('app.string.tmpl_pal_lantern_night'), '#1A0E1E', '#FCD34D', '#FBE9FF', '#D9C2E8',
          '#2E1440', '#F0ABFC', '#FCD34D'),
        CoverPalette.of($r('app.string.tmpl_pal_duanwu_green'), '#0E2415', '#E8B84B', '#EAF6EC', '#A8C8B0',
          '#14361F', '#7CFF9E', '#E8B84B'),
        CoverPalette.of($r('app.string.tmpl_pal_qixi_purple'), '#14081E', '#B388FF', '#F2E8FA', '#C9B2E8',
          '#2A1044', '#FF9DE2', '#B388FF'),
      ],
      [CoverFont.WENKAI, CoverFont.XIAO_WEI, CoverFont.HANI_SANS, CoverFont.MA_SHAN, CoverFont.SERIF],
      { 'body': '愿得年年，常见中秋月', 'sign': '随身工具宝', 'tag': '中秋' }));

    // ---------- T18 红包对联风（红金竖批 + 铜钱团花，参照 docs/文案海报候选_红包对联风.html） ----------
    // 配色字段约定：bg/bg2=正红渐变 accent=描金 title=金字 sub=浅金 block=横批底 grid=团花纹色
    list.push(CopyPosterTemplate.of('T18', $r('app.string.poster_tmpl_t18'), 'red_couplet',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_true_gold'), '#A80F13', '#F4D07C', '#FCE9BF', '#F4D07C',
          '#C0181B', '#7A0A0D', '#D9A84E'),
        CoverPalette.of($r('app.string.tmpl_pal_zhusha_gold'), '#9C1A1E', '#F6D9A0', '#FBEBD0', '#E8C28A',
          '#B82328', '#6E1013', '#D9A84E'),
        CoverPalette.of($r('app.string.tmpl_pal_dark_red_gold'), '#3A0A0C', '#E8B84B', '#F2DCA8', '#C9A05E',
          '#58090B', '#260406', '#B8863B'),
        CoverPalette.of($r('app.string.tmpl_pal_crimson_plum'), '#4A1030', '#F0C060', '#F8E8D8', '#D9A8C0',
          '#6E1A48', '#31081E', '#C9A05E'),
        CoverPalette.of($r('app.string.tmpl_pal_jade_gold'), '#0B3A2E', '#F4D07C', '#EAF6EC', '#A8C8B0',
          '#0E4A3A', '#072A20', '#D9B84E'),
      ],
      [CoverFont.HUANG_YOU, CoverFont.XIAO_WEI, CoverFont.FEI_BAI, CoverFont.MA_SHAN, CoverFont.HANI_SANS],
      { 'body': '岁岁平安，万事胜意', 'sign': '随身工具宝', 'tag': '新春大吉' }, false));

    // ---------- T19 撕纸拼贴（大字金句 · 手撕纸 + 胶带） ----------
    // 配色字段约定：bg=桌面底色 accent=强调/胶带 title=纸面墨色 sub=次要墨色 block=纸面块色 grid=胶带色
    list.push(CopyPosterTemplate.of('T19', $r('app.string.poster_tmpl_t19'), 'torn_paper',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_kraft_desk'), '#8C7A63', '#D8231A', '#2B241C', '#6E5F4E',
          '', '#F4EFE3', '#D9C9A8'),
        CoverPalette.of($r('app.string.tmpl_pal_slate_blue'), '#4A5568', '#E8B84B', '#F7F5EF', '#8A94A6',
          '', '#FFFFFF', '#B8C2D0'),
        CoverPalette.of($r('app.string.tmpl_pal_moss_green'), '#4F5D45', '#E86A33', '#F5F3E8', '#79856F',
          '', '#FDFBF2', '#C3CDB4'),
        CoverPalette.of($r('app.string.tmpl_pal_plum_dark'), '#3A2C3F', '#F2A2C0', '#F6EFF4', '#8E7A94',
          '', '#FFFBFE', '#BFA3C8'),
        CoverPalette.of($r('app.string.tmpl_pal_charcoal'), '#2E2E30', '#5AC8E8', '#F2F4F5', '#8A8E93',
          '', '#FFFFFF', '#9AA0A6'),
      ],
      [CoverFont.HUANG_YOU, CoverFont.WENKAI, CoverFont.XIAO_WEI, CoverFont.SERIF, CoverFont.MA_SHAN],
      { 'body': '慢慢来，比较快', 'sign': '—— 木舟', 'tag': 'DAILY' }));

    // ---------- T20 竖排标点（大字金句 · 日式竖排 + 右侧竖线） ----------
    // 配色字段约定：bg=纸色 accent=竖线/强调色 title=正文墨色 sub=标签色 block=留白块 grid=辅助线色
    list.push(CopyPosterTemplate.of('T20', $r('app.string.poster_tmpl_t20'), 'vertical_quote',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_washi'), '#F5F1E6', '#B03A2E', '#26221C', '#8A7E6C',
          '', '#FBF8F0', '#C9BCA4'),
        CoverPalette.of($r('app.string.tmpl_pal_indigo_washi'), '#EAEDF2', '#2E4A7D', '#1A1E28', '#6E7686',
          '', '#FFFFFF', '#C2C9D6'),
        CoverPalette.of($r('app.string.tmpl_pal_ink_washi'), '#1E1E20', '#D94F3D', '#F0EEE8', '#9A968E',
          '', '#2A2A2C', '#4A4A4E'),
        CoverPalette.of($r('app.string.tmpl_pal_moss_washi'), '#EDF0E8', '#4A6B4F', '#20281F', '#77836F',
          '', '#FAFBF6', '#BCC7B4'),
        CoverPalette.of($r('app.string.tmpl_pal_blush_washi'), '#FBF0F2', '#C0446A', '#2E2026', '#A08890',
          '', '#FFFFFF', '#E8C6CE'),
      ],
      [CoverFont.XIAO_WEI, CoverFont.WENKAI, CoverFont.SERIF, CoverFont.FEI_BAI, CoverFont.MA_SHAN],
      { 'body': '所爱隔山海，山海皆可平', 'sign': '在路上', 'tag': 'QUOTE' }));

    // ---------- T21 层叠色块（大字金句 · 三色错位叠压） ----------
    // 配色字段约定：bg=底色 accent=前景色块 title=纸面墨色 sub=标签/署名色 block=后景色块 grid=分隔色
    list.push(CopyPosterTemplate.of('T21', $r('app.string.poster_tmpl_t21'), 'color_blocks',
      ['body', 'sign', 'tag'],
      [
        CoverPalette.of($r('app.string.tmpl_pal_cobalt_stack'), '#F2F4F8', '#2E5FD6', '#1A2233', '#6B7688',
          '', '#FFD84D', '#2E5FD6'),
        CoverPalette.of($r('app.string.tmpl_pal_sunset_stack'), '#FFF4EC', '#F2622E', '#2B1D14', '#8A7264',
          '', '#2E6B5E', '#F2622E'),
        CoverPalette.of($r('app.string.tmpl_pal_lilac_stack'), '#F4F1FA', '#7C4DD6', '#231A33', '#7A6E94',
          '', '#F0B429', '#7C4DD6'),
        CoverPalette.of($r('app.string.tmpl_pal_mint_stack'), '#EEF7F1', '#12A06A', '#132A1E', '#6C8478',
          '', '#F25F5C', '#12A06A'),
        CoverPalette.of($r('app.string.tmpl_pal_sand_stack'), '#F6F1E4', '#C98A2E', '#2E2618', '#8C7C5E',
          '', '#2F5FA8', '#C98A2E'),
      ],
      [CoverFont.HUANG_YOU, CoverFont.KUAI_LE, CoverFont.SMILEY, CoverFont.ROUND, CoverFont.HANI_SANS],
      { 'body': '把日子过成诗', 'sign': '随身工具宝', 'tag': 'LIFE' }));

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
