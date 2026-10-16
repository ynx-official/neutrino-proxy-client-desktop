# 后台独立进程架构

状态：Archived（批准实施前的讨论，已被[实际架构](../03-architecture/background-process-design.md)替代）  
最后更新：2026-10-16  
关联文档：[协议依据](../03-architecture/protocol-and-architecture.md)、[历史实施计划](background-process-plan-proposal.md)、[现有内存基线](../04-quality/verification.md#后台内存基线)

## 目标与确认状态

**已确认：** 用户要求明显降低后台内存，让网络内核独立运行，收起时真正释放界面；本轮要求开始架构规划。先前已选择纯 Dart 网络路线，协议仍以官方 Java 为依据，保留现有 Flutter 页面和透明图标。随后用户进一步询问能否达到个位数后台占用，并以 Rust 为比较对象；这尚不等于批准更换网络语言。

**原提案（保留纯 Dart 的条件下）：** 增加轻量原生宿主，独立运行 Dart AOT 内核，Flutter 界面按需启动和退出。Windows 优先交付，macOS 使用相同进程边界。进程拆分、凭证适配和下述性能门槛待用户确认后实施。若以个位数为优先目标，应先评审下节的 Rust 候选路线，不直接执行原 Dart 拆分计划。

**待实测：** 两个常驻进程的总内存、界面重开延迟、macOS 子进程沙盒/Keychain 行为。30 MiB 是拟定验收目标，不是已达到或保证可达到的结果。

原 Dart 提案不增加新的网络运行时；下节 Rust 路线属于待批准的替代方案。两条路线均不修改服务端协议，不处理用户已暂缓的偶发 TCP 目标/隧道警告，不增加开机自启、系统服务、管理员权限或数据库。

## 个位数内存目标的补充评估

2026-10-16 用户追问：“能后台运行时压到个位数吗，我看 Rust 都可以”。本节记录新的可行性比较，尚未批准语言切换；后文三进程详细设计仍是保留 Dart 的备选。

**判断：** 可以把 Windows 空闲保持连接时、全部后台应用进程私有工作集合计低于 10 MiB 作为原型验证目标。当前没有本项目的 Rust 独立后台测量，不能把语言特性等同于达标证据；纯 Dart AOT 也未经测量，不能断言绝对做不到。

Rust 不要求垃圾回收器；Dart 的独立 AOT 可执行文件仍包含负责垃圾回收等工作的 Dart 运行时。因此，在严格限制常驻内存的条件下，Rust 更适合作为优先验证对象，但依赖库、TLS、线程、日志、平台框架和实际连接数仍会影响结果。[Rust 官方说明](https://rust-lang.org/)、[Dart AOT 说明](https://dart.dev/tools/dart-compile)

若用户接受调整纯 Dart 约束，建议候选结构为：**一个 Rust 常驻进程同时承载网络内核与原生托盘，另一个 Flutter UI 进程按需启动，收起后退出。** 后台不加载 Flutter/Tauri/WebView，不再常驻两个分别承载宿主和内核的进程。原生托盘通过平台 API/薄适配接入 Rust 进程；macOS 仍需验证主线程事件循环和 Keychain 身份。

代价是需要迁移和重新验证网络实现，且托盘宿主与内核共处一个故障边界：常驻进程崩溃时托盘和网络一同退出，不能沿用原三进程方案中“宿主监督内核重启”的承诺。UI 崩溃仍不影响常驻内核。协议与业务行为继续以官方 Java 为依据，不因选 Rust 就把旧 Tauri 版本改成协议权威来源。

首个可行性原型必须包含真实托盘、TLS 连接、心跳、配置/凭证读取和有界日志，不能只测一个 Rust 空程序。预热后连续采样，报告所有相关进程的私有工作集中位数、P95、峰值、私有提交量和总工作集；争取空闲连接 P95 <10 MiB，同时报告启动/TLS 握手峰值。实际转发和高并发另测，不承诺任何负载下都低于 10 MiB。Windows 和 macOS 分别验收。

在语言路线确认前，不自动改写现有 Dart 网络代码、不迁移用户数据。确认后先执行原型测量，再按结果更新详细架构、内存门槛和实施阶段。

## Android APK 目标与已有 Rust 内核

2026-10-16 用户补充：选择 Flutter 还希望能够打包 Android APK。这是架构必须考虑的新目标，不表示已批准切换 Rust 或立即实施 Android。当前工程只有 Windows/macOS 平台目录，尚未建立或验证 Android 工程。

Flutter 可以与 Rust 原生库组合并打包 Android；使用 Flutter 不要求所有网络代码都用 Dart。Flutter 官方提供平台通道及原生互操作机制，Rust 可通过 C ABI 或 Android JNI 适配接入。[Flutter 架构与原生互操作](https://docs.flutter.dev/resources/architectural-overview)

本地检查发现，原 App 已有独立的 `../neutrino-proxy/neutrino-proxy-client-app/crates/client-core`，其 Cargo.toml 不直接依赖 Tauri，网络使用 Tokio/rustls。它是可复用候选，不能因更换界面就默认再写一份 Rust 网络内核；但尚未验证其 Android 交叉编译、依赖支持和运行行为。复用仍需获得对原纯 Dart 约束的调整确认，协议验收继续以官方 Java 为依据。

若采用共享 Rust 内核，建议按平台托管：

| 平台 | 界面 | 内核运行方式 |
| --- | --- | --- |
| Windows/macOS | Flutter 窗口 | 独立原生后台进程，承担托盘与 Rust 内核；收起退出 UI |
| Android | Flutter Activity | 原生前台服务拥有 Rust 内核，JNI 加载 APK 内的 `.so`；界面经平台通道与服务交互，不拥有内核生命周期 |

Android 若要隔离 Flutter 引擎，可评估独立服务进程与 Binder 通信。不能只在 Flutter isolate 中加载 Rust，再假设销毁 Flutter 后网络会自动存活。Android 的 Activity、引擎销毁及缓存进程回收需单独设计与实测，不套用桌面“关闭窗口即结束进程”的行为。

长期连接需要评审适合实际用途的前台服务类型、通知和系统后台限制；服务不是不受系统约束的常驻进程。不能简单把持续代理连接归类为无限期 dataSync：面向 Android 15 及以上时该类型在后台有运行时限。也不应仅为保活把普通反向代理改成 VPN。[前台服务说明](https://developer.android.com/develop/background-work/services/fgs)、[运行时限说明](https://developer.android.com/develop/background-work/services/fgs/timeout)

Android 的内存验收应计入服务、ART、原生库和可能缓存的 UI 进程，按设备记录 PSS/RSS 等口径；不承诺与 Windows 相同的个位数占用。打包 APK、长期后台运行和低内存是三个独立验收项。

还有一条减少改造的备选：保留现有 Tauri 桌面客户端，仅为 Android 新建 Flutter 界面，两端共享经过验证的 Rust 内核。是否要求桌面与手机共用 Flutter UI 尚待产品选择；本轮只补充方案，不改变已运行程序。

## 现状与问题

- `lib/main.dart` 同时初始化 Flutter、配置、凭证、网络桥和托盘。
- `lib/application/engine_bridge.dart` 的网络 isolate 仍在 Flutter 进程内，`dispose()` 会断开并杀死 isolate。
- `lib/platform/desktop.dart` 关闭窗口只调用 `windowManager.hide()`；托盘和安全存储使用 Flutter 插件。
- `lib/application/controller.dart` 当前持有配置、凭证和连接指令；若直接退出界面，无界面的重连与托盘连接操作没有独立所有者。
- Windows 单实例锁属于 Flutter runner，第二次启动只寻找已有窗口；界面退出后需要由新宿主承担激活职责。

因此，单独增加网络进程、继续让 Flutter 承载托盘，不能满足“后台释放整个界面”。当前短时空闲样本约 64 MiB 私有工作集，采样条件和局限见[验证记录](../04-quality/verification.md#后台内存基线)。

## 方案比较

| 方案 | 后台组成 | 收益与代价 | 结论 |
| --- | --- | --- | --- |
| 原生宿主 + Dart 内核 + 按需 Flutter UI | 原生宿主、Dart 内核 | Flutter 可以完全退出；平台生命周期清晰；增加 C++/Swift 薄宿主和 IPC | 保持纯 Dart 约束时的推荐 |
| Rust 内核与原生托盘同进程 + 按需 Flutter UI | 一个 Rust 常驻进程 | 减少后台运行时与进程开销；需要迁移网络实现，宿主与内核共用故障边界 | 个位数目标下优先验证，待批准语言切换 |
| Dart 内核通过 FFI 同时管理原生托盘 + 按需 Flutter UI | 一个 Dart 进程 | 少一个常驻进程；需自行适配平台事件循环，尤其 macOS 主线程和 AppKit 生命周期 | 作为后续优化候选，首轮不采用 |
| 独立内核 + 常驻 Flutter 托盘 | Dart、Flutter | 改动较小，但 Flutter 仍常驻 | 不满足本次目标 |

下文详细展开的是保留纯 Dart 的方案，其中 C++/Swift 只负责桌面系统集成。若确认 Rust 替代路线，应先依据原型结果修订这些进程边界，不能直接沿用。

## 进程边界与技术栈

```mermaid
flowchart LR
    UI[Flutter 界面\n按需启动，收起退出] <-->|私有管道：命令与状态| Host[原生宿主\n常驻：托盘、进程、凭证]
    Host <-->|私有管道：控制与事件| Core[Dart AOT 内核\n常驻：配置、日志、连接]
    Core <-->|原协议 TCP / UDP / TLS| Server[代理服务端与本地目标]
```

打开窗口时通常有三个应用进程；后台只有宿主和内核。所有性能统计必须把它们相加，不能只展示内核进程的数字。

| 部分 | 拟用技术 | 职责和限制 |
| --- | --- | --- |
| 管理界面 | 已锁定 Flutter 3.47.5 / Dart 3.13.4、Riverpod | 复用三页、表单、导入预览；只通过 IPC 读写业务状态，不拥有连接 |
| 网络内核 | 纯 Dart、`dart:io`、AOT 可执行程序 | 复用协议、TLS、TCP/UDP、取消、重连；唯一持有网络 socket 和有效配置 |
| Windows 宿主 | C++、Win32、现有 VS/CMake 工具链 | 原生托盘、单实例、启动监督、DPAPI 适配；不加载 `flutter_windows.dll` |
| macOS 宿主 | Swift、AppKit、Security.framework | 状态栏、启动监督、Keychain；不加载 FlutterMacOS.framework |
| 本地控制通信 | 父子进程继承的双向匿名管道、带长度的 JSON 消息 | 不开本机 HTTP/TCP 管理端口；只传控制、状态、配置和有界日志 |
| 配置 | 现有版本化 JSON + 系统安全存储 | 无数据库；保留客户端 ID、证书副本和已保存参数 |

独立 Dart 程序用 `dart compile exe` 打包，无需用户安装 Dart SDK。包含 build hooks 的依赖需要改用 `dart build`，因此内核包必须隔离 Flutter 插件依赖；这是构建可行性检查的一部分。[Dart 官方编译说明](https://dart.dev/tools/dart-compile)

暂不为本次拆分升级 Flutter、引入通用服务框架或更换状态库。依赖升级与架构改造分开验证。

## 生命周期与桌面行为

| 触发 | 拟定行为 |
| --- | --- |
| 启动桌面快捷方式 | 启动/激活唯一宿主；宿主确保一个内核，然后打开一个 UI；不因此自动连接服务器 |
| 关闭窗口或“收起到托盘” | 检查未保存编辑和进行中的保存；确认完成后 UI detach 并退出；内核保持现有 TCP/UDP 会话 |
| 系统最小化按钮 | 暂按普通最小化处理，保留 UI；真正释放的入口为关闭窗口/收起到托盘。这是提案默认交互，可在批准时调整 |
| 托盘打开/查看日志 | UI 存在则激活，否则重启；读取完整状态快照，恢复页面、窗口位置等非敏感视图状态 |
| 后台托盘连接/断开 | 宿主直接向内核发命令，不启动 Flutter |
| UI 异常退出 | 清理 UI 订阅，内核继续工作；托盘可再次打开 UI |
| 内核崩溃 | 宿主明确显示连接已中断；有限次数退避重启；不能声称现有转发会话得以保留 |
| 宿主崩溃 | 内核检测控制管道 EOF 后关闭网络并退出，防止没有托盘入口的孤儿进程；重启应用后恢复可操作状态 |
| 托盘“退出应用” | 宿主停止新操作，要求内核断开、退出 UI，等待退出；超时只终止自己创建的子进程 |
| 托盘初始化失败 | 不允许悄悄退出唯一界面；显示恢复入口和退出操作，避免用户失去控制 |

用户主动断开与应用退出必须清除宿主内存中的重连意图。宿主只在收到明确的连接命令后记住该意图；认证失败按原协议规则停止或重试，不把正常认证失败当成进程崩溃。

建议内核异常退出的自动重启上限为 5 分钟内 3 次，等待 1、3、10 秒；达到上限停止，保留托盘手动重试。宿主重启后不跨进程持久化“自动连接”意图，避免新增自启连接行为。

关闭 UI 不调用内核 disconnect/shutdown。新的桥接接口明确区分 `attach`、`detach`、`connect`、`disconnect`；应用级 `shutdown` 仅由宿主执行。未保存内容继续沿用现有确认，取消关闭后窗口保持打开；不把未保存 License 写入视图状态。

## IPC 契约与资源边界

1. 宿主分别创建内核和 UI 的管道，严格限定子进程可继承的句柄；宿主不保留错误的写端副本，以便退出后能收到 EOF。Windows 句柄继承依据[官方管道文档](https://learn.microsoft.com/en-us/windows/win32/ipc/pipe-handle-inheritance)。
2. 优先把子进程 stdin/stdout 专用于协议，stderr 用于有界、脱敏诊断；首阶段验证 Windows GUI runner 不重定向这些句柄、不向协议输出写普通日志，以及 macOS helper 可用性。若 GUI 标准流不可可靠隔离，在同样的继承管道上使用小型原生桥，不改成本机公开接口。
3. 每帧为 4 字节大端长度 + UTF-8 JSON；每条消息含 `protocolVersion`、`hostEpoch`、`requestId`、`kind`，事件另含 `coreEpoch`、`revision`。版本不兼容拒绝控制并提示完整重装，不启动第二个内核兜底。
4. 操作包括 handshake、snapshot、connect、disconnect、saveConfig、subscribeLogs、unsubscribeLogs；宿主专用 vault 操作不向 UI 开放任意凭证读取。正常状态仅包含 `hasLicense` 等标记，不能回传完整秘密。
5. UI 和托盘的变更命令在内核中串行化，带预期配置 revision，拒绝过期保存。相同会话中的重复 requestId 返回已有结果，不重复连接；超时后先查询状态，不盲目重发。重启后 epoch 变化，不能把旧响应当作新状态。
6. 控制帧建议上限 256 KiB；证书保持现有 4 MiB 文件限制，按有序小块发送，累计计数、哈希校验、超时清理；配置导入保持 1 MiB 限制。各方向待发送队列有硬上限（首版 1 MiB），控制回复优先于日志，慢 UI 不阻塞网络读写。
7. 日志继续仅存内核最近 500 条，每条保持现有限长；无 UI 时不推送日志，宿主只订阅摘要。UI 连接后先快照，再按序号拉取增量；丢失区间显式提示，避免持续复制整个日志数组。
8. 网络载荷不经过宿主或 UI；网络回压、帧长和并发上限继续由现有内核实施。

宿主内所有 IPC 操作异步执行，不阻塞托盘主事件循环。唯一宿主负责启动 UI，快速重复点击合并成一个启动任务。

Windows 重复启动入口通过仅当前用户/会话可访问的激活通道通知宿主，只允许“打开窗口/日志”，不允许发送凭证、连接或退出命令。子进程按安装目录内固定路径启动，不接受外部指定可执行文件；凭证不放命令行、环境变量、诊断日志或普通临时文件。父子管道不宣称能隔离同一用户下的恶意进程。

## 状态、文件与凭证所有权

| 数据 | 唯一所有者 | UI 的使用方式 |
| --- | --- | --- |
| 活跃连接、重连、转发会话 | Dart 内核 | 快照与事件显示 |
| 已保存普通配置、clientId、证书副本 | Dart 内核 | 经校验命令保存，等待成功确认 |
| 系统凭证读写 | 原生宿主的 vault 适配器 | 新输入的秘密一次性提交；不请求已有秘密的明文副本 |
| 配置事务和 credentialId 关联 | Dart 内核 | 失败显示错误，不能假报保存成功 |
| 表单草稿、筛选和页面选择 | Flutter UI | 敏感草稿仅内存；可保存非敏感视图状态 |
| 托盘摘要和进程状态 | 原生宿主 | UI 读取宿主健康状态 |

保存继续遵循“写新凭证 → 原子替换配置 → 清理不再引用的旧凭证”的顺序，失败保留旧配置和旧凭证。仅内核写配置，宿主仅写 vault；旧版与新版不能同时操作同一份数据。新配置不改变当前会话，只有下次连接采用。

已核对本机锁定依赖：Windows `flutter_secure_storage_windows 4.2.2` 的 Dart 实现以 DPAPI 加密 JSON 文件为主，并有旧 C++ 存储兼容分支；不能仅按其 README 推断为 Credential Manager。macOS 当前显式使用普通登录 Keychain（`usesDataProtectionKeychain: false`）。

迁移首先使用合成凭证验证兼容适配：保留现有应用数据路径、键前缀、服务名和 clientId，避免因为改了入口 EXE/Bundle 导致“读不到配置”。Windows 优先兼容现有 DPAPI 格式；macOS 验证宿主身份和现有 Keychain 条目的访问要求。读取失败不得删除旧存储或降级到明文。

若实际平台无法直接兼容，允许首启由旧 UI 存储适配器读取本 Flutter 客户端的数据，通过继承管道交给新宿主，校验成功后才记录迁移状态；该路径需独立测试、保留可恢复的旧数据。不得读取原 Java/Tauri 客户端的凭证。Keychain 如需系统授权应让用户看到原生提示，禁止绕过访问控制。

## 平台构建与安装

建议保持 Flutter 工程在根目录，新增职责清晰的小目录：

```text
packages/proxy_core/       # 提取现有纯 Dart 协议和网络，不引入 Flutter
packages/desktop_ipc/      # Dart 消息契约、帧编解码与行为测试
services/proxy_worker/     # AOT 入口、配置服务、引擎和宿主 vault 客户端
native/host_windows/      # 托盘、监督、管道、系统存储
native/host_macos/        # 对应 Swift 宿主
lib/                     # 原有 Flutter 页面和新的 IPC 状态适配
```

Windows 快捷方式指向宿主，界面 EXE 是宿主启动的子程序。保留透明 ICO；宿主用进程句柄/Job Object 管理自己的子进程，不能按进程名批量结束应用。先验证旧实例退出，再接管配置和单实例锁。发布物须包含一致版本的宿主、worker、UI、Flutter 动态库和证书资源。

macOS 以一个 `.app` 封装原生主入口、Dart helper 和 Flutter UI helper；保留用户看到的应用名和图标。主宿主保持 App Sandbox，helper 使用相应的继承配置，逐项验证启动、文件导入、Dock、菜单栏与退出。Apple 说明子进程仅继承静态沙盒权限，文件选择器临时授权不会自动继承，因此 UI 读入选定文件后通过有界 IPC 交付内容，而不只传路径。[Apple 沙盒继承说明](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html)

macOS 普通 Keychain、helper 沙盒、签名和 UI 激活需要在真实 macOS 上验证；Windows 验证不能替代。架构不要求新增付费签名服务、App Group 或 Keychain Sharing 权限。若平台试验表明必须改变此边界，先回到架构评审。

## 性能验收建议

| 指标 | 拟定门槛 | 条件 |
| --- | --- | --- |
| 后台内存 | 所有应用进程私有工作集合计，中位数 ≤30 MiB、P95 ≤35 MiB；较同场景旧版中位数下降 ≥50% | Windows Release、相同机器与连接场景；此值尚未实测 |
| 真正释放 UI | 关闭处理完成后 3 秒内 UI 进程退出，后台进程不加载 Flutter 引擎 | 未保存确认/文件保存尚未结束时不开始计时 |
| 前后台切换 | 连续 50 次打开/收起，内核 PID 不变，已建立的测试 TCP/UDP 流不中断或错序 | 无故障注入；验证有效载荷与序号 |
| 恢复界面 | 磁盘缓存热时点击到正确状态可交互，P95 ≤2 秒 | 冷启动另行记录；完整日志不阻塞首屏 |
| 稳定性 | 8 小时可控空闲连接测试；预热后首尾各 30 分钟内存中位数差 ≤5 MiB | 配置、转发数、日志上限一致；同时检查线程/句柄持续增长 |
| 完整退出 | 收到退出命令后 5 秒内无本应用后台子进程 | 不包含正在等待用户处理的未保存确认 |

每个场景预热 5 分钟，随后每秒采样至少 30 分钟；至少覆盖未连接、已连接无流量、固定 TCP/UDP 流量三组。30/35 MiB 门槛用于前两组；负载场景报告吞吐、活跃隧道数、峰值和队列回收情况，不把空闲预算硬套到大并发。

同时记录总工作集、私有提交量、CPU、线程、句柄、进程树和加载模块。不得使用工作集裁剪、定时强制 GC、只统计某个子进程来制造下降。macOS 单独记录相应内存口径和原始工具数据，不直接把不同操作系统的数值混比。

先做最小可运行原型测量；若完整宿主 + 内核不能达到显著下降，先报告分项结果、调整方案或目标，不能完成大规模改造后才发现收益不足。
