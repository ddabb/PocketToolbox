/**
 * 模板体系统一 - 注册入口
 * 设计文档：docs/模板体系统一设计文档.md §3.3
 * Phase 1：注册 4 个工具描述符（模板列表为空）。
 * Phase 2~3：各工具模板改为 extends UnifiedTemplate 后在此补充注册。
 * 调用方：Index.aboutToAppear（幂等，重复调用仅覆盖）
 */

import { UnifiedToolKind, UnifiedToolDescriptor } from './UnifiedTemplateModels';
import { UnifiedTemplateRegistry } from './UnifiedTemplateRegistry';

export function registerUnifiedTemplateSets(): void {
  UnifiedTemplateRegistry.register(UnifiedToolDescriptor.of(
    UnifiedToolKind.CHAR_CARD, '生字卡', '田字格生字卡，一键注音', 'CharCardPage', 'creative_charcard', '#D8231A'
  ), []);
  UnifiedTemplateRegistry.register(UnifiedToolDescriptor.of(
    UnifiedToolKind.COVER, '首图制作', '公众号封面 30 秒出图', 'CoverMakerPage', 'creative_cover', '#2E6FD6'
  ), []);
  UnifiedTemplateRegistry.register(UnifiedToolDescriptor.of(
    UnifiedToolKind.MD2PNG, '文字转图片', 'Markdown文本生成图片', 'Md2PngPage', 'creative_md2png', '#9b59b6'
  ), []);
  UnifiedTemplateRegistry.register(UnifiedToolDescriptor.of(
    UnifiedToolKind.WORD_CLOUD, '词云生成', '粘贴文本，30秒出图', 'WordCloudPage', 'creative_wordcloud', '#8b5cf6'
  ), []);
}
