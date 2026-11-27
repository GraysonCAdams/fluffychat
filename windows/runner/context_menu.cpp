#include "context_menu.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <variant>

namespace {

// uxtheme.dll's PreferredAppMode, which decides the theme of popup menus.
enum class PreferredAppMode { kDefault, kAllowDark, kForceDark, kForceLight };

using SetPreferredAppModeFn = PreferredAppMode(WINAPI*)(PreferredAppMode);
using FlushMenuThemesFn = void(WINAPI*)();

// Win32 has no public switch for dark popup menus. Notepad, Explorer and
// Windows Terminal use these two exports, which uxtheme.dll has only by
// ordinal (Windows 10 1903 and later); without them the menu stays light.
void ApplyMenuTheme(bool dark) {
  static HMODULE uxtheme =
      ::LoadLibraryExW(L"uxtheme.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!uxtheme) {
    return;
  }
  static auto set_preferred_app_mode = reinterpret_cast<SetPreferredAppModeFn>(
      ::GetProcAddress(uxtheme, MAKEINTRESOURCEA(135)));
  static auto flush_menu_themes = reinterpret_cast<FlushMenuThemesFn>(
      ::GetProcAddress(uxtheme, MAKEINTRESOURCEA(136)));
  if (!set_preferred_app_mode || !flush_menu_themes) {
    return;
  }
  set_preferred_app_mode(dark ? PreferredAppMode::kForceDark
                              : PreferredAppMode::kForceLight);
  flush_menu_themes();
}

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  int length = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                     static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring utf16(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        utf16.data(), length);
  return utf16;
}

// The Ctrl key's name as the keyboard layout spells it ("Strg" in German).
std::wstring ControlKeyName() {
  LONG scan_code = ::MapVirtualKeyW(VK_CONTROL, MAPVK_VK_TO_VSC) << 16;
  wchar_t name[32];
  int length = ::GetKeyNameTextW(scan_code, name, 32);
  return length > 0 ? std::wstring(name, length) : L"Ctrl";
}

const flutter::EncodableValue* Find(const flutter::EncodableMap& map,
                                    const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::optional<double> GetNumber(const flutter::EncodableMap& map,
                                const char* key) {
  const flutter::EncodableValue* value = Find(map, key);
  if (!value) {
    return std::nullopt;
  }
  if (auto* d = std::get_if<double>(value)) {
    return *d;
  }
  if (auto* i = std::get_if<int32_t>(value)) {
    return *i;
  }
  if (auto* l = std::get_if<int64_t>(value)) {
    return static_cast<double>(*l);
  }
  return std::nullopt;
}

bool GetBool(const flutter::EncodableMap& map, const char* key) {
  const flutter::EncodableValue* value = Find(map, key);
  auto* b = value ? std::get_if<bool>(value) : nullptr;
  return b && *b;
}

std::string GetString(const flutter::EncodableMap& map, const char* key) {
  const flutter::EncodableValue* value = Find(map, key);
  auto* s = value ? std::get_if<std::string>(value) : nullptr;
  return s ? *s : std::string();
}

// Builds and tracks the menu, returning the chosen id or 0.
int ShowMenu(HWND view, const flutter::EncodableMap& args) {
  HMENU menu = ::CreatePopupMenu();
  if (!menu) {
    return 0;
  }
  const flutter::EncodableValue* items_value = Find(args, "items");
  auto* items = items_value ? std::get_if<flutter::EncodableList>(items_value)
                            : nullptr;
  if (items) {
    std::wstring control = ControlKeyName();
    for (const flutter::EncodableValue& item_value : *items) {
      auto* item = std::get_if<flutter::EncodableMap>(&item_value);
      if (!item) {
        continue;
      }
      if (GetBool(*item, "separator")) {
        ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
        continue;
      }
      std::wstring label = Utf16FromUtf8(GetString(*item, "label"));
      std::string ctrl_key = GetString(*item, "ctrlKey");
      if (!ctrl_key.empty()) {
        // Text after a tab is drawn right-aligned, as the shortcut column.
        label += L"\t" + control + L"+" + Utf16FromUtf8(ctrl_key);
      }
      UINT flags = MF_STRING | (GetBool(*item, "enabled") ? 0 : MF_GRAYED);
      UINT_PTR id = static_cast<UINT_PTR>(GetNumber(*item, "id").value_or(0));
      ::AppendMenuW(menu, flags, id, label.c_str());
    }
  }

  POINT point{static_cast<LONG>(GetNumber(args, "x").value_or(0)),
              static_cast<LONG>(GetNumber(args, "y").value_or(0))};
  ::ClientToScreen(view, &point);
  ApplyMenuTheme(GetBool(args, "dark"));

  // TPM_RETURNCMD makes this block in the menu's own message loop until the
  // user picks an item or dismisses the menu, and return the choice.
  UINT flags = TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON | TPM_LEFTALIGN |
               TPM_TOPALIGN;
  if (::GetSystemMetrics(SM_MENUDROPALIGNMENT)) {
    flags = (flags & ~TPM_LEFTALIGN) | TPM_RIGHTALIGN;
  }
  int chosen = static_cast<int>(::TrackPopupMenuEx(
      menu, flags, point.x, point.y, ::GetAncestor(view, GA_ROOT), nullptr));
  ::DestroyMenu(menu);
  return chosen;
}

}  // namespace

ContextMenuChannel::ContextMenuChannel(flutter::BinaryMessenger* messenger,
                                       HWND view)
    : view_(view) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "chat.fluffy.fluffychat/context_menu",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
        if (call.method_name() != "show" || !args) {
          result->NotImplemented();
          return;
        }
        int chosen = ShowMenu(view_, *args);
        if (chosen > 0) {
          result->Success(flutter::EncodableValue(chosen));
        } else {
          result->Success();
        }
      });
}
