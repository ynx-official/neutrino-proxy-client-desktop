# 桌面客户端本地开发与运行

状态：Review
最后更新：2026-10-27

关联文档：[开发进展](../06-delivery/client-app-development-status.md)、[实施计划](../06-delivery/client-app-implementation-plan.md)、[界面设计](../02-design/client-app-ui.md)

## 运行已构建的 Windows 程序

本地 Windows 开发构建默认输出 `target/release/neutrino-proxy-client-desktop.exe`，包含前端资源，不需要先启动 Vite，也不依赖 Java。当前修订、构建结果及文件哈希以[开发进展](../06-delivery/client-app-development-status.md)为准。

切换到本地修正版时，先从托盘退出正在运行的旧版，再打开新程序并连接。仅关闭主窗口会保留旧进程，单实例机制会恢复旧进程的界面。构建本身不会退出已安装的客户端或修改其配置。

2026-10-16 托盘已改为系统原生菜单；当前测试、构建与平台验证边界见[开发进展](../06-delivery/client-app-development-status.md)。

第一次打开不会自动连接。进入“设置”，填写服务器地址、对应的隧道端口和 License，选择是否启用 SSL，然后“保存并连接”。填写真实连接信息前，请确认服务器及 License 的使用权限；开发验证使用本地测试对端和虚构凭证。

“设置 → 应用设置”提供两个独立开关，默认关闭、修改后自动保存：

- **开机自启**：登录系统后启动 Neutrino。开启时注册当前程序所在路径，便携版应放在固定目录；移动程序后应关闭再开启一次。macOS 应先将 App 移到固定安装目录再开启。
- **启动后自动连接**：下次完整启动进程时，已保存的地址、端口及 License 等信息完整才尝试连接一次。初次失败会停止，可查看日志并手动重试；成功后的断线重连沿用连接配置。只打开托盘窗口、修改开关或补全配置不立即触发。

新偏好单独保存为应用配置目录中的 `app-settings.json`，不包含 License，开机自启状态从系统读取。系统权限或文件写入失败会显示错误。配置文件损坏时保留原文件、跳过自动连接；修复后重新启动应用再读取。

关闭窗口后应用仍在托盘运行，再次打开同一个 exe 会恢复主窗口。单击或右击托盘图标直接打开系统原生菜单，可查看状态和服务器、打开主窗口或日志，并按状态连接、取消、停止重连或断开。Escape 或点击外部按系统规则收起菜单；完全结束应用使用“退出应用”。重新构建 exe 前先退出测试实例，或使用独立构建输出目录，避免 Windows 文件占用导致替换失败。

## 开发环境

在本仓库根目录执行命令。需要 Node 22.12+（CI 使用 Node 22 的当前维护版本）、npm、Rust stable；Windows 还需要 C++ Build Tools 和 WebView2。macOS 需要 Xcode Command Line Tools。

首次安装依赖：

```powershell
npm ci
```

启动桌面开发窗口：

```powershell
cargo run
```

此命令会先启动前端、等待就绪，再打开桌面程序；在 `src-tauri/` 目录运行也适用。已启动的本项目 Vite 服务会被复用，其他程序占用端口则报错，不结束该程序。退出应用或终止开发进程后，仅清理本次启动的前端；关闭主窗口保留托盘运行时，前端也保持运行。

仍可使用 Tauri CLI 入口（支持其开发监听流程）：

```powershell
npm run desktop:dev
```

编译包含前端的原生可执行程序：

```powershell
npm run desktop:build
```

此命令暂不生成安装程序，也不执行签名、公证或发布。Windows 输出 exe；macOS 的原生构建与运行结果必须在 macOS 环境验证。

## 验证命令

```powershell
npm test
npm run build
cargo test --workspace
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
npm run test:e2e
```

浏览器流程测试使用本机 Edge，并由 Playwright 临时启动 Vite；结束后自动关闭服务器。测试替身仅在开发构建允许注入，Release 构建不能通过浏览器测试标志伪造连接状态。浏览器截图不替代桌面窗口验证。

本机首次 npm 10.9 安装出现依赖解析错误，随后用临时运行的 npm 11.6.2 完成安装；Vue 固定为 3.5.22，避免仓库返回不完整的新版本依赖。没有修改全局 npm。其他环境优先使用锁文件执行 `npm ci`。

## 配置与凭证

普通配置写入 Tauri 的应用配置目录；Windows 通常为 `%APPDATA%/fun.neutrino.proxy.desktop/config.json`。License 与 JKS 密码写入系统安全存储，JSON 中只有凭证引用。系统安全存储失败时，保存操作返回错误，不降级为明文保存。

导入 YAML 会先显示脱敏预览，用户确认后才保存且不会自动连接。旧官方 `neutrino.proxy.client` 与新版 `neutrino.proxy.tunnel` 均可导入，兼容嵌套及点分键。预览只显示本次实际读取的字段，不把本机保留值显示为已导入。有效字段合并到现有配置；缺少分组、字段为空或无效时跳过，已有值与凭证保留。首次使用可先导入部分字段，之后补齐必填信息再连接。无可用字段仅提示“未发现可导入的配置”。格式无效、文件不可读和超过 1 MiB 仍返回错误。

2026-10-26 已支持导入 `protocol.water-mark`、`all-idle-time-seconds`、`max-frame-length`、`length-field-offset`、`length-field-length`、`length-adjustment`、`initial-bytes-to-strip`。这些参数在预览中展示、保存后用于下一次连接；修改时重新导入相应 YAML 即可。空闲时间 0 或负数表示禁用。无效拆包组合整体保留原值，其他有效字段仍可导入。若没有显式 client-id，会读取所选 YAML 同目录的 `.NEUTRINO_PROXY_CLIENT_ID` 并在预览说明来源；不会修改旧文件。

SSL 按用户本次要求与 Java 对齐，不做主机名校验；仍验证信任和握手签名，失败不降级明文。信任库中完全相同的证书直接信任，否则验证签发链、用途和有效期；内置 JKS 支持 TLS 1.2/1.3。证书算法范围和精确行为见[七项同步说明](../03-architecture/client-app-java-compatibility.md)，不提供接受任意证书的开关。

## 图标资源维护

原 Logo 位于 `assets/logo/logo.png`（仓库根目录）；窗口使用它的副本，托盘使用等比透明小图。桌面图标母版为 `src-tauri/icons/app-icon.png`（App 目录），平台资源通过现有 CLI 导出：

```powershell
npm run tauri -- icon src-tauri/icons/app-icon.png --output target/release-icons
```

发布流水线使用相同母版和命令；日常构建直接读取已保存的 `.ico`、`.icns` 和 `.png`。本轮未更改安装签名、发布授权或实际发布版本。

原生菜单的小图标位于 `src-tauri/icons/menu/`，SVG 为可编辑源文件，PNG 为运行时内嵌的 16 × 16 RGBA 资源；修改时同步导出 PNG 并执行对应 Rust 资源校验。动作路径复用 `src/components/AppIcon.vue`，不新增运行时图标库。
