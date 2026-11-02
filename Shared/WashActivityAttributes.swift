import ActivityKit
import Foundation

struct WashActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var start: Date
        var end: Date
        var phase: String
        var done: Bool
    }
    var device: String
    var name: String
}
