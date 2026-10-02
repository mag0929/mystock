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
}