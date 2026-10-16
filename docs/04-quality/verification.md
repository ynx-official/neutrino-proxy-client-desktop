# 验证记录

状态：Draft  
最后更新：2026-10-16  
关联文档：[计划](../00-project/desktop-plan.md)、[协议](../03-architecture/protocol-and-architecture.md)

## 当前环境

Windows，本机存在 Visual Studio Build Tools 2022 C++ 工具链。Flutter 3.47.5 / Dart 3.13.4 位于项目 `.tools/flutter/`。

## 已有验证证据

- 初版完整测试 23 项通过，Windows Release 构建成功，实际主窗口已打开检查。用户随后反馈主连接成功，但偶发 TCP 转发警告；该警告本次按用户要求暂不处理。
- 证书本机保存与连续保存凭证的两项新增回归测试先失败后通过；对应存储与控制器测试共 3 项通过。尚不能将这些分次运行写成一次完整 25 项测试结果。
- 2026-10-16 图标更新：`flutter analyze --no-pub` 通过，无问题。透明 PNG 与原 App 逐字节一致，转换后的 ICO 包含七个尺寸且每层保留透明度；浅色/深色文件预览见[图标说明](../02-design/icon-assets.md)。
- 图标更新后 `flutter test --no-pub test/ui_test.dart --reporter expanded` 通过（1 项）。`flutter build windows --release --no-pub --config-only` 及独立输出目录的 CMake Release / INSTALL 构建成功，产物位于 `build/icon-refresh/runner/Release/`，包含新透明 PNG/ICO；该输出避免覆盖用户正在使用的 EXE/DLL。
- 现有 `build/windows/x64/runner/Release/` 仅替换托盘 ICO 文件，源文件、原运行目录和新构建目录三者校验一致。当前进程未停止；退出重开原程序也会加载新托盘图标。macOS 资源目录各 PNG 的像素尺寸与 Contents.json 核对通过。

## 验证边界

2026-10-16 仓库发布准备：完整执行 `flutter analyze --no-pub` 无问题、25 项 `flutter test --no-pub --reporter expanded` 全部通过、25 个 Dart 文件格式检查通过、6 项 Python 发布脚本测试通过、actionlint 1.7.12 和 Bash 脚本语法检查通过。发布脚本测试覆盖 tag 校验、Windows 运行文件完整性、缺包、混入其他提交产物和哈希篡改。

同轮在 `.tools/release-verification/` 独立源码副本中锁定依赖，执行 Windows Release 构建（`--build-name 0.1.0 --build-number 1`）成功，并打包验证 ZIP。本机缺少 Developer Mode 符号链接支持，使用已有 `prepare-windows-links.ps1` 创建项目内目录联接后完成构建；补齐 x64 Visual C++ 运行库。未停止或覆盖正在运行的客户端。本轮尚未创建 tag 或公开 Release；GitHub macOS 构建结果另行记录。

Java 源码静态核对及本地模拟对端测试不等同于完整真实服务端兼容验收。用户反馈的连接成功单独记录，不作为自动化验收结果。macOS 构建、原生图标显示和长期资源测试未执行。为保留用户当前连接，本次不重启正在运行的客户端；透明图标文件预览不冒充系统托盘截图。

## 后台内存基线

2026-10-16 后续内存检查记录，独立于上述图标更新时的运行情况。用户反馈管理界面打开与后台均约 60–70 MB。已有本机采样文件为 `build/memory-hidden.json`，本轮规划读取并整理了该记录，没有重新启动应用或进行新架构测试。

条件：Windows Release，原单进程客户端，窗口已隐藏、空闲未连接。采样时间为 2026-10-16 11:05:04 至 11:05:26（UTC+8），PID 49036；共 5 个样本，约 23 秒。数值统一为 MiB（1024² 字节）。

| 时间 | 私有工作集 | 总工作集 | 私有提交量 | 句柄 | 线程 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 11:05:04 | 63.87 | 122.85 | 161.70 | 742 | 72 |
| 11:05:09 | 63.55 | 122.34 | 161.20 | 740 | 72 |
| 11:05:15 | 64.74 | 123.55 | 161.26 | 735 | 71 |
| 11:05:21 | 64.21 | 123.23 | 159.79 | 731 | 70 |
| 11:05:26 | 63.93 | 122.74 | 159.36 | 731 | 70 |

私有工作集均值 64.06 MiB，中位数 63.93 MiB。进程累计 CPU 时间从 3.156 秒到 3.234 秒。该短样本支持“隐藏后仍保留约 64 MiB 私有工作集”，不能证明长期没有泄漏，也不是已连接或持续转发时的内存上限。

新架构指标见[架构提案](../03-architecture/background-process-design.md#性能验收建议)，全部为待验证目标。最终对照必须重新按相同场景测量两版，并统计所有应用进程；不能把本短样本冒充完整性能验收。
