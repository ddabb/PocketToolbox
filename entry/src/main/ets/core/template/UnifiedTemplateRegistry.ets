/**
 * 模板体系统一 - 模板注册表
 * 设计文档：docs/模板体系统一设计文档.md §3.3
 * 进程内静态注册：新模板以"数据 + 预览 Builder"注册即接入，不改动页面代码。
 * 注册时机见 UnifiedTemplateSets.ets（应用启动即静态初始化）。
 */

import { UnifiedTemplate, UnifiedToolDescriptor } from './UnifiedTemplateModels';

export class UnifiedTemplateRegistry {
  private static tools: Map<string, UnifiedToolDescriptor> = new Map<string, UnifiedToolDescriptor>();
  private static templates: Map<string, UnifiedTemplate[]> = new Map<string, UnifiedTemplate[]>();
  /** 保持注册顺序，allTools() 返回稳定 */
  private static kindOrder: string[] = [];

  static register(tool: UnifiedToolDescriptor, templates: UnifiedTemplate[]): void {
    if (!UnifiedTemplateRegistry.tools.has(tool.kind)) {
      UnifiedTemplateRegistry.kindOrder.push(tool.kind);
    }
    UnifiedTemplateRegistry.tools.set(tool.kind, tool);
    UnifiedTemplateRegistry.templates.set(tool.kind, templates);
  }

  static allTools(): UnifiedToolDescriptor[] {
    let list: UnifiedToolDescriptor[] = [];
    for (let i = 0; i < UnifiedTemplateRegistry.kindOrder.length; i++) {
      let tool: UnifiedToolDescriptor | undefined =
        UnifiedTemplateRegistry.tools.get(UnifiedTemplateRegistry.kindOrder[i]);
      if (tool !== undefined) {
        list.push(tool);
      }
    }
    return list;
  }

  static toolOf(kind: string): UnifiedToolDescriptor | null {
    let tool: UnifiedToolDescriptor | undefined = UnifiedTemplateRegistry.tools.get(kind);
    return tool ?? null;
  }

  static templatesOf(kind: string): UnifiedTemplate[] {
    let list: UnifiedTemplate[] | undefined = UnifiedTemplateRegistry.templates.get(kind);
    return list ?? [];
  }

  static templateById(kind: string, id: string): UnifiedTemplate | null {
    let list: UnifiedTemplate[] = UnifiedTemplateRegistry.templatesOf(kind);
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === id) {
        return list[i];
      }
    }
    return null;
  }
}
