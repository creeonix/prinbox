import Foundation

/// Keyboard and hover selection over the visible items. Movement wraps at both ends.
public struct Selection: Equatable, Sendable {
    public let current: InboxItemID?

    public init(current: InboxItemID? = nil) { self.current = current }

    public func movingDown(in items: [InboxItemID]) -> Selection { step(in: items, by: 1) }

    public func movingUp(in items: [InboxItemID]) -> Selection { step(in: items, by: -1) }

    /// Keeps the selection if its item survives. Otherwise selects the nearest preceding item that still
    /// exists (so folding lands on the section header), else the first item.
    public func reconciled(previous: [InboxItemID], current items: [InboxItemID]) -> Selection {
        guard let current else { return self }
        if items.contains(current) { return self }
        let index = previous.firstIndex(of: current) ?? 0
        let survivor = previous[..<index].reversed().first(where: items.contains)
        return Selection(current: survivor ?? items.first)
    }

    private func step(in items: [InboxItemID], by delta: Int) -> Selection {
        guard !items.isEmpty else { return Selection() }
        guard let current, let index = items.firstIndex(of: current) else {
            return Selection(current: delta > 0 ? items.first : items.last)
        }
        return Selection(current: items[(index + delta + items.count) % items.count])
    }
}
