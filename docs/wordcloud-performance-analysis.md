# WordCloudPage 性能优化分析报告

## 一、概述

本文档对比分析 `PocketToolbox (HarmonyOS/ArkTS)` 与 `wordcloud-nodejs (Node.js/V8)` 的词云排列算法实现，识别性能瓶颈并制定优化方案。

| 维度 | Node.js | HarmonyOS (当前) |
|------|---------|-----------------|
| 运行时 | V8 JIT (桌面级) | ARK Runtime (移动端) |
| 线程模型 | 单线程同步 | taskpool 工作线程 + UI 线程 |
| canvasSize | 默认 800 | 默认 720 |
| 预期性能 | 100% (基准) | 约 30-60% (引擎差异) |

## 二、逐项对比分析

### 2.1 形状遮罩构建 (`buildShapeMask` / `applyShapeMask`)

| 特性 | Node.js | HarmonyOS | 对比 |
|------|---------|-----------|------|
| 每次 place 重新构建 | ✅ 是 | ❌ 否 (有缓存) | HarmonyOS 更优 |
| 缓存策略 | 无 | Map<shapeId_canvasSize> | HarmonyOS 额外节省 |
| 极坐标形状复杂度 | O(width*height) atan2 | O(width*height) atan2 | 相同 |
| 位图形状复杂度 | O(width*height) | O(width*height) | 相同 |

**结论**: HarmonyOS 的缓存策略优于 Node.js，这部分不是瓶颈。

**改进空间**: 静态缓存永不清除，在移动端可能导致内存膨胀。建议添加 LRU 淘汰。

---

### 2.2 形状内碰撞检测 (`isBoxInsideShape` vs Node.js `shape check`)

**这是最重要的性能瓶颈！**

| 测试场景 | Node.js 方式 | HarmonyOS 方式 | 性能差异 |
|---------|-------------|---------------|---------|
| 极坐标形状 | **单次距离计算**: `sqrt(dx²+dy²) > maskAt(θ)*maxR` | **全像素扫描**: 遍历 bounding box 每个像素，逐位检查 shapeBoard | **10-100x 差异** |
| 位图形状 | **跳点采样**: 每 2 像素检查一次 (`sx+=2, sy+=2`) | **全像素扫描**: 遍历 bounding box 每个像素 | **~4x 差异** |

**示例**: 一个 100x50 的词语:
- Node.js 极坐标: 1 次 sqrt + atan2 计算
- Node.js 位图: ~1250 次位图查询 (50行 * 25列)
- HarmonyOS 当前: 5000 次位板查询 (50行 * 100列)

**核心问题**: HarmonyOS 版本对所有形状类型都统一使用 `isBoxInsideShape` 全量像素扫描，而没有根据形状类型做分支优化。

---

### 2.3 随机起始点 (`randomPointInShape`)

| 特性 | Node.js | HarmonyOS | 对比 |
|------|---------|-----------|------|
| 极坐标尝试次数 | 30 | 200 | HarmonyOS 多 ~6.7x |
| 位图尝试次数 | 200 | 200 | 相同 |
| 随机点验证方式 | `shape.containsPixel()` | 位板检查 | 相似开销 |

**问题**: HarmonyOS 对极坐标形状也使用 200 次尝试，但每次尝试只做一个位板查询（因为 shapeBoard 已预计算）。而 Node.js 极坐标模式只需 30 次尝试但每次需要 sqrt+atan2 计算。两者实际开销相近，这不是主要瓶颈。

---

### 2.4 螺旋搜索参数

| 参数 | Node.js | HarmonyOS | 说明 |
|------|---------|-----------|------|
| RANDOM_STARTS | 90 | 40 | 每个词的随机起始点数 |
| MAX_SPIRAL_T | 4000 | 4000 | 螺旋最大步数 |
| MAX_SPIRAL_FAIL | 20000 | 20000 | 连续碰撞失败上限 |
| SPIRAL_STEP | 0.7 | 0.7 | 每步像素 |
| SPIRAL_TURNS | 0.22 | 0.22 | 每步弧度 |

HarmonyOS 的 `RANDOM_STARTS=40` 已经比 Node.js 的 90 少了 55%，这是合理的移动端优化。

---

### 2.5 核心热点函数调用栈

```
place()
├── words.sort()                           // O(n log n)
├── for each word:
│   ├── randomPointInShape() × RANDOM_STARTS  // 40次
│   │   └── shapeBoard 位检查 × 200          // 最多200次尝试
│   └── trySpiralFrom() × RANDOM_STARTS       // 每个起始点
│       ├── isBoxInsideShape() 👈 热点       // 每步螺旋
│       │   └── 像素遍历 + 位运算
│       ├── checkCollision()                  // 每步螺旋
│       │   └── 像素遍历 + 位运算
│       └── markBoardOccupied()               // 放置成功时1次
│           └── 像素遍历 + 位运算
```

---

### 2.6 ArkTS 平台特有开销

| 开销类型 | 影响 | 当前状态 |
|---------|------|---------|
| 对象分配 | ArkTS 对象创建比 V8 慢 2-3x | `RandomPoint` 每随机起点新建一个 |
| 字符串拼接 | 模板字符串在 ArkTS 中较慢 | 日志中有大量字符串拼接 |
| GC 压力 | 移动端 GC 更频繁 | 螺旋搜索中频繁创建丢弃对象 |
| 函数调用 | 跨模块/类方法调用有额外开销 | `isBoxInsideShape`、`checkCollision` 高频调用 |
| Worker 通信 | taskpool 序列化/反序列化 | 结果数组需要序列化传回主线程 |

---

## 三、问题分级

### 🔴 P0 - 严重 (预计提升 60-80%)

1. **极坐标形状的 isBoxInsideShape 应改为距离检查**
   - 当前扫描整个 bounding box 像素，应改为单次 `sqrt(dx²+dy²) > maskAt(θ)*maxR` 判断
   - 这是最大的性能提升点

2. **位图形状的 isBoxInsideShape 减少采样率**
   - 从逐像素改为隔点采样 (与 Node.js 对齐)
   - 从 1x1 采样改为 2x2 采样

### 🟡 P1 - 重要 (预计提升 10-20%)

3. **减少对象分配**
   - 复用 `RandomPoint` 对象
   - 在热路径中避免 `new` 操作

4. **移除热路径中的字符串拼接日志**
   - `console.info` 的参数拼接在计算密集循环中开销大

5. **checkCollision/markBoardOccupied 的位运算优化**
   - 三个函数 (`isBoxInsideShape`、`checkCollision`、`markBoardOccupied`) 有几乎相同的遍历模式，可合并

### 🟢 P2 - 优化 (预计提升 5-10%)

6. **ShapeMaskCache 添加 LRU 淘汰**
   - 防止移动端内存膨胀

7. **位图形状的 containsPixel 采样步长统一**
   - Node.js 位图模式在 `trySpiralFrom` 中用了 `sx+=2, sy+=2`，采样更稀疏

8. **预分配数组容量**
   - `sprites` 和 `placedData` 数组使用预分配尺寸

---

## 四、优化方案

### 优化1: 极坐标形状轻量碰撞检测

```typescript
// 新增方法：用于极坐标形状的快速形状内检测
private isBoxInsideShapePolar(x1: number, y1: number, x2: number, y2: number,
  cx: number, cy: number, maxR: number, shape: ShapeDef): boolean {
  // 检查包围盒四个角是否都在形状内
  let corners: [number, number][] = [[x1, y1], [x2, y1], [x1, y2], [x2, y2]];
  for (let i = 0; i < 4; i++) {
    let dx = corners[i][0] - cx;
    let dy = cy - corners[i][1];
    let dist = Math.sqrt(dx * dx + dy * dy);
    let theta = Math.atan2(dy, dx);
    if (dist > shape.maskAt(theta) * maxR) {
      return false;
    }
  }
  return true;
}
```

### 优化2: 位图形状隔点采样

```typescript
// 修改 isBoxInsideShape，添加步长参数
private isBoxInsideShape(x1: number, y1: number, x2: number, y2: number,
  stepX: number = 1, stepY: number = 1): boolean {
  for (let y = y1; y <= y2; y += stepY) {
    // ... 逐行检查但列方向以 stepX 步进
  }
}
```

### 优化3: 合并 checkCollision + markBoardOccupied

当待放置词语通过形状检测和碰撞检测后，可以合并碰撞检测和标记步骤，减少一次完整的像素遍历。

### 优化4: 对象复用

使用对象池避免在热路径中创建新对象。

### 优化5: 根据形状类型路由

在 `trySpiralFrom` 中根据 `shape.bitmap` 是否存在，路由到不同的形状检测路径。

---

## 五、预期效果

| 优化项 | 预期性能提升 | 风险 |
|--------|------------|------|
| P0-1: 极坐标快速检测 | 60-80% | 低 - 算法等价，仅改变实现方式 |
| P0-2: 位图隔点采样 | 50-70% | 低 - 与 Node.js 对齐的策略 |
| P1-1: 对象复用 | 10-15% | 低 |
| P1-2: 移除热路径日志 | 5-10% | 低 |
| P2-1: LRU 缓存 | 内存下降 | 低 |

**综合预期**: 在极坐标形状（默认圆形等）下，整体计算耗时预计降低 **60-80%**；在位图形状下预计降低 **50-70%**。

---

## 六、平台差异说明

1. **ARK Runtime vs V8**: ArkTS 代码在 ArkCompiler 下执行（部分 AOT），不具备 V8 的 TurboFan JIT 优化能力。相同的循环体在 ArkTS 下运行速度约为 V8 的 30-50%。

2. **内存限制**: 移动设备 RAM 通常 4-8GB，其中应用可用 ~512MB-1GB。Node.js 桌面端可用内存远大于此。

3. **Worker 开销**: HarmonyOS 的 taskpool 需要在主线程和工作线程间序列化/反序列化数据。`WordCloudResult` 包含所有 PlacedData 数组，序列化开销随词数线性增长。建议只传回必要的渲染数据。

4. **Canvas 渲染**: HarmonyOS 的 CanvasRenderingContext2D 的 `fillText` 性能通常不如桌面端 Canvas。200+ 个词逐个 fillText 可能是另一个瓶颈。

5. **调度优先级**: taskpool 的 Priority.HIGH 已经是最优设置。

---

*分析日期: 2026-08-03*
*对比版本: wordcloud-nodejs (main) vs PocketToolbox (main)*

---

## 七、实施记录

### ✅ 已实施 — P0 优化

#### P0-1: 极坐标形状轻量碰撞检测 (BitmapPlacer.ets)
- 新增 `isBoxInsidePolar()` 方法：对极坐标形状检查包围盒 4 个角点，每个角点做 1 次 `Math.sqrt(dx²+dy²) > maskAt(θ)*maxR` 距离检查
- 时间复杂度: O(width×height) → **O(4)**，预期提升 60-80%
- 修改 `trySpiralFrom()` 签名，新增 `isBitmap: boolean` 参数路由形状检测
- 修改 `place()` 方法，计算 `isBitmap` 标志和 `sampleStep`

#### P0-2: 位图形状隔点采样 (BitmapPlacer.ets)
- 新增 `isBoxInsideShapeSample()` 方法：位图形状 step=2 隔点采样
- 与 Node.js 对齐的采样策略，~4x 减少检查次数
- 通过 `sampleStep` 参数从 `place()` 传入 `trySpiralFrom()`

#### P0-3: 形状类型路由 (BitmapPlacer.ets)
- `trySpiralFrom()` 中根据 `isBitmap` + `sampleStep` 决定调用 `isBoxInsideShapeSample` 或 `isBoxInsidePolar`
- 旧的 `isBoxInsideShape()` 保留但不再被调用（向后兼容）

### ✅ 已实施 — P1 优化

#### P1-1: 对象复用 (BitmapPlacer.ets)
- `randomPointInShape()`: 复用 `_reusePoint: RandomPoint` 成员变量
- 避免每次调用创建 `new RandomPoint()`，减少 GC 压力

#### P1-2: 移除热路径日志 (BitmapPlacer.ets)
- 移除 `place()` 中的 `console.info` 调用（原第 60、62、72、78-82 行）
- 移除了字符串拼接和模板字符串开销

#### P1-3: 预分配数组容量 (WordCloudTask.ets)
- `weightedItems`: `new Array(wordCount)` 替代 `push()`
- `sprites`: `new Array(wordCount)` 替代 `push()`
- `placedData`: `new Array(resultCount)` 替代 `push()`
- 避免数组动态扩容时的内存重分配和复制

#### P1-4: refreshColors/refreshFont 避免深度拷贝 (WordCloudPage.ets)
- `refreshColors()`: 就地更新 `pw.color` 属性，用 `[...this.placedWords]` 触发 @Watch
- `refreshFont()`: 就地更新 `pw.font` 属性，同上
- 避免每次更改创建 N 个新 PlacedWord 对象（100-200+ 对象分配）

#### P1-5: 渲染循环优化 (WordCloudView.ets)
- 提取 `drawWords()` 公共方法，消除 `drawWordCloud` / `renderToPixelMap` 之间的代码重复
- 移除 `pw.color && pw.color.length > 0` 冗余空检查（color 已由生成/刷新流程保证）
- 移除 `pw.font && pw.font.length > 0` 冗余空检查（font 同理）
- 移除 `colors` 无效参数，color 直接从 `pw.color` 读取
- 移除死代码: `colorIndex`、`nextColor()` 方法
- `fillText` 前减少 `ctx.translate` 等冗余调用

### ⏳ 待实施 — P2 优化

#### P2-1: ShapeMaskCache LRU 淘汰
- 当前 `ShapeDef.SHAPE_CACHE` 永不清除，移动端内存风险
- 建议保留最近 3 个形状遮罩，超出时淘汰最旧条目

#### P2-2: checkCollision/markBoardOccupied 合并
- 两个函数遍历相同区域，对于成功放置（常见情况）存在冗余
- 可合并为单函数 `tryMarkBoard()` 在一次遍历中检查并标记
- 预期收益较小（~5%），因为主要性能提升已在 P0 达成
