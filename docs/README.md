# 项目文档索引

状态：Review
最后更新：2026-10-27

关联文档：[仓库说明](../README.md)、[协作约定](../AGENTS.md)

本仓库为独立的 Rust / Tauri / Vue 桌面客户端，源码和构建配置位于根目录。文档覆盖需求、设计、架构、验证及独立发布；各项运行结果以记录注明的执行日期与验证范围为准。

## 当前入口

- [项目拆分与验证](06-delivery/project-extraction.md)：目录、命名、工作流分离及本轮验证边界。
- [本地开发与运行](05-operations/client-app-local-development.md)：启动、测试、应用设置与构建。
- [独立构建与发布](06-delivery/releasing.md)：Windows 安装包 / 便携包、两个 macOS 架构、版本、产物完整性及发布保护。
- [界面与交互](02-design/client-app-ui.md)：简约布局、原生托盘及应用设置；[样图生成记录](02-design/client-app-mockup-prompts.md)。
- [架构与配置迁移](03-architecture/client-app-architecture.md)：网络内核、IPC、凭证存储及进程启动。
- [Java 七项逻辑同步](03-architecture/client-app-java-compatibility.md)：水位线、空闲、拆包、TLS、并发及旧 ID 迁移。
- [验收方案](04-quality/client-app-acceptance.md)：功能、协议、生命周期和平台验收；[开发验证记录](06-delivery/client-app-development-status.md)。

## 原始方案与历史

- [总体方案](00-project/client-app-proposal.md)、[分阶段计划](06-delivery/client-app-implementation-plan.md)：保留设计目标，未完成的长期与平台验收不能视为已通过。
- [初始样式](99-archive/client-app-ui-initial.md)、[色块方案](99-archive/client-app-ui-color-variant.md)：被当前简约设计替代的视觉依据。
