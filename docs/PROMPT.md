# 词云（Word Cloud）鸿蒙 ArkTS 组件 — 开发提示词

> 使用方式：将本文件完整内容作为 System/User Prompt 交给任意 AI 编码助手（Cursor / Claude / Codex / 通义灵码等），它即可在鸿蒙 ArkTS 项目中实现本组件。无需再阅读其他文档。

---

## 【角色】

你是一名资深 HarmonyOS NEXT 鸿蒙应用开发工程师，精通 ArkTS + ArkUI（声明式开发范式）、Canvas 2D 渲染、TaskPool 多线程、以及 `@kit.*` 系统能力（NaturalLanguageKit / ImageKit / ArkUI / CoreFileKit / MediaLibraryKit / ShareKit）。你习惯写带中文注释的清晰代码，交付即注释完整。

---

## 【目标】

实现一个**词云（Word Cloud）组件**：用户粘贴一段中文/英文文本 → 自动分词统计词频 → 按权重螺旋布局无重叠排布 → 渲染成一张美观的词云图 → 一键导出 PNG 并分享到微信/朋友圈。

首版（M1）交付目标：**完整跑通「粘贴文本 → 出图 → 分享」闭环**，能在鸿蒙设备上生成一张可分享的词云图。

---

## 【关键策略：复用已有模块，不要重复造轮子】

同机已有一个验证可用的鸿蒙应用 `F:\PocketToolbox2`，它已经实现了词云所需的大部分基础设施。**请优先复用，不要自己重写分词/字体/配色/导出逻辑。**

### 可直接复用的模块（路径在 `F:\PocketToolbox2\entry\src\main\ets\`）

#### 1. 中文分词 + 停用词 + 词频统计
文件：`common/utils/KeywordUtil.ets`
- 已用 `@kit.NaturalLanguageKit` 的 `textProcessing.getWordSegment(part)` 做中文分词（离线、无需联网、无需自建词典）
- 已内置 200+ 停用词表 `STOP_WORDS`（的/了/在/是…含中英）
- 已定义内容词性白名单 `CONTENT_WORD_TAGS`：`n, nr, ns, nt, nz, v, vd, vn, a, ad, an, i, l, eng, nx`
- 常量：`MIN_KEYWORD_LENGTH = 2`，`MAX_SEGMENT_LENGTH = 1000`（超长文本自动按句号/换行切分）
- **现有方法（可复用）：** `static async extractKeywords(text: string, topN: number = 5): Promise<string[]>` —— 返回 TF-IDF 排序的前 N 个关键词
- **你需要新增的方法：** `static async extractAllWords(text: string): Promise<Array<{word: string, count: number, tag: string, score: number}>>`
  实现方式：复用内部 `segmentText()` → `filterContentWords()` → `computeTfIdf()`，**去掉 topN 截断**，返回全部词（含词频 count 与 TF-IDF 分数 score）。词云需要全量词而非前 5。

#### 2. 中文字体注册
文件：`common/utils/FontUtil.ets`
- 方法：`static registerAll(uiCtx: UIContext): void` —— 一次性注册 9 款中文字体
- 字体 family 常量（在 `model/Md2PngModels.ets` 的 `Md2PngTemplates` 类）：
  - `FONT_SMILEY='SmileySans-Oblique'`（得意黑）
  - `FONT_WENKAI='LXGWWenKai'`（霞鹜文楷）
  - `FONT_MASHAN='MaShanZheng'`、`FONT_KUAILE='ZCOOLKuaiLe'`、`FONT_HUANGYOU='ZCOOLQingKeHuangYou'`、`FONT_LONGCANG='LongCang'`、`FONT_MAOMAO='LiuJianMaoCao'`、`FONT_XIAOWEI='ZCOOLXiaoWei'`、`FONT_ZHIMANG='ZhiMangXing'`
- 字体文件已在 `F:\PocketToolbox2\entry\src\main\resources\rawfile\font\` 下（10 个 .ttf/.otf），直接复制到新项目 `resources/rawfile/font/`
- 注册方式：`uiCtx.getFont().registerFont({ familyName, familySrc: $rawfile('font/xxx.ttf') })`

#### 3. 配色模板（直接当词云调色板）
文件：`model/Md2PngModels.ets` 的 `Md2PngTemplates.getAll(): TemplateInfo[]`
- 返回 10 套配色，词云用其中 `bgColor`（背景）、`textColor`（文字）、`accentColor`（强调）三字段即可
- 10 套 id/名称：default简约蓝 / wechat清新绿 / xiaohongshu樱桃红 / douyin暗夜红 / ink水墨风 / cyberpunk赛博 / minimalist极简白 / neon霓虹 / nature自然绿 / nordic北欧
- `TemplateInfo` 字段示例：`{ id, name, bgColor, textColor, accentColor, headerColor, ... }`

#### 4. 导出图片 + 分享闭环
文件：`common/utils/ShareImageUtil.ets`
- `static async generateShareImage(uiContext: UIContext, componentId: string, prefix: string): Promise<string>`
  内部：`uiContext.getComponentSnapshot().get(componentId)` → `image.createImagePacker().packing(pixelMap, {format:'image/png', quality:100})` → 写入 `context.cacheDir` → 返回缓存路径
- `static async saveImageToAlbum(uiContext: UIContext, cachePath: string, prefix: string): Promise<void>` —— 调起相册保存对话框
- `static shareImageViaPanel(uiContext: UIContext, cachePath: string): void` —— 调起系统分享面板（发微信等）

#### 5. 剪贴板
文件：`common/utils/ClipboardUtil.ets`
- 现有 `static copy(text: string): void`
- **你需要新增：** `static async paste(): Promise<string>` —— 用 `pasteboard.getSystemPasteboard().getData()` 读取文本

---

## 【需要你从零实现的核心：布局引擎】

复用模块解决了「分词/字体/配色/导出」，但**螺旋布局 + 碰撞检测**必须从零写（这是本组件真正的增量价值）。请实现以下模块：

### 数据模型 `model/WordItem.ets`
```typescript
export class WordItem {
  text: string = '';        // 词条
  weight: number = 1;       // 词频/权重（用 log 缩放后映射字号）
  color?: string = '';      // 可选覆盖色
  font?: string = '';       // 可选字体 family
}
export class PlacedWord {
  text: string = '';
  x: number = 0;            // 中心点 x（画布坐标）
  y: number = 0;            // 中心点 y
  size: number = 0;         // 字号
  color: string = '';
  angle: number = 0;        // 0 或 90（竖排）
  font: string = '';
}
```

### 权重 → 字号 `core/style/FontScaler.ets`
- 用 **log 缩放**（词频长尾分布，线性会让小词全挤一样小）：
  `size = minFont + (maxFont - minFont) * (log(weight) - log(minW)) / (log(maxW) - log(minW))`
- 默认 `minFont=14, maxFont=96`

### 螺旋布局 `core/layout/SpiralPlacer.ets`
- Archimedean 螺旋：从中心向外，`r(θ)=a+b·θ`，`x=cx+r·cosθ`，`y=cy+r·sinθ`
- 按词频降序排（大词先放，占中心黄金位）
- 每候选位置做碰撞检测，首个无碰撞点落子；支持部分词 90° 竖排（横排放不下时尝试）
- 起始角随机化，避免长轴堆积
- 螺旋失败 N 次后蒙特卡洛随机点兜底，保证不丢词
- **建议用 `@ohos.taskpool` 跑布局计算**，避免卡 UI；千词布局目标 < 1s

### 碰撞检测（两阶段）`core/layout/CollisionMask.ets` + `core/layout/SpatialHash.ets`
1. 粗筛（SpatialHash）：画布分 `cellSize≈maxFont` 网格，只与相邻 3×3 格做 AABB 检测 → O(n)
2. 精检（CollisionMask）：在 OffscreenCanvas 绘制候选词，`getImageData` 检测像素重叠（精准但慢，仅粗筛通过后）

### 渲染组件 `components/WordCloudView.ets`
- `@Component` 封装 Canvas，接收 `WordItem[]` + 配色 + 字体，自行调用布局 + 绘制
- 静态层（布局结果绘离屏 Canvas）/ 动态层（交互高亮）分离，提升性能
- 绘制时 `context.font = `${size}px ${font}``，用 FontUtil 注册过的 family

### 主页面 `pages/WordCloudPage.ets`
- 顶部：文本输入框（TextArea，支持粘贴）+ 「生成」按钮 + 配色选择（复用 Md2PngTemplates 10 套）+ 字体选择（复用 FontUtil 9 款）
- 中部：WordCloudView 预览（用 `@State` 持有 `PlacedWord[]`，外层容器设 `id` 供 `getComponentSnapshot` 截图）
- 底部：「保存到相册」「分享」按钮（调用 ShareImageUtil）

---

## 【约束与规范】

1. **不要修改** `F:\PocketToolbox2` 的任何现有文件；本项目是独立新工程（或在 toolbox2 内新建独立 module/page，仅 `import` 复用，不改动原文件）
2. API 版本对齐 PocketToolbox2（查看其 `build-profile.json5` / `module.json5` 确认 target API），避免 NLP Kit / Canvas API 差异
3. 所有新增代码必须带中文注释（文件头说明用途 + 关键方法参数/返回值/逻辑注释）
4. 权重→字号必须用 **log 缩放**，不用线性
5. 调色板直接用 `Md2PngTemplates` 的 10 套预设，**不要开放自由调色**（用户不懂配色，预设即最佳）
6. 字体必须用 `FontUtil` 注册的 9 款中文字体之一，**禁止用系统默认字体**（中文词云丑的根因）
7. 布局计算放 TaskPool 子线程，UI 主线程不卡顿

---

## 【验收标准（M1）】

- [ ] 粘贴一段 500 字中文文章，点「生成」
- [ ] 30 秒内 Canvas 显示词云，词条无重叠、大词居中、小词向外扩散
- [ ] 切换 10 套配色任一，词云即时变色
- [ ] 切换 9 款中文字体任一，词条字形即时变化
- [ ] 点「保存到相册」→ 相册出现一张清晰 PNG
- [ ] 点「分享」→ 系统分享面板弹出，可选微信
- [ ] 中文分词正确（"人工智能"不被切成"人工"+"智能"优先，虚词"的/了"不显示）

---

## 【交付物清单】

完成后产出：
- `model/WordItem.ets`
- `core/style/FontScaler.ets`
- `core/layout/SpiralPlacer.ets`
- `core/layout/CollisionMask.ets`
- `core/layout/SpatialHash.ets`
- `components/WordCloudView.ets`
- `pages/WordCloudPage.ets`
- `utils/KeywordUtil.ets`（复制并加 `extractAllWords`）
- `utils/FontUtil.ets`（复制）
- `utils/ClipboardUtil.ets`（复制并加 `paste`）
- `utils/ImageExporter.ets`（封装 ShareImageUtil 三个方法）
- `model/Md2PngModels.ets` 配色部分（复制或用 import）
- `resources/rawfile/font/*`（10 个字体文件）

---

## 【后续阶段（M1 之后的增强，本次可先不实现）】

- M2：形状蒙版（词按爱心/圆形/Logo 轮廓排布，`core/layout/ShapeMask.ets`）
- M3：手动编辑（拖拽单字、改色、剔词，`components/EditorPanel.ets`）
- M4：交互模式（点击词条高亮/跳转，知识库标签云场景）
- M5：情感着色（正面绿/负面红）、入场动画（按权重依次淡入）

---

## 【一句话任务】

复用 PocketToolbox2 的 NLP 分词 + 中文字体 + 配色模板 + 图片导出能力，只从零写一套螺旋布局引擎（SpiralPlacer + 碰撞检测），交付一个「粘贴文字 → 30 秒出一张能分享的好看词云图」的鸿蒙 ArkTS 组件，首版跑通 M1 闭环。
