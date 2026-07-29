# ArkTS 图云（词云）组件 — 开发计划（产品视角 v3 · 基于 PocketToolbox2 复用）

> 技术栈：HarmonyOS NEXT · ArkTS + ArkUI（声明式 Canvas）
> 定位：**面向内容创作者的「粘贴文字 → 30 秒出一张能发公众号/朋友圈的词云图」工具**
> 关键策略：**不重复造轮子**，直接复用同机 `F:\PocketToolbox2` 鸿蒙应用已验证的能力模块

---

## 0. 复用基础（来自 F:\PocketToolbox2，已验证可用）

| 能力 | 源文件 | 直接复用点 |
|------|--------|-----------|
| 中文分词 + 停用词 + TF-IDF 关键词 | `entry/src/main/ets/common/utils/KeywordUtil.ets` | `extractKeywords()` 已用 `@kit.NaturalLanguageKit` 的 `textProcessing.getWordSegment()`，自带 200+ 停用词表、`n/nr/ns/v/a` 词性过滤、TF-IDF 打分。→ **直接拿来做词频统计** |
| 中文字体注册 | `entry/src/main/ets/common/utils/FontUtil.ets` | 9 款字体（霞鹜文楷/得意黑/站酷系列/马善政…）已 `registerFont($rawfile(...))`。→ **词云文字样式直接复用** |
| 字体文件 | `entry/src/main/resources/rawfile/font/*.ttf`（10 个） | 连字体文件都现成，复制到本项目即可 |
| 配色模板 | `entry/src/main/ets/model/Md2PngModels.ets` | `Md2PngTemplates.getAll()` 有 10 套配色（微信绿/小红书红/水墨/赛博…），含 bgColor/accentColor。→ **词云调色板直接复用** |
| 文字 → 图片导出 | `entry/src/main/ets/common/utils/ShareImageUtil.ets` | `getComponentSnapshot()` → PNG → `saveImageToAlbum()` / `shareImageViaPanel()`。→ **导出+分享闭环直接复用** |
| 剪贴板输入 | `entry/src/main/ets/common/utils/ClipboardUtil.ets` | `ClipboardUtil.copy()`。→ 扩展为 `paste()` 做输入 |

**结论：词云真正需要从零写的只有一块——「布局引擎」（螺旋扫描 + 碰撞检测 + 形状蒙版）。** 其余全部复用。

---

## 1. 竞品拆解（优秀产品做对了什么）

| 产品 | 出圈点 | 借鉴 |
|------|--------|------|
| 微词云 | 形状蒙版（爱心/人像/Logo）、中文字体美、模板多 | **形状蒙版是传播第一杀手锏** |
| WordArt | 多语言、形状、动画 | 轮廓算法、多格式导出 |
| Wordle | 排版极致美观、配色优雅 | 配色「设计过」而非随机 |
| 图悦 | 中文分词精准、停用词全 | 分词质量决定中文词云成败 |
| MonkeyLearn | 业务场景（评论分析） | 场景化模板 |

**共性：形状蒙版 + 中文字体美感 + 预设配色 + 一键分享 = 传播闭环。**

---

## 2. 真实场景 → 功能映射（结合彪哥实际）

| 场景 | 输入 | 关键需求 | 复用模块 |
|------|------|---------|---------|
| A 公众号文章关键词云（高频） | 粘贴正文 | 去停用词、突出核心词、中国风 | KeywordUtil + Md2PngTemplates(水墨) |
| B 读者评论 / 反馈词云 | 粘贴评论堆 | 高频突出、可剔噪声词 | KeywordUtil + 手动剔词 |
| C 年度复盘 / 个人关键词 | 一年笔记 | 好看有仪式感、能晒 | 形状蒙版 + 节日模板 |
| D 知识库标签云（PortableKnowledge） | API 拉标签 | 点击跳转 | 交互模式 |
| E 商业分析（问卷/竞品） | CSV/粘贴 | 抓重点、透明背景贴 PPT | 透明导出 + 阈值过滤 |

---

## 3. 功能清单（按价值排序）

### P0 — 必须有（M1 交付）
1. **一键生成**：粘贴文本 → `KeywordUtil.extractKeywords(全部词频版)` → 螺旋布局 → 出图 ≤ 30 秒
   - 注：现有 `extractKeywords` 只返回 topN，需新增 `extractAllWords(text)` 返回全量词频 Map（改 `filterContentWords` 后直接返回，去掉 topN 截断）
2. **中文分词 + 停用词**：直接复用 `KeywordUtil`（NLP Kit，离线可用）
3. **权重→字号**：log 缩放（词频长尾，线性会让小词挤成一样小）
4. **螺旋布局 + 碰撞检测**：新增布局引擎（本项目核心增量代码）
5. **预设配色板**：复用 `Md2PngTemplates` 的 10 套
6. **字体**：复用 `FontUtil` 的 9 款中文字体
7. **高清导出 + 分享**：复用 `ShareImageUtil`

### P1 — 差异化
8. **形状蒙版**：词按轮廓排布（矩形/圆/爱心/自定义 PNG 轮廓）——新增 `ShapeMask.ets`
9. **手动编辑**：拖拽单字、改色、剔词（所见即所得）——新增 `EditorPanel.ets`
10. **模板中心**：公众号竖版、朋友圈方图、年度关键词预设组合

### P2 — 增强
11. 交互模式（点击词高亮/跳转，场景 D）
12. 情感着色（正面绿/负面红，场景 B）
13. 入场动画（按权重依次淡入，可录屏）
14. 数据导入（CSV / 知识库 API）

---

## 4. 架构设计

```
arkts-wordcloud/
├── entry/src/main/ets/
│   ├── pages/WordCloudPage.ets        // 主页面（输入区+预览+导出）
│   ├── components/
│   │   ├── WordCloudView.ets          // Canvas 渲染组件（对外）
│   │   └── EditorPanel.ets            // 手动编辑（P1）
│   ├── core/
│   │   ├── layout/
│   │   │   ├── SpiralPlacer.ets       // 螺旋布局（核心新增）
│   │   │   ├── CollisionMask.ets       // 像素掩码碰撞（核心新增）
│   │   │   ├── SpatialHash.ets         // 空间哈希加速（核心新增）
│   │   │   └── ShapeMask.ets          // 形状蒙版（P1 新增）
│   │   ├── style/
│   │   │   └── Palette.ets            // 复用 Md2PngTemplates 配色
│   │   └── export/ImageExporter.ets   // 封装 ShareImageUtil
│   ├── model/WordItem.ets
│   └── utils/
│       ├── KeywordUtil.ets            // 从 PocketToolbox2 复制 + 改 extractAllWords
│       ├── FontUtil.ets               // 从 PocketToolbox2 复制
│       └── ClipboardUtil.ets          // 从 PocketToolbox2 复制 + 加 paste()
├── resources/rawfile/font/            // 复制 10 个 ttf/otf
```

**数据流：**
`粘贴文本` → `KeywordUtil.extractAllWords()`（分词+词频）→ `FontScaler`（权重→字号）→ `SpiralPlacer`（TaskPool 布局，碰撞用 CollisionMask+SpatialHash）→ `WordCloudView`（Canvas 渲染，字体用 FontUtil 注册的 family）→ `ImageExporter`（getComponentSnapshot → 存相册/分享）

---

## 5. 核心新增：布局引擎实现要点

### 5.1 Archimedean 螺旋
```
r(θ)=a+b·θ; x=cx+r·cosθ; y=cy+r·sinθ; θ 步进 Δθ 直到无碰撞或超过最大半径
```

### 5.2 两阶段碰撞检测
1. **粗筛（SpatialHash）**：画布分 `cellSize≈maxFont` 网格，只与相邻 3×3 格 AABB 检测 → O(n)
2. **精检（CollisionMask）**：OffscreenCanvas 绘制候选词，`getImageData` 检测像素重叠（精准但慢，仅粗筛通过后）

### 5.3 启发式
- 大词优先（按词频降序，先占中心）
- 起始角随机化，避免长轴堆积
- 横排放不下时尝试 90° 竖排（长词友好）
- 螺旋失败 N 次后蒙特卡洛随机点兜底，保证不丢词

### 5.4 性能
- TaskPool 跑 SpiralPlacer → UI 不卡
- 千词布局 < 1s
- 静态层（布局结果绘离屏）/ 动态层（交互高亮）分离

---

## 6. 优化空间

### 6.1 出图美感（最重要）
- 中文字体优先（复用 FontUtil 9 款，告别丑默认字）
- 配色预设化（复用 Md2PngTemplates 10 套，不让用户手调）
- 留白呼吸感（词间距比塞满更显高级，参考 Wordle）

### 6.2 零门槛
- 默认就好看（打开即出图，高级选项折叠）
- 分词智能（NLP Kit 中英文混排自动处理）
- 停用词兜底（KeywordUtil 已内置 200+）

### 6.3 闭环
- 导出直接调系统分享面板 → 发微信/朋友圈
- 模板一键套用，降低选择困难

### 6.4 复用带来的额外优化
- 字体文件共用，安装包不增重（rawfile 直接拷）
- 分词走系统 NLP Kit，**零网络、零自建词典**，比本地二元切分准得多

---

## 7. 开发里程碑（按场景交付）

| 阶段 | 交付物 | 对应场景 |
|------|--------|----------|
| M1 | 复用 KeywordUtil+FontUtil+Md2PngTemplates+ShareImageUtil，+ 自写 SpiralPlacer，跑通「粘贴→出图→分享」 | 场景 A 闭环 |
| M2 | 形状蒙版 + 模板中心 | 场景 C（能晒） |
| M3 | 手动编辑（拖拽/剔词/改色） | 精细化 |
| M4 | 交互模式 + 数据导入 | 场景 D |
| M5 | 情感着色 + 动画 | 场景 B/E |

---

## 8. 落地改动清单（具体到文件）

**从 PocketToolbox2 复制（几乎零改）：**
- `FontUtil.ets` → 本项目 `utils/FontUtil.ets`
- `ClipboardUtil.ets` → 加 `static paste(): Promise<string>`
- `ShareImageUtil.ets` 的 `generateShareImage/saveImageToAlbum/shareImageViaPanel` → 封装进 `ImageExporter.ets`
- `Md2PngModels.ets` 的配色部分 → `Palette.ets`
- `rawfile/font/*`（10 个）→ 本项目 `rawfile/font/`

**需要改的：**
- `KeywordUtil.ets`：新增 `extractAllWords(text): Promise<Map<string, number>>`，去掉 topN 截断，返回全量词频（供词云用全部词而非前 5）

**从零写的（本项目核心增量）：**
- `core/layout/SpiralPlacer.ets`
- `core/layout/CollisionMask.ets`
- `core/layout/SpatialHash.ets`
- `core/layout/ShapeMask.ets`（P1）
- `components/WordCloudView.ets`
- `pages/WordCloudPage.ets`

---

## 9. 待你拍板

1. **首版主攻场景**：建议 M1 直接打「公众号文章关键词云」（彪哥最高频）？
2. **形状蒙版是否提前到 M1.5**：若「能晒」是核心诉求，蒙版可前移
3. **目标 API 版本**：PocketToolbox2 用的 API 版本即基线（建议对齐，避免 NLP Kit/Canvas API 差异）
4. **词云是独立 App 还是 PocketToolbox2 里的一个新页面**？独立 repo 更干净，但复用要拷文件；作为 toolbox2 新 page 则零拷贝直接 import

---

## 10. 一句话总结
> 不造轮子：NLP 分词、中文字体、配色模板、导出分享全部复用 PocketToolbox2 已验证模块；
> 只写一块布局引擎（螺旋+碰撞+蒙版），就能 30 秒把文字变成能发出去的好看词云图。
