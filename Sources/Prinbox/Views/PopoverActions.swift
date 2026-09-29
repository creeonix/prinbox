import Foundation

/// Side effects the views can trigger. AppCoordinator implements them.
struct PopoverActions {
    let open: @MainActor (URL) -> Void
    let refresh: @MainActor () -> Void
    let quit: @MainActor () -> Void
}
