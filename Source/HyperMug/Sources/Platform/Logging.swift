import Foundation
import HyperMugCore
import os

/// A Core `LogSink` that writes to the unified log under `AppIdentity.logSubsystem`.
/// Read it with `log stream --predicate 'subsystem == "com.maxmeis.hypermug"'`.
func makeLogSink(category: String) -> LogSink {
    let logger = Logger(subsystem: AppIdentity.logSubsystem, category: category)
    return { level, message in
        switch level {
        case .info: logger.info("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
    }
}
