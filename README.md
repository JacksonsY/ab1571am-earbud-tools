# AB1571AM Earbud Tools

AB1571AM 耳机互操作性研究与 macOS 工具：弹窗、设备信息和双耳配置排查。

**[阅读技术研究长文](https://jacksonsy.github.io/ab1571am-earbud-tools/)** · 报文、配置条件、双耳链路与主机识别的完整分析过程。

本仓库提供可迁移的研究方法，并记录一副 AB1571AM 耳机上的验证案例。**研究方法可以复用，具体参数不能视为所有同芯片设备的通用设置。** 本项目与 Apple、Airoha 或耳机及伴侣应用厂商无隶属、合作或认证关系。

> Bluetooth earbud interoperability research with macOS tools and source code. Configuration writes are restricted to one reviewed firmware profile; this is not a universal unlock or authenticity-verification tool.

## 配套软件和源码

- [下载发布版本](https://github.com/JacksonsY/ab1571am-earbud-tools/releases/latest)：包含 Mac 命令行程序、源码和使用说明；请查看对应架构及系统要求。
- [工具使用说明](docs/TOOLS.md)：安装、编译、离线自检、双耳查询和受限修复命令。
- [源码](tools/)与[构建/自检脚本](scripts/)：可以在 Mac 上自行审阅、构建和运行。
- [第三方软件与来源](docs/SOFTWARE.md)：Flycc 下载入口及版本记录；不转载厂家安装包。
- [编程 Agent 提示词](prompts/README.md)：给 Claude Code、Codex 等 agent 的启动模板，以及诊断、固件适配、平台移植、真机验证、发布和交接流程。

```sh
# 在仓库根目录运行；只编译和离线检查，不连接耳机。
bash scripts/build-macos.sh
bash scripts/check.sh
```

## 从哪里开始

| 文档 | 内容 |
|---|---|
| [通用排查教程](docs/TUTORIAL.md) | 区分配对、广播、系统缓存、设备信息和功能实现，逐步建立可验证的修复流程 |
| [单一固件案例](docs/CASE_STUDY.md) | 已观察到的配置关系、双耳验证、UI 结果及未解决事项 |
| [协议笔记](docs/PROTOCOL.md) | RACE 报文边界、双耳转发、写入确认及运行缓存的研究注意事项 |
| [发布范围、隐私与法律说明](docs/PUBLICATION_AND_LEGAL.md) | 脱敏规则、第三方权利、责任边界及材料使用限制 |
| [来源](docs/SOURCES.md) | 厂商说明、原始协议研究和法律政策来源 |

## 用编程 Agent 使用与二次开发

用 Claude Code、Codex 或其他 agent 打开本仓库，复制 [prompts/README.md](prompts/README.md) 的通用启动提示词，填入设备、目标、系统和授权范围；再按任务选择一个模板。共用项目规则在 [AGENTS.md](AGENTS.md)，[CLAUDE.md](CLAUDE.md) 引入同一份内容。

新固件默认从只读证据和离线检查开始。提示词不会替代协议证据、硬件访问授权或真机验证，也不会使所有同芯片设备自动兼容。

## 本次案例能说明什么

- 弹窗出现、系统能加载耳机图片、设备信息正常上报，是不同的观察目标。
- 参数写入成功不等于手机 UI 已刷新，更不等于原厂功能和认证都已实现。
- 两只耳机必须分别核对；当前连接耳与另一耳的角色会变化。
- 恢复设备已有的型号和序列号上报，与改写或伪造这些信息有本质区别。
- 系统开关变灰时，应区分连接状态和协议适配，不能仅凭伴侣 App 能控制就认定系统控制路径也已兼容。

案例中的弹窗、耳机/充电盒图片、型号及原有序列号显示已得到用户验证。iOS 充电盒声音开关仍灰，伴侣 App 可控制；本仓库不宣称已修复该开关，也不宣称真实心率、精确查找或全部高级功能已验证。

## 公开内容与使用范围

本仓库发布重新整理的教程、研究结论和脱敏配套代码，不包含个人修复包、厂家固件、配置区镜像、APK、蓝牙密钥、真实序列号、设备地址、个人截图或原始会话。主工具具有受限配置写入及指定缓存同步能力，不能把它当作纯只读程序；它没有 MCU 擦除/刷写或任意序列号改写功能。

运行产生的 `work/`、日志和本地编译产物不进入 Git 提交。不要把自己的运行备份当作发布包上传。

研究对象应当是本人合法持有或明确获授权的设备。不得用本资料冒充官方认证、伪造序列号、申请不实保修、隐瞒产品来源进行销售，或访问他人的设备与账户。自用、研究目的和免责声明都不能自动免除法律责任；详细边界见[法律说明](docs/PUBLICATION_AND_LEGAL.md)。

维护日期：2026-10-05。提交补充材料时只提供脱敏的固件版本、步骤和结果，不要在 Issue 或 PR 中上传完整设备转储。

## 网站维护

这个分支 `pages-research-notes` 专门维护研究型 GitHub Pages。页面从该分支的 `docs/` 发布，`.nojekyll` 禁用 Jekyll 处理；本次页面更新不合并到 `main`。

页面使用原生 HTML、CSS、JavaScript，不依赖外部字体或统计脚本。编辑 `docs/index.html`、`docs/site.css`、`docs/site.js` 后，显式推送 `pages-research-notes` 分支即可部署；本地预览可运行 `python3 -m http.server 8765 --directory docs`。新增研究结论时应同时核对证据级别、适用范围和来源链接。
