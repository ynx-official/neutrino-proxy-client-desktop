# TLS 测试证书

状态：Review

最后更新：2026-10-16

关联文档：[验证记录](verification.md)、[发布说明](../06-delivery/releasing.md)

`test/fixtures/tls/` 仅用于回环地址上的真实 TLS 测试：`ca.pem` 是测试信任根，`server.pem` 是测试 CA 签发的 localhost 服务端证书，`server-key.pem` 是公开的测试私钥。三者都不能用于实际服务部署，Flutter 资产清单不会包含它们。测试 CA 私钥只存在于生成过程的临时目录，完成后删除。

刷新命令：`python scripts/generate-test-certificates.py`。需要 OpenSSL；Windows 会优先从 PATH 查找，再尝试 Git for Windows 的附带版本。该命令只修改上述三个测试文件，不修改应用内置 JKS、用户证书或系统信任库。CI 每次测试前自动刷新，开发者刷新后不必为了重新生成随机测试密钥而提交文件。

测试根使用 RSA 2048/SHA-256；服务端证书有效期 365 天、`CA:FALSE`、`serverAuth` EKU、DNS SAN 为 `localhost`。保留 IP 地址 `127.0.0.1` 的名称不匹配反例，不能通过接受任意证书使测试通过。

原测试使用有效期 10 年、无 serverAuth EKU 的自签名 CA 证书直接充当服务器证书。它在 Windows 上通过，但不满足 [Apple TLS 证书要求](https://support.apple.com/en-us/103769)。[Dart macOS 证书验证实现](https://github.com/dart-lang/sdk/blob/3.13.4/runtime/bin/security_context_macos.cc) 对自定义信任根仍使用系统 TLS 策略，因此测试证书也必须满足该要求。当前变更只调整测试材料和诊断，不改变生产 TLS 验证规则。
