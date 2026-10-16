#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <filesystem>
#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // The native host owns single-instance, tray and the network worker.
  const auto arguments = GetCommandLineArguments();
  const bool hosted = std::find(arguments.begin(), arguments.end(), "--hosted") != arguments.end();
  if (!hosted) {
    wchar_t executable[32768];
    GetModuleFileNameW(nullptr, executable, 32768);
    auto host = std::filesystem::path(executable).parent_path() / L"neutrino_proxy_host.exe";
    std::wstring command = L"\"" + host.wstring() + L"\"";
    STARTUPINFOW startup{}; startup.cb = sizeof(startup);
    PROCESS_INFORMATION child{};
    if (CreateProcessW(host.c_str(), command.data(), nullptr, nullptr, FALSE,
                      CREATE_NO_WINDOW, nullptr, host.parent_path().c_str(), &startup, &child)) {
      CloseHandle(child.hThread); CloseHandle(child.hProcess);
      return EXIT_SUCCESS;
    }
    MessageBoxW(nullptr, L"后台组件缺失，请使用完整安装包或重新构建。", L"Neutrino", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(860, 620);
  if (!window.Create(L"Neutrino", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
