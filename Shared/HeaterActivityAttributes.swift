import Foundation
#if canImport(ActivityKit)
import ActivityKit

struct HeaterActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var endsAt: Date
        var unlimited: Bool
        var watts: Int
    }
    var name: String
}
#endif
