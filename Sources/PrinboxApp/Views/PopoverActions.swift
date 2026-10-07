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
    let snooze: @MainActor (String) -> Void
    let unsnooze: @MainActor (String) -> Void
    let copyLink: @MainActor (URL) -> Void
    let setNotifications: @MainActor (Bool) -> Void
    let setFollowReviewThreads: @MainActor (Bool) -> Void
    let setDirectReviewRequestsOnly: @MainActor (Bool) -> Void
    let setHideDrafts: @MainActor (Bool) -> Void
    let toggleRepository: @MainActor (String) -> Void
    let clearRepositories: @MainActor () -> Void
}
