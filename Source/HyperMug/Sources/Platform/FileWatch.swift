import Foundation
import HyperMugCore

/// Hands out a way to stop something started here.
private final class Token: Cancellable {
    private let onCancel: () -> Void

    init(_ onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() { onCancel() }
}

/// OS side of `ConfigStore`: a main-queue timer and `open(O_EVTONLY)` + `DispatchSource` file watchers.
func makeConfigStoreEnvironment(log: @escaping LogSink) -> ConfigStoreEnvironment {
    ConfigStoreEnvironment(
        log: log,
        schedule: { delay, work in
            let item = DispatchWorkItem(block: work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return Token { item.cancel() }
        },
        watch: { path, onEvent in
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke], queue: .main)
            source.setEventHandler { [unowned source] in
                onEvent(!source.data.isDisjoint(with: [.delete, .rename, .revoke]))
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            return Token { source.cancel() }
        })
}
