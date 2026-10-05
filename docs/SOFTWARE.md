# 配套软件、版本与来源

## 本仓库提供的软件

`inspect-earbud` 是本项目的 macOS 命令行程序，对应完整 Swift 源码和构建脚本。发布包还包含 Python/Swift 离线分析辅助代码、教程和校验清单。没有把任何人的设备备份或厂家固件作为示例数据。

首版构建环境：Apple Silicon，macOS 26.5.1，Apple Swift 6.3.2。二进制只发布实际构建验证的架构；Intel Mac 可尝试自行编译源码，但本次未验证 Intel 环境。程序未作 Developer ID 公证。

## Flycc

- [原发布页](http://apkdown.198509.xyz/index_zh.html)
- [原发布页链接的 iOS App Store 页面](https://apps.apple.com/us/app/flycc/id1661245709)

2026-10-05 核对原发布页时，列出的安卓版本为 2.0.34，日期为 2026/09/07。研究中还参考过 2.0.29。历史文件校验记录如下，仅用于识别当时材料，不代表安全审计或适配保证：

| 版本 | 字节数 | SHA-256 |
|---|---:|---|
| 2.0.29 | 23,397,442 | `29d220a948b47562085c3cd0acff520ed3646b041a5282eed66d8fdeed1de092` |
| 2.0.34 | 22,506,520 | `07ebe605cfe9f151c786fb892ceb67d370b78abbf9db4812adda4a3bfd86ed90` |

仓库没有记录厂商授予的再分发许可，因此提供原发布入口，不镜像 APK、不去壳或修改分发包。用户已确认 Flycc 能控制案例设备的充电盒声音；它不是本 Mac 工具的运行依赖，也不应为了执行教程而强制降级已有应用。

## 开发环境和协议资料

- Xcode Command Line Tools / Swift：由 Apple 提供，本仓库不分发系统 SDK。
- Python 3：仅用于辅助脚本和完整离线检查；BLE 主工具不依赖第三方 Python 包。
- RACE Toolkit、LibrePods、CAPod 和 PairBridge：协议研究参考，链接见[来源](SOURCES.md)，不要求把这些项目全部安装。
- NVDM 解析器的布局与校验规则参考 `dangkhoalk95/demoMT` 的 `middleware/MTK/nvdm_core`；本仓库只包含整理后的 Python 解析实现，没有复制或分发该 SDK 的 C 源文件。[布局参考仓库](https://github.com/dangkhoalk95/demoMT)

第三方项目的许可证不因被引用而改变。本仓库的发布范围及责任边界见[法律说明](PUBLICATION_AND_LEGAL.md)。
