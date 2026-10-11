# 模拟器迁移 E 盘检查清单

> 生成时间：2026-10-08
> 迁移脚本：`docs/migrate_emulator_to_E.bat`
> 用途：迁移执行后，由助手按本清单逐项核对迁移结果

## 一、背景摘要

- 问题：MatePad Pro 13（HarmonyOS 7.0.0 平板）启动失败，报"磁盘空间不足"
- 根因：模拟器镜像与实例数据物理存储在 F 盘（`F:\Huawei`），F 盘剩余仅约 25 GB，低于模拟器启动空间阈值
- 方案：
  1. `F:\Huawei` 整体迁移到 `E:\Huawei`（E 盘剩余约 246 GB）
  2. 创建 Junction `F:\Huawei → E:\Huawei`，兼容 qcow2 镜像内嵌的回溯路径（backing file 指向 `F:/Huawei/Sdk/...`）
  3. 全部配置文件中的 `F:/Huawei/` 文本替换为 `E:/Huawei/`

## 二、迁移前基线（2026-10-08 采集）

| 项目 | 值 |
|---|---|
| F:\Huawei 文件数 | 110 |
| F:\Huawei 总字节 | 19,628,034,173 字节（18.28 GB） |
| E:\Huawei 是否存在 | 否 |
| C 盘剩余 | 64.55 GB |
| D 盘剩余 | 3.91 GB |
| E 盘剩余 | 246.80 GB |
| F 盘剩余 | 25.08 GB |
| deployed 实例（6 个） | Huawei_TV, Mate X7, MateBook Pro, MatePad Pro 13, Pura 90, Pura 90 Pro |
| 镜像版本（F:\Huawei\Sdk\system-image） | HarmonyOS-6.1.1, HarmonyOS-7.0.0, HarmonyOS-7.0.0-B1 |

## 三、待更新路径引用清单（迁移前共 19 个文本文件）

**Emulator26.0 / IDE 配置：**

| # | 文件 | 引用内容 |
|---|---|---|
| 1 | `F:\MigratedFolders\AppData\Local\Huawei\Emulator26.0\.emu_config` | imagePath、emuPath |
| 2 | `C:\Users\60138546\AppData\Roaming\Huawei\DevEcoStudio26.0\options\deviceManager.xml` | imageDeployPath、openharmonyDeployPath |
| 3 | `C:\Users\60138546\AppData\Roaming\Huawei\DevEcoStudio26.0\options\other.xml` | 最近路径列表 1 处 |
| 4 | `C:\Users\60138546\AppData\Roaming\Huawei\DevEcoStudio6.1\options\other.xml` | 最近路径列表 1 处（F:/Huawei/Sdk） |

**deployed 根目录：**

| # | 文件 | 引用内容 |
|---|---|---|
| 5-10 | `Huawei_TV.ini`、`Mate X7.ini`、`MateBook Pro.ini`、`MatePad Pro 13.ini`、`Pura 90.ini`、`Pura 90 Pro.ini` | path=F:/Huawei/Emulator/deployed/... |
| 11 | `lists.json` | 6 处 path 字段 |

**实例目录内：**

| # | 文件 | 引用内容 |
|---|---|---|
| 12-17 | 6 个实例的 `config.ini` | instancePath=F:/Huawei/... |
| 18 | `Pura 90\hardware-qemu.ini` | 3 处镜像路径（system/vendor/userdata） |
| 19 | `Pura 90 Pro\hardware-qemu.ini` | 3 处镜像路径 |

**二进制文件（不做文本替换，由 Junction 兜底）：**

- `Pura 90\cache.img.qcow2` 等全部 qcow2 文件——内嵌 backing 路径指向 `F:/Huawei/Sdk/...`，经 Junction `F:\Huawei → E:\Huawei` 继续可达

## 四、核对清单

### A. 数据完整性

- [ ] **A1** 镜像目录已就位：`Get-ChildItem 'E:\Huawei\Sdk\system-image' -Directory` 返回 HarmonyOS-6.1.1 / HarmonyOS-7.0.0 / HarmonyOS-7.0.0-B1
- [ ] **A2** 实例目录已就位：`(Get-ChildItem 'E:\Huawei\Emulator\deployed' -Directory).Name` 返回 6 个实例
- [ ] **A3** 文件数与总大小一致：`Get-ChildItem 'E:\Huawei' -Recurse -File -Force | Measure-Object Length -Sum` = 110 个 / 19,628,034,173 字节（若迁移前又启动过模拟器，允许少量偏差，以脚本第 2 步输出为准）
- [ ] **A4** 旧目录已清理：`Test-Path 'F:\Huawei_old'` = False
- [ ] **A5** Junction 生效：`(Get-Item 'F:\Huawei').LinkType` = Junction，Target = `E:\Huawei`

### B. 配置路径更新

- [ ] **B1** `.emu_config`：imagePath=`E:/Huawei/Sdk`，emuPath=`E:/Huawei/Emulator/deployed`，且同目录存在 `.emu_config.bak`
- [ ] **B2** `deviceManager.xml`：imageDeployPath=`E:/Huawei/Sdk`，openharmonyDeployPath=`E:/Huawei/Emulator/deployed`，存在 `.bak`
- [ ] **B3** 4 个固定配置文件（上表 #1-#4）中 grep `F:/Huawei` 无匹配
- [ ] **B4** `E:\Huawei\Emulator\deployed` 下全部 `*.ini` / `*.json` / `*.cfg` 中 grep `F:/Huawei` 无匹配
- [ ] **B5** `lists.json` 6 处 path 均为 `E:/Huawei/Emulator/deployed/...`
- [ ] **B6** `MatePad Pro 13\config.ini`：instancePath=`E:/Huawei/Emulator/deployed/MatePad Pro 13`
- [ ] **B7** 被修改的文件均有对应 `.bak` 备份（与原文件同目录）

### C. qcow2 兼容性（Junction 兜底）

- [ ] **C1** 旧回溯路径经 Junction 可达：`Test-Path 'F:\Huawei\Sdk\system-image\HarmonyOS-6.1.1\phone_all_x86\system.img'` = True
- [ ] **C2** Pura 90 的 qcow2 backing 路径有效：`Pura 90\cache.img.qcow2` 内嵌路径形如 `F:/Huawei/Sdk/...`，其指向的文件存在

### D. 磁盘空间

- [ ] **D1** F 盘剩余 ≈ 43.3 GB（25.08 + 18.28）
- [ ] **D2** E 盘剩余 ≈ 228.5 GB（246.80 - 18.28）

### E. 旧环境不受影响（DevEco 6.1，位于 F:\MigratedFolders）

- [ ] **E1** 旧镜像完整：`F:\MigratedFolders\AppData\Local\Huawei\Sdk\system-image` 仍有 HarmonyOS-5.1.1 / 6.0.31 / 6.1.1 三个目录（约 27.8 GB）
- [ ] **E2** 旧实例完整：`F:\MigratedFolders\AppData\Local\Huawei\Emulator\deployed` 仍有 Huawei_Phone / PadPhone / Pura 90 / Tablet / Tablet23 五个实例（约 9.2 GB）

### F. 功能验证（需人工确认）

- [ ] **F1** DevEco Studio 启动后，Device Manager 设备列表显示 6 个设备
- [ ] **F2** MatePad Pro 13 启动成功（本次迁移要解决的原始问题）
- [ ] **F3** Pura 90（已启动过的旧实例，qcow2 经 Junction 回溯）启动成功
- [ ] **F4** （可选）DevEco 6.1 的 Tablet / Tablet23 旧模拟器不受影响

## 五、回退方案

1. **配置回退**：将各被修改文件同目录的 `.bak` 改回原文件名
2. **数据回退**：删除 Junction `F:\Huawei`（`rmdir F:\Huawei`，只删链接不删数据），再将 `E:\Huawei` 整体移回 `F:\Huawei`

## 六、执行顺序提醒

1. 保存工作，完全关闭 DevEco Studio
2. 双击运行 `docs\migrate_emulator_to_E.bat`（复制约 18 GB，预计 5-20 分钟）
3. 运行完成后，让助手按本清单核对
