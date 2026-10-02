import Foundation

enum LotType: String, Codable, Sendable {
    case buy
    case stockAllocation = "stock-allocation"
}
