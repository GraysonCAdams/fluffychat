#ifndef RUNNER_CONTEXT_MENU_H_
#define RUNNER_CONTEXT_MENU_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// Shows Windows' own popup menu for the Dart side, which uses it as the
// right-click menu of the message input (lib/utils/native_context_menu.dart).
//
// The channel takes one method, "show", whose arguments are a map:
//   "x", "y": where to open the menu, in physical pixels relative to the
//             Flutter view's client area.
//   "dark":   whether to draw the menu in the dark theme.
//   "items":  a list of maps, either {"separator": true} or
//             {"id": int > 0, "label": string, "enabled": bool,
//              "ctrlKey": optional string}. A "ctrlKey" of "X" shows the
//             shortcut as Ctrl+X, with Ctrl in the keyboard's language.
// It answers with the chosen item's id, or null when the menu was dismissed.
class ContextMenuChannel {
 public:
  // |view| is the window of the Flutter view the menu belongs to.
  ContextMenuChannel(flutter::BinaryMessenger* messenger, HWND view);

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWND view_;
};

#endif  // RUNNER_CONTEXT_MENU_H_
