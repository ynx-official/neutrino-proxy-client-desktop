# 协议与架构

状态：Review  
最后更新：2026-10-16  
关联文档：[计划](../00-project/desktop-plan.md)、[验证](../04-quality/verification.md)

## 权威来源

源仓库 `../neutrino-proxy`：`neutrino-proxy-core/.../ProxyMessageEncoder.java`、`ProxyMessageDecoder.java`、`ProxyMessage.java`、`ExceptionEnum.java`、`IdleCheckHandler.java`；`neutrino-proxy-client/.../handler/`、`core/CmdChannelHandler.java`、`core/RealServerChannelHandler.java`、`util/UdpServerUtil.java`、`core/UdpRealServerHandler.java`、`util/ProxyUtil.java` 和 `src/main/resources/app.yml`。Rust 版本不是兼容依据。

## 字节协议

全部整数大端：4 字节 body length（不含自身）、1 字节 type、8 字节 signed serial、4 字节 info 字节长度、UTF-8 info、剩余 data。Java 构建器未设置 serial 时为 0。最大完整帧默认 2097152 字节，检查长度后才分配内存。结构合法未知 type 按原 dispatcher 忽略；结构损坏终止对应通道。

类型：1 心跳，2 认证，3 TCP 连接，4 断开，5 TCP 转发，6 错误，8 UDP 连接，9 UDP 断开，16 UDP 转发。

认证 info=`license,clientId`。认证 code=0 成功；code=1 在 unlimited=false 时停止重试；code=2/3 关闭本次连接但按间隔重试。ERROR code=1 在 Java 中退出进程，桌面版本停止会话并保留 UI。不要把服务器原始认证 JSON 写入日志，它可能包含 License。

TCP 控制帧 info=visitorId，data=UTF-8 `host:port`。先连接目标，再创建数据隧道，以 type=3、info=`visitorId@license` 绑定。转发 type=5、info=visitorId。目标错误只结束对应数据连接，连接失败以 type=4 通知控制通道。

UDP 控制 type=8，info 为 UdpBaseInfo。新隧道发送 type=8，info 包含 visitorId/serverPort/targetIp/targetPort，data 为 License。type=16 投递 datagram，保留 visitorIp/visitorPort 等回程元数据。端口范围含两端，最小端口保留给单向投递。responses=0 或 timeout<=0 单向；responses<0 不限制响应次数；每次发送重置计数，收发均更新活跃时间。端口耗尽按 Java 降级为单向并记录警告。到期/响应上限释放隧道和端口；扫描全部会话，不能复制旧扫描器只检查首项的缺陷。

## 模块与并发

2026-10-16 已按用户批准的 Flutter + Dart 路线拆分进程，生命周期、IPC、凭证和构建边界以[后台独立进程架构](background-process-design.md)为准。本文继续作为网络协议权威说明。

`lib/core/` 不依赖 Flutter。独立 Dart AOT worker 持有唯一 engine；UI 通过宿主的私有管道发送命令，接收状态和脱敏日志。每代连接拥有取消标记、socket 集合和定时器，迟到的 DNS/握手结果必须关闭，不得恢复被取消的连接。TCP 写入等待 flush 并暂停上游读取，防止无限缓存；日志最多 500 条，每条有长度限制。

`lib/background/` 管理进程协议、命令串行化与后台服务；`lib/application/` 保留配置事务和 Riverpod 投影；`lib/ui/` 处理表单和显示；`lib/platform/` 管理窗口。托盘及系统凭证移至 `native/` 宿主。普通配置和凭证独立保存，配置写入失败不能删除仍被引用的凭证。客户端身份首次生成后保持不变。

## TLS 和导入

Dart `SecureSocket` + `SecurityContext`。从官方 Java 资源复制内置公开 JKS，仅提取信任证书；自定义 JKS 校验完整性与口令，支持 PEM/DER 证书。JKS 解析不执行私钥解密，不启动 Java。对过期、未知根和名称不匹配拒绝连接，不提供接受任意证书的兜底。

JSON 和 YAML 导入先生成预览再由用户应用，大小限制 1 MiB；证书限制 4 MiB。占位符仅使用当前环境和显式默认值。非默认 Netty 帧布局阻止导入；线程池参数记录不等价说明。原文件不变，敏感值不进入预览摘要、日志或普通 JSON。
