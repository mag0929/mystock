import Foundation
import SwiftData

@Model
final class SaleAllocation {
    var id: UUID = UUID()
    var sale: Sale?
    var lot: Lot?
    var quantity: Int = 0

    init(id: UUID = UUID(), sale: Sale? = nil, lot: Lot? = nil, quantity: Int = 0) {
        self.id = id
        self.sale = sale
        self.lot = lot
        self.quantity = quantity
    }
}
