# 来源与证据使用

资料核对日期：2026-10-05。网页与上游代码可能更新；以下链接用于定位原始资料，不表示任何第三方认可本项目。

## 原始技术资料

- [RACE Toolkit](https://github.com/auracast-research/race-toolkit)：原研究项目，提供 RACE 报文和多种传输接口的实现。
- [RACE packets.py](https://github.com/auracast-research/race-toolkit/blob/main/librace/packets.py)：报文构造与命令布局的对照来源。
- [PairBridge](https://github.com/MattiaIppoliti/pairbridge)：旧型号互操作性研究线索；其具体设备配置不能直接用于本案例。
- [LibrePods DeviceInfo 文档](https://github.com/kavishdevar/librepods/blob/main/docs/device-info.md)：设备信息协议参考。
- [LibrePods 控制命令](https://github.com/kavishdevar/librepods/blob/main/docs/control_commands.md)：耳机和盒子控制命令的独立研究，不能据此假定第三方固件已实现全部命令。
- [CAPod](https://github.com/d4rken-org/capod)：广播设备识别研究参考。

本仓库重新撰写了研究摘要，没有复制上述项目的完整源码或附带它们的安装包；使用其代码时仍需自行遵守各项目许可证。

## Apple 官方产品行为

- [AirPods 设置说明](https://support.apple.com/zh-cn/guide/airpods/dev57e5b7e58/27/web/27)：原装耳机的原生设置入口与充电盒声音控制条件。
- [识别 AirPods](https://support.apple.com/en-us/109525)：官方型号识别信息。
- [Pro 3 心率说明](https://support.apple.com/zh-cn/123184)：原装设备在训练 App 和健康 App 中的心率功能。

官方说明只能用于对照原装产品行为，不能证明本案例第三方硬件也具有相同传感器、认证和服务支持。社区讨论仅可提供排查线索，不作为已确认根因。

## 法律与平台政策

- [GitHub 可接受使用政策](https://docs.github.com/en/site-policy/acceptable-use-policies/github-acceptable-use-policies)
- [GitHub 仓库许可说明](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)
- [美国版权局 §1201 说明](https://www.copyright.gov/policy/1201/)
- [37 CFR §201.40](https://www.copyright.gov/title37/201/37cfr201-40.html)

法规链接用于解释为什么不能简单承诺免责，不代表本案例已经满足某项例外的全部条件。

## 本地实测证据的公开边界

案例结论还来自授权设备的查询响应、局部修改后读回、离线分析及用户确认。为保护隐私及第三方材料，这些原始文件不随公开仓库分发，因此读者无法仅凭本仓库完整重放全部实机证据。请把它当作范围明确的案例记录，而不是独立认证报告或大样本兼容性保证。
