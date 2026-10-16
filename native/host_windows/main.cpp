#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <wincrypt.h>
#include <nlohmann/json.hpp>
#include <atomic>
#include <condition_variable>
#include <deque>
#include <filesystem>
#include <fstream>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include "tray_icon.h"

using Json = nlohmann::json;
namespace fs = std::filesystem;
constexpr UINT kPacket = WM_APP + 1, kGone = WM_APP + 2, kTray = WM_APP + 3;
constexpr UINT kOpen = 100, kLogs = 101, kConnect = 102, kDisconnect = 103, kQuit = 104;
constexpr size_t kMaxFrame = 8 * 1024 * 1024, kMaxQueue = 16 * 1024 * 1024;
const wchar_t* kClass = L"NeutrinoDartHost";
std::wstring wide(const std::string& s) {
  if (s.empty()) return {};
  int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s.data(), (int)s.size(), nullptr, 0);
  if (!n) throw std::runtime_error("Invalid UTF-8");
  std::wstring out(n, 0);
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), out.data(), n);
  return out;
}
std::string utf8(const std::wstring& s) {
  if (s.empty()) return {};
  int n = WideCharToMultiByte(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0, nullptr, nullptr);
  std::string out(n, 0);
  WideCharToMultiByte(CP_UTF8, 0, s.data(), (int)s.size(), out.data(), n, nullptr, nullptr);
  return out;
}
std::wstring quote(const std::wstring& text) {
  std::wstring out = L"\"";
  size_t slashes = 0;
  for (auto c : text) {
    if (c == L'\\') { ++slashes; continue; }
    out.append(slashes * (c == L'"' ? 2 : 1), L'\\');
    slashes = 0;
    if (c == L'"') out += L'\\';
    out += c;
  }
  out.append(slashes * 2, L'\\');
  return out + L'"';
}
bool readAll(HANDLE h, void* data, DWORD size) {
  auto* p = static_cast<char*>(data);
  while (size) { DWORD n = 0; if (!ReadFile(h, p, size, &n, nullptr) || !n) return false; p += n; size -= n; }
  return true;
}
bool writeAll(HANDLE h, const void* data, DWORD size) {
  auto* p = static_cast<const char*>(data);
  while (size) { DWORD n = 0; if (!WriteFile(h, p, size, &n, nullptr) || !n) return false; p += n; size -= n; }
  return true;
}
struct Child;
struct Packet { std::shared_ptr<Child> child; Json data; size_t bytes; };
std::atomic<size_t> postedBytes{0};
struct Child : std::enable_shared_from_this<Child> {
  HANDLE process = nullptr, input = nullptr, output = nullptr;
  DWORD pid = 0;
  std::thread reader, writer;
  std::mutex mutex;
  std::condition_variable ready;
  std::deque<std::string> queue;
  size_t queued = 0;
  bool closed = false;
  std::string session;
  bool send(const Json& message) {
    auto text = message.dump();
    std::lock_guard<std::mutex> guard(mutex);
    if (closed || text.size() > kMaxFrame || queued + text.size() > kMaxQueue) return false;
    queued += text.size(); queue.push_back(std::move(text)); ready.notify_one(); return true;
  }
  void start(HWND window) {
    auto self = shared_from_this();
    writer = std::thread([self] {
      for (;;) {
        std::string text;
        { std::unique_lock<std::mutex> guard(self->mutex);
          self->ready.wait(guard, [&] { return self->closed || !self->queue.empty(); });
          if (self->closed) break;
          text = std::move(self->queue.front()); self->queue.pop_front();
        }
        uint32_t size = (uint32_t)text.size();
        unsigned char head[4] = {(unsigned char)(size >> 24), (unsigned char)(size >> 16), (unsigned char)(size >> 8), (unsigned char)size};
        bool ok = writeAll(self->input, head, 4) && writeAll(self->input, text.data(), size);
        { std::lock_guard<std::mutex> guard(self->mutex); self->queued -= text.size(); }
        if (!ok) break;
      }
    });
    reader = std::thread([self, window] {
      try {
        for (;;) {
          unsigned char head[4];
          if (!readAll(self->output, head, 4)) break;
          uint32_t size = (uint32_t(head[0]) << 24) | (uint32_t(head[1]) << 16) | (uint32_t(head[2]) << 8) | head[3];
          if (!size || size > kMaxFrame) break;
          std::string text(size, '\0');
          if (!readAll(self->output, text.data(), size)) break;
          Json data = Json::parse(text);
          if (!data.is_object()) break;
          if (postedBytes.fetch_add(size) + size > kMaxQueue) { postedBytes -= size; break; }
          auto packet = new Packet{self, std::move(data), size};
          if (!PostMessageW(window, kPacket, 0, (LPARAM)packet)) { postedBytes -= size; delete packet; break; }
        }
      } catch (...) {}
      auto packet = new Packet{self, Json(), 0};
      if (!PostMessageW(window, kGone, 0, (LPARAM)packet)) delete packet;
    });
  }
  void stop() {
    { std::lock_guard<std::mutex> guard(mutex); closed = true; ready.notify_all(); }
    if (process && WaitForSingleObject(process, 0) == WAIT_TIMEOUT) TerminateProcess(process, 0);
    if (writer.joinable()) writer.join();
    if (reader.joinable()) reader.join();
    if (input) { CloseHandle(input); input = nullptr; }
    if (output) { CloseHandle(output); output = nullptr; }
    if (process) { CloseHandle(process); process = nullptr; }
  }
  ~Child() { stop(); }
};

std::shared_ptr<Child> launch(HWND window, HANDLE job, const fs::path& executable,
                             const std::vector<std::wstring>& args) {
  SECURITY_ATTRIBUTES sa{sizeof(sa), nullptr, TRUE};
  HANDLE childIn = nullptr, childOut = nullptr;
  auto child = std::make_shared<Child>();
  if (!CreatePipe(&childIn, &child->input, &sa, 0) || !CreatePipe(&child->output, &childOut, &sa, 0))
    throw std::runtime_error("Pipe creation failed");
  SetHandleInformation(child->input, HANDLE_FLAG_INHERIT, 0);
  SetHandleInformation(child->output, HANDLE_FLAG_INHERIT, 0);
  HANDLE errors = CreateFileW(L"NUL", GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, nullptr);
  STARTUPINFOEXW si{}; si.StartupInfo.cb = sizeof(si);
  si.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  si.StartupInfo.hStdInput = childIn; si.StartupInfo.hStdOutput = childOut; si.StartupInfo.hStdError = errors;
  SIZE_T bytes = 0;
  InitializeProcThreadAttributeList(nullptr, 1, 0, &bytes);
  std::vector<unsigned char> attributes(bytes);
  si.lpAttributeList = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(attributes.data());
  HANDLE inherited[] = {childIn, childOut, errors};
  bool initialized = InitializeProcThreadAttributeList(si.lpAttributeList, 1, 0, &bytes) != FALSE;
  bool listed = initialized && UpdateProcThreadAttribute(si.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                         inherited, sizeof(inherited), nullptr, nullptr);
  std::wstring command = quote(executable.wstring());
  for (const auto& arg : args) command += L" " + quote(arg);
  PROCESS_INFORMATION pi{};
  bool ok = listed && CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr, TRUE,
      EXTENDED_STARTUPINFO_PRESENT | DETACHED_PROCESS | CREATE_SUSPENDED, nullptr, executable.parent_path().c_str(), &si.StartupInfo, &pi);
  if (initialized) DeleteProcThreadAttributeList(si.lpAttributeList);
  CloseHandle(childIn); CloseHandle(childOut); CloseHandle(errors);
  if (!ok) throw std::runtime_error("Process creation failed");
  child->process = pi.hProcess; child->pid = pi.dwProcessId;
  if (!AssignProcessToJobObject(job, pi.hProcess)) {
    TerminateProcess(pi.hProcess, 1); CloseHandle(pi.hThread); throw std::runtime_error("Job assignment failed");
  }
  ResumeThread(pi.hThread); CloseHandle(pi.hThread);
  child->start(window); return child;
}

class Vault {
 public:
  explicit Vault(fs::path path) : path_(std::move(path)) {}
  Json call(const Json& m) {
    std::string key = m.at("key").get<std::string>();
    if (key.rfind("neutrino.flutter.", 0) != 0 || key.size() > 160) throw std::runtime_error("Invalid vault key");
    Json values = Json::object();
    if (fs::exists(path_)) {
      if (fs::file_size(path_) > kMaxFrame) throw std::runtime_error("Vault too large");
      std::ifstream file(path_, std::ios::binary);
      std::vector<unsigned char> encrypted((std::istreambuf_iterator<char>(file)), {});
      DATA_BLOB input{(DWORD)encrypted.size(), encrypted.data()}, plain{};
      if (!CryptUnprotectData(&input, nullptr, nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &plain))
        throw std::runtime_error("Vault decryption failed");
      try { values = Json::parse(plain.pbData, plain.pbData + plain.cbData); }
      catch (...) { SecureZeroMemory(plain.pbData, plain.cbData); LocalFree(plain.pbData); throw; }
      SecureZeroMemory(plain.pbData, plain.cbData); LocalFree(plain.pbData);
      if (!values.is_object()) throw std::runtime_error("Invalid vault");
    }
    auto op = m.at("op").get<std::string>();
    if (op == "read") return values.contains(key) ? values.at(key) : Json();
    if (op == "write") values[key] = m.at("value").get<std::string>();
    else if (op == "delete") values.erase(key);
    else throw std::runtime_error("Invalid vault operation");
    auto text = values.dump();
    DATA_BLOB input{(DWORD)text.size(), reinterpret_cast<BYTE*>(text.data())}, encrypted{};
    bool ok = CryptProtectData(&input, nullptr, nullptr, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &encrypted) != FALSE;
    SecureZeroMemory(text.data(), text.size());
    if (!ok) throw std::runtime_error("Vault encryption failed");
    fs::create_directories(path_.parent_path());
    auto temp = path_; temp += L".tmp";
    HANDLE file = CreateFileW(temp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    ok = file != INVALID_HANDLE_VALUE && writeAll(file, encrypted.pbData, encrypted.cbData) && FlushFileBuffers(file);
    if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
    LocalFree(encrypted.pbData);
    if (!ok || !MoveFileExW(temp.c_str(), path_.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
      throw std::runtime_error("Vault persistence failed");
    return nullptr;
  }
 private:
  fs::path path_;
};

struct Host {
  HWND window = nullptr;
  HANDLE job = nullptr;
  fs::path root, data;
  std::unique_ptr<Vault> vault;
  std::shared_ptr<Child> core, ui;
  NOTIFYICONDATAW icon{};
  TrayIcons trayIcons;
  Json state = Json::object();
  unsigned long long next = 0, uiGeneration = 0;
  bool quitting = false, wanted = false, showOnReady = true, trayReady = false;
  std::deque<ULONGLONG> failures;
  std::string route = "connection", shutdownId;
  std::string command(const std::string& op) {
    if (!core) return {};
    auto id = "host-" + std::to_string(++next);
    core->send({{"kind", "request"}, {"version", 1}, {"source", "host"}, {"session", "host"},
                {"id", id}, {"op", op}, {"params", Json::object()}});
    return id;
  }
  void startCore() {
    core = launch(window, job, root / L"neutrino_worker.exe", {data.wstring(), (root / L"data/flutter_assets/assets/test.jks").wstring()});
  }
  void open(const std::string& page = "connection") {
    if (quitting) return;
    route = page;
    if (!ui) {
      ui = launch(window, job, root / L"neutrino_proxy_client_desktop.exe", {L"--hosted"});
      ui->session = std::to_string(++uiGeneration);
    }
    ui->send({{"kind", "activate"}, {"route", route}, {"trayReady", trayReady}});
  }
  void updateTray() {
    auto engine = state.value("engine", Json::object());
    auto phase = engine.value("state", "idle");
    icon.hIcon = trayIcons.forState(phase);
    std::wstring label = L"尚未连接";
    if (phase == "connected") label = L"已连接";
    else if (phase == "connecting" || phase == "authenticating") label = L"正在连接";
    else if (phase == "reconnecting") label = L"等待重连";
    else if (phase == "error") label = L"连接失败";
    auto text = L"Neutrino · " + label;
    wcsncpy_s(icon.szTip, text.c_str(), _TRUNCATE);
    Shell_NotifyIconW(NIM_MODIFY, &icon);
  }
  void menu() {
    auto engine = state.value("engine", Json::object());
    auto phase = engine.value("state", "idle");
    bool active = phase != "idle" && phase != "error";
    HMENU menu = CreatePopupMenu();
    AppendMenuW(menu, MF_STRING | MF_DISABLED, 0, L"Neutrino Proxy");
    AppendMenuW(menu, MF_STRING | MF_DISABLED, 0, icon.szTip);
    auto config = state.value("config", Json::object());
    if (active && engine.contains("activeConfig") && engine["activeConfig"].is_object()) config = engine["activeConfig"];
    auto server = config.value("server", "");
    if (!server.empty()) AppendMenuW(menu, MF_STRING | MF_DISABLED, 0, wide(server + ":" + std::to_string(config.value("port", 0))).c_str());
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kOpen, L"打开主窗口");
    AppendMenuW(menu, MF_STRING, kLogs, L"查看日志");
    AppendMenuW(menu, MF_STRING | (!core || state.value("ready", false) ? 0 : MF_GRAYED), active ? kDisconnect : kConnect, active ? L"断开连接" : L"连接");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kQuit, L"退出应用");
    POINT point; GetCursorPos(&point); SetForegroundWindow(window);
    UINT action = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, point.x, point.y, 0, window, nullptr);
    DestroyMenu(menu);
    if (action) PostMessageW(window, WM_COMMAND, action, 0);
  }
  void quit() {
    if (quitting) return;
    quitting = true; wanted = false;
    if (core) shutdownId = command("shutdown"); else PostQuitMessage(0);
    SetTimer(window, 2, 5000, nullptr);
  }
  void packet(const std::shared_ptr<Child>& child, Json m) {
    auto kind = m.value("kind", "");
    if (child == core) {
      if (kind == "ready") {
        if (m.value("version", 0) != 1) { quit(); return; }
        command("snapshot");
        if (wanted) command("connect");
        if (ui) core->send({{"kind", "request"}, {"version", 1}, {"source", "ui"},
          {"session", ui->session}, {"id", "reattach"}, {"op", "attach"}});
        if (showOnReady) { showOnReady = false; open(); }
      } else if (kind == "vault") {
        Json reply = {{"kind", "vaultResult"}, {"id", m.at("id")}};
        try { reply["result"] = vault->call(m); } catch (...) { reply["error"] = "System vault unavailable"; }
        core->send(reply);
      } else if (kind == "state") {
        state = m.at("data");
        auto phase = state.value("engine", Json::object()).value("state", "idle");
        if (phase == "error") wanted = false;
        if (ui) ui->send(m);
        state["engine"]["logs"] = Json::array();
        updateTray();
      } else if (kind == "response") {
        if (m.value("source", "") == "ui" && ui && m.value("session", "") == ui->session) ui->send(m);
        if (quitting && m.value("source", "") == "host" && m.value("id", "") == shutdownId) PostQuitMessage(0);
      }
    } else if (child == ui) {
      if (kind == "request") {
        if (!core) { m["kind"] = "response"; m["error"] = "网络内核已退出，请从托盘重试。"; ui->send(m); return; }
        auto op = m.value("op", "");
        if (op == "shutdown") return;
        if (op == "connect" || (op == "save" && m.value("params", Json::object()).value("reconnect", false))) wanted = true;
        if (op == "disconnect") wanted = false;
        m["source"] = "ui"; m["session"] = ui->session;
        core->send(m);
      } else if (kind == "uiReady") {
        SetPropW(window, L"Neutrino.UIReady", reinterpret_cast<HANDLE>(static_cast<uintptr_t>(ui->pid)));
        ui->send({{"kind", "activate"}, {"route", route}, {"trayReady", trayReady}});
      } else if (kind == "quitApproved") { quit(); }
    }
  }
  void gone(const std::shared_ptr<Child>& child) {
    child->stop();
    if (child == ui) {
      RemovePropW(window, L"Neutrino.UIReady");
      if (core) core->send({{"kind", "request"}, {"version", 1}, {"source", "host"}, {"session", ui->session}, {"id", "detach"}, {"op", "detach"}});
      ui.reset();
    } else if (child == core) {
      core.reset();
      if (quitting) { PostQuitMessage(0); return; }
      state["ready"] = false;
      state["error"] = "网络内核已退出，正在尝试恢复。";
      state["engine"] = {{"state", "error"}, {"logs", Json::array()}};
      state["epoch"] = "stopped";
      if (ui) ui->send({{"kind", "state"}, {"data", state}});
      updateTray();
      auto now = GetTickCount64();
      while (!failures.empty() && now - failures.front() > 300000) failures.pop_front();
      if (failures.size() < 3) { static const UINT delays[] = {1000, 3000, 10000}; SetTimer(window, 1, delays[failures.size()], nullptr); failures.push_back(now); }
    }
  }
};
Host* host = nullptr;
LRESULT CALLBACK procedure(HWND hwnd, UINT message, WPARAM w, LPARAM l) {
  try {
    if (message == kPacket || message == kGone) {
      std::unique_ptr<Packet> packet(reinterpret_cast<Packet*>(l));
      postedBytes -= packet->bytes;
      if (message == kPacket) host->packet(packet->child, std::move(packet->data)); else host->gone(packet->child);
      return 0;
    }
    if (message == kTray) {
      if (l == WM_LBUTTONUP || l == WM_LBUTTONDBLCLK) host->open();
      if (l == WM_RBUTTONUP || l == WM_CONTEXTMENU) host->menu();
      return 0;
    }
    if (message == WM_COMMAND) {
      switch (LOWORD(w)) {
        case kOpen: host->open(); break;
        case kLogs: host->open("logs"); break;
        case kConnect:
          if (host->core && host->state.value("ready", false) && (!host->state.value("hasLicense", false) ||
              host->state.value("config", Json::object()).value("server", "").empty())) {
            host->open("settings"); break;
          }
          host->wanted = true;
          if (!host->core) { host->failures.clear(); host->startCore(); }
          else host->command("connect");
          break;
        case kDisconnect: host->wanted = false; host->command("disconnect"); break;
        case kQuit:
          if (host->ui) { host->ui->send({{"kind", "prepareQuit"}}); }
          else host->quit();
          break;
      }
      return 0;
    }
    if (message == WM_TIMER) {
      KillTimer(hwnd, w);
      if (w == 1 && !host->quitting && !host->core) host->startCore();
      if (w == 2) PostQuitMessage(0);
      return 0;
    }
    if (message == WM_QUERYENDSESSION) { host->quit(); return TRUE; }
    if (message == RegisterWindowMessageW(L"TaskbarCreated")) Shell_NotifyIconW(NIM_ADD, &host->icon);
  } catch (...) {
    MessageBoxW(hwnd, L"无法完成操作。请确认安装包完整、配置目录可写，然后重试。", L"Neutrino", MB_OK | MB_ICONERROR);
  }
  return DefWindowProcW(hwnd, message, w, l);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  Host app; host = &app;
  wchar_t executable[32768]; GetModuleFileNameW(nullptr, executable, 32768);
  app.root = fs::path(executable).parent_path();
  PWSTR folder = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &folder))) return 1;
  app.data = fs::path(folder) / L"cn.neutrino" / L"Neutrino"; CoTaskMemFree(folder);
  int count = 0; auto args = CommandLineToArgvW(GetCommandLineW(), &count);
  bool customProfile = false;
  for (int i = 1; i < count; ++i) {
    if (std::wstring(args[i]) == L"--background") app.showOnReady = false;
    if (std::wstring(args[i]) == L"--data-dir" && i + 1 < count) { app.data = fs::absolute(args[++i]); customProfile = true; }
  }
  LocalFree(args);
  std::wstring mutexName = L"Local\\NeutrinoProxyFlutter";
  std::wstring title = L"Neutrino";
  if (customProfile) { auto suffix = std::to_wstring(std::hash<std::wstring>{}(app.data.wstring())); mutexName += suffix; title += suffix; }
  HANDLE singleton = CreateMutexW(nullptr, FALSE, mutexName.c_str());
  if (!singleton) return 1;
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = FindWindowW(kClass, title.c_str());
    if (existing) PostMessageW(existing, WM_COMMAND, kOpen, 0);
    else {
      existing = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Neutrino");
      if (existing) { ShowWindow(existing, SW_RESTORE); SetForegroundWindow(existing); }
      MessageBoxW(nullptr, L"请先从旧版客户端托盘完整退出，再启动新版。", L"Neutrino", MB_OK);
    }
    CloseHandle(singleton); return 0;
  }
  try {
    fs::create_directories(app.data);
    app.vault = std::make_unique<Vault>(app.data / L"flutter_secure_storage.dat");
    app.job = CreateJobObjectW(nullptr, nullptr);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION info{}; info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!app.job || !SetInformationJobObject(app.job, JobObjectExtendedLimitInformation, &info, sizeof(info))) throw std::runtime_error("Job creation failed");
    WNDCLASSW type{}; type.hInstance = instance; type.lpszClassName = kClass; type.lpfnWndProc = procedure;
    RegisterClassW(&type);
    app.window = CreateWindowW(kClass, title.c_str(), WS_OVERLAPPED, 0, 0, 0, 0, nullptr, nullptr, instance, nullptr);
    if (!app.window) throw std::runtime_error("Host window creation failed");
    app.icon.cbSize = sizeof(app.icon); app.icon.hWnd = app.window; app.icon.uID = 1;
    app.icon.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP; app.icon.uCallbackMessage = kTray;
    app.icon.hIcon = app.trayIcons.forState("idle");
    wcscpy_s(app.icon.szTip, L"Neutrino · 正在启动");
    app.trayReady = Shell_NotifyIconW(NIM_ADD, &app.icon) != FALSE;
    if (!app.trayReady) app.showOnReady = true;
    app.startCore();
    MSG message;
    while (GetMessageW(&message, nullptr, 0, 0) > 0) { TranslateMessage(&message); DispatchMessageW(&message); }
  } catch (...) { MessageBoxW(nullptr, L"后台启动失败，请检查安装包是否包含网络内核和界面。", L"Neutrino", MB_OK | MB_ICONERROR); }
  if (app.ui) app.ui->stop();
  if (app.core) app.core->stop();
  app.ui.reset(); app.core.reset();
  Shell_NotifyIconW(NIM_DELETE, &app.icon);
  if (app.job) CloseHandle(app.job);
  CloseHandle(singleton); CoUninitialize(); return 0;
}
