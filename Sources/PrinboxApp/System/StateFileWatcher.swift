import Foundation

/// Watches the state directory for the atomic replacements other writers (the command, the server) make to
/// state.json, and reloads after a fixed window (spec 5.1). A rename into a directory is a write to the
/// directory, so the directory is watched; a watch on the file itself would go stale at the first replacement,
/// since the inode changes. The window is fixed: the first event starts it and later events do not restart
/// it, so a burst delays the reload by at most 200 ms. The app's own writes cost one no-op reload.
@MainActor
final class StateFileWatcher {
    static let window: Duration = .milliseconds(200)

    private let directory: URL
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: Task<Void, Never>?

    init(directory: URL, onChange: @escaping @MainActor () -> Void) {
        self.directory = directory
        self.onChange = onChange
    }

    func start() {
        guard source == nil else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let source = self.source else { return }
                if source.data.contains(.delete) || source.data.contains(.rename) {
                    self.stop()
                } else {
                    self.schedule()
                }
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    /// One reload per window, whatever the number of events inside it.
    private func schedule() {
        guard pending == nil else { return }
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: StateFileWatcher.window)
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            self.onChange()
        }
    }

    /// The directory went away (`make uninstall` while the app runs): nothing to watch.
    func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }

    deinit {
        pending?.cancel()
        source?.cancel()
    }
}
