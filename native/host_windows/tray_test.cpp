// Verify the actual host state updates without adding a system tray item or UI.
#include <windows.h>
#include <shellapi.h>
HICON notifiedIcon = nullptr;
BOOL WINAPI captureTray(DWORD, PNOTIFYICONDATAW icon) {
  notifiedIcon = icon->hIcon;
  return TRUE;
}
#define Shell_NotifyIconW captureTray
#include "main.cpp"
#undef Shell_NotifyIconW
#include <iostream>

void check(bool value, const char* message) {
  if (!value) throw std::runtime_error(message);
}
std::vector<DWORD> pixels(HICON icon, int size = 32) {
  check(icon != nullptr, "missing tray icon");
  BITMAPINFO info{};
  info.bmiHeader = {sizeof(BITMAPINFOHEADER), size, -size, 1, 32, BI_RGB};
  void* bits = nullptr;
  HBITMAP bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  HDC dc = CreateCompatibleDC(nullptr);
  auto previous = SelectObject(dc, bitmap);
  ZeroMemory(bits, size * size * 4);
  bool drawn = DrawIconEx(dc, 0, 0, icon, size, size, 0, nullptr, DI_NORMAL) != FALSE;
  GdiFlush();
  std::vector<DWORD> result(static_cast<DWORD*>(bits), static_cast<DWORD*>(bits) + size * size);
  SelectObject(dc, previous); DeleteDC(dc); DeleteObject(bitmap);
  check(drawn, "cannot render tray icon");
  return result;
}
// Render the production HICONs on light/dark taskbar-like surfaces for visual QA.
void preview(HICON idle, HICON connected, const char* path) {
  const int width = 320, height = 160;
  BITMAPINFO info{};
  info.bmiHeader = {sizeof(BITMAPINFOHEADER), width, -height, 1, 32, BI_RGB};
  void* bits = nullptr;
  HBITMAP bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  HDC dc = CreateCompatibleDC(nullptr);
  auto previous = SelectObject(dc, bitmap);
  auto* data = static_cast<DWORD*>(bits);
  for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x)
    data[y * width + x] = y < 80 ? 0xfff3f4f6 : 0xff292a2d;
  SetBkMode(dc, TRANSPARENT);
  for (int row = 0; row < 4; ++row) {
    SetTextColor(dc, row < 2 ? RGB(24, 29, 38) : RGB(255, 255, 255));
    const auto label = row % 2 ? L"Connected" : L"Offline";
    TextOutW(dc, 10, row * 40 + 12, label, (int)wcslen(label));
    int column = 0;
    for (int size : {16, 20, 24, 32}) {
      DrawIconEx(dc, 104 + column++ * 52, row * 40 + (40 - size) / 2,
                 row % 2 ? connected : idle, size, size, 0, nullptr, DI_NORMAL);
    }
  }
  GdiFlush();
  BITMAPFILEHEADER file{};
  file.bfType = 0x4d42; file.bfOffBits = sizeof(file) + sizeof(BITMAPINFOHEADER);
  file.bfSize = file.bfOffBits + width * height * 4;
  std::ofstream output(path, std::ios::binary);
  output.write(reinterpret_cast<const char*>(&file), sizeof(file));
  output.write(reinterpret_cast<const char*>(&info.bmiHeader), sizeof(BITMAPINFOHEADER));
  output.write(static_cast<const char*>(bits), width * height * 4);
  check(output.good(), "cannot save preview");
  SelectObject(dc, previous); DeleteDC(dc); DeleteObject(bitmap);
}
int main(int argc, char** argv) {
  try {
    Host app;
    auto original = (HICON)LoadImageW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(101), IMAGE_ICON, 32, 32, LR_DEFAULTCOLOR);
    app.icon.hIcon = app.trayIcons.forState("idle");
    check(pixels(app.icon.hIcon)[7 * 32 + 25] == 0xff9297a0, "startup must have a gray dot");
    app.core = std::make_shared<Child>();
    const auto base = pixels(original);
    auto state = [&](const char* phase) {
      app.packet(app.core, {{"kind", "state"}, {"data", {{"engine", {{"state", phase}}}}}});
      check(notifiedIcon == app.icon.hIcon, "icon not sent to system tray");
      return pixels(app.icon.hIcon);
    };
    auto connected = state("connected");
    const auto connectedIcon = app.icon.hIcon;
    check(connected[7 * 32 + 25] == 0xff39bf45, "connected must have a green upper-right dot");
    for (const auto* phase : {"idle", "connecting", "authenticating", "reconnecting", "error", "stopping", "unknown"}) {
      auto disconnected = state(phase);
      check(disconnected[7 * 32 + 25] == 0xff9297a0, "non-connected state must have a gray dot");
      for (int y = 0; y < 32; ++y) for (int x = 0; x < 32; ++x) {
        if ((x < 16 || y >= 16) && disconnected[y * 32 + x] != base[y * 32 + x]) {
          std::cerr << "pixel " << x << ',' << y << ": " << std::hex << base[y * 32 + x] << " -> " << disconnected[y * 32 + x] << std::dec << '\n';
          throw std::runtime_error("base logo or transparency changed outside badge");
        }
      }
    }
    const auto disconnectedIcon = app.icon.hIcon;
    const auto handles = GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS);
    const auto userHandles = GetGuiResources(GetCurrentProcess(), GR_USEROBJECTS);
    for (int i = 0; i < 100; ++i) {
      state("connected"); check(app.icon.hIcon == connectedIcon, "connected icon must be cached");
      state("idle"); check(app.icon.hIcon == disconnectedIcon, "gray icon must be cached");
    }
    check(GetGuiResources(GetCurrentProcess(), GR_GDIOBJECTS) == handles, "state updates leaked GDI objects");
    check(GetGuiResources(GetCurrentProcess(), GR_USEROBJECTS) == userHandles, "state updates leaked icon handles");
    if (argc > 1) preview(disconnectedIcon, connectedIcon, argv[1]);
    state("connected");
    app.quitting = false;
    const auto now = GetTickCount64();
    app.failures = {now, now, now}; // No recovery timer needed in this isolated test.
    app.gone(app.core);
    check(pixels(app.icon.hIcon)[7 * 32 + 25] == 0xff9297a0, "worker exit must clear green dot");
    DestroyIcon(original);
    std::cout << "PASS: startup, connected/other states, unchanged transparent logo, cached icons, GDI handles, worker exit\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
}
