import Foundation
import HyperMugCore

/// Fetches the latest GitHub release and hands the resulting alert to `done` on the main thread.
/// What the response means is decided by Core's `updateOutcome`.
enum UpdateChecker {
    static func check(_ done: @escaping (UpdateAlert) -> Void) {
        let local = appVersion(infoDictionary: Bundle.main.infoDictionary)
        var request = URLRequest(url: githubLatestAPI)
        for (field, value) in updateRequestHeaders(version: local) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.timeoutInterval = updateRequestTimeout

        URLSession.shared.dataTask(with: request) { data, response, error in
            let alert = updateOutcome(
                errorDescription: error?.localizedDescription,
                status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                body: data,
                local: local
            )
            // A run-loop block, not a GCD main-queue block: `done` may run a modal alert, and the main
            // queue must keep draining (config watchers, debounce) while it is up.
            RunLoop.main.perform(inModes: [.common]) { done(alert) }
        }.resume()
    }
}
