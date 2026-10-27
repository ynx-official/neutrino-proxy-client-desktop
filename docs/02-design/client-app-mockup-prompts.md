# 桌面客户端样图生成记录

状态：Review
最后更新：2026-10-27
关联文档：[界面设计](client-app-ui.md)、[文档索引](../README.md)

## 2026-10-27 应用设置预览确认

用户确认上一轮使用内置 `image_gen`、参照现有设置页截图生成的[应用设置预览](assets/client-app-application-settings-approved.png)，并要求按图实现。设计意图摘要：保留 Neutrino 品牌、顶部三项导航与白色画布；设置下新增“连接配置 / 应用设置”页签；应用设置用两行启动开关、简短说明和细分隔线，底部提示自动保存。此处是设计意图摘要，不将其冒充完整原始提示词。

预览不包含原截图中的真实连接地址或凭证。图片中的开关状态仅用于展示；本轮实现默认关闭，当前 Vue 截图、交互及运行边界见[界面设计](client-app-ui.md#设置与日志)和[开发记录](../06-delivery/client-app-development-status.md)。

## 已确认的简约预览

用户于 2026-10-15 要求生图查看简约风格，并明确回复“就改成这种风格”。[批准样图](assets/client-app-minimal-approved.png)由内置 image_gen 生成；原始文件为 `exec-40705a22-80e7-4c54-b9e0-0a33c47d1ef3.png`，已复制到本项目。该图是设计预览，数据虚构；当前 UI 以[界面设计](client-app-ui.md)及实现为准。

生成要求：单一白色画布、顶部导航、细线分隔、无侧栏与色块卡片；连接状态、示例地址、断开、时长、SSL、License 与最近事件构成单列界面，不添加性能指标或教学文字。以下早期提示词与样图保留为历史记录。

## 已确认的精简原生托盘预览（2026-10-16）

用户在查看新预览后回复“那就改成这样吧”，随后再次明确“托盘必须要用原生的实现方式”。[批准预览](assets/client-app-native-tray-approved.png)由内置 image_gen 生成，原始输出名为 `exec-b3b930cb-2744-4da3-ba79-3bdaf7e3ed8b.png`；本轮仅保存已确认图片，没有重新生图。

生成要求摘要：并排展示已连接、未连接两个状态；白色简约菜单；无重复应用名或“状态：”前缀；小状态图标和状态名称、虚构服务器端点、打开主窗口、查看日志、互斥的连接操作、退出应用；仅两个分隔线。实际实现使用 Tauri Rust 原生菜单与内嵌小图标，系统决定字体、行高、主题及弹出行为，不将图片尺寸当成原生布局约束。

已检查 PNG 的中文标签、两种互斥动作、图标和分隔线，未包含真实连接或凭证。图片是设计参考，不能作为实际系统菜单截图、点击验证或性能测量证据；执行记录见[开发进展](../06-delivery/client-app-development-status.md)。

## 早期样图来源与用途

用户选择的 Style ID 为 `airtable`，来源为本地 `awesome-design-md` / `VoltAgent/awesome-design-md`。使用内置 `image_gen` 工具生成，不使用 CLI 或外部 API 调用脚本。以下为本次实际使用的提示词；页面是设计概念图，数据全部虚构。

- [已连接主页](assets/client-app-connected.png)：按提示词 1 生成，再按提示词 2 修订中文标题与窗口图标。
- [首次连接配置](assets/client-app-connection-setup.png)：按提示词 3 生成。

最终 PNG 已复制到本项目 `docs/02-design/assets/`；原生成文件保留，未覆盖既有资源。图中没有真实 License、生产连接地址或实测性能数值。两张图用于评审布局和功能层级，不证明桌面功能已实现。

## 提示词 1：已连接主页初稿

```text
Use case: ui-mockup.
Create a high-fidelity, practical desktop application UI mockup for "Neutrino Proxy", a Windows and macOS local tunnel connection utility. One flat, straight-on application window, landscape approximately 1560 x 1080, very sharp readable Simplified Chinese text. This is a product design review image, not a photograph, poster or marketing landing page. Fill the frame with the full app window and a tiny neutral outer margin. No device mockup or perspective.
Approved visual reference is the local Airtable design system adapted for a small utility: white #ffffff main canvas; very light #f8fafc sidebar; dark ink #181d26 titles; #333840 body; #41454d secondary text; thin #dddddd separators; #1b61c9 text links; success #006400; small cream #f5e9d4 information band. Ordinary system sans-serif Chinese typography, regular/medium weight, modest 6px input, 10px callout and 12px button corners. Crisp grid, open whitespace, restrained outlines and no heavy shadows. No gradients, purple, black dashboard, nested cards, or Airtable wordmark/logo.
Window chrome: thin Windows-style titlebar with exact title "Neutrino Proxy" at left and standard minimize, maximize, close controls only at right. Left sidebar about 17% width. Small product label "Neutrino Proxy" near top; three simple line-icon navigation items "连接", "日志", "设置"; "连接" is selected with a pale neutral rectangular highlight. Sidebar bottom shows a green dot and "已连接"; below it "设计预览".
Main pane has about 40px padding. Top row title "连接" at left and understated outlined button "编辑连接" at right.
Below, a clean open status area with small green outlined check icon, large text "已连接", subtext "服务器认证通过，连接正在运行". At right of this area put a white outline button labeled "断开连接". Under the status use a thin horizontal separator, not a card.
Next heading "连接信息". Under it show a tidy two-column definition grid with small labels above dark values, two rows: "服务器" / "edge.example.com"; "端口" / "9002"; "SSL" / "已启用"; "License" / "•••• •••• •••• 8F2A". Add a small separate line "本次连接  02:18:36". All values are fictitious illustrative data. Do not show bandwidth, latency, memory, charts or maps.
Next heading "最近事件" aligned with a blue text link "查看全部日志". Three rows with fine separators, left aligned time and middle concise exact Chinese message: "10:24:08" and "连接已建立"; "10:24:09" and "License 验证通过"; "10:24:09" and "开始后台运行". Use small green checks, not large colorful icon tiles.
Near the bottom use ONE full-width shallow cream information band with a simple information icon and exact text "关闭窗口后仍会保持连接，可从托盘重新打开". Keep readable ink text.
Very bottom right small annotation "概念样图 · 示例数据". Must not imply this is an actual running app screenshot.
All required text must be accurate, legible, unclipped and spaced cleanly. No extra menus, tabs, accounts, profile collections, port mapping controls, charts, performance claims or decorative illustration. Exactly one app window.
```

## 提示词 2：主页文字与窗口图标修订

以提示词 1 生成的初稿为编辑目标，保持原布局。

```text
Use case: text-localization / precise UI correction.
Edit the provided Neutrino Proxy desktop mockup. Keep the entire composition, window size, sidebar, status, fields, buttons, colors, typography, and all other text unchanged.
Correct the section heading directly below the first horizontal divider and above the server details. It must read EXACTLY "连接信息" in Simplified Chinese. The first character must be 连 (Unicode U+8FDE), not 適, 通, 遮, 遖 or any invented glyph. The four characters are 连 接 信 息. Render clean standard sans-serif glyphs at the existing heading size.
Remove the tiny headphone-shaped icon at the far left of the title bar so that the title bar begins with plain text "Neutrino Proxy", consistent with the other configuration screen. Preserve the existing title bar controls at the right.
Do not change any other text or UI element. Keep "概念样图 · 示例数据" visible in the bottom right. No new elements. This remains a flat high-fidelity UI mockup with opaque background.
```

## 提示词 3：首次连接配置

```text
Use case: ui-mockup.
Create a high-fidelity desktop application UI mockup for "Neutrino Proxy", a Windows and macOS local tunnel connection utility. Show the first connection configuration form with fictitious entered values, ready to save. One flat straight-on full desktop app window, landscape approximately 1560 x 1080, very sharp readable Simplified Chinese text, tiny neutral outer margin. No device, photograph, marketing page or perspective.
Use the approved local Airtable design system adapted for a small utility: white #ffffff main canvas; light #f8fafc sidebar; ink #181d26 heading and primary action; body #333840 and secondary #41454d; hairline #dddddd borders; #1b61c9 links; cream #f5e9d4 supporting note. Ordinary system sans-serif Chinese type, regular/medium weight. Inputs 6px corners, callout 10px, primary button 12px. Dense enough to fit the form but with generous clear spacing. No gradients, purple, heavy shadows, nested cards or Airtable branding.
Shell must be consistent with a companion connected-screen mockup: thin Windows-style titlebar exact "Neutrino Proxy" at left, minimize/maximize/close only at right. Sidebar 17% width with simple product label "Neutrino Proxy" and line-icon items "连接", "日志", "设置". Select "设置" with a pale neutral highlight. Sidebar bottom gray dot "未连接", then "设计预览".
Main pane title "配置连接" and short subtext "填写连接信息，或导入已有 app.yml". Top right outlined action "导入配置".
Below create a compact form, no wrapping all content in a big card:
First row two labeled inputs: "服务器地址" with entered "edge.example.com" taking about 70% of width, and "端口" with "9002" taking 30%.
Second row full width password-style field label "License", field contents "•••• •••• •••• 8F2A", eye icon right.
Next row a toggle ON in dark ink color, label "启用 SSL", helper text "需与服务器的 SSL 隧道端口一致".
Next label "信任证书". One select box with selected text "内置证书", downward chevron, and adjacent outlined button "选择文件". Below a compact explanatory line "使用自定义 JKS 时，将提示输入证书库密码". The password field is conditional and therefore not present in this built-in-certificate state.
Next a thin divider and collapsed disclosure row with right-pointing chevron "高级设置", below a short muted line "客户端 ID、重连间隔、心跳与 UDP 端口". Do not expose advanced implementation fields individually.
Use one shallow cream information band "配置保存在本机，端口映射仍在管理后台设置".
Bottom action row, aligned to the right: white outline button "保存" and ONE dark ink #181d26 filled button with white label "保存并连接". Buttons readable and aligned. No automatic-start checkboxes on this form.
Very bottom right small annotation "概念样图 · 示例数据".
All text exact, legible and unclipped. No actual credentials, no charts, memory or speed claims, no profile switching, no server-side controls, no extra primary actions. Exactly one app window.
```

## 目视检查与边界

- 已连接主页：检查连接状态、服务器、端口、SSL、掩码 License、断开操作和最近事件；修正初稿的“连接信息”字形，移除不一致的标题栏图标。
- 配置页：检查基础字段、SSL 开关、证书入口、高级折叠区及“保存 / 保存并连接”；内置证书状态下不显示证书库密码字段。
- 两张图：中文主要标签可读，无明显重叠或截断；白底、深色主操作、奶油色说明区和简洁导航保持一致；均明确标记“概念样图 · 示例数据”。
- 当前目视检查针对静态 PNG，不涵盖实际窗口缩放、键盘焦点、屏幕阅读器或可运行 UI 的交互验证。


## 托盘菜单预览（Draft，2026-10-15）

使用内置 image_gen 生成，[预览图](assets/client-app-tray-preview.png)已保存到项目。图片展示两个状态的互斥操作，尚未实现或获得样式确认；图片中的域名、系统时钟为虚构示例。

```text
Use case: ui-mockup.
Create a high resolution, refined design preview of an improved SYSTEM TRAY MENU for the desktop utility "Neutrino Proxy". This is a small practical app menu, NOT an application dashboard or marketing composition. One landscape image, approximately 1536x1024, showing TWO compact system tray menu flyouts side by side at equal scale: connected state on the left, disconnected state on the right. Each flyout is approximately 260 × 300 logical pixels; show them large enough that all simplified Chinese labels are sharp and perfectly readable. Tiny quiet captions outside each menu: left "已连接", right "未连接". Fill the image with these useful close-up views rather than a huge blank background.

Visual style matches the user's approved minimalist desktop app: white surfaces, very subtle neutral gray background, dark ink #181d26 typography, thin light-gray dividers, precise 16px padding, restrained 6–8px corners, a very light system popup shadow, crisp Segoe UI / Microsoft YaHei UI / PingFang SC type. No cream or beige, no dark green blocks, no gradients, no illustrations, no colored cards, no explanatory paragraphs, no oversized toggles or power controls, no decorative orbit diagrams. System-menu proportions and behavior: compact rows, 18px monochrome line icons, about 36px row height. Do not make this look like a browser dropdown inside an app window. This is a polished native-looking tray popup anchored just above a thin understated Windows system-tray/taskbar strip at bottom of each view. The tray strip can contain a small original N icon and a subtle chevron, network, speaker and clock; avoid unrelated application icons.

Both menus have:
- A small original minimalist N monogram and "Neutrino Proxy" in a modest header.
- A compact read-only connection status line beneath the header; a fictional endpoint "edge.example.com:9002" in smaller secondary type.
- A fine divider beneath this status section.
- Clickable menu row "打开主窗口" with a small window outline icon.
- Clickable menu row "查看日志" with a small document outline icon.
- A fine divider before the connection action.
- The single context-appropriate connection action.
- A fine divider.
- Bottom row "退出应用" with a small exit outline icon, normal dark text, no bright red fill.

LEFT MENU, CONNECTED:
Tiny muted green dot with exact status text "已连接" in the read-only status line.
The connection action must be exactly "断开连接" with a small power icon.
CRITICAL: DO NOT include a separate action labeled "连接" anywhere in the LEFT menu. The app is already connected, so showing a connect command is incorrect.
The N tray icon has a tiny green corner status dot.

RIGHT MENU, DISCONNECTED:
Tiny neutral gray dot with exact status text "未连接" in the read-only status line.
The connection action must be exactly "连接" with a small link icon.
CRITICAL: DO NOT include "断开连接" in the RIGHT menu.
The N tray icon has a tiny gray corner status dot.

The two states should have identical structure, dimensions and alignment, changing only the status indicator, status wording and connection action. Only the listed exact texts, icons and fictional endpoint. Do not include License or passwords, timing statistics, memory/traffic/speed metrics, settings panels, badges, tips, tooltips, sample watermarks or long instructions. Make it beautifully simple and focused on knowing the current state and choosing a valid action.
```


2026-10-15 后续确认：用户明确回复“托盘就按照这个改”，该托盘预览曾成为浮层实现基线。2026-10-16 已改为系统原生菜单，并由本页上方的精简预览替代。实现与测试边界见[界面设计](client-app-ui.md)及[验证记录](../06-delivery/client-app-development-status.md)；生图本身仍为设计参考。


## 2026-10-15 项目 Logo 桌面图标适配

模式：内置 `image_gen`，编辑本地图片；未使用 API / CLI 生图。输入编辑目标为仓库原始 `assets/logo/logo.png`，生成后保留原图，复制输出到 `src-tauri/icons/app-icon.png`。母版实际为 1254 × 1254 RGBA，平台格式由 Tauri CLI 等比导出；窗口与托盘的小图直接使用原 PNG，避免生成误差。用户授权原 Logo 的桌面加工，尚未单独确认这张生成稿。

完整提示词：

> Edit the attached original Neutrino Proxy project logo into ONE production-ready desktop application icon, for a Windows .ico and macOS .icns. The attached PNG is the edit target and exact brand artwork: two blue outward-opening wing/panel shapes framing a central orange lowercase i/person-shaped motif. Preserve the original logo silhouette, topology, proportions, orange and blue colors exactly; no replacement symbol, no N monogram, no text. Center this original mark at approximately 70% of a 1024 by 1024 square canvas, on a clean white / very pale cool-white rounded-square application tile with restrained corner curvature, a barely perceptible edge and a soft extremely subtle shadow. Original mark remains flat solid color with crisp vector-like edges. Comfortable optical padding on all sides and clear readability at small sizes. Straight front view, precisely square, no perspective, no environment, no device, no mockup grid. Transparent pixels outside the single rounded-square tile. No glow, no decorative elements, no badges, no lettering, no gradients on the original logo shapes. Output a single centered isolated icon master, not a presentation or comparison sheet.

目视检查：保留蓝色两翼、橙色主体和中部切口，未添加文字或新符号。生成版带轻微表面明暗，不能把提示词中的“exactly”视为逐像素一致保证；应用内和托盘的原 PNG 副本已核对逐字节一致。已检查导出 PNG / ICO / ICNS 的尺寸和容器；不将生成稿、容器检查或浏览器截图当作 macOS Dock 实测。

[当前图标设计](client-app-ui.md#项目-logo-与桌面图标)及[验证记录](../06-delivery/client-app-development-status.md)。
