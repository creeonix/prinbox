import Foundation
import PrinboxCore

/// Side effects the views can trigger. AppCoordinator implements them.
struct PopoverActions {
    let open: @MainActor (URL) -> Void
    let refresh: @MainActor () -> Void
    let quit: @MainActor () -> Void
    let toggleShortcutRecording: @MainActor () -> Void
    let setShortcut: @MainActor (HotKeySpec?) -> Void
    let setLaunchAtLogin: @MainActor (Bool) -> Void
    let copy: @MainActor (String) -> Void
}
