# SudokuOCR 网格线中性化 — 经验教训

## 测试结果

### 日志58 (灰度级中性化 v1 — 整图拷贝)

| 测试用例 | 结果 | 详情 |
|---------|------|------|
| 01_standard_544 | PASS | given:100% full:100% fp:0 fn:0 |
| 02_small_300 | FAIL | given:90% full:96% fp:0 fn:3 |
| 03_large_800 | CRASH | THREAD_BLOCK_3S → appfreeze |

### 日志59 (in-place修改gray，内存修复)

| 测试用例 | 结果 | 详情 |
|---------|------|------|
| 01_standard_544 | PASS | given:100% full:100% fp:0 fn:0 |
| 02_small_300 | FAIL | given:90% full:96% fp:0 fn:3 |
| 03_large_800 | PASS | given:100% full:100% fp:0 fn:0 |
| 04_blue_numbers | FAIL | given:90% full:96% fp:0 fn:3 |
| 05_red_theme | FAIL | given:90% full:96% fp:0 fn:3 |
| 06_green_theme | FAIL | given:97% full:99% fp:0 fn:1 |
| 07_light_gray_numbers | FAIL | given:37% full:77% fp:0 fn:19 |
| 08_gray_bg_dark_numbers | FAIL | given:93% full:98% fp:0 fn:2 |
| 09_serif_font | PASS | given:100% full:100% fp:0 fn:0 |
| 10_italic_font | FAIL | given:90% full:96% fp:0 fn:3 |
| 11_thin_font | PASS | given:100% full:100% fp:0 fn:0 |
| 12_all_thin_lines | FAIL | given:97% full:99% fp:0 fn:1 |
| 13_no_outer_border | PASS | given:100% full:100% fp:0 fn:0 |
| 14_tiny_200 | FAIL | given:60% full:85% fp:0 fn:12 |
| 15_huge_1000 | FAIL | given:97% full:99% fp:0 fn:1 |
| photos | FAIL | given:97% full:99% fp:0 fn:1 |

**fp全部为0** — 网格线中性化没有引入任何误识别。

## 关键教训

### 1. 灰度级网格线中性化有效，但必须避免整图拷贝

**问题**：初始实现用 `new Float32Array(gray.length)` 创建 `cleanedGray` 拷贝整张灰度图。对于大图（800×800=640K像素），每个cell分配2.5MB，51个cell累计127.5MB，导致内存耗尽、线程阻塞3秒被系统杀掉。

**修复**：改为 in-place 修改 `gray` 数组（保存原始值 → 设为bg → 处理完毕后恢复），只保存网格线像素的原始值（通常几十个像素），内存开销从 O(W×H) 降到 O(gridLinePixels)。

**原则**：**永远不要为每个cell拷贝整张灰度图**。局部修改+恢复才是正确做法。

### 2. 灰度级中性化 vs 签名级剥离

**之前尝试**：`stripEdgeGridLines()` 在签名生成后剥离边缘行/列的ink bin。
- 效果差：(4,3)的best match从8变成了4（更差）
- 原因：签名级剥离无法修复sauvola阈值已被网格线污染的问题

**正确做法**：在灰度图阶段就中性化网格线，这样：
- sauvola阈值计算不受网格线影响
- ink检测bbox不受网格线影响
- 签名生成基于干净的灰度数据
- `stripEdgeGridLines` 作为双保险仍保留

### 3. 模块级常量 vs 函数内常量

`GRID_LINE_GRAY_DIFF` 被两个函数（`cellSigFromGray` 和 `cellSigFromGrayLowThresh`）使用，必须提升为模块级常量，不能放在函数内部。

### 4. 函数多return点必须配合资源恢复

`cellSigFromGray` 有多个 return 路径（sauvola成功、gray签名成功、ink不足等），in-place修改gray后必须确保每条路径都恢复原始值。改为单出口模式（先算result，最后统一恢复+return）最安全。

### 5. cellSigFromGrayLowThresh 也需要网格线中性化

Low-thresh重试路径和主路径面对相同的灰度数据，如果不做中性化，重试时仍会受网格线污染。

### 6. 测试框架异常隔离

**问题**：某个测试用例崩溃（如THREAD_BLOCK_3S）会导致整个测试套件中断，后续用例全部无法执行。

**修复**：在 `runPipelineTest` 中：
- `.then` 回调内包裹 try-catch，捕获意外异常，确保 `done()` 始终被调用
- `.catch` 中也标记 `expect(false).assertTrue()` 使框架记录失败
- 所有 assertion 错误都被捕获后 swallow，不阻止 `done()` 调用

**原则**：每个测试用例必须是自包含的异常隔离单元，一个用例崩溃不应影响其他用例执行。

## 当前状态

- 03_large_800 崩溃已修复（in-place替代整图拷贝）
- 01_standard_544 目标达成（fn:0, fp:0）
- 网格线中性化对标准尺寸图片效果良好，fp保持0
- 小图(300px/200px)和浅色数字仍有较多fn，属于独立问题
- 测试框架已增加异常隔离
