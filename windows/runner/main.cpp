#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Only one instance may open the database. A second launch, for example
  // from the Start menu while the app sits in the tray, brings the running
  // window to the front instead. The name is AppConfig.seamApplicationId, so
  // it does not clash with an installed FluffyChat, which keeps its own data.
  //
  // A debug build skips the lock when SEAM_SKIP_INSTANCE_LOCK is set, which
  // lets `flutter test integration_test -d windows` run beside an installed
  // Seam. Those tests pump their own widgets and never open the database;
  // anything run this way that does would share it with the running app.
  // Profile and release builds always take the lock.
  bool skip_lock = false;
#ifndef NDEBUG
  skip_lock =
      ::GetEnvironmentVariableW(L"SEAM_SKIP_INSTANCE_LOCK", nullptr, 0) > 0;
#endif
  if (!skip_lock) {
    ::CreateMutexW(nullptr, TRUE, L"Local\\dev.threeonetwo.seam");
  }
  if (!skip_lock && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND running = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Seam");
    if (running) {
      ::ShowWindow(running, ::IsIconic(running) ? SW_RESTORE : SW_SHOW);
      ::SetForegroundWindow(running);
    }
    return EXIT_SUCCESS;
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
  Win32Window::Size size(864, 720);
  if (!window.CreateAndShow(L"Seam", origin, size)) {
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
