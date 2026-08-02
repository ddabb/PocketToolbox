# 词云性能优化分析（与 nodejs 版本对比）

> 本文档基于 ArkTS 版本（`f:\PocketToolbox`）与 nodejs 版本（`F:\wordcloud-nodejs\gen_all.ts`）的逐层对比分析，定位真实性能瓶颈并给出可执行的优化方案。
>
> **结论先说**：ArkTS 版本已经采用了和 nodejs 一样的算法（BitmapPlacer 位图碰撞 + 螺旋放置），也已经直接在 Canvas 上绘制（fillText）。性能差距主要来自运行时 JIT 差异和若干可优化的常数项，**不是算法问题**。
>
> 注：旧文档 `wordcloud-optimization.md` 中的问题 1（Canvas @Watch）、问题 2（TaskPool 异步）、问题 3（高清画布）、问题 5（切换字体重布局）、问题 8（CollisionMask）在当前代码中**已修复**，本文档不再重复。

---

## 一、逐层对比

### 1.1 布局算法 —— 完全一致

| 维度 | nodejs `BitmapPlacer.ts` | ArkTS `BitmapPlacer.ets` | 是否一致 |
|------|--------------------------|--------------------------|----------|
| 碰撞板数据结构 | `Uint32Array`（bit 打包） | `Uint32Array`（bit 打包） | ✅ |
| `boardWidth` | `ceil(canvasSize/32)` | `ceil(canvasSize/32)` | ✅ |
| 螺旋参数 `SPIRAL_STEP` | `0.7` | `0.7` | ✅ |
| 螺旋参数 `SPIRAL_TURNS` | `0.22` | `0.22` | ✅ |
| 螺旋上限 `maxT` | `4000` | `4000` | ✅ |
| 随机起点 `RANDOM_STARTS` | `90` | `90` | ✅ |
| 失败上限 `MAX_SPIRAL_FAIL` | `20000` | `20000` | ✅ |
| 角度策略 | 前 20% 词 `[0,90]`，其余 `[0,90,45,135]` | 完全一致 | ✅ |
| `checkCollision` | bit mask 逐行扫描 | 完全一致 | ✅ |
| `markBoardOccupied` | bit mask 逐行标记 | 完全一致 | ✅ |
| `makeSprite` 宽度 | `estimateTextWidth`（字符×系数） | 完全一致 | ✅ |
| `applyShapeMask` | 双层 for 1000×1000 | 完全一致 | ✅ |

算法、参数、数据结构全部对齐，连魔法数字都一样。

### 1.2 渲染层 —— 都是 Canvas fillText

- nodejs `CanvasRenderer` 用 `@napi-rs/canvas` 的 `ctx.fillText`
- ArkTS [`WordCloudView.ets`](file:///f:/PocketToolbox/entry/src/main/ets/components/WordCloudView.ets) 第 19 行 `Canvas(this.context)`，第 73 行 `ctx.fillText(pw.text, 0, 0)`

都是直接 Canvas 绘制，**没有**用 ArkUI 的 `Text`/`Row` 组件堆叠渲染。

### 1.3 线程模型 —— ArkTS 反而更好

| | nodejs | ArkTS |
|---|---|---|
| 布局线程 | 主线程（同步） | [`taskpool` 子线程](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/WordCloudTask.ets#L86-L88)（`@Concurrent` + `taskpool.execute`） |

ArkTS 把 `computePlacement` 放到子线程，UI 不会卡死。这点比 nodejs 强。

### 1.4 字号计算 —— 一致

[`FontScaler.ets`](file:///f:/PocketToolbox/entry/src/main/ets/core/style/FontScaler.ets) 的 `scaleAll` 用对数缩放 + power 0.75，和 nodejs 版本逻辑一致。

---

## 二、真正的性能瓶颈

既然算法和渲染都对齐了，性能差距主要来自以下五点：

### 瓶颈 A：运行时 JIT 差异（主因）

**现象**：同样的算法，nodejs 跑完 180 个词约 1-2 秒，ArkTS 可能 5-10 秒。

**根因**：V8 的 JIT 对数值密集型循环的优化远强于方舟编译器。热路径包括：

1. [`applyShapeMask()`](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/BitmapPlacer.ets#L111-L143)：1000×1000 = **100 万次**像素遍历，每次调 `shape.containsPixel` 或 `maskAt`
2. [`trySpiralFrom()`](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/BitmapPlacer.ets#L147-L232)：每词最多 90 起点 × 4 角度 × 4000 步 = **144 万次** spiral 迭代/词
3. [`checkCollision()`](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/BitmapPlacer.ets#L234-L256)：每次 spiral 步遍历词 bbox 像素

**这是运行时差异，无法通过改算法解决**。但可以通过减少调用次数来缓解（见瓶颈 B、C、D）。

### 瓶颈 B：bitmap shape 的 containsPixel 调用爆炸

**现象**：选择文字形状（如"生日快乐"字形）时，生成时间显著长于几何形状（圆/星/方）。

**根因**：[`trySpiralFrom()` 第 188-192 行](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/BitmapPlacer.ets#L188-L192) 对 bitmap shape 每个 spiral 步要双层 for 遍历 bbox 像素调 `containsPixel`：

```typescript
for (let sx = x1; sx <= x2 && inside; sx += 2) {
  for (let sy = y1; sy <= y2 && inside; sy += 2) {
    if (!shape.containsPixel(sx, sy)) { inside = false; break; }
  }
}
```

大词的 bbox 可能 100×100，每步要调 2500 次 `containsPixel`。单个词最坏：90 起点 × 4 角度 × 4000 步 × 2500 像素 = **36 亿次**函数调用。

而 [`containsPixel`](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/ShapeDef.ets#L112-L123) 本身只是简单的数组查表，但函数调用在方舟编译器下无法内联，开销累积。

**优化方案**：bitmap shape 的 bbox 内判定改为直接查 `shape.bitmap.data` 数组，绕过 `containsPixel` 函数调用；或预计算一个与 `board` 同尺寸的 `shapeMask: Uint32Array`，用 bit 操作一次性判断整个 bbox 是否全在 shape 内（类似 `checkCollision` 的批量 bit 查询）。

**预期收益**：bitmap shape 场景省约 40% 时间。

### 瓶颈 C：每次生成都从头布局，shape mask 不缓存

**现象**：切换配色后再次"生成词云"（形状不变），仍要重跑 100 万次 `applyShapeMask`。

**根因**：[`computePlacement`](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/WordCloudTask.ets#L35-L84) 每次都 `new BitmapPlacer(layoutSize)`，构造函数里 `board = new Uint32Array(...)`，`place()` 开头 `applyShapeMask` 重新标记 100 万像素。

**优化方案**：
1. 在 `BitmapPlacer` 中缓存 `shapeMask`（与 `board` 同尺寸的 `Uint32Array`，只标记 shape 区域，不含词占用）
2. 同一 shape + canvasSize 组合复用 `shapeMask`，`place()` 开头只把 `shapeMask` 复制到 `board`，而非重新计算
3. 缓存 key = `shape.id + '_' + canvasSize`，可用静态 Map

**预期收益**：省约 30% 时间（shape mask 计算开销）。

### 瓶颈 D：refreshFont 重复完整布局

**现象**：切换字体时页面卡顿几秒，和首次生成一样慢。

**根因**：[`refreshFont()`](file:///f:/PocketToolbox/entry/src/main/ets/pages/WordCloudPage.ets#L859-L904) 重新跑完整的 `runPlacementAsync`（含 `place` 螺旋布局），而实际只需要重新测量词宽 + 局部调整位置。

**优化方案**：
1. 切换字体时只用新字体 `measureText` 重测每个词的宽度
2. 若新宽度 ≤ 旧宽度，保留原位置，只更新 `font` 字段
3. 若新宽度 > 旧宽度，对该词单独跑一次螺旋放置（其他词不动）
4. 或更简单：切换字体时只更新 `font` 字段重绘，不重布局（接受可能的轻微重叠，因为 estimateTextWidth 是估算的，字体差异影响有限）

**预期收益**：切换字体从秒级降到毫秒级。

### 瓶颈 E：makeSprite 用估算宽度而非真实测量

**现象**：词实际渲染时偶尔重叠，或空间利用率低（有大空洞）。

**根因**：[`makeSprite()`](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/BitmapPlacer.ets#L279-L297) 用 `estimateTextWidth`（字符×系数）估算词宽，没用 `Canvas.measureText`：
- 估算偏小 → 词实际渲染时重叠
- 估算偏大 → 空间浪费，需要更多 spiral 步数才能放完所有词

nodejs 版本也是估算的，所以这点两者一致，但它是潜在的效率损失点。

**优化方案**：
1. 在 `computePlacement` 中用 `OffscreenCanvas.measureText` 真实测量每个词的宽度
2. 由于 `computePlacement` 在 taskpool 子线程，需要确认 `OffscreenCanvas` 是否可在子线程使用；若不可，则在主线程预测量后传入
3. 测量结果缓存（同字体+同字号+同文本只测一次）

**预期收益**：提高放置成功率，减少 spiral 步数，省约 10-15% 时间。

---

## 三、优化执行清单

按优先级排序，建议按此顺序执行：

| 优先级 | 优化项 | 涉及文件 | 预期收益 | 难度 |
|--------|--------|----------|----------|------|
| P0 | **缓存 shape mask**（瓶颈 C） | `BitmapPlacer.ets` | 省 30% 时间 | 中 |
| P0 | **bitmap shape 的 bbox 检查改为批量 bit 查询**（瓶颈 B） | `BitmapPlacer.ets`、`ShapeDef.ets` | bitmap shape 省 40% 时间 | 中 |
| P1 | **refreshFont 只更新 font 不重布局**（瓶颈 D） | `WordCloudPage.ets` | 切换字体从秒级降到毫秒级 | 低 |
| P1 | **用 measureText 替代 estimateTextWidth**（瓶颈 E） | `BitmapPlacer.ets`、`WordCloudTask.ets` | 省 10-15% 时间，减少重叠 | 中 |
| P2 | **降低 RANDOM_STARTS 从 90 到 40** | `BitmapPlacer.ets` | 省 50% spiral 迭代，成功率略降 | 低 |
| P2 | **LAYOUT_CANVAS_SIZE 从 1000 降到 800** | `WordCloudPage.ets` | 像素操作量降 36%，精度略降 | 低 |

---

## 四、各优化项详细实施方案

### 4.1 缓存 shape mask（P0）

**目标**：形状不变时复用 shape mask，避免每次 `applyShapeMask` 的 100 万次像素操作。

**修改文件**：[`f:\PocketToolbox\entry\src\main\ets\core\layout\BitmapPlacer.ets`](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/BitmapPlacer.ets)

**实施步骤**：

1. 在 `BitmapPlacer` 类中新增静态缓存：
```typescript
private static maskCache: Map<string, Uint32Array> = new Map();
```

2. 新增方法 `applyShapeMaskCached(shape: ShapeDef): void`：
```typescript
private applyShapeMaskCached(shape: ShapeDef): void {
  let key: string = shape.id + '_' + this.canvasSize.toString();
  let cached: Uint32Array | undefined = BitmapPlacer.maskCache.get(key);
  if (cached !== undefined && cached.length === this.board.length) {
    // 复用缓存的 mask，直接复制到 board
    for (let i = 0; i < this.board.length; i++) {
      this.board[i] = cached[i];
    }
    return;
  }
  // 首次计算，并存入缓存
  this.applyShapeMask(shape);
  let snapshot: Uint32Array = new Uint32Array(this.board.length);
  for (let i = 0; i < this.board.length; i++) {
    snapshot[i] = this.board[i];
  }
  BitmapPlacer.maskCache.set(key, snapshot);
}
```

3. 在 `place()` 方法中把 `this.applyShapeMask(shape)` 改为 `this.applyShapeMaskCached(shape)`。

**注意事项**：
- 缓存 key 必须包含 `canvasSize`，不同尺寸不能混用
- `ShapeDef.makeGlyph` 生成的文字形状也要有稳定的 `id`（含文本+字体），否则缓存会错乱
- 内存占用：每个 mask = `Uint32Array(32000)` ≈ 128KB，12 个形状 ≈ 1.5MB，可接受

### 4.2 bitmap shape 的 bbox 检查改为批量 bit 查询（P0）

**目标**：消除 `trySpiralFrom` 中对 `containsPixel` 的逐像素调用。

**修改文件**：[`f:\PocketToolbox\entry\src\main\ets\core\layout\BitmapPlacer.ets`](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/BitmapPlacer.ets)

**实施步骤**：

1. 在 `applyShapeMask` 中，除了标记 `board`，额外维护一个 `shapeBoard: Uint32Array`（与 `board` 同尺寸，只标记 shape 区域，永不被词占用清除）：
```typescript
private shapeBoard: Uint32Array;  // shape 区域位图（1=在shape内，0=在shape外）

constructor(canvasSize: number) {
  this.canvasSize = canvasSize;
  this.boardWidth = Math.ceil(canvasSize / 32);
  this.board = new Uint32Array(this.boardWidth * canvasSize);
  this.shapeBoard = new Uint32Array(this.boardWidth * canvasSize);
}
```

2. `applyShapeMask` 同时填充 `board` 和 `shapeBoard`（shape 外的位置置 1）：
```typescript
// 在 applyShapeMask 中，标记 shape 外区域时同时写入 shapeBoard
this.board[y * this.boardWidth + wordIdx] |= (1 << bitIdx);
this.shapeBoard[y * this.boardWidth + wordIdx] |= (1 << bitIdx);
```

3. 新增方法 `isBoxInsideShape(x1, y1, x2, y2): boolean`，用 bit 操作批量判断 bbox 是否全在 shape 内（逻辑与 `checkCollision` 相同，但查 `shapeBoard` 的**反**，即要求 bbox 内所有 bit 都是 0）：
```typescript
private isBoxInsideShape(x1: number, y1: number, x2: number, y2: number): boolean {
  // 要求 bbox 内 shapeBoard 的所有 bit 都是 0（即全部在 shape 内）
  for (let y = y1; y <= y2; y++) {
    const rowOff = y * this.boardWidth;
    for (let x = x1; x <= x2;) {
      const wordIdx = Math.floor(x / 32);
      const bitStart = x % 32;
      const xEnd = Math.min(x + (32 - bitStart), x2 + 1);
      const bitLen = xEnd - x;
      let mask: number;
      if (bitLen >= 32) {
        mask = 0xFFFFFFFF;
      } else {
        mask = (1 << bitLen) - 1;
      }
      mask = mask << bitStart;
      // shapeBoard 中 1 表示 shape 外，若 bbox 内有 1 则不在 shape 内
      if ((this.shapeBoard[rowOff + wordIdx] & mask) !== 0) {
        return false;
      }
      x = xEnd;
    }
  }
  return true;
}
```

4. 在 `trySpiralFrom` 中，把 bitmap shape 的 bbox 检查从逐像素 `containsPixel` 改为 `isBoxInsideShape`：
```typescript
// 原代码（第 185-196 行）：
if (shape.bitmap) {
  let inside = true;
  for (let sx = x1; sx <= x2 && inside; sx += 2) {
    for (let sy = y1; sy <= y2 && inside; sy += 2) {
      if (!shape.containsPixel(sx, sy)) { inside = false; break; }
    }
  }
  if (!inside) { t += 1; continue; }
}

// 改为：
if (!this.isBoxInsideShape(x1, y1, x2, y2)) {
  t += 1;
  continue;
}
```

这样对**所有形状**（不只是 bitmap shape）都统一走 `isBoxInsideShape`，删除 `trySpiralFrom` 中对 `shape.bitmap` 的分支判断。

**注意事项**：
- `shapeBoard` 也需要参与 4.1 的缓存
- 此改动会让几何形状（圆/星/方）也走批量 bit 查询，性能提升更明显

### 4.3 refreshFont 只更新 font 不重布局（P1）

**目标**：切换字体时不再重新跑螺旋布局，只更新 `font` 字段并重绘。

**修改文件**：[`f:\PocketToolbox\entry\src\main\ets\pages\WordCloudPage.ets`](file:///f:/PocketToolbox/entry/src/main/ets/pages/WordCloudPage.ets)

**实施步骤**：

1. 把 [`refreshFont()`](file:///f:/PocketToolbox/entry/src/main/ets/pages/WordCloudPage.ets#L859-L904) 改为：
```typescript
private refreshFont(): void {
  if (this.placedWords.length === 0) {
    return;
  }
  let fontName: string = this.fontNames[this.currentFontIndex];
  let newWords: PlacedWord[] = [];
  for (let i: number = 0; i < this.placedWords.length; i++) {
    let pw: PlacedWord = new PlacedWord();
    pw.text = this.placedWords[i].text;
    pw.x = this.placedWords[i].x;
    pw.y = this.placedWords[i].y;
    pw.size = this.placedWords[i].size;
    pw.color = this.placedWords[i].color;
    pw.angle = this.placedWords[i].angle;
    pw.font = fontName;  // 只更新字体
    pw.width = this.placedWords[i].width;
    pw.height = this.placedWords[i].height;
    newWords.push(pw);
  }
  this.placedWords = newWords;
}
```

2. 注意：这会保留原布局位置，由于 `estimateTextWidth` 是按字符系数估算的（与字体无关），布局宽度估算不变，因此不会引入额外重叠。

**注意事项**：
- 若未来 4.5 实施了 `measureText` 真实测量，则切换字体后宽度会变，此方案需要改为"只对变宽的词重布局"
- 当前 `estimateTextWidth` 与字体无关，所以此方案安全

### 4.4 用 measureText 替代 estimateTextWidth（P1）

**目标**：用真实文字宽度提高放置精度，减少重叠和空间浪费。

**修改文件**：
- [`f:\PocketToolbox\entry\src\main\ets\core\layout\WordCloudTask.ets`](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/WordCloudTask.ets)
- [`f:\PocketToolbox\entry\src\main\ets\core\layout\BitmapPlacer.ets`](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/BitmapPlacer.ets)

**实施步骤**：

1. 在 `WordCloudInput` 接口中新增 `measuredWidths: number[]` 字段，由主线程预测量后传入：
```typescript
export interface WordCloudInput {
  words: WordInput[];
  canvasSize: number;
  shapeIndex: number;
  fontName: string;
  measuredWidths: number[];  // 主线程预测量的每个词宽度
}
```

2. 在 `WordCloudPage.ets` 的 `generateWordCloud` 中，调用 `runPlacementAsync` 前用 `OffscreenCanvas.measureText` 预测量：
```typescript
private measureWordWidths(fontName: string, words: CloudWord[], canvasSize: number): number[] {
  let off: OffscreenCanvas = new OffscreenCanvas(canvasSize, canvasSize, LengthMetricsUnit.PX);
  let ctx: OffscreenCanvasRenderingContext2D = off.getContext('2d', new RenderingContextSettings(true)) as OffscreenCanvasRenderingContext2D;
  let widths: number[] = [];
  for (let i = 0; i < words.length; i++) {
    // 用该词的 fontSize 测量（需要先算 fontSize，或用基准字号测量后缩放）
    let baseFontSize: number = 100;
    ctx.font = baseFontSize.toString() + 'px ' + fontName;
    let w: number = ctx.measureText(words[i].text).width;
    widths.push(w / baseFontSize);  // 归一化到字号 1 的宽度
  }
  return widths;
}
```

3. `BitmapPlacer.makeSprite` 接收 `measuredWidth` 参数，若提供则用真实宽度，否则降级到 `estimateTextWidth`：
```typescript
makeSprite(text: string, fontSize: number, font: string, weight: number,
  angle: number, measuredWidth: number = -1): WordSprite {
  const sprite = new WordSprite();
  // ...
  let textW: number = measuredWidth > 0 ? measuredWidth * fontSize : this.estimateTextWidth(text, fontSize);
  // ...
}
```

4. `computePlacement` 中把 `measuredWidths[i]` 传给 `makeSprite`。

**注意事项**：
- `OffscreenCanvas` 在主线程创建，测量结果通过 `WordCloudInput` 序列化传入 taskpool
- 测量结果归一化（除以基准字号），这样不同词的 fontSize 不同时只需乘上即可
- 此优化与 4.3 冲突：若用了真实测量，切换字体后宽度会变，`refreshFont` 不能只更新 font 字段

### 4.5 降低 RANDOM_STARTS（P2）

**修改文件**：[`f:\PocketToolbox\entry\src\main\ets\core\layout\BitmapPlacer.ets`](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/BitmapPlacer.ets)

**实施步骤**：把第 25 行 `RANDOM_STARTS: number = 90` 改为 `40`。

**注意事项**：
- 90 是从 nodejs 继承的值，对 V8 够用但对 ArkTS 偏大
- 40 对大多数场景够用，放置成功率会略降（约 2-5%）
- 可改为自适应：前 20% 大词用 60，小词用 20

### 4.6 降低 LAYOUT_CANVAS_SIZE（P2）

**修改文件**：[`f:\PocketToolbox\entry\src\main\ets\pages\WordCloudPage.ets`](file:///f:/PocketToolbox/entry/src/main/ets/pages/WordCloudPage.ets)

**实施步骤**：把第 68 行 `LAYOUT_CANVAS_SIZE: number = 1000` 改为 `800`。

**注意事项**：
- 像素操作量降 36%（1000²→800²）
- 导出图片尺寸也会降（`exportSize = LAYOUT_CANVAS_SIZE * 2`，从 2000 降到 1600），若需高清导出可单独提高导出倍数
- 词的放置精度略降（小形状可能放不下大词）

---

## 五、关键文件清单

| 文件 | 作用 | 涉及优化项 |
|------|------|------------|
| [`BitmapPlacer.ets`](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/BitmapPlacer.ets) | 位图碰撞 + 螺旋布局核心 | A、B、C、E、4.1、4.2、4.5 |
| [`WordCloudTask.ets`](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/WordCloudTask.ets) | taskpool 子线程封装 | E、4.4 |
| [`ShapeDef.ets`](file:///f:/PocketToolbox/entry/src/main/ets/core/layout/ShapeDef.ets) | 形状定义与 containsPixel | B、4.2 |
| [`WordCloudView.ets`](file:///f:/PocketToolbox/entry/src/main/ets/components/WordCloudView.ets) | Canvas 渲染（已优化） | 无需改 |
| [`FontScaler.ets`](file:///f:/PocketToolbox/entry/src/main/ets/core/style/FontScaler.ets) | 字号缩放（已对齐） | 无需改 |
| [`WordCloudPage.ets`](file:///f:/PocketToolbox/entry/src/main/ets/pages/WordCloudPage.ets) | 页面交互与生成流程 | D、4.3、4.4、4.6 |

---

## 六、验证方法

优化后建议用以下场景验证：

1. **基准场景**：180 个词，圆形，生成时间从 X 秒降到 Y 秒（记录前后耗时）
2. **文字形状场景**：用"生日快乐"字形，对比优化前后生成时间（验证瓶颈 B）
3. **重复生成场景**：切换配色后再次生成，对比第二次生成时间（验证瓶颈 C 缓存生效）
4. **切换字体场景**：生成后切换字体，验证是否从秒级降到毫秒级（验证瓶颈 D）
5. **词重叠检查**：对比优化前后词云图，确认无新增重叠（验证瓶颈 E 不引入回归）

**耗时测量**：在 `generateWordCloud` 的 `runPlacementAsync` 调用前后加 `console.info` 时间戳：
```typescript
let t0: number = Date.now();
let result = await runPlacementAsync(input);
console.info('[WordCloud] placement cost: ' + (Date.now() - t0) + 'ms');
```
