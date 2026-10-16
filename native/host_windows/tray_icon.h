#pragma once
#include <windows.h>
#include <string>
#include <vector>

inline HICON statusIcon(HICON base, bool connected, int size) {
  BITMAPINFO info{};
  info.bmiHeader = {sizeof(BITMAPINFOHEADER), size, -size, 1, 32, BI_RGB};
  void* bits = nullptr;
  HBITMAP bitmap = CreateDIBSection(nullptr, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  HDC dc = CreateCompatibleDC(nullptr);
  if (!bitmap || !dc) {
    if (bitmap) DeleteObject(bitmap);
    if (dc) DeleteDC(dc);
    return nullptr;
  }
  ICONINFO source{};
  bool copied = GetIconInfo(base, &source) != FALSE && source.hbmColor &&
      GetDIBits(dc, source.hbmColor, 0, size, bits, &info, DIB_RGB_COLORS) == size;
  if (source.hbmColor) DeleteObject(source.hbmColor);
  if (source.hbmMask) DeleteObject(source.hbmMask);
  DeleteDC(dc);
  if (!copied) { DeleteObject(bitmap); return nullptr; }

  auto* pixels = static_cast<DWORD*>(bits);
  const DWORD color = connected ? 0xff39bf45 : 0xff9297a0;
  const double cx = size * .78, cy = size * .22;
  const double radius = size * .16, outer = size * .20;
  // Copy the icon's straight-alpha bitmap, not its already blended rendering.
  // Supersample only the badge and cut a transparent separator, with no white rim.
  for (int y = 0; y < size; ++y) for (int x = 0; x < size; ++x) {
    int fill = 0, clear = 0;
    for (int sy = 0; sy < 4; ++sy) for (int sx = 0; sx < 4; ++sx) {
      double dx = x + (sx + .5) / 4 - cx, dy = y + (sy + .5) / 4 - cy;
      double distance = dx * dx + dy * dy;
      fill += distance < radius * radius;
      clear += distance < outer * outer;
    }
    if (!clear) continue;
    DWORD original = pixels[y * size + x];
    DWORD remaining = (original >> 24) * (16 - clear), added = 255 * fill;
    DWORD alpha = remaining + added;
    DWORD result = ((alpha + 8) / 16) << 24;
    for (int shift = 0; shift < 24; shift += 8) {
      DWORD channel = alpha ? (((original >> shift) & 255) * remaining +
                               ((color >> shift) & 255) * added + alpha / 2) / alpha : 0;
      result |= channel << shift;
    }
    pixels[y * size + x] = result;
  }
  const int stride = ((size + 15) / 16) * 2;
  std::vector<BYTE> maskBytes(stride * size, 0);
  for (int y = 0; y < size; ++y) for (int x = 0; x < size; ++x) {
    if (!(pixels[y * size + x] >> 24)) maskBytes[y * stride + x / 8] |= 0x80 >> (x % 8);
  }
  HBITMAP mask = CreateBitmap(size, size, 1, 1, maskBytes.data());
  ICONINFO iconInfo{};
  iconInfo.fIcon = TRUE; iconInfo.hbmColor = bitmap; iconInfo.hbmMask = mask;
  HICON icon = mask ? CreateIconIndirect(&iconInfo) : nullptr;
  if (mask) DeleteObject(mask);
  DeleteObject(bitmap);
  return icon;
}

class TrayIcons {
 public:
  TrayIcons() = default;
  TrayIcons(const TrayIcons&) = delete;
  TrayIcons& operator=(const TrayIcons&) = delete;
  ~TrayIcons() {
    if (connected_) DestroyIcon(connected_);
    if (disconnected_) DestroyIcon(disconnected_);
    if (base_) DestroyIcon(base_);
  }
  HICON forState(const std::string& phase) {
    // Cache two tiny icons for the host lifetime; log/state events allocate none.
    if (!base_) {
      base_ = (HICON)LoadImageW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(101), IMAGE_ICON, 32, 32, LR_DEFAULTCOLOR);
      if (base_) {
        connected_ = statusIcon(base_, true, 32);
        disconnected_ = statusIcon(base_, false, 32);
      }
    }
    HICON icon = phase == "connected" ? connected_ : disconnected_;
    return icon ? icon : base_;
  }
 private:
  HICON base_ = nullptr, connected_ = nullptr, disconnected_ = nullptr;
};
