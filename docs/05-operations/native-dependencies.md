# 原生宿主依赖

状态：Review  
最后更新：2026-10-16  
关联文档：[后台架构](../03-architecture/background-process-design.md)

Windows 宿主使用 nlohmann/json v3.12.0 的单头文件，不增加运行时 DLL。来源：[官方 Release](https://github.com/nlohmann/json/releases/tag/v3.12.0)。

- 源码：`native/third_party/nlohmann/json.hpp`。
- SHA-256：`aaf127c04cb31c406e5b04a63f1ae89369fccde6d8fa7cdda1ed4f32dfc5de63`，下载后已核对。
- MIT 许可证：`native/third_party/nlohmann/LICENSE.MIT`；发行目录包含 `THIRD-PARTY-NOTICES.txt`。
- macOS 宿主仅使用系统 AppKit、Foundation、Security 和 Darwin。

纯 Dart worker 的依赖由 `services/proxy_worker/pubspec.lock` 锁定；Flutter 插件不得加入此包。TLS、证书解析和网络协议继续使用原代码，未增加原生网络库。
