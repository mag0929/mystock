import XCTest

final class HoldingsScreenUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testToolbarButtonOpensLotEditorAndSavesABatch() {
        let addButton = app.buttons["新增批次"].firstMatch
        XCTAssertTrue(
            addButton.waitForExistence(timeout: 5),
            "持股畫面必須有可見的新增批次按鈕"
        )
        addButton.tap()

        let symbolField = app.textFields.firstMatch
        XCTAssertTrue(symbolField.waitForExistence(timeout: 5), "新增批次表單應出現")

        symbolField.tap()
        symbolField.typeText("2330")
        app.textFields.element(boundBy: 1).tap()
        app.textFields.element(boundBy: 1).typeText("1000")
        app.textFields.element(boundBy: 2).tap()
        app.textFields.element(boundBy: 2).typeText("150")

        app.buttons["儲存"].tap()

        XCTAssertTrue(
            app.staticTexts["2330"].waitForExistence(timeout: 5),
            "儲存後應在持股清單看到該批次"
        )
    }

    func testEmptyStateOffersAProminentAddButton() {
        let addButton = app.buttons["holdings.addFirstLot"]
        XCTAssertTrue(
            addButton.waitForExistence(timeout: 5),
            "空狀態必須提供明顯的新增入口"
        )
        XCTAssertTrue(addButton.isHittable, "空狀態的新增按鈕必須可點擊")
    }

    func testEveryTabIsReachable() {
        for tab in ["持股", "賣出", "已實現損益", "設定"] {
            let tabButton = app.tabBars.buttons[tab]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 5), "找不到分頁 \(tab)")
            tabButton.tap()
        }
    }

    private func addLot(symbol: String, quantity: String, price: String) {
        let addButton = app.buttons["新增批次"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "找不到新增批次按鈕")
        addButton.tap()

        let symbolField = app.textFields.firstMatch
        XCTAssertTrue(symbolField.waitForExistence(timeout: 5), "批次表單應出現")
        symbolField.tap()
        symbolField.typeText(symbol)
        app.textFields.element(boundBy: 1).tap()
        app.textFields.element(boundBy: 1).typeText(quantity)
        app.textFields.element(boundBy: 2).tap()
        app.textFields.element(boundBy: 2).typeText(price)
        app.buttons["儲存"].tap()
    }

    private func expandLotsUnderSymbol(_ symbol: String) {
        let row = app.staticTexts[symbol].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "持股清單應出現 \(symbol)")
        let toggle = app.buttons["holdings.toggleLots"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "每個代號都應有展開批次的入口")
        toggle.tap()
    }

    /// Matches the lot row itself rather than the summary figure above it, which
    /// also contains the share count and would swallow a swipe meant for the lot.
    private func lotCell(containing text: String) -> XCUIElement {
        app.cells.containing(NSPredicate(format: "label CONTAINS '剩餘'"))
            .containing(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }

    func testALotCanBeEdited() {
        addLot(symbol: "2330", quantity: "1000", price: "150")
        expandLotsUnderSymbol("2330")

        let lotRow = lotCell(containing: "1,000")
        XCTAssertTrue(lotRow.waitForExistence(timeout: 5), "展開後應看到批次列")
        lotRow.tap()

        XCTAssertTrue(
            app.navigationBars["編輯批次"].waitForExistence(timeout: 5),
            "點擊批次列應開啟編輯表單，而不是唯讀"
        )

        let quantityField = app.textFields.element(boundBy: 1)
        quantityField.tap()
        // Append rather than replace: "1000" plus "2000" would read as 10002000,
        // which still contains "2,000" and would let a broken edit pass.
        quantityField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        quantityField.typeText("2000")
        XCTAssertEqual(quantityField.value as? String, "2000", "股數欄位應為 2000")
        app.buttons["儲存"].tap()

        XCTAssertTrue(
            app.navigationBars["持股"].waitForExistence(timeout: 5),
            "儲存後應回到持股清單"
        )
        XCTAssertTrue(
            lotCell(containing: "2,000").waitForExistence(timeout: 5),
            "批次列應顯示修改後的 2,000 股"
        )
        XCTAssertFalse(
            lotCell(containing: "1,000").exists,
            "修改後不應還看得到舊的 1,000 股"
        )
        XCTAssertTrue(
            app.staticTexts["2,000 股"].waitForExistence(timeout: 5),
            "持股總股數也應跟著更新"
        )
    }

    func testALotCanBeDeleted() {
        addLot(symbol: "2330", quantity: "1000", price: "150")
        expandLotsUnderSymbol("2330")

        let lotRow = lotCell(containing: "1,000")
        XCTAssertTrue(lotRow.waitForExistence(timeout: 5), "展開後應看到批次列")
        lotRow.swipeLeft()

        let deleteButton = app.buttons["刪除"]
        let found = deleteButton.waitForExistence(timeout: 5)
        XCTAssertTrue(found, "左滑後應出現刪除按鈕")
        if !found {
            let labels = app.buttons.allElementsBoundByIndex.map { "\($0.identifier):\($0.label)" }
            XCTFail("左滑後可見的按鈕：\(labels)")
        }
        deleteButton.tap()

        let confirm = app.buttons["刪除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "刪除前應有確認")
        confirm.tap()

        XCTAssertTrue(
            app.staticTexts["尚無持股"].waitForExistence(timeout: 5),
            "刪掉唯一批次後應回到空狀態"
        )
    }
}