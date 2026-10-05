# 工具使用说明

## 下载或自行构建

[GitHub Releases](https://github.com/JacksonsY/earbud-interop-research/releases) 提供源码与 Mac 命令行程序的合并 ZIP。首个二进制发布面向 Apple Silicon，最低部署目标为 macOS 26.0，在 macOS 26.5.1 上编译和离线验证；它不是 iOS 或安卓安装包。

程序没有 Developer ID 公证。若系统阻止下载的二进制，请审阅源码后使用 Apple 开发工具在本机编译，不需要关闭系统安全保护。源码构建需要 Xcode Command Line Tools；若未安装，可使用 `xcode-select --install`。以下命令在仓库根目录执行：

```sh
bash scripts/build-macos.sh
bash scripts/check.sh
bin/inspect-earbud --help
```

也可以不构建二进制，直接运行 `swift tools/inspect-earbud.swift --self-test`。离线检查不连接耳机，包括报文解析、NVDM 校验、ELF 包装和禁止写入参数的拒绝检查。

## 工具组成

| 文件 | 用途 |
|---|---|
| `tools/inspect-earbud.swift` | macOS 原生 IOBluetooth / CoreBluetooth 查询、受限双耳配置写入和指定缓存同步 |
| `tools/inspect_nvdm.py` | 离线解析已合法取得的 NVDM 备份，默认仅列编号/长度，不打印值 |
| `tools/wrap_thumb.py` | 将本地原始 Thumb 数据包装为 ELF，供离线反汇编，不生成补丁或写入设备 |
| `tools/check_menu_artwork.swift` | 检查特定竖屏设置页布局中的图片区域是否空白；不能代替人工视觉确认 |
| `tools/hold_audio_link.swift` | 向已选择的音频输出播放 45 秒静音，用于链路排查；不是修复必需步骤 |
| `scripts/build-macos.sh` | 使用本机 Swift 编译器构建 CLI，保留断言并映射构建路径 |
| `scripts/check.sh` | 运行离线自检和六个禁止写入调用检查 |

主工具不需要网络连接，不安装驱动，不修改系统音量或默认音频设备。Python 辅助脚本和完整离线自检需要 Python 3；CLI 的蓝牙功能不依赖 Python。

## 支持范围与连接准备

受限写入和 RAM 访问只接受以下固件身份：

```text
platform: ab157x_evk
SDK: IoT_SDK_for_BT_Audio_V3.10.0.c43sp_YFY_1
build: 2026/09/14 15:40:24 GMT +08:00
```

工具比对返回的身份字符串，并不为每次操作重新计算完整 MCU 哈希。这不是密码学真实性验证，也不保证同版本字符串的其他厂商设备完全兼容。发现不同固件、未知原值或异常响应时停止，不要删掉校验。

先在 macOS 设置中连接自己的耳机，按需要允许终端蓝牙权限；将两耳戴上、盒盖保持打开，并避免另一台手机抢占连接。工具只匹配指定的已连接设备，不扫描并写入附近其他耳机。

```sh
EARBUD_DEVICE='你的原始蓝牙名称或这台Mac上的设备UUID'
earbud() { ./bin/inspect-earbud "$EARBUD_DEVICE" "$@"; }
earbud --ble-info
```

请将占位文字换成实际目标。系统显示别名可能不同于 BLE 原始名称；CoreBluetooth UUID 也不保证能跨 Mac 复用。不要把 UUID 贴到公开 Issue。

## 先读取并比较两耳

```sh
(
  set -e
  earbud --check-info-cache
  earbud --peer-check-info-cache
  earbud --read-nvkey 0xFB03
  earbud --peer-read-nvkey 0xFB03
  earbud --read-nvkey 0xFC04
  earbud --peer-read-nvkey 0xFC04
  earbud --read-nvkey 0xFB00
  earbud --peer-read-nvkey 0xFB00
)
```

当前连接耳与 peer 不是固定左右角色。另一耳不可达时应先处理连接问题，不能硬填转发目标。各字段在本样本中的初值和结果见[案例](CASE_STUDY.md)。下面写入步骤只用于该范围内已核实的设备，不是所有 AB1571AM 的通用配方。

## 弹窗配置的受限写入

仅在固件、两耳读值和适用条件都已核对后执行。已有正确值时跳过写入；未知原值会拒绝。

```sh
(
  set -e
  earbud --check-info-cache
  earbud --peer-check-info-cache
  earbud --set-nvkey 0xFB03 0x01 0x00
  earbud --set-nvkey 0xFC04 0x01 0x7A
  earbud --peer-set-nvkey 0xFB03 0x01 0x00
  earbud --peer-set-nvkey 0xFC04 0x01 0x7A
)
```

每个实际写入都先保存原值，再检查成功响应并读回比较。随后再次执行读取步骤，确认两耳一致。此过程不是原子事务，中途失败时可能只完成了前几项，需要按本地记录判断状态。

断开 Mac，在手机端正常开盖测试。若参数正确但图片空白，本案例的有效处理是手机忽略设备并重新配对；这会删除该设备的手机配对记录，不等于恢复耳机出厂设置。不要再次套用会把正确参数覆盖为旧值的旧版口令。

## 恢复设备原有信息的上报

本案例中已有原始型号和序列号，只是上报开关关闭。以下步骤不会写入型号或序列号值：

```sh
(
  set -e
  earbud --check-info-cache
  earbud --peer-check-info-cache
  earbud --set-nvkey 0xFB00 0x00 0x01
  earbud --peer-set-nvkey 0xFB00 0x00 0x01
  earbud --sync-info-cache
  earbud --peer-sync-info-cache
  earbud --read-nvkey 0xFB00
  earbud --peer-read-nvkey 0xFB00
  earbud --check-info-cache
  earbud --peer-check-info-cache
)
```

`sync-info-cache` 是写操作：在固件匹配、字段已加载且对齐字两次读值稳定后，只更新指定标志，保留其他字节并读回整个字；已经一致时不写。期望两耳持久值和运行值均为 `01`。断开 Mac，让手机重新连接并在设置页验证。

公开版没有任意 NVKEY、序列号或 RAM 地址写入接口，没有 MCU 擦除/编程命令，也没有厂家固件升级功能。充电盒声音灰色开关仍未解决。

## 备份、回退与日志

原值记录和读取备份写入程序所在 `tools/` 或 `bin/` 的上一级 `work/`；源码/二进制应保留发布目录结构。新建目录和文件采用仅当前用户可访问的权限，已有文件不会被作为通用配置覆盖。

主工具的 `--read-nvkey` 可显示请求字段的原始值，终端输出也可能含设备名称。不要上传整个运行日志、JSON 或 Flash 备份。`--read-flash START SIZE` 只用于合法取得的本地研究，默认 256 字节页；本样本没有验证其他页大小，不要自行扩大。

回退应以自己保存的 `before` 值为依据，并保持工具支持的值域，使用 `--set-nvkey KEY 当前预期值 原值` 和对应 peer 命令；涉及 `FB00` 时再同步两耳缓存。不要把本案例初值称作所有设备的出厂值，也不要把整块备份刷到另一副耳机。源码中的回退接口没有在本次发布时重新对健康设备执行。

遇到超时、固件不匹配、未知原值、peer 不可达或缓存不稳定时停止。保留本地记录，先恢复可验证的只读状态；不要绕过保护或猜测重启/擦除命令。

## 本次公开版本验证

该版本以已完成实机修复的本地工具为基础，删除个人测试名称和私有备份摘要，补充帮助信息、私有文件权限及构建/检查脚本。发布前进行编译、离线功能检查和敏感内容扫描；没有为打包再次修改用户耳机。实机范围仍以单一案例为限，不等于新发布程序已经通过多设备认证。
