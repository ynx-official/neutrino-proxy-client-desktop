# 桌面客户端开发进展与验证记录

状态：Review
最后更新：2026-10-27

关联文档：[总体方案](../00-project/client-app-proposal.md)、[界面设计](../02-design/client-app-ui.md)、[架构设计](../03-architecture/client-app-architecture.md)、[完整验收计划](../04-quality/client-app-acceptance.md)、[本地运行](../05-operations/client-app-local-development.md)

## 2026-10-27 Windows CI 自启恢复修复

[独立仓库 CI](https://github.com/ynx-official/neutrino-proxy-client-desktop/actions/runs/40440501075) 的两个 macOS 构建成功，Windows 在“任务管理器禁用后重新启用开机自启”的真实插件测试失败。已核对锁定的 auto-launch 0.6.0 源码：插件默认优先注册系统启动项，有管理员权限时只重置系统的 StartupApproved，当前用户的禁用标记仍然存在；本机无系统注册表写权限，因此原用例此前通过。

Windows 注册收尾现在同时写入带引号的当前用户启动命令及启用标记；注册失败继续返回错误并撤销启动注册。补充无需管理员权限的回归用例，使用唯一测试名和真实注册表，先模拟当前用户禁用状态，再核对注册收尾可以恢复插件查询结果并保留含空格路径的引号。该用例在修复前实际失败，修复后通过；原真实插件测试保留，测试清理覆盖当前用户与系统中的同名测试批准项。

本轮本机 Windows 验证：Rust 70 项、Vue 17 项、Python 发布回归 13 项、Playwright / Edge 12 项通过；Cargo 格式与 Clippy 通过。浏览器开发服务器已停止，1420 端口无监听。未修改依赖、锁文件或 CI 测试开关，未操作用户实际自启项、连接配置或凭证。

Windows Release / NSIS 构建和独立打包通过，便携 ZIP 解包后的可执行文件与本次构建逐字节一致，且仅包含可执行文件及 LICENSE。本地产物在 `release-assets/`，未上传或发布：

- 安装包：`neutrino-proxy-client-desktop-0.1.0-windows-x64-setup.exe`，3203392 字节，SHA-256 `e68a1126fd8ae18cf26def65a03e289f87131d21baeee0640d31560f2f8b6c05`。
- 便携包：`neutrino-proxy-client-desktop-0.1.0-windows-x64-portable.zip`，4443588 字节，SHA-256 `d5c824ad58fe7696d3ce6b90010573c1f8a87430cd72129b3c5211c71c3e78e3`。

本节记录本机验证；修订后的远端三平台结果以对应提交的 Actions 为准。系统实际登录启动、安装器安装、macOS 原生交互及长期稳定性仍需分别验收。

## 2026-10-27 独立仓库迁移

桌面项目已完整迁到本仓库根目录，包名及可执行文件改为 neutrino-proxy-client-desktop，工作流与主仓库分离。本轮完整证据见[拆分记录](project-extraction.md)，构建与发版见[独立发布](releasing.md)。下方历史路径、主仓库 tag 和产物哈希保留原始语境，不代表当前可执行文件路径或独立仓库发布结果。

## 2026-10-27 应用设置与启动行为

用户确认应用设置样图并授权实现。设置页现分为“连接配置 / 应用设置”；新增独立的开机自启、启动后自动连接开关，默认关闭、自动保存。启动时仅在连接配置完整、凭证读取成功时发起一次初始尝试，失败停止，认证成功后恢复既有断线重连。托盘窗口重建、第二实例唤起及运行中修改开关不重复触发。完整规则、IPC 与存储边界见[架构说明](../03-architecture/client-app-architecture.md#应用偏好与进程启动2026-10-27)，操作见[本地运行](../05-operations/client-app-local-development.md)。

TDD 证据：先新增启动失败用例，旧重连入口实际出现第二次连接而失败；新增页面用例因缺少应用设置页签失败，再实现两个入口。布局回归发现小窗口新增页签后高级设置被固定操作区遮挡，调整表单间距后保持原断言通过。Windows 注册命令检查另外复现上游裸路径缺少引号，增加平台适配后通过；未放宽失败断言。

| 检查 | 本轮结果 |
|---|---|
| `cargo test --workspace --locked` | 69 项通过：内核 37、宿主 32。覆盖初始网络 / 认证失败不重试、成功后重连、手动连接策略保留、缺配置跳过、重复启动及用户先断开的竞态边界 |
| 应用偏好持久化 | 重启读回、反复修改、连接配置不变、损坏 / 未来版本保留、落盘失败不修改内存及拒绝多项混合更新通过 |
| Windows 系统启动项 | 真实插件及当前用户注册表，使用唯一测试名称；启用 / 读取 / 禁用、启动命令引号、任务管理器禁用状态及再次开启通过；测试 Run 和 StartupApproved 值已清理，未修改用户的 Neutrino 自启设置 |
| `npm test` | 17 项通过，含加载 / 保存期间禁用、只提交变更项、失败不显示已保存、重新读取 |
| Playwright / Edge | 12 项通过；含跨页未保存确认、两个开关独立保存 / 刷新、失败回读、既有导入 / SSL / 高级设置流程和最小窗口可用性；使用开发 IPC 替身 |
| 格式与静态检查 | `cargo fmt --all -- --check`、`cargo clippy --workspace --all-targets --locked -- -D warnings` 通过 |
| 生产构建 | `npm run desktop:build` 退出码 0；前端 Vite 和 Windows Release 可执行程序构建通过 |
| 目视检查 | [应用设置](../04-quality/assets/client-app-application-settings.png)、[连接配置含 SSL](../04-quality/assets/client-app-settings-tabs.png)，860 × 620，文字、开关、页签及操作按钮无重叠 |

新增 Cargo 依赖 `tauri-plugin-autostart`（锁定 2.7.0）和 Windows 平台 `windows-registry`，后者补全安全的带引号启动命令；Tauri `test` 仅用于测试运行时。npm 依赖和锁文件未改，没有重新安装 npm 依赖。应用偏好与 License 存储隔离，未改变 Java 客户端和服务端。

本轮未执行系统注销 / 重启后的自动启动、macOS 实机、原生窗口人工点击或真实服务连接；注册表和浏览器测试不替代这些验收。未生成安装包，未提交、推送或发布。当前本地可执行文件路径为 `neutrino-proxy-client-app/target/release/neutrino-proxy-client-app.exe`，12536320 字节，SHA-256：`ac83caae28d59c49c4563e4399d362019f6ed3de13a9037c3bb3b86a03afa86a`；构建不会替换已安装 App，使用新版前需从旧版托盘完整退出。`git diff --check` 通过，测试自有开发服务已退出，1420 端口无监听。

## 2026-10-26 七项 Java 逻辑同步

用户明确要求同步本轮审查列出的七项差异。现已补齐写缓冲水位线、TCP/UDP 读空闲、写空闲心跳、全空闲与自定义拆包、Java TLS 名称策略及内置 JKS、活动连接上限移除、同目录旧 clientId 迁移。配置从导入预览到保存和运行贯通；另修复已确认导入后旧设置草稿仍可能覆盖导入结果的问题。实现依据和边界见[七项同步说明](../03-architecture/client-app-java-compatibility.md)。

本轮在 Windows 本机使用 loopback 对端和测试凭证验证，先复现新增字段丢失、数据通道无读超时、固定周期心跳、全空闲未生效、第 1025 个连接被拒绝、可信证书名称不符被拒绝、旧 ID 未迁移及表单导入覆盖等失败，再实现修复。

| 检查 | 结果 |
|---|---|
| `cargo test --workspace --locked` | 59 项通过；包含内核 32 项及宿主 27 项。追加 64 MiB 慢接收测试确认背压、跨越两个读空闲周期仍不断开及恢复后数据完整 |
| `cargo clippy --workspace --all-targets --locked -- -D warnings` | 通过，未屏蔽告警 |
| `cargo fmt --all -- --check` | 通过；`git diff --check` 同时通过 |
| `npm test` | 14 项通过 |
| `npm run test:e2e` | 11 项通过，Edge；IPC 测试替身 |
| Java `JavaProtocolVectors.java` | 实际编码、解码七组向量通过，Rust 固定向量验证通过 |
| 前端生产构建 | Vite 构建通过 |
| Windows Release App | `npm run desktop:build` 通过，最终源码构建退出码 0；产物 `neutrino-proxy-client-app/target/release/neutrino-proxy-client-app.exe`，未打安装包 |
| 导入预览目视检查 | 已检查 860 × 620 截图，新增字段及确认按钮可读、无重叠 |

内置公开示例 JKS 已分别完成 TLS 1.2 与 1.3 握手；未知根、非直接信任的过期证书、被篡改的握手签名均拒绝。TLS 边界及直接信任证书策略详见兼容文档，不能推断任意外部 Java PKI 组合均已验证。

macOS 原生运行、生产服务互通、安装包及 72 小时负载未在本轮执行。没有提交、推送或发布。以下按日期保留历史记录，其中此前“自定义协议参数未支持”和“TLS 校验服务器名称”的现状描述已由本节及兼容文档替代。

## 2026-10-16 v2.0.6 正式发布（历史记录）

已按用户要求提交并推送源码 `4c47ea8ec6e45c81ffa908dba062a9f23b4952ad`，正式发布 [v2.0.6](https://github.com/ynx-official/neutrino-proxy/releases/tag/v2.0.6)，包含下方精简原生托盘与 `cargo run` 统一启动。本次以 `publish=true`、`skip_tests=true` 执行，[构建运行](https://github.com/ynx-official/neutrino-proxy/actions/runs/38863160071)全部 9 个作业成功；2026-10-16 14:57:28（Asia/Shanghai）公开为最新正式版本，`draft=false`、`prerelease=false`。

12 个附件准确齐备，远端 digest 与下载的 `SHA256SUMS`、`release-manifest.json` 一致，10 个分发文件的大小与哈希匹配 manifest。源码、tag 和工作流来源一致，manifest 明确 `tests_skipped=true`；测试和运行冒烟步骤均为跳过，构建及静态检查通过。另下载 Windows 安装包和便携 ZIP 核对实际哈希，匹配公开附件；安装包文件版本及产品版本均为 `2.0.6`。发布说明已记录主要变更和本次跳过测试。

本次发布没有重跑下方开发阶段测试，也未执行安装、系统菜单实际点击、真实服务连接、长期资源或 macOS 实机功能验收。完整分发证据见[统一发布记录](releasing.md#v206-正式发布2026-10-16)。

## 2026-10-16 精简原生托盘与 cargo run 统一启动（开发记录）

用户确认新托盘预览并再次明确必须原生实现。本轮保留 Tauri Rust `Menu` / `IconMenuItem` / `TrayIconBuilder`，去掉重复应用标题与“状态：”前缀，状态行可打开连接页，服务器为禁用次要行，动作配小图标，仅两个分隔线。图标以 16 × 16 PNG 内嵌、启动时解码缓存，SVG 源文件同步保留；没有新增托盘 HTML、窗口、WebView、IPC 或依赖。

`cargo run` 现在检查本机 Vite，缺少服务时自动启动并等待页面就绪，然后打开桌面程序；已有本项目开发服务会复用，其他程序占用端口明确报错。仅本次启动的服务由 Rust 持有，正常退出与父进程终止均清理；关闭主窗口保留托盘时仍可重建页面。生产构建不包含开发启动模块，不依赖 Node / Vite。操作方式见[本地开发](../05-operations/client-app-local-development.md)。

本轮验证（2026-10-16，Windows）：

- TDD：先加入状态行点击与直接 Cargo 启动 / 外部服务占用回归，在旧实现中稳定失败，再完成实现。Windows 关闭端口可能先返回超时的行为也由实际失败定位并修正。
- `cargo test --workspace`：34 项通过（内核 12、导入 11、托盘 7、开发启动 4）。开发启动测试实际启动 Vite、请求页面、验证复用与自有进程清理；EOF 用例覆盖 Rust 析构未运行时的清理。原生测试实际创建 Windows 菜单句柄，检查已连接 / 未连接 / 断开中的八行结构、禁用项、图标项及互斥动作，不打开主窗口或读取用户配置。
- `npm test`：13 项通过；`npm run test:e2e`：10 个主窗口流程通过；`cargo fmt --all --check`、`cargo clippy --workspace --all-targets -- -D warnings` 通过。未安装依赖或修改锁文件。
- 实际执行 `cargo run`，通过临时 `TAURI_CONFIG` 使用独立应用标识与隐藏主窗口验证：自动 Vite 返回 HTTP 200、本项目标记与 Vue 入口，桌面进程及 WebView2 子进程成功启动。只终止本次拥有的桌面进程后，Cargo、Node / Vite 和 WebView2 全部退出，1420 端口不再监听；未操作日常客户端、真实连接或凭证。

`npm run desktop:build`：Windows Release 构建通过，程序位于 `neutrino-proxy-client-app/target/release/neutrino-proxy-client-app.exe`，12024832 字节，SHA-256：`5221ed6d77902849b2e9b22e0090dfc20153d0aa135e48d2525d85bd9e25b264`。检查 MZ 文件头、九个菜单 PNG 均已内嵌，二进制不包含开发启动就绪标记、开发脚本路径、Vite 响应标记或旧 `tray.html`；生产前端仅生成主窗口 `index.html`。这是本地可执行文件，没有生成安装包或修改已安装版本。

开发阶段未进行系统菜单实际点击 / 收起、右键时延测量或 macOS 实机验证；原生句柄检查和浏览器测试不能替代这些平台验收。当时尚未提交、推送或发版，v2.0.5 不包含本节改动；后续已按用户新授权发布 v2.0.6，结果见本页上方，开发测试和本地产物哈希保留为历史依据。

## 2026-10-16 v2.0.5 正式发布（历史记录）

已按用户要求正式发布 [v2.0.5](https://github.com/ynx-official/neutrino-proxy/releases/tag/v2.0.5)，包含下述原生托盘和配置导入修复。源码为 `525b895a33812c811a2b3750b8730515e9553b9a`，本次不重跑开发测试，远端发布也显式跳过测试与运行冒烟，保留构建、静态检查、附件齐备、哈希和来源校验。

2026-10-16 13:22:33（Asia/Shanghai）公开为最新正式版本，9 个作业成功、12 个附件齐备。Windows 安装版 / 便携版、Intel / Apple Silicon DMG 均生成，远端 digest 与下载的 manifest / 校验和一致，manifest 标明 `tests_skipped=true`。实际分发证据及未执行的运行验收边界见[统一发版记录](releasing.md)。下方开发阶段的测试与本地二进制哈希保留为历史，不表示本次重新运行测试。

## 2026-10-16 托盘切换系统原生菜单（本地开发记录）

用户反馈通知区域右击卡顿并要求改用系统原生菜单。代码检查确认原流程每次打开都创建新的 WebView 并加载 Vue，失焦后销毁，存在额外冷启动路径；本轮没有将该代码依据写成已测量的唯一性能瓶颈。

已用 Tauri Rust 原生菜单替代自定义浮层：启动时创建并绑定，单击 / 右击由系统弹出，保留应用名、状态、服务器摘要、打开主窗口、日志、互斥连接动作及退出。菜单摘要缓存不含日志、连接时长或 revision，仅相关状态改变时更新；连接角标仍复用预生成图。窗口创建和网络操作在异步任务中执行，重复点击和过时的相反动作被拒绝。错误记录到日志并打开日志页反馈。

已删除托盘 WebView、独立 HTML / Vue / 样式构建入口、事件 capability、四个托盘 IPC 命令和旧调试预览入口。原浮层专用的布局、DOM 事件与坐标测试随旧组件退役，状态 / 操作规则改由 Rust 回归验证，主窗口导航及未保存修改确认的浏览器测试保留。未更改网络协议、配置导入或凭证存储方式。

验证：

- TDD：菜单摘要在仅 revision 改变时仍失效的 Rust 回归先失败，移除非菜单数据后通过；构建资源回归先检出额外的 `tray.html` 入口而失败，移除托盘资源后通过。
- `cargo test --workspace`：28 项通过（托盘 5、导入 11、内核 12），覆盖各状态互斥动作与文案、过时 ID、重复激活、活动服务器与摘要脱敏、无关更新不影响菜单。
- `cargo clippy --workspace --all-targets -- -D warnings`、`cargo fmt --all --check`：通过。
- `npm test`：13 项通过；`npm run test:e2e`：10 个主窗口流程通过，含托盘导航与未保存编辑确认。构建资源回归确认只有主窗口入口及 capability，不再携带托盘 WebView 入口。
- `npm run build`：通过；生产包仅生成 `index.html`，未检出旧托盘 IPC 或开发测试桥接；未安装或修改依赖。

`npm run desktop:build`：Windows Release 构建通过，输出为 `neutrino-proxy-client-app/target/release/neutrino-proxy-client-app.exe`，12007424 字节，`MZ` 文件头；SHA-256：`c811f3df1a470d4e6e5788811189b6c055ec99b26d3b57ab91ee3d98694f3af8`。二进制含原生菜单项，已无 `tray.html` 或旧 `--preview-tray` 入口；构建前复查未发现运行中的同名客户端，使用常规输出目录。

本轮未启动或操控日常客户端，未修改用户配置或中断连接；未提交、推送或发布新版本。Windows / macOS 的原生菜单实际点击、收起、状态切换显示、右键时延和长期内存尚未实机验证，不能以编译或浏览器测试替代。

## 2026-10-16 旧官方 client 分组兼容与预览修复（本地，未发布）

用户提供的配置结构位于 `neutrino.proxy.client`，原增量导入仅识别 `neutrino.proxy.tunnel` 下的连接字段，导致官方旧格式无法导入。预览同时错误展示了合并候选中的本机已保存地址与 License 状态，让“没有读取到文件字段”看起来像已经读取成功。

现已逐字段兼容两个分组，明确存在的 tunnel 字段优先，缺失时再读取 client 同名字段。导入结果附实际读取字段清单，确认弹窗只显示清单中的字段；License 和证书密码始终隐藏明文。无匹配字段时不再显示本机保留值。缺失项保留、确认后保存、不自动连接及完整连接校验的规则不变，详见[配置迁移](../03-architecture/client-app-architecture.md#4-配置兼容与迁移)。

验证：

- TDD：先新增两项 Rust 回归，均在原解析器中失败；随后新增空导入预览浏览器回归，稳定复现本机地址被误显示。修复后全部通过，未删除或弱化原有校验。
- `cargo test --workspace`：26 项通过（导入 11、托盘 3、内核 12）；`cargo clippy --workspace --all-targets -- -D warnings` 与 `cargo fmt --all --check` 通过。
- `npm test`：16 项通过；`npm run test:e2e`：11 个流程通过，覆盖部分导入确认、空导入不显示本机值、旧官方结构对应的六项字段预览、凭证脱敏以及 860 × 620 窗口内操作可达。
- 已目视检查[导入确认截图](../04-quality/assets/client-app-import-legacy.png)，使用虚构配置和开发 IPC 替身；Rust 回归使用用户提供的键名与缩进，真实连接值未写入测试、文档或截图。
- `npm run build`：通过；未安装或变更依赖。

`npm run desktop:build`：Windows Release 构建通过，程序为 `neutrino-proxy-client-app/target/release/neutrino-proxy-client-app.exe`，12072960 字节，文件头为 `MZ`，SHA-256：`de8b6ad4475268e67f44d1962f6b075cad6015ccc2fc9e7b4c43a982a59cb511`。构建前复查未发现运行中的同名客户端，使用常规输出目录；没有执行退出或重启操作。生产前端资源不包含开发 IPC 测试桥接。

未操作已安装客户端的配置、凭证或连接。本轮未执行原生文件选择 / 系统凭证库交互或 macOS 实机导入验证，自动化结果不替代这些平台检查。未提交、推送、创建 tag 或发布新版本。

## 2026-10-16 配置增量导入修复（本地，未发布）

用户明确要求缺少 `neutrino.proxy.tunnel` 等配置时跳过，只导入有用内容。原实现会立即返回“没有找到 neutrino.proxy.tunnel 配置”，且后续必填校验会阻止部分导入。本轮把解析从 Tauri 存储边界抽为可独立测试的模块，以当前已保存配置和凭证为基线：仅覆盖有效且受支持的字段，缺失、空值、错误类型 / 范围、缺失环境变量、不可用证书路径及未支持项跳过。兼容嵌套 YAML 与 Solon 点分键；已跳过的已知字段只提示名称，不输出凭证或值。

首次使用可确认保存部分配置，之后到设置补齐必填信息；手动保存与连接的完整校验没有放宽，导入不自动连接。无可用字段只显示不可应用的预览提示。YAML 格式无效、文件不可读、超过 1 MiB 仍返回错误。详细规则及原“阻止整份导入”策略的替代原因见[配置迁移](../03-architecture/client-app-architecture.md#4-配置兼容与迁移)。未改变服务端、配置文件 schema、凭证存储方式、网络协议或已发布版本。

验证：

- 首先保留旧解析行为，新增 4 个回归用例；全部稳定失败，其中缺少 tunnel 场景复现原报错。实现增量解析后通过，再补充完整旧字段、点分键、环境默认值、错误类型、证书路径与格式错误覆盖。
- `cargo test --workspace`：24 项通过，其中本轮导入回归 9 项、托盘 3 项、原内核 12 项；没有删除或弱化已有网络测试。
- `cargo clippy --workspace --all-targets -- -D warnings`、`cargo fmt --all --check`：通过。
- `npm test`：13 项通过；`npm run test:e2e`：9 个流程通过。新增首次缺少 License 的部分配置能确认保存、进入设置补齐、无全局错误且不调用连接的浏览器流程，使用开发 IPC 替身。
- `npm run build`：通过。未安装或变更依赖。

`npm run desktop:build`：Windows Release 构建通过，本地修正版为 `neutrino-proxy-client-app/target/release/neutrino-proxy-client-app.exe`；12068864 字节，SHA-256：`6a554ebe0913bdfd15d081128385e6c8275ee685b0402ff247a1ae45d29876e3`。检查二进制已移除原分组缺失报错并包含增量导入提示；这是本地开发构建，不是新发布的版本。

本轮没有修改已安装客户端的配置或中断其连接。未执行原生文件选择 / 系统凭证库交互或 macOS 实机验证；解析行为由 Rust 回归覆盖，确认保存流程由浏览器流程覆盖。未提交、推送、创建 tag 或发布新版本。

## 2026-10-15 v2.0.4 正式发布（历史记录）

已按用户要求将源码提交 `be080e19987fca69aeb10fe1b0b084bf63073bf4` 正式发布为 [v2.0.4](https://github.com/ynx-official/neutrino-proxy/releases/tag/v2.0.4)，包含本页记录的简约界面、托盘浮层和项目 Logo。Windows 安装程序及便携 ZIP、Intel / Apple Silicon macOS DMG 均由 CI 成功生成并公开；验证与附件溯源以[统一发版记录](releasing.md#v204-发布记录)为准。

本节更新下方历史里程碑中的“尚未生成安装程序 / 尚未正式发布”状态；历史开发版本号与本地产物哈希保留用于追溯。发布不代表补齐托盘原生交互复验、macOS 原生窗口验收、真实兼容矩阵和长期稳定性测试，这些待办仍保留。

## 2026-10-15 项目 Logo 图标与目录清理

用户指定 `assets/logo/logo.png` 为图标来源，授权加工适配 Windows / macOS，同时明确删除根目录 `.idea`、`.workflow`。本轮以原蓝橙标识制作浅色圆角底座母版，导出 `.ico` / `.icns` / PNG，更新默认窗口、托盘、页面品牌及发布流水线的图标来源。原 Logo 文件保持不变；页面使用逐字节副本，托盘使用直接从原图等比导出的透明小图，连接状态角标预生成并缓存。

目录清理：原生 PowerShell 的直接递归删除被自动审批以 `blocked by policy` 拦截。核对两个绝对路径均在项目根目录、不是重解析点且没有嵌套链接后，改用可恢复的系统回收站删除，调用成功；两个目录均已不存在。Git 记录对应 `.idea/icon.png` 和 `.workflow/pipeline-docs-build.yml` 的删除，`.github/workflows` 保留。未清理其他工作区修改。

已验证：

- Tauri CLI 实际导出成功；PNG 母版 1254 × 1254、运行时 PNG 512 × 512、托盘 PNG 64 × 64，均为 RGBA；ICO 含 16 / 24 / 32 / 48 / 64 / 256 图层；ICNS 含 `ic10` 1024 图层，各块长度有效。
- `npm test`：13 项通过；`npm run test:e2e`：8 个流程通过；浏览器中实际检查主页面与托盘的新 Logo，[连接页](../04-quality/assets/client-app-project-logo-connected.png)、[托盘](../04-quality/assets/client-app-project-logo-tray.png)使用开发 IPC 测试替身。
- `cargo test --workspace`：15 项通过；Rust Clippy 通过。
- `python -m unittest discover -s scripts/release -p test_release.py`：9 项中 8 项通过、1 项按原条件跳过。

Windows Release 构建通过：`neutrino-proxy-client-app/target/ui-refresh/release/neutrino-proxy-client-app.exe`，12064768 字节，SHA-256：`cb41a7ae9202d7ccaff8a8f923d8046b2372861bc9b7fff4ef8ff44e0896156c`。核对 ICO 的六个图层字节均存在于 EXE 资源，确认已嵌入新图标。

当前程序在常规 `target/release` 路径运行，本轮使用 `target/ui-refresh` 构建，不退出或覆盖正在运行的实例。未启动新的原生 UI 测试；上一轮托盘 Windows 交互复验与 macOS 原生验证的待办仍保留，不能用本轮图标导出代替它们。

## 2026-10-15 托盘浮层实现

用户已明确批准[托盘样图](../02-design/assets/client-app-tray-preview.png)。已替换旧的静态原生菜单：新增按需创建的本地 Vue 浮层，显示应用名、真实连接状态及服务器；提供打开主窗口、查看日志、随状态切换的单一连接动作与独立退出项。连接中可取消，等待重连可停止，断开中禁用操作；宿主复查状态，拒绝过时的相反动作。未配置时连接入口跳转设置。托盘图标角标及悬停文字随状态更新。

主窗口和托盘分别接收对应事件；托盘摘要不包含日志或凭证。主窗口导航使用待消费路径，在窗口重建后也能打开日志；已有页面仍通过 Router guard 确认未保存修改。浮层失焦、Escape 或操作完成后销毁，不保留隐藏的托盘 WebView。未修改服务端、Rust 网络协议或用户保存的连接配置，未自动提交或发布。

已执行：

- `npm test`：13 个测试通过，新增托盘互斥动作、实时更新、初始化快照竞态、断开禁用、重复点击和失败反馈覆盖。新增组件在尚未实现时测试失败，接入后通过。
- `cargo test --workspace`：15 个测试通过，其中托盘宿主 3 个，原内核 12 个；覆盖状态与过时动作、实际活动地址、摘要脱敏、屏幕工作区和缩放坐标计算。
- `npm run test:e2e`：8 个流程通过，新增 288 × 342 浮层的两种状态、无溢出、动作分发、Escape 与未保存编辑确认。数据来自开发 IPC 替身，见[已连接](../04-quality/assets/client-app-tray-connected.png)、[未连接](../04-quality/assets/client-app-tray-idle.png)。
- `cargo fmt --all --check`、`cargo clippy --workspace --all-targets -- -D warnings`：通过。
- `npm run build`：主窗口与托盘两个入口构建通过；产物未包含开发 IPC 测试桥接。

Windows 原生验证边界：使用独立应用标识与虚构本机地址，实际打开主窗口和未连接托盘，确认布局、状态、地址与四个操作显示。首次交互暴露窗口卡顿；检查本地 Tauri 2.12.4 文档后，按其 Windows 已知问题说明将同步原生事件回调中的 WebView 创建移入既有阻塞任务池，并串行化托盘创建请求；失焦销毁另改为离开回调后执行。自动化检查和编译不能代替原生复验。随后用户按物理 Escape 停止 Computer Use，已停止全部原生 UI 操作并结束本轮测试实例。**修复后的失焦、Escape、窗口恢复、连接/断开及退出原生流程尚未复验，不得视为原生交互验收通过。**

Windows Release 构建成功，程序：`neutrino-proxy-client-app/target/release/neutrino-proxy-client-app.exe`；大小 11994624 字节，SHA-256：`d1dce09a00ef354d4ff9d2a08b16ec9f92062c70f4feea67a3865425bb9a6476`。确认 Release 中不包含 `--preview-tray` 调试入口。没有自动启动新版或替换正在运行的日常实例。

调试构建的单实例入口接受 `--preview-tray` 以调用真实浮层创建路径，便于在无法自动化系统任务栏时验证界面；该调试入口通过条件编译从 Release 中移除。macOS 原生测试和长期内存测量未执行。

## 2026-10-15 默认窗口与托盘预览

用户要求默认使用原最小窗口尺寸。本轮将主窗口配置设为 860 × 620，最小尺寸维持 860 × 620；托盘恢复窗口改为复用同一窗口配置，避免关闭后重建又变回 1040 × 720。窗口配置回归先在旧尺寸失败，再在修改后通过，`npm test` 共 9 个测试通过。Windows Release 构建通过，新程序为 `neutrino-proxy-client-app/target/release/neutrino-proxy-client-app.exe`；大小 11918848 字节，SHA-256 为 `70d2e53a2c8e022c2d332ef714e0bb82c84a32b9200e6f92d50812e67cfbcd81`。当前运行程序未被重启。

托盘本轮交付为[设计预览](../02-design/client-app-ui.md)，展示已连接与未连接的互斥操作；尚未改变实际托盘菜单，避免把生图当成已实现功能。当前运行中的连接保留。

## 2026-10-15 首页事件数量调整

按用户要求，首页最近事件由五条改为仅显示最新三条；新事件到达后自动更新这三条，不修改原日志数组或日志页查看范围。回归用例已先在五条实现下失败，再在修改后通过；`npm test` 共 8 个测试通过，生产前端构建通过。Windows Release 已构建通过，更新程序为 `neutrino-proxy-client-app/target/ui-refresh/release/neutrino-proxy-client-app.exe`；大小 11920896 字节，SHA-256 为 `ba42f724659405fc2819103b4fc5a825e1a1ae5ba5bd06acb1394234a23fd49c`。当前运行中的旧程序未被替换或重启，退出托盘后打开这个更新程序即可应用三条事件上限。

## 2026-10-15 简约样图落地

用户已明确确认[简约样图](../02-design/assets/client-app-minimal-approved.png)，本轮将连接、设置和日志统一为顶部导航、白色画布、细分隔线与无卡片布局，删除旧侧栏、色块和装饰。页面真实状态、错误、重连操作、凭证保留与保存生效语义继续使用现有逻辑。根目录 AGENTS.md 与[界面设计](../02-design/client-app-ui.md)已同步视觉基线，旧色块设计归档。

- `npm test`：7 个组件测试通过。
- `npm run test:e2e`：6 个浏览器流程通过；新增水平导航与三页可达检查，旧侧栏稳定失败后在新布局通过。小窗口检查另复现保存栏遮挡高级入口，增加实际命中区域回归并收紧小窗口间距。
- `npm run build`：生产前端构建通过，确认产物不包含开发 IPC 测试桥接入口。
- Windows Release：简约版构建通过，独立输出为 `neutrino-proxy-client-app/target/ui-refresh/Neutrino-Proxy.exe`；大小 11920896 字节，SHA-256 为 `5ceb2b7cfb36161abb5edef036b7c3798dc89c5816385a1ea66e064d21c8443c`。
- Windows 原生预览：已实际打开独立标识的简约预览，检查连接、设置和日志三页、顶部导航及基础控件。预览使用空配置，没有连接真实服务器或修改用户配置；检查后已关闭，仅保留原有正在运行的客户端。

[原生设置页截图](../04-quality/assets/client-app-minimal-windows.jpg)。已连接状态与日志筛选使用浏览器 IPC 测试替身验证，本轮不把样例数据视为真实服务器认证结果。
- 旧版当前正在保持连接；构建使用独立输出目录，未退出旧进程、未修改用户配置或凭证。

## 上一轮色块方案（已替代）

用户反馈旧界面缺少设计感、说明文字过多。本轮已重做导航、连接状态面板、设置表单和日志列表：采用奶油色导航与深绿状态面板，收紧字级和间距，删除常驻教程与重复说明，保留错误、未保存和配置生效时间等必要反馈。网络内核及配置含义不变。当前视觉基线和实际页面截图见[界面设计](../02-design/client-app-ui.md)；原概念方案保存在[初稿归档](../99-archive/client-app-ui-initial.md)。

该轮验证记录：

- `npm test`：7 个组件测试通过，包括重连操作、活动配置与待应用配置的显示区分。
- `npm run test:e2e`：5 个 Edge 浏览器流程通过，覆盖首次配置、连接状态、日志筛选、860 × 620 小窗口与长地址、SSL 和高级设置。
- `npm run build`：生产前端构建通过；确认 Release 资源不包含开发测试桥接入口。
- Windows Release：原生构建通过，已将新版更新到原启动路径并实际打开。通过 computer-use 读取连接页、导航与设置页，确认原有配置和已保存凭证状态正确加载；本轮没有修改或保存用户连接参数。
- 本轮原生检查覆盖未连接页和设置页；已连接页面使用浏览器 IPC 替身核对。本轮未操作真实服务器连接，不把历史原生认证结果算作本轮验证。

新版启动路径：`neutrino-proxy-client-app/target/release/neutrino-proxy-client-app.exe`。同一构建另保留在 `target/ui-refresh/release/`。文件大小 11,924,992 字节，SHA-256：`5b19f36315198670309e02da63d6effc25a467044556516144ae0cec70abeda9`。本轮没有修改依赖、Rust 内核、配置结构或服务端代码。

以下保留初次可运行里程碑的测试与截图，不能将历史截图当成本轮页面。

## 初次可运行里程碑

用户本轮要求为“开始重写客户端，直到软件能打开，页面一致”。在独立的 `neutrino-proxy-client-app/` 中实现 Rust / Tokio 内核、Tauri 2 宿主和 Vue 3 页面，形成 Windows 可直接运行的开发版本。当前版本为 0.1.0，用户于 2026-10-15 授权将源代码提交至 [GitHub 仓库](https://github.com/ynx-official/neutrino-proxy)。Windows 构建产物保留在本地工作区，尚未正式发布。

这份记录只说明当前实现与已执行的验证。完整迁移方案中的旧证书兼容、全部非默认参数、长期资源测试、macOS 原生验收及安装包发布仍需后续完成。

## 已实现

| 部分 | 当前行为 |
|---|---|
| 桌面程序 | Windows 原生 exe，内嵌前端资源；启动不依赖 Vite、命令行窗口或 Java |
| 页面 | 按 `airtable` 样图实现连接、日志、设置三页；浅色导航、连接摘要、最近事件、基础表单和高级折叠区 |
| 配置 | 地址、端口、License、SSL、证书、客户端 ID、重连间隔、心跳、读超时、UDP 范围；Rust 再次校验输入 |
| 本地持久化 | 原子替换普通配置文件；License 和 JKS 密码使用系统安全存储；界面只接收掩码摘要 |
| 通信内核 | 原有二进制帧格式、认证、心跳、读超时、网络重连、认证失败停止、手动断开和取消；TCP / UDP 双向转发 |
| 资源边界 | 共享 2 个异步工作线程，阻塞任务池最多 4 个线程；连接任务、日志和事件有界，数据包不推送到前端 |
| 桌面生命周期 | 单实例；关窗销毁 WebView、Rust 保持运行；重复打开 exe 恢复窗口和状态；托盘提供连接、断开及退出入口 |
| 日志 | 当前会话脱敏日志、筛选、暂停视图更新、导出；当前内存最多 500 条、单条最多 512 字符 |
| 导入 | YAML 脱敏预览并显式确认；读取基本连接配置与部分高级参数，不修改原文件；已知不支持的协议参数阻止应用 |
| 开发基础 | npm / Cargo 锁文件、组件与浏览器测试、Rust 测试和 Clippy、Windows/macOS CI 工作流 |

## 初次里程碑已执行的验证

| 检查 | 本机结果 | 覆盖与限制 |
|---|---|---|
| `cargo test -p neutrino-client-core` | 12 个测试通过 | 原字节格式、半包、Unicode / 二进制、异常长度、配置错误、内置 JKS 读取、短凭证掩码、认证与取消、TCP / UDP 回传 |
| `cargo clippy --workspace --all-targets -- -D warnings` | 通过 | Rust 静态检查，不等同于网络兼容性或内存测试 |
| `cargo fmt --all --check` | 通过 | Rust 格式检查 |
| `npm test` | 5 个测试通过 | 首次配置校验、保持已存凭证、异步加载配置、初始状态、断开操作 |
| `npm run test:e2e` | 4 个流程通过 | 表单与导航、已连接信息层级和日志筛选、最小尺寸与长地址、默认配置页无需多余滚动；使用明确的 IPC 测试替身 |
| `npm run desktop:build` | Windows Release 构建成功 | 生成可直接运行的 exe；不是安装包签名或发布验收 |
| Windows 原生窗口 | 已实际打开并检查 | `computer-use` 读取真实窗口和控件；核对页面、表单、状态和导航 |
| 原生保存并连接 | 本地测试对端认证成功 | 从实际窗口填入虚构 License；确认状态由 Rust 认证结果驱动，配置文件不包含凭证明文 |
| 关窗和恢复 | 通过 | 关闭后窗口从原生窗口列表消失，Rust 进程及本地 TCP 连接仍在；重开 exe 保持同一进程、原连接及持续时间 |
| 整个程序重启 | 通过 | 保留连接参数与安全存储凭证，不自动连接；点击连接可再次认证成功 |

最小窗口回归测试曾复现保存按钮底部超出 620 像素，修正为固定可见的操作区后通过；默认窗口另有回归测试确认折叠状态的完整配置表单不产生多余滚动。断开与重连生命周期测试没有通过删除用例或跳过断言获得通过。认证帧固定向量依据所读 Java 编码代码构造，尚未建立完整的 Java 客户端对照矩阵。

本次原生测试对端仅监听 `127.0.0.1`，属于测试夹具，不是服务端产品改造。测试后已停止夹具，删除本次创建的测试配置与对应安全存储条目，让 App 回到未配置状态；没有使用真实 License 或连接生产服务。

## 初次里程碑运行截图

初次 Windows Release 已重新打开，停留在干净的配置页；完整基础表单在默认窗口内显示，没有多余滚动条：

![最终 Windows 原生配置页](../04-quality/assets/client-app-windows-setup.jpg)

初次里程碑 exe：`neutrino-proxy-client-app/target/release/neutrino-proxy-client-app.exe`，SHA-256 为 `906229aa3f098361c1dd69808bc7152240dadf448cb8e1216cfb478058695ac0`。

Windows 原生窗口通过本地测试对端认证后的状态：

![Windows 原生客户端已连接](../04-quality/assets/client-app-windows-connected.jpg)

截图中的地址、端口与凭证均为本机测试数据，与设计样图中的示例域名不同。运行截图证明页面和状态已在原生窗口中呈现，不能据此推导出真实服务兼容、吞吐或长期内存表现。

## 后续迁移与验收

- macOS 源码路径与 CI 已准备，但本机为 Windows，尚未执行 macOS 构建、菜单栏、窗口及系统安全存储验证；远程构建结果以 [GitHub Actions](https://github.com/ynx-official/neutrino-proxy/actions) 的实际运行记录为准。
- JKS 可直接读取，但当前 TLS 按证书链、有效期和服务器名称验证。旧 Java 行为差异仍需真实的脱敏证书矩阵验证，不提供忽略证书错误的开关。
- 当前未完整迁移自定义帧布局、水位线、全空闲超时和所有框架专用参数；不能宣称旧配置已经全部无损兼容。
- 当前不复用空闲数据隧道池；TCP / UDP 基础转发已验证，但池化、并发容量、慢连接压力、异常 UDP 回收和全部路由场景仍需扩大测试。
- 当前日志为内存记录与手动导出，退出后不会保留完整历史；尚未实现滚动日志文件和系统登录自动启动。
- 托盘退出当前直接结束连接，活动传输确认和更细的托盘状态操作仍需补齐。
- 未运行 72 小时稳定性、Java 对照基线、完整进程树内存和吞吐测试；不承诺固定 MB 占用或性能提升比例。
- 尚未生成安装程序、签名、公证、自动更新或正式发布。

## 下一阶段顺序

按[实施计划](client-app-implementation-plan.md)补全旧配置与 TLS 兼容测试、转发并发和资源回收，再执行双平台及长期运行验收。当前可运行里程碑的完成不代表全部阶段已经完成。
