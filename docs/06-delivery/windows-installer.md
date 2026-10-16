# Windows 安装包

状态：Approved（用户要求 Windows 改为安装包）  
最后更新：2026-10-16  
关联文档：[自动发布](releasing.md)、[v0.1.0](releases/v0.1.0.md)

## 安装行为

- Windows 10/11 x64，默认使用简体中文；同时提供英文。使用原有透明应用图标和标准系统安装向导。
- 默认安装到 `%LOCALAPPDATA%\Programs\Neutrino Proxy`，允许选择其他可写目录；仅当前用户安装，不请求管理员权限。
- 创建开始菜单入口，桌面快捷方式可选；Windows“已安装的应用”提供卸载入口。
- 安装结束可选择启动客户端。安装脚本不配置开机自启或 Windows 服务。
- 固定 `AppId=cn.neutrino.neutrinoProxyClientDesktop`，后续安装沿用安装目录和快捷方式选项。
- 安装和卸载检测原生宿主的 `Local\NeutrinoProxyFlutter` mutex，仍在运行时提示从托盘退出；不强制终止网络隧道。
- 配置与系统加密凭证仍保存在原有 Roaming AppData 目录，安装和卸载不修改或删除这些文件。卸载只移除安装器登记的程序文件与快捷方式。

## 构建

`packaging/windows/setup.iss` 定义安装流程；`scripts/package-windows.ps1` 调用固定版本 Inno Setup 6.7.3，生成安装 EXE 与便携 ZIP。依赖只用于构建，不要求用户另外安装。

```powershell
pwsh -File scripts/copy-windows-runtime.ps1
pwsh -File scripts/package-windows.ps1 -Tag v0.1.0 -BuildNumber 1
```

已有完整运行目录时可指定 `-Source` 与 `-Output`；`-InstallerOnly` 仅生成 EXE，适用于给已发布版本补安装包。`scripts/release.py` 对两种产物使用同一运行目录完整性检查；常规发布必须同时包含安装 EXE、便携 ZIP 和两份 macOS 产物。

构建工具来源：[Inno Setup 6.7.3](https://github.com/jrsoftware/issrc/releases/tag/is-6_7_3)。工具下载 SHA-256 固定为 `9c73c3bae7ed48d44112a0f48e66742c00090bdb5bef71d9d3c056c66e97b732`；通过校验后安装到项目 `.tools/`，不修改 PATH。[Inno Setup 许可证](https://jrsoftware.org/files/is/license.txt) 保持原有版权声明。

中文翻译原样来自该 tag 的 [ChineseSimplified.isl](https://github.com/jrsoftware/issrc/blob/is-6_7_3/Files/Languages/Unofficial/ChineseSimplified.isl)，文件保留原作者说明；SHA-256 为 `7d544b9bb1d142cfa11f2e5d3cc8abe2e55f8e066c5124e3772675aa236e1278`。

## 本次验证范围

v0.1.0 安装包使用已发布 Windows ZIP，下载后确认 SHA-256 为 `cd06fedd5fd5b8ef4a966ab1abe6a1b515af00867401d0006d58b60232705795`。Inno Setup 编译成功，生成版本为 0.1.0.1 的 Windows 安装 EXE。程序文件和既有下载保持不变。

沿用本次发布“跳过测试”的要求：未执行安装、覆盖升级、卸载和应用运行测试；新补的发布完整性回归用例保留给后续默认 CI，本次未运行。编译通过不代表上述流程已实机验收。
