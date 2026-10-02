import Foundation
import SwiftData

@Model
final class Stock {
    var symbol: String = ""
    var name: String = ""

    init(symbol: String, name: String = "") {
        self.symbol = symbol
        self.name = name
    }
}
