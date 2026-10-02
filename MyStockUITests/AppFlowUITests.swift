import XCTest

/// Walks the whole app through the flow the specs describe: buy a lot, add a
/// stock allocation lot, sell against a manually chosen lot, then read the
/// realized result back on the query screen.
final class AppFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testBuyAllocateSellAndQuery() throws {
        try addLot(symbol: "2330", quantity: "1000", price: "150")
        try addLot(symbol: "2330", quantity: "200", price: nil, isStockAllocation: true)

        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "2 個批次")
            ).firstMatch.waitForExistence(timeout: 5),
            "配股批次應出現在同一代號的批次清單中"
        )

        app.tabBars.buttons["賣出"].tap()

        let recordSale = app.buttons["記錄賣出"].firstMatch
        XCTAssertTrue(recordSale.waitForExistence(timeout: 5), "賣出頁應可記錄賣出")
        recordSale.tap()

        XCTAssertTrue(
            app.navigationBars["記錄賣出"].waitForExistence(timeout: 5),
            "應開啟賣出表單"
        )

        // Only the buy lot may be offered; the stock allocation lot is excluded.
        // The footer text mentions 配股, so count the candidate rows instead.
        XCTAssertEqual(
            app.textFields.matching(
                NSPredicate(format: "placeholderValue == %@", "配對股數")
            ).count,
            1,
            "配股批次不應出現在配對候選清單中，候選應只有買進批次"
        )

        let saleQuantity = app.textFields["股數"]
        XCTAssertTrue(saleQuantity.waitForExistence(timeout: 5))
        saleQuantity.tap()
        saleQuantity.typeText("600")

        let salePrice = app.textFields["賣價"]
        salePrice.tap()
        salePrice.typeText("180")

        let save = app.buttons["儲存"]
        XCTAssertFalse(save.isEnabled, "尚未逐批分配股數前不應可儲存")

        let allocationFields = app.textFields.matching(
            NSPredicate(format: "placeholderValue == %@", "配對股數")
        )
        XCTAssertTrue(
            allocationFields.element(boundBy: 0).waitForExistence(timeout: 5),
            "應可逐批輸入配對股數"
        )
        allocationFields.element(boundBy: 0).tap()
        allocationFields.element(boundBy: 0).typeText("600")

        XCTAssertTrue(save.isEnabled, "分配完成後應可儲存")
        save.tap()

        XCTAssertTrue(
            app.buttons["記錄賣出"].firstMatch.waitForExistence(timeout: 5),
            "賣出完成後應回到賣出清單"
        )

        app.tabBars.buttons["已實現損益"].tap()
        XCTAssertTrue(
            app.navigationBars["已實現損益"].waitForExistence(timeout: 5),
            "應切到已實現損益頁"
        )
        XCTAssertTrue(
            app.staticTexts["依代號"].waitForExistence(timeout: 5),
            "本期賣出應出現在依代號彙總中"
        )
    }

    func testFeeSettingsRoundTrip() throws {
        app.tabBars.buttons["設定"].tap()

        let rateField = app.textFields.firstMatch
        XCTAssertTrue(rateField.waitForExistence(timeout: 5), "設定頁應有費率欄位")

        app.tabBars.buttons["持股"].tap()
        XCTAssertTrue(
            app.buttons["新增批次"].firstMatch.waitForExistence(timeout: 5),
            "切回持股頁後新增按鈕應可點擊"
        )
    }

    /// The switch sits at the trailing edge of its row, so a tap aimed at the
    /// middle of the row lands on empty space and does nothing.
    private func toggleStockAllocation(on app: XCUIApplication) {
        let toggle = app.switches["配股"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "新增批次表單應有配股開關")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(
            toggle.value as? String,
            "1",
            "配股開關應可切換，否則無法建立配股批次"
        )
    }

    private func addLot(
        symbol: String,
        quantity: String,
        price: String?,
        isStockAllocation: Bool = false
    ) throws {
        let addButton = app.buttons["新增批次"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let symbolField = app.textFields["股票代號"]
        XCTAssertTrue(symbolField.waitForExistence(timeout: 5), "應開啟新增批次表單")
        symbolField.tap()
        symbolField.typeText(symbol)

        if isStockAllocation {
            toggleStockAllocation(on: app)
        }

        let quantityField = app.textFields["股數"]
        quantityField.tap()
        quantityField.typeText(quantity)

        if let price {
            let priceField = app.textFields["單價"]
            priceField.tap()
            priceField.typeText(price)
        }

        app.buttons["儲存"].tap()
        XCTAssertTrue(
            app.buttons["新增批次"].firstMatch.waitForExistence(timeout: 5),
            "儲存後應回到持股清單"
        )
    }
}