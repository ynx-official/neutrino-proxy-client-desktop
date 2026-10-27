# Java client 与桌面 App 七项逻辑同步

状态：Review
最后更新：2026-10-26

关联文档：[架构](client-app-architecture.md)、[验收](../04-quality/client-app-acceptance.md)、[开发记录](../06-delivery/client-app-development-status.md)、[导入和运行](../05-operations/client-app-local-development.md)

## 范围与依据

用户于 2026-10-26 明确要求同步本轮审查列出的七项差异。对照基线为本地 `dev` 的 `d2b96da6`；Java client 自桌面 App 初始提交 `3233731e` 以来没有业务源码变化。本次补齐的是最初移植未覆盖的行为，包括 Java 最近业务改动中的写缓冲水位线；不是仅按目录最后提交日期判断同步程度。

本次只修改 `neutrino-proxy-client-app` 及相关文档，没有修改 Java client、服务端或管理后台。同步不包括提交、推送、发布，也不等于桌面迁移全部长期验收已完成。

## 七项对应关系

| 项目 | App 行为 | 主要验证 |
|---|---|---|
| 写缓冲水位线 | 导入 `protocol.water-mark`，支持 B/K/KB/M/MB/G/GB、大小写及小数；默认低 32 KiB、高 64 KiB。TCP 数据隧道和本地目标双向各自排队；超过高水位暂停来源读取，低于低水位后恢复。控制及 UDP 通道使用默认水位，与 Java 配置适用范围一致 | 慢消费者、取消后继续部分写入、完整字节顺序、水位迟滞和溢出校验；64 MiB 慢接收真实 TCP 测试 |
| 数据通道读空闲 | 控制、TCP 和 UDP 隧道各自计时。控制超时关闭；数据隧道仅在自身可写时关闭，不因发送阻塞触发读超时 | 控制仍活跃时 TCP 单独超时；尚未取得 UDP 回包端口也会超时 |
| 写空闲心跳 | `write-idle-time` 以最近成功完成写入计算；持续发数据会推迟心跳，收数据不重置写空闲时间；停止发送后恢复心跳 | TCP 连续发送及恢复心跳；共用计时器的读写隔离 |
| 全空闲和拆包参数 | 支持全部五个长度字段参数及 `all-idle-time-seconds`；全空闲仅关闭控制通道，TCP/UDP 按 Java 行为忽略。非正的旧 idle 值导入为 0，表示禁用 | 禁用其他计时器后全空闲关闭；1/2/3/4/8 字节长度字段、正负调整、前缀剥离、半包/多包、最大帧边界和非法长度 |
| TLS | 与 Java 的无主机名识别策略对齐；保留信任和握手签名校验。内置 JKS 可直接用于 TLS 1.2/1.3 | 名称不一致的可信证书成功；未知根、非直接信任的过期证书和伪造签名拒绝；内置 JKS 实际握手 |
| 并发限制 | 移除 TCP/UDP 共用的 1024 个活动绑定硬上限。Java 的 100 是空闲池容量，不是业务并发上限；App 仍按需建连接并在结束时回收 | 1025 个同时活动的 TCP 数据通道；已有断开取消测试 |
| 旧 clientId | 导入所选 YAML 同目录的 `.NEUTRINO_PROXY_CLIENT_ID`，显式 YAML clientId 优先；缺失、空白、无效 UTF-8、符号链接或超过 4 KiB 时保留 App 当前值 | 优先级、原文件不改写、缺失/空白/超大/无效编码的回退；浏览器保存后保留 ID |

水位统计采用待完成写入的实际缓冲字节；Netty 的消息估算开销不属于跨语言一致的内存数值承诺。高水位允许当前一个完整消息跨越阈值，随后停止读取，缓冲不是严格等于 high 的分配上限。没有复刻 Java 将大于有符号 32 位范围的水位强转溢出的缺陷。

## 配置导入、持久化与协议边界

新增参数沿用原 YAML 键，从导入预览、确认保存到后续连接贯通。App JSON 使用 `waterMark`、`allIdleSeconds`、`maxFrameLength`、`lengthFieldOffset`、`lengthFieldLength`、`lengthAdjustment`、`initialBytesToStrip`。旧 JSON 无这些字段时补默认值，保留原 clientId，schemaVersion 不变。

拆包默认 `(max, offset, width, adjustment, strip)` 为 `(2097152, 0, 4, 0, 0)`，最大帧长包含外层长度字段。配置影响接收解码器；发送仍采用 Java 固定四字节 body length。接收端先按长度字段抽取并剥离，再按 `ProxyMessageDecoder` 读取固定消息头。不是所有数值合法的任意组合都能解释普通协议包，使用自定义组合时对端必须发送对应封装。

长度字段只接受 1/2/3/4/8 字节；最大帧长、偏移及剥离数必须在 Java 整数范围内，字段末端不得超过最大帧长。无效的组合整体保留已存拆包配置，并列明跳过项；合法的其他字段继续导入。原 YAML 和旧 ID 文件不改写，凭证值不出现在预览说明中。

确认导入后重新建立设置表单草稿，避免旧的未保存输入在下次保存时覆盖已导入的隐藏协议字段。取消导入仍保留原草稿。

## TLS 决策与限制

Java `ProxyUtil.createSslHandler` 使用不带 peer host 的 `createSSLEngine()`，没有 endpoint identification。按本次明确授权，App 不验证证书名称，也不发送 SNI；只因名称不同而失败的旧部署可以连接。SSL 失败不会降级为明文。

信任库中完全相同的终端证书直接视为信任锚，行为与 Java 一致；这一路径不另外检查该锚本身的有效期。其他证书必须通过签发链、用途、有效期校验。所有路径都必须证明持有私钥，不能仅凭提供一个受信证书完成握手。

内置公开示例 JKS 为 1024 位 RSA，ring 的默认签名验证下限为 2048 位。仅对信任库中 DER 完全相同、1024–2047 位的 RSA 证书，使用 RustCrypto RSA 验证握手签名：TLS 1.2 支持 PKCS#1/PSS SHA-256/384/512；TLS 1.3 仅允许 PSS。测试以现有公开示例证书完成真实握手，并故意破坏签名验证拒绝路径。没有增加“信任任意证书”开关。

这次覆盖名称策略和仓库内置证书。任意旧 Java 安全提供者允许的算法、外部 PKI 链、撤销策略不在已验证矩阵内；例如小 RSA 中间 CA 链仍受 rustls 的链验证算法限制。TLS 1.0/1.1 不在本实现支持范围。

## 可复现的证据

- `crates/client-core/tests/compatibility.rs`：配置往返、数据通道超时、全空闲、写空闲、1025 并发。
- `crates/client-core/src/channel.rs` 单测：缓冲阈值、部分写入取消安全、读写计时分离。
- `crates/client-core/tests/protocol.rs` 及 `tests/fixtures/java-protocol-vectors.json`：解析边界及 Java 生成的七组向量。
- `tests/fixtures/JavaProtocolVectors.java`：实际调用仓库 Java 编码器、解码器和 Netty EmbeddedChannel；生成日期 2026-10-26，JDK 21，源码基线 `d2b96da6`。将已构建的 core 类和其依赖加入 classpath 后，用 JDK source-file 模式运行；JSON 输出以外的 Netty 日志不属于向量文件。常规 Cargo 测试读取已提交向量，不要求安装 Java。
- `crates/client-core/tests/tls.rs`：真实本地 TLS 对端，所有凭证都是测试值；不连接生产系统。
- `src-tauri/src/config_import.rs` 单测与 `tests/e2e/pages.spec.js`：导入识别、保留、预览和下一次保存。

本机测试与构建结果统一记录在[开发记录](../06-delivery/client-app-development-status.md)。macOS 原生运行、生产服务互通及 72 小时负载未在此次 Windows 验证中执行。
