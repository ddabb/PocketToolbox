# 生字卡拼音显示为「u252」混淆名 Bug 修复记录（2026-10-10）

## 现象
- 真机（Mate 60 Pro，HarmonyOS 7.0.0.109，API 26）上生字卡拼音显示为 `u252 n258 p252 g252 t251`（学而时习之），声调字符变成了「数字样」乱码
- 模拟器（debug 构建）显示正常 `xué ér shí xí zhī`
- 用户反馈截图见 `docs/拼音不对.png`

## 根因
`entry/obfuscation-rules.txt` 中开启了 `-enable-property-obfuscation`（仅 release 构建生效）：

1. pinyin-pro（3.26.0，ohpm 锁定）的字典结构为 `{ "xué": ["乴","学",…], … }` —— **属性名本身就是带调拼音串**
2. 汉字→拼音的反向查表在运行时**遍历字典属性名**作为拼音返回
3. release 属性混淆把 2 万+ 拼音属性名（`xué` 等）重命名为混淆器生成的短名（`u252`、`n258`、`a258` 这类 字母+数字 格式）
4. 反向查表于是把**混淆后的属性名当拼音返回** —— 即用户看到的「数字化」乱码
5. `toneType:'symbol'` 在 pinyin-pro 内是零转换直出字典内容，无兜底修正机会

## 为什么各环境表现不同
| 环境 | 是否属性混淆 | 结果 |
|---|---|---|
| Node（oh_modules dist 直接跑） | 否 | `xué ér shí xí zhī` 正确 |
| 模拟器（debug 构建） | 否 | 正确 |
| 真机（AGC/本地 release 构建） | **是** | `u252 n258 …` 乱码 |

1.4.1 的「拼音改系统字体」修复方向错误——本 Bug 与字体完全无关（LXGW 文楷、模拟器/真机 HarmonyOS Sans 的 cmap 拼音覆盖均完整，已逐一验证）。

## 证据链
- 真机 `uitest dumpLayout`：拼音 Text 内容字节级确认为纯 ASCII `u252`（无反斜杠转义），全 dump 无任何声调字符
- 本地 Node 跑同一 dist 输出正确 → 库本身无损
- 复现构建（原混淆规则，release+default 产品）：`modules.abc` 常量池中出现混淆名序列 `a258 b258 c258 … a259`（替换了拼音属性名），词组拼音**字符串值**（非属性名）如 `"xué zhōng"` 保留
- 修复构建：混淆名序列消失，`xué`/`ér`/`xí` 独立出现次数各 +1（单字字典键恢复）

## 修复
`entry/obfuscation-rules.txt`：注释掉 `-enable-property-obfuscation`（保留 toplevel/filename/export 混淆与 remove-log）。

不能改用 `-keep-property-name` 白名单：字典属性名 2 万+ 且为运行数据，只能整体关闭属性混淆。

## 真机验证（2026-10-10 14:3x）
1. 修复版 release 构建（default 产品，debug 签名）
2. `hdc install -r` 原位覆盖安装到 Mate 60 Pro
3. 首页 → 最近使用 → 生字卡，`uitest dumpLayout` 确认拼音 Text 为 `xué ér shí xí zhī` ✅

## 遗留事项
- [ ] AGC 已发布的 1.4.1 带此 Bug，需发布修复版（1.4.2）
- [ ] 发版前建议在 release 包上回归：生字卡（单字/多字/批量导出）、词云、文字转图片、Md2Png、数独、计算器（确认关闭属性混淆不影响其余混淆项）
