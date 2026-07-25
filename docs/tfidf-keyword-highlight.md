# 文字转图片 - TF-IDF 关键词高亮功能设计

## 1. 功能概述

在"文字转图片"功能中，用户输入文本后，自动使用 HarmonyOS 自然语言分词服务 + TF-IDF 算法提取关键词，将关键词在渲染图片中以行内代码样式（`关键词`）高亮显示，使生成图片的重点内容一目了然。

**适用范围**：仅 Md2PngPage 的 10 个通用模板（简约蓝、清新绿、樱桃红等），诗词/成语/歇后语的 ShareImageCard 不做高亮处理。

## 2. 技术选型

### 2.1 分词服务

使用 HarmonyOS 内置的 `@kit.NaturalLanguageKit` 提供的 `textProcessing.getWordSegment()` 接口：

```typescript
import { textProcessing } from '@kit.NaturalLanguageKit';

let result: textProcessing.WordSegment[] = await textProcessing.getWordSegment(text);
// result[i].word  → 词语
// result[i].wordTag → 词性（n=名词, v=动词, adj=形容词, nr=人名, ns=地名 等）
```

**约束与限制**：
- 支持语言：简体中文、英文、繁体中文
- 文本长度：不超过 1000 字符
- **不支持模拟器**（真机才能调用）
- 不支持同一特性并发调用
- API 起始版本：5.0.0(12)

### 2.2 TF-IDF 关键词提取

分词后按词性过滤保留实词（名词、动词、形容词、人名、地名等），再用 TF-IDF 评分取 Top N 关键词。

**TF（词频）**：词语在当前文本中出现的频率
```
TF(word) = count(word) / totalWords
```

**IDF（逆文档频率）**：词语的普遍重要性，越常见的词 IDF 越低
```
IDF(word) = log(totalDocs / (1 + docsContainingWord))
```

由于移动端无法访问大规模语料库，采用内置简化 IDF 表方案：
- 预置约 200 个常见中文虚词/停用词的高 IDF 衰减值（的、是、了、在、我...）
- 未收录词默认 IDF = 1.0
- 通过词性过滤 + TF 排序 + IDF 加权，组合选取 Top 5 关键词

### 2.3 高亮渲染

将关键词用 Markdown 行内代码语法包裹：

```
原文：今天天气真好，阳光明媚
高亮：今天`天气`真好，`阳光`明媚
```

Markdown 组件的行内代码样式已由模板配置：
- `setInlineCodeColor(tpl.accentColor)` — 文字颜色跟随主题强调色
- `setInlineCodeBackgroundColor(tpl.codeBgColor)` — 背景色跟随模板

因此高亮效果会自动适配每个模板的配色方案，无需额外处理。

## 3. 数据流

```
用户输入 inputText
       │
       ▼
  [文本分段] ← 超过1000字符按句号/换行分段
       │
       ▼
  [textProcessing.getWordSegment] ← 调用系统分词服务
       │
       ▼
  [词性过滤] ← 保留 n/v/adj/nr/ns/nt/a/ad/an 等实词
       │
       ▼
  [TF-IDF 评分] ← 计算词频 × IDF权重
       │
       ▼
  [取 Top 5] → highlightWords: string[]
       │
       ▼
  [原文包裹] ← 将 highlightWords 在原文中用 `词` 包裹
       │
       ▼
  highlightedText → 传给 Markdown 组件渲染
```

## 4. 新增文件

### 4.1 `entry/src/main/ets/common/utils/KeywordUtil.ets`

关键词提取工具类，职责：

```typescript
export class KeywordUtil {
  // 调用系统分词 + TF-IDF 提取关键词
  static async extractKeywords(text: string): Promise<string[]>

  // 将关键词在原文中用 Markdown 行内代码包裹
  static highlightText(original: string, keywords: string[]): string

  // 文本分段（按1000字符上限切分）
  static splitText(text: string): string[]

  // 判断是否为实词词性
  static isContentWord(wordTag: string): boolean
}
```

**核心逻辑**：

1. `splitText()` — 按句号、问号、感叹号、换行符将超长文本切分为 ≤1000 字符的段
2. `extractKeywords()` — 对每段调用 `getWordSegment()`，合并分词结果，过滤实词，计算 TF-IDF，返回 Top 5
3. `highlightText()` — 在原文中查找关键词出现位置，用反引号包裹（跳过已在 Markdown 标记中的内容）
4. 模拟器 fallback — 分词调用失败时返回空数组，不高亮

### 4.2 内置停用词表

约 200 个常见中文停用词，用于：
- 分词后过滤无意义虚词
- 作为简化 IDF 表的基础（停用词 IDF = 0.01，接近于无关键词价值）

停用词表直接在 `KeywordUtil.ets` 中以 `Set<string>` 常量形式定义。

## 5. 修改文件

### 5.1 `entry/src/main/ets/pages/Md2PngPage.ets`

**新增状态**：
```typescript
@State highlightedText: string = '';      // 高亮后的文本
@State isExtractingKeywords: boolean = false; // 是否正在提取关键词
```

**修改流程**：
1. `inputText` 变化时（`onChange` / 填入示例），先调用 `KeywordUtil.extractKeywords()` 提取关键词
2. 调用 `KeywordUtil.highlightText(inputText, keywords)` 生成高亮文本
3. 将 `highlightedText` 传给 `Markdown` 组件（而非原始 `inputText`）
4. 分词失败时 `highlightedText = inputText`，退回不高亮

**防抖**：复用现有 `scheduleRegenerate()` 的 800ms 防抖机制，关键词提取与图片生成串联执行。

### 5.2 不修改的文件

- `ShareImageCard.ets` — 诗词/成语/歇后语模板不走高亮
- `ShareImageUtil.ets` — `build*Markdown()` 不变
- `Md2PngModels.ets` — 模板定义不变
- `DecorPatternUtil.ets` — 装饰图案不变

## 6. 词性过滤规则

保留以下词性的词语作为关键词候选：

| wordTag | 含义 | 说明 |
|---------|------|------|
| n | 名词 | 核心关键词来源 |
| nr | 人名 | 重要实体 |
| ns | 地名 | 重要实体 |
| nt | 机构名 | 重要实体 |
| nz | 其他专名 | 专有名词 |
| v | 动词 | 动作关键词 |
| vd | 副动词 | |
| vn | 名动词 | |
| adj / a | 形容词 | 修饰关键词 |
| ad | 副形词 | |
| an | 名形词 | |

过滤掉的词性：代词(r/rr/ry)、副词(d)、介词(p)、连词(c)、助词(u)、叹词(e)、语气词(y)、数词(m)、量词(q)、标点(w)。

## 7. 高亮包裹规则

1. **只包裹关键词本身**，不破坏原有 Markdown 格式
2. **跳过已在 Markdown 标记中的词**（如已是行内代码 `` `词` ``、加粗 **词**、链接 [词] 中的词）
3. **同一关键词只高亮首次出现**（避免过度高亮影响阅读），或全文本高亮（待 UI 效果确认，默认全文本高亮）
4. **关键词长度 ≥ 2 个字符**才高亮（单字词如"的""了"即使误入也跳过）

## 8. 错误处理与降级策略

| 场景 | 处理方式 |
|------|----------|
| 模拟器环境（分词不支持） | `getWordSegment()` 抛异常 → catch 后返回空数组 → 不高亮，原文渲染 |
| 文本超过 1000 字符 | `splitText()` 分段后逐段分词，合并结果 |
| 分词服务系统繁忙 | catch 错误 → 不高亮，原文渲染 |
| 网络或权限问题 | 同上，静默降级 |
| 提取结果为 0 个关键词 | `highlightedText = inputText`，不高亮 |

## 9. 性能考虑

- 分词调用是异步的，不阻塞 UI
- 防抖 800ms 后才触发提取，避免频繁调用
- 同一时间不并发调用（HarmonyOS 限制），使用串行队列
- 分词结果可缓存：同一 inputText 不重复分词
- `highlightText()` 是纯字符串操作，性能无压力

## 10. 测试要点

1. **真机测试**：输入中文文本，确认关键词被正确提取和高亮
2. **英文文本**：确认英文分词和高亮正常
3. **中英混合**：确认混合文本处理正常
4. **长文本**：超过 1000 字符的文本，确认分段分词和合并正常
5. **模拟器测试**：确认降级不高亮，页面正常渲染
6. **空文本**：不触发分词，无高亮
7. **Markdown 输入**：确认已有 Markdown 标记中的关键词不被重复包裹
8. **各模板配色**：确认行内代码高亮颜色在每个模板下正确显示
