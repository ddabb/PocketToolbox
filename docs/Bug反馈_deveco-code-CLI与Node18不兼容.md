# 【Bug 反馈】deveco-code CLI 在 Node.js 18 环境下启动崩溃（依赖 string-width 8.x 使用 Node 20+ 专有正则语法）

| 项目 | 内容 |
| --- | --- |
| 组件 | @deveco/deveco-code（deveco CLI，含 devecocli 命令及 DevEco Code 工具链 build/docs 等） |
| 版本 | 0.1.10（安装来源：npm 全局安装；官方已提示 1.3.2 可用，请一并核实 1.3.2 是否已修复） |
| 严重级别 | **阻断（Blocker）**：CLI 所有子命令均无法执行 |
| 发生环境 | Windows 10/11 + DevEco Studio 标准安装（PATH 中自带 Node 18 优先） |
| 复现概率 | 100%（满足"PATH 中 node < 20"即必现） |

---

## 一、问题概述

`deveco` CLI（以及 DevEco Code 工具链中的 `build_project`、`devecocli docs` 等功能）在启动时加载 JS 代码阶段直接崩溃，抛出 `SyntaxError: Invalid regular expression flags`。

根因是依赖树中的 `string-width@8.2.2` 使用了正则 `v` flag（Unicode Sets，Node 20+ 才支持），而该包 `engines` 声明 `node >= 20`。但 CLI 实际运行时通过 PATH 解析 `node`，在所有标准 DevEco Studio 安装的机器上，PATH 中排在最前的是 DevEco Studio 自带的 **Node 18.20.1**（`<DevEco Studio 安装目录>\tools\node`），导致必然命中不兼容。

即：**DevEco Studio 自带 Node 18 + deveco-code 依赖要求 Node 20+，两者在同一台机器上的默认组合 100% 冲突。**

---

## 二、环境信息

| 项 | 值 |
| --- | --- |
| 操作系统 | Windows（win32），PowerShell 5.1 |
| DevEco Studio | 6.1.1.300（自带 Node v18.20.1，位于 `F:\DevEco Studio\tools\node`，安装器已将其加入 PATH 且排在其他 Node 之前） |
| 系统 Node | v24.20.0（`C:\Program Files\nodejs`，PATH 顺序靠后，未被 CLI 使用） |
| deveco-code | 0.1.10，npm 全局安装于 `F:\MigratedFolders\npm` |
| SDK | HarmonyOS 6.1.1（API 24），`F:\DevEco Studio\sdk\default` |
| 测试项目 | F:\PocketToolbox（ArkTS 工程，targetSdkVersion 5.1.0(18)） |

`where node` 结果（PATH 顺序）：

```
F:\DevEco Studio\tools\node\node.exe      <- v18.20.1，CLI 实际使用的解释器
C:\Program Files\nodejs\node.exe         <- v24.20.0
```

---

## 三、复现步骤

1. 全新安装 DevEco Studio（任意近期版本，自带 Node 18.20.1 并置于 PATH 首位）；
2. `npm i -g @deveco/deveco-code`；
3. 在任意终端执行 `deveco build`（或 `deveco docs`、`deveco --help` 等任何会加载完整 JS 入口的命令）；
4. CLI 在输出任何业务内容前崩溃。

亦可通过 DevEco Code 工具链（MCP/Agent）触发：`build_project`、`devecocli docs search <keyword>` 均报同样错误。

## 四、预期行为 vs 实际行为

- **预期**：CLI 兼容 DevEco Studio 自带的 Node 18 运行；若确实要求 Node 20+，应在启动时做显式版本检测并给出明确的升级指引错误信息。
- **实际**：无任何版本检查，直接抛出晦涩的第三方依赖语法错误堆栈，用户无从判断原因。

## 五、完整错误日志

```
file:///F:/MigratedFolders/npm/node_modules/@deveco/deveco-code/node_modules/string-width/index.js:19
const zeroWidthClusterRegex = /^(?:\p{Default_Ignorable_Code_Point}|\p{Control}|\p{Format}|\p{Nonspacing_Mark}|\p{Enclosing_Mark}|\p{Surrogate})+$/v;
                              ^

SyntaxError: Invalid regular expression flags
    at ModuleLoader.moduleStrategy (node:internal/modules/esm/translators:152:18)
    at ModuleLoader.moduleProvider (node:internal/modules/esm/loader:299:14)

Node.js v18.20.1

BUILD FAILED (exitCode=1)
```

---

## 六、根因分析

依赖链与不兼容点：

```
@deveco/deveco-code@0.1.10
  └─ @deveco/deveco-cli（唯一 dependencies）
       └─ ora@9.4.1
            └─ string-width@8.2.2   engines: { "node": ">=20" }   <-- 问题依赖
```

`string-width@8.2.2` 的 `index.js` 共 4 处使用 `v` flag 正则（第 19、22、23、26 行）：

```js
const zeroWidthClusterRegex = /^(?:\p{Default_Ignorable_Code_Point}|\p{Control}|\p{Format}|\p{Nonspacing_Mark}|\p{Enclosing_Mark}|\p{Surrogate})+$/v;
const leadingNonPrintingRegex = /^[\p{Default_Ignorable_Code_Point}...]+/v;
const spacingMarkRegex = /\p{Spacing_Mark}/v;
const rgiEmojiRegex = /^\p{RGI_Emoji}$/v;   // \p{RGI_Emoji} 为"字符串属性"，v flag 专有
```

正则 `v` flag（Unicode Sets）自 Node 20 起支持，Node 18 在**模块加载阶段**解析该文件即抛 `SyntaxError`，因此命令完全不可用，而非局部功能降级。

另核实：
- `deveco-code` 自身的 `package.json` **未声明 `engines` 字段**，npm 安装时不会给出任何 Node 版本告警；
- `bin/deveco` 引导脚本定位 `@deveco/deveco-code-windows-x64/bin/deveco.exe` 后，由该二进制再经 **PATH 查找 `node`** 来执行 JS 负载，因此运行时解释器不受用户控制，始终命中 DevEco Studio 自带的 Node 18。

## 七、影响范围

- `deveco` CLI 所有子命令（build、docs、update 等）；
- DevEco Code 工具链中所有需要调用 CLI 的功能（如 `build_project`、`devecocli docs`）；
- 受影响用户群：**所有同时安装 DevEco Studio 与 deveco-code、且未手动调整 PATH 顺序的用户**——这是两种产品的默认共存形态，属于高频场景。

## 八、临时规避方案（本机已实施，供参考）

**方案 A**：将高版本 `node.exe` 复制到 npm 全局 prefix 目录（与 deveco.cmd/deveco.ps1 同级）。npm 生成的 shim 会优先使用 `%dp0%\node.exe`：

```
F:\MigratedFolders\npm\
├─ node.exe        <- 复制自 C:\Program Files\nodejs\node.exe（v24.20.0）
├─ deveco.cmd      <- shim：IF EXIST "%dp0%\node.exe" 则优先使用
├─ deveco.ps1      <- 同上逻辑
└─ node_modules\@deveco\deveco-code\...
```

> 局限：`deveco.exe` 二进制内部另行经 PATH 解析 `node` 时不受此 shim 控制（例如 DevEco Code 工具链的某些调用路径），因此本机还需配合方案 B。

**方案 B**：直接修补 `string-width/index.js` 使其兼容 Node 18（已验证 `node 18.20.1` 下可正常加载，且对 Node 20+ 无影响）：

```diff
- const zeroWidthClusterRegex = /^(?:\p{Default_Ignorable_Code_Point}|\p{Control}|\p{Format}|\p{Nonspacing_Mark}|\p{Enclosing_Mark}|\p{Surrogate})+$/v;
+ const zeroWidthClusterRegex = /^(?:\p{Default_Ignorable_Code_Point}|\p{Control}|\p{Format}|\p{Nonspacing_Mark}|\p{Enclosing_Mark}|\p{Surrogate})+$/u;
- const leadingNonPrintingRegex = /^[\p{Default_Ignorable_Code_Point}...]+/v;
+ const leadingNonPrintingRegex = /^[\p{Default_Ignorable_Code_Point}...]+/u;
- const spacingMarkRegex = /\p{Spacing_Mark}/v;
+ const spacingMarkRegex = /\p{Spacing_Mark}/u;
- const rgiEmojiRegex = /^\p{RGI_Emoji}$/v;
+ const rgiEmojiRegex = /(?!)/;
```

说明：前三处涉及的均为普通二元 Unicode 属性，`u` flag 在 Node 18 下完全支持；第四处 `\p{RGI_Emoji}` 是"字符串属性"、`v` flag 专有，`u` flag 下不合法，故改为永不匹配（emoji 宽度回退到东亚宽度计算，仅影响 CLI 输出排版中 emoji 的对齐，无功能影响）。

> **注意**：方案 B 属于对 node_modules 的就地修改，`deveco-code` 升级/重装后补丁即丢失。需要官方修复根治。

修补后验证结果：`build_project` 完整构建成功（`hvigor BUILD SUCCESSFUL`），`deveco --version` 正常输出。

## 九、修复建议（任选其一或组合）

1. **降级/替换依赖（推荐）**：将 `string-width` 固定到 `^6.1.0`（engines: node >= 18，API 与 8.x 兼容，均为默认导出的 `stringWidth(str, options)`），或由 CLI 内部以约 30 行代码实现等价的宽度计算，彻底摆脱该依赖的 Node 版本约束；
2. **显式版本门槛**：为 `deveco-code` 声明 `engines` 并在 `bin/deveco` / `deveco.exe` 启动路径中加入运行时版本检测，Node < 20 时输出明确指引（如"请在 PATH 前部配置 Node 20+"），替代当前的语法错误堆栈；
3. **自带运行时**：`deveco.exe` 不再依赖 PATH 解析 `node`，改为携带/指定受控版本的 Node 运行时，与 DevEco Studio 自带 Node 18 的 PATH 布局彻底解耦；
4. 请顺带核实 **1.3.2 版本**是否已包含上述任一修复（本机仍为 0.1.10，未敢在排查期间升级以免破坏现场）。

## 十、附加信息

- 同一环境下，`devecocli docs search` 与 `build_project` 报错完全一致，均为加载 `string-width` 阶段崩溃，可交叉验证；
- 已扫描 `@deveco/deveco-code` 全部 JS 依赖（含 node_modules），`v` flag 正则仅存在于 `string-width@8.2.2` 一个包中，未发现 `Promise.withResolvers`、`Array.fromAsync`、`util.styleText` 等其他 Node 20+ API，故修复该依赖后 Node 18 兼容性问题即全部消除；
- 本机规避后已完整跑通构建：`BUILD SUCCESSFUL in 1min 39s`（含 CompileArkTS、PackageHap、SignHap）。

---
*反馈人联系方式：* 刘石丰
*附件：完整构建日志、修补前后 string-width/index.js 对比*（如需可提供）
