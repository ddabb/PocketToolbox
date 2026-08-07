# 数独识别优化方案

> 本文档记录数独识别管线的优化计划与实施状态。每项优化完成后更新状态标记。

## 状态标记说明

| 标记 | 含义 |
|------|------|
| `[ ]` | 未开始 |
| `[~]` | 进行中 |
| `[x]` | 已完成 |
| `[-]` | 取消/延后 |

---

## 一、当前架构分析

### 1.1 识别管线

```
用户操作: 拍照/相册选图
       │
       ▼
[SudokuSolverPage.ets] processImageOCR(uri)
       │
       ├─ initDigitTemplates(ctx)  // 加载 digit_templates.json (9字体×9数字=81模板)
       │
       ▼
[SudokuOCR.ets] recognizeSudokuFromImage(imagePath)
       │
       ├─ 路径A: tryVisionKitRecognition(imagePath)
       │     ├─ 缩放至 ≤1280px → 探测棋盘BBox → 裁剪+放大(每格56px, 360~4096px)
       │     ├─ textRecognition.recognizeText()
       │     ├─ Strategy A: buildGridByPosition() — cornerPoints位置映射
       │     ├─ Strategy B: parseOCRToGrid() — 纯文本解析
       │     ├─ Strategy C: extractStructuredText() — 分块文本解析
       │     ├─ validateAndFixConflicts() — 冲突修复(VisionKit+像素重识)
       │     └─ fillMissingCells() — 缺格填充(VisionKit+像素)
       │
       └─ 路径B(回退): tryPixelGridRecognition(imagePath)
             ├─ 缩放至 ≤1280px
             ├─ bgColor() — 直方图众数
             ├─ findBoardBBox() — 7级策略级联
             └─ 逐格 cellSigFromGray() → recognizeDigit()
                   ├─ 12×8=96位签名 + 模板匹配(F1加权)
                   ├─ 6/9消歧: 孔洞+质心+墨量比+模板分 投票
                   └─ 最低得分阈值=12
```

### 1.2 关键文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `SudokuOCR.ets` | 798 | 顶层编排: VisionKit OCR + 像素回退 + 冲突修复 |
| `SudokuPixel.ets` | 1146 | 像素引擎: 棋盘检测、签名提取、模板识别 |
| `SudokuEngine.ets` | 484 | 求解器(DLX) + OCR文本解析 |
| `SudokuSolverPage.ets` | 903 | UI页面: 相机/相册 + OCR调用 + 棋盘渲染 |
| `digit_templates.json` | 8268 | 81个模板(9字体×9数字), 12×8签名 |

### 1.3 硬编码参数一览

| 参数 | 当前值 | 位置 | 用途 |
|------|--------|------|------|
| `INK_THRESH` | 50 | `SudokuPixel.ets:163` | 灰度偏移判定墨迹 |
| `SIG_ROWS / SIG_COLS` | 12 / 8 | `SudokuPixel.ets:16-18` | 签名网格分辨率 |
| Cell margin | 8% | `SudokuPixel.ets:793-794` | 裁剪边距避免网格线 |
| Min ink % | 2% | `SudokuPixel.ets:822` | 最低墨迹占比 |
| Ink count range | 6-90 | `SudokuPixel.ets:852` | 合法签名墨点范围 |
| Min score | 12 | `SudokuPixel.ets:1145` | 最低模板匹配得分 |
| F1 weight | 40 | `SudokuPixel.ets:1088` | F1在得分中的权重 |
| Mismatch penalty | 0.5 | `SudokuPixel.ets:1088` | 不匹配惩罚系数 |
| Max image dim | 1280 | `SudokuOCR.ets:122,213,461,710` | 处理分辨率上限 |
| Target cell px | 56 | `SudokuOCR.ets:490` | VisionKit目标每格像素 |
| VisionKit upscale | 3x | `SudokuOCR.ets:344` | 单格重识放大倍率 |
| Cell crop pad | 15% | `SudokuOCR.ets:295` | 裁剪边距 |
| Board aspect | 0.3~3.0 | `SudokuPixel.ets:424` | 合法宽高比 |

---

## 二、优化方案

### P0-1: 透视校正 (Hough直线 + 仿射/单应性变换)

- **状态**: `[ ]`
- **影响场景**: 拍照倾斜、梯形畸变
- **当前问题**:
  - `findBoardBBox()` 返回矩形 AABB，无法处理梯形/四边形棋盘
  - 无旋转检测，倾斜拍照导致网格对不齐
  - `cellSigFromGray()` 假设格子是矩形，倾斜时裁剪区域偏移
- **优化方案**:
  1. Hough直线检测 → 提取最显著的4条线(2水平+2垂直)
  2. 计算四交点 → 棋盘四角
  3. 单应性矩阵(warpPerspective) → 输出正方形棋盘
  4. 回退: 若Hough失败，尝试最小外接旋转矩形 → 仿射旋转
- **实施文件**: `SudokuPixel.ets` 新增 `detectPerspective()`, `warpPerspectiveGray()`
- **预期收益**: 拍照场景准确率 +15~30%
- **验证**: 使用旋转/倾斜的测试图片验证棋盘矫正效果

### P0-2: 自适应阈值 (Sauvola局部自适应)

- **状态**: `[ ]`
- **影响场景**: 拍照光照不均、阴影、低对比度
- **当前问题**:
  - `INK_THRESH=50` 全局固定，对浅色数字/彩色主题失效
  - Otsu回退仅在签名墨点越界时触发，且 `|thresh-bg|<12` 时拒绝
  - `bgColor()` 取直方图众数，受大面积阴影干扰
- **优化方案**:
  1. Sauvola局部自适应阈值: `T(x,y) = mean(x,y) * (1 + k * (std(x,y)/R - 1))`，k=0.2, R=128, 窗口=cellW/2
  2. 在 `cellSigFromGray` 中: 优先Sauvola → 失败回退Otsu → 最终回退全局INK_THRESH
  3. 保留 `isDark` 判定逻辑，Sauvola在两种模式下均适用
- **实施文件**: `SudokuPixel.ets` 新增 `sauvolaThreshold()`, 修改 `cellSigFromGray()`
- **预期收益**: 光照不均场景准确率 +10~20%
- **验证**: 使用低对比度/阴影测试图片验证墨迹判定

### P1-1: 分辨率自适应策略

- **状态**: `[ ]`
- **影响场景**: 截屏(高分辨率)、小图
- **当前问题**:
  - 统一缩放到 ≤1280px，截屏1080×2400+丢失大量细节
  - `TARGET_CELL_PX=56` 对截屏远不够(截屏单格可达200+px)
  - 高分辨率图像的细节在缩放后被抹平
- **优化方案**:
  1. 分辨率分级策略:
     - 截屏/高分辨率(>2000px): 保留原始分辨率，直接在原图处理
     - 中等分辨率(800~2000px): 轻度缩放(≤1600px)
     - 低分辨率(<800px): 适度放大以保证每格≥40px
  2. 动态 `TARGET_CELL_PX`: 根据输入分辨率调整，截屏目标80px，拍照目标56px
  3. 像素分析路径也采用相同的自适应策略
- **实施文件**: `SudokuOCR.ets` 修改 `tryVisionKitRecognition()`, `tryPixelGridRecognition()`, `validateAndFixConflicts()`, `fillMissingCells()`
- **预期收益**: 截屏准确率 +5~15%
- **验证**: 截屏图片 vs 当前方案对比

### P1-2: Hough线检测替代投影峰值检测

- **状态**: `[ ]`
- **影响场景**: 细线/无边框变体、截屏多种App风格
- **当前问题**:
  - `findPeriodicPeaks()` 依赖投影峰值，对细线/无边框/彩色边框不鲁棒
  - 7级策略级联是修补式设计，每种变体加一级策略
  - 保守策略 `findBBoxConservative` 在形态学开运算后丢失1-2px细线
- **优化方案**:
  1. Hough直线检测(概率版): 检测所有直线段
  2. 角度聚类: 主方向(0°/90°) + 允许±5°偏差
  3. 等间距聚类: 在两个主方向上各找10条近似等间距的线
  4. 交点计算: 10×10=100个交点，最小外接矩形=棋盘BBox
  5. 回退: Hough失败时保留当前7级策略级联
- **实施文件**: `SudokuPixel.ets` 新增 `findBoardByHoughLines()`, 修改 `findBoardBBox()`
- **预期收益**: 变体兼容性大幅提升，减少策略级联层数
- **验证**: 各变体测试图片(细线/无边框/粗边框/彩色)

### P1-3: 签名分辨率提升至28×20

- **状态**: `[ ]`
- **影响场景**: 全场景数字识别
- **当前问题**:
  - 12×8=96位签名过于粗糙，3/5、8/0、6/9易混淆
  - 孔洞检测在12×8下极不稳定(孔洞仅占1-2个签名格)
  - 模板匹配区分度不足
- **优化方案**:
  1. `SIG_ROWS=28, SIG_COLS=20` (560位签名)
  2. 重新生成 `digit_templates.json`: 扩展字体库(加入Arial/Times/Courier等)，数据增强(膨胀/腐蚀/平移)，模板量扩至500+
  3. 修改 `cellSigFromGray()` 和 `cellSig()` 的签名网格参数
  4. 修改 `recognizeDigit()` 的得分公式和阈值
  5. 修改 `holeCenterRow()` 在更高分辨率下做孔洞检测
  6. 修改 6/9 消歧逻辑参数
- **实施文件**: `SudokuPixel.ets`, `scripts/gen_digit_templates.js`, `digit_templates.json`
- **预期收益**: 模板匹配精度 +3~5%, 6/9孔洞检测稳定性大幅提升
- **验证**: 全部测试图片对比新旧签名精度

### P1-4: 精确网格线定位 + 数字居中验证

- **状态**: `[ ]`
- **影响场景**: 格子偏移、字号不一致
- **当前问题**:
  - `cellSigFromGray` 用8% margin裁剪网格线，经验值不同字体下偏移不同
  - 无亚像素级网格定位
  - 数字可能偏移到相邻格子
- **优化方案**:
  1. 在棋盘BBox内做水平/垂直投影 → 寻找9个等间距谷值 → 插值精确定位网格线
  2. 亚像素修正: 谷值附近做抛物线拟合，得亚像素级分割线位置
  3. 数字居中验证: 每格提取数字BBox后，检查中心是否在格子中心附近，偏移过大则重新定位
  4. 连通域分析辅助: 若网格线定位失败，用连通域标记筛选数字BBox
- **实施文件**: `SudokuPixel.ets` 新增 `findPreciseGridLines()`, `validateCellCentering()`
- **预期收益**: 减少跨格误识别
- **验证**: 字号不一致/数字偏移测试图片

### P2-1: 6/9混淆专项优化

- **状态**: `[ ]`
- **影响场景**: 全场景6/9识别
- **当前问题**:
  - 12×8签名下孔洞检测极不可靠(孔洞仅1-2格)
  - 4票投票中孔洞占2票权重，但孔洞本身不稳定
  - 质心和墨量比权重偏低
- **优化方案**:
  1. 依赖 P1-3 签名提升后，孔洞检测在28×20分辨率下自然改善
  2. 重新调整投票权重: 孔洞3票 + 质心2票 + 墨量比2票 + 模板分1票
  3. 新增HOG特征: 计算梯度方向直方图(6的弧线从上往下收紧，9从下往上收紧)
  4. 新增笔画宽度比: 6的上半部分笔画较窄，9的下半部分笔画较窄
- **实施文件**: `SudokuPixel.ets` 修改 `disambiguate69()`, `recognizeDigit()`
- **依赖**: P1-3 (签名分辨率提升)
- **预期收益**: 6/9混淆率降低50%+
- **验证**: 6/9密集测试图片

### P2-2: 置信度输出 + 低置信标记

- **状态**: `[ ]`
- **影响场景**: 全场景用户体验
- **当前问题**:
  - 当前识别结果无置信度，低质量识别静默通过
  - 用户无法知道哪些格可能识别错误
  - 最低得分阈值12缺乏直观含义
- **优化方案**:
  1. `OCRResult` 新增 `confidence: number[]` (81个浮点值, 0~1)
  2. 模板匹配: `confidence = bestScore / (SIG_LEN + 40)` 归一化
  3. VisionKit: 使用文字识别置信度(如API提供)
  4. 低置信阈值: confidence < 0.4 标记为"待确认"
  5. UI层: 低置信格子显示橙色边框，提示用户手动校验
- **实施文件**: `SudokuOCR.ets` 修改 `OCRResult`, `SudokuSolverPage.ets` UI展示
- **预期收益**: 减少静默错误，用户可针对性校验
- **验证**: 识别结果中置信度分布合理

### P3-1: VisionKit引擎复用 + 内存优化

- **状态**: `[ ]`
- **影响场景**: 性能
- **当前问题**:
  - `reRecognizeCellVisionKit()` 每次init/release TextRecognition，开销大
  - 为裁剪单格克隆整个PixelMap (`fullPixelMap.cloneSync()`)
  - 81格串行处理，无并行
- **优化方案**:
  1. VisionKit引擎复用: `validateAndFixConflicts` 和 `fillMissingCells` 共享一个TextRecognition实例，只在最后release
  2. 子PixelMap创建: 使用 `image.createPixelMap` 从指定区域创建，替代clone+crop
  3. 批量重识: 收集所有冲突格/缺格，统一初始化一次VisionKit，逐格识别后统一释放
- **实施文件**: `SudokuOCR.ets` 重构 `reRecognizeCellVisionKit()`, `validateAndFixConflicts()`, `fillMissingCells()`
- **预期收益**: 速度提升3~5×, 内存降低50%+
- **验证**: 性能计时对比

### P3-2: 整体架构优化 (并行化 + 多帧融合)

- **状态**: `[ ]`
- **影响场景**: 性能 + 拍照鲁棒性
- **当前问题**:
  - 81格串行处理
  - 单帧识别，无法利用多帧信息
  - 无相机实时预览
- **优化方案**:
  1. 像素分析并行: 将81格分为9组(每宫9格)，并行处理
  2. 多帧融合(远期): 连续拍多帧 → 每帧独立识别 → 多数投票定最终结果
  3. 相机实时预览(远期): 集成相机 + 实时棋盘检测叠加层(四角高亮)
- **实施文件**: `SudokuPixel.ets`, `SudokuSolverPage.ets`
- **预期收益**: 速度 +2~3×, 拍照准确率 +2~5%
- **验证**: 性能计时 + 多帧测试

---

## 三、实施顺序

```
P0-1 透视校正 ─────────────────────────┐
P0-2 自适应阈值 ───────────────────────┤  第一批(核心痛点)
                                        │
P1-1 分辨率自适应 ──────────────────────┤
P1-2 Hough线检测 ───────────────────────┤  第二批(截屏/变体)
P1-3 签名分辨率提升 ─────────────────────┤
P1-4 精确网格线定位 ─────────────────────┘
                                        │
P2-1 6/9混淆优化 (依赖P1-3) ────────────┤  第三批(精度)
P2-2 置信度输出 ────────────────────────┘
                                        │
P3-1 VisionKit复用+内存 ────────────────┤  第四批(性能)
P3-2 并行化+多帧 ───────────────────────┘
```

---

## 四、回归测试方案

| 测试集 | 来源 | 数量 | 说明 |
|--------|------|------|------|
| 合成变体 | `scripts/generate_sudoku_variants.js` | 15 | 不同样式(粗/细边框/无边框/暗色等) |
| 真实照片 | `ohosTest/resources/rawfile/photos.jpg` | 1 | 木纹桌面复杂背景 |
| 截屏样本 | 各App数独截图 | TBD | 多种App风格 |
| 倾斜照片 | 旋转/倾斜拍摄 | TBD | 验证透视校正 |
| 低对比度 | 浅色数字/暗色主题 | TBD | 验证自适应阈值 |

每项优化完成后，需全部测试集通过方可标记为 `[x]`。

---

## 五、变更记录

| 日期 | 优化项 | 变更摘要 |
|------|--------|----------|
| 2026-08-07 | 文档创建 | 初始优化方案文档 |
