# 桌面项目独立拆分

状态：Review
最后更新：2026-10-27

关联文档：[README](../../README.md)、[文档索引](../README.md)、[独立发布](releasing.md)、[开发记录](client-app-development-status.md)

## 已确认范围

用户要求将原主仓库 neutrino-proxy-client-app 完整移入 neutrino-proxy-client-desktop，清空后者旧项目内容，按原 README 格式重写说明，并处理两个仓库工作流。本轮按此替换旧 Flutter 工作树，保留目标仓库 .git、远程地址、分支和既有历史；不提交、推送、创建 tag 或发布。

代码、测试、图标、锁文件、已确认样图、34 份桌面文档及本机依赖 / 构建缓存一起迁移。Cargo workspace、src-tauri、src、package.json、scripts、tests 均直接位于新仓库根目录，原目录已移除。旧目标工作树备份在仓库外，未混入新源码。

包和可执行文件名改为 neutrino-proxy-client-desktop，核心 crate 仍为 neutrino-client-core；应用显示名、Tauri 标识 fun.neutrino.proxy.desktop、配置与系统凭证含义保持兼容。既有协议、Java 七项同步、原生托盘及应用设置均随代码迁入。

## 两套工作流

- 主仓库：Java / 管理后台构建，八份服务端和命令行分发文件、两个校验文件；移除桌面 job、版本注入、产物要求与桌面 CI，增加主仓库 CI。
- 桌面仓库：三个平台独立 CI / 打包；四份桌面分发文件、两个校验文件；根目录注入版本，三个平台记录源提交后汇总，独立 tag 发布。
- 发布保护沿用缺包拒绝、哈希校验、上传中断不公开及已发布版本不覆盖；新增独立桌面版本注入和三平台来源一致性回归。

## 本轮验证

- 在新根目录运行：Rust 69 项、Vue 17 项、Edge 页面流程 12 项通过；Cargo 格式与 Clippy 通过。
- 主仓库 Maven reactor 执行 test 成功，现有 Java 模块没有测试源码，不能将其表述为 Java 单测覆盖。
- 主仓库 Python 发布回归 26 项执行，25 通过、1 项因 Windows 无 POSIX shell 跳过；Linux CI 保留该用例。
- 两个仓库共五份 GitHub Actions YAML 通过 actionlint。
- 桌面 Python 发布回归 13 项通过，包含根目录版本注入、四份准确分发清单、来源提交不一致拒绝、哈希篡改拒绝、上传失败不公开、已发布不覆盖及 prerelease 不更新 Latest。
- 原客户端受版本控制的 85 个文件全部迁到；79 个内容一致，6 个仅调整包名、路径提示或忽略规则，无缺失及非预期源码变化。
- 两仓库相关文档的本地链接检查通过，原客户端目录已不存在。未重装 npm 依赖，两个锁文件只同步包名，依赖版本未改。
- Windows Vite / Rust Release / NSIS 实际构建与独立打包脚本通过。安装包位于 `../../release-assets/neutrino-proxy-client-desktop-0.1.0-windows-x64-setup.exe`，3203140 字节，SHA-256：`83fc45bcd9ae627782856e6b808e53d90e86e6f50e09cecc182b46dd0f8e8d62`。
- 便携 ZIP 位于 `../../release-assets/neutrino-proxy-client-desktop-0.1.0-windows-x64-portable.zip`，4443328 字节，SHA-256：`2f162c0469af67fca42da0f2711bbd950ba62fdf2364293054d66e0ecab8e893`；这是本机验证产物，未上传或替换历史 0.1.0 Release。
- 实际解包检查确认 ZIP 只包含本次编译的可执行文件及保留的 LICENSE，文件内容与构建输出一致。测试开发服务器已退出，1420 端口无监听；两仓库 diff 格式检查通过。

macOS 编译 / 实机、系统登录启动、安装器实际安装、真实服务及远端 Actions 未在本轮执行；保留前轮验证边界。所有当前测试使用本地对端和虚构凭证，不触及用户实际配置。
