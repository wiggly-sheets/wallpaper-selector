import Combine
import XCTest

extension XCTestCase {
    /// Waits for the first image list the publisher sends that matches.
    ///
    /// The image scans run in a task, so a test waits for the load itself
    /// instead of guessing how long the scan takes.
    @discardableResult
    func waitForImages(
        _ publisher: Published<[URL]>.Publisher,
        where matches: @escaping ([URL]) -> Bool,
        timeout: TimeInterval = 10
    ) async -> [URL]? {
        let loaded = expectation(description: "the images are loaded")
        var result: [URL]?
        // The publisher remembers its current value, so a load that finished
        // before the subscription is not missed.
        let subscription = publisher.first(where: matches).sink { images in
            result = images
            loaded.fulfill()
        }
        defer { subscription.cancel() }
        await fulfillment(of: [loaded], timeout: timeout)
        return result
    }
}
