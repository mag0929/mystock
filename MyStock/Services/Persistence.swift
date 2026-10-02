import Foundation
import SwiftData

enum Persistence {
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([Lot.self, Sale.self, SaleAllocation.self, Stock.self, FeeSettingsRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([Lot.self, Sale.self, SaleAllocation.self, Stock.self, FeeSettingsRecord.self])
        if isUITesting {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [configuration])
        }
        let configuration = ModelConfiguration(schema: schema)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }
}
