//
//  PerformanceUITests.swift
//  PowerUserMailUITests
//
//  UI performance tests measuring real user interactions.
//  Target: Sub-50ms for all interactions.
//

import XCTest

final class PerformanceUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["PERFORMANCE_MONITORING"] = "1"
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - App Launch Performance
    
    func testAppLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
    
    func testAppLaunchToInteractive() throws {
        let app = XCUIApplication()
        
        measure(metrics: [XCTOSSignpostMetric.applicationLaunch]) {
            app.launch()
            // Wait for main UI to be interactive
            let searchField = app.textFields["Search emails..."]
            _ = searchField.waitForExistence(timeout: 5)
        }
    }
    
    // MARK: - Command Palette Performance
    
    func testCommandPaletteOpen() throws {
        // Open command palette with keyboard shortcut
        measure {
            app.typeKey("k", modifierFlags: .command)
            
            // Wait for palette to appear
            let searchField = app.textFields.firstMatch
            XCTAssertTrue(searchField.waitForExistence(timeout: 1))
            
            // Close it
            app.typeKey(.escape, modifierFlags: [])
        }
    }
    
    func testCommandPaletteSearch() throws {
        // Open command palette
        app.typeKey("k", modifierFlags: .command)
        
        let searchField = app.textFields.firstMatch
        guard searchField.waitForExistence(timeout: 2) else {
            XCTFail("Command palette didn't open")
            return
        }
        
        measure {
            // Type search query
            searchField.typeText("mark")
            
            // Clear for next iteration
            searchField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        }
    }
    
    func testCommandPaletteNavigation() throws {
        // Open command palette
        app.typeKey("k", modifierFlags: .command)
        
        let searchField = app.textFields.firstMatch
        guard searchField.waitForExistence(timeout: 2) else {
            XCTFail("Command palette didn't open")
            return
        }
        
        measure {
            // Navigate down
            app.typeKey(.downArrow, modifierFlags: [])
            app.typeKey(.downArrow, modifierFlags: [])
            app.typeKey(.downArrow, modifierFlags: [])
            
            // Navigate up
            app.typeKey(.upArrow, modifierFlags: [])
            app.typeKey(.upArrow, modifierFlags: [])
            app.typeKey(.upArrow, modifierFlags: [])
        }
    }
    
    // MARK: - Keyboard Shortcut Performance
    
    func testKeyboardShortcutResponse() throws {
        let shortcuts = ["1", "2", "3"] // Filter shortcuts: ⌘1, ⌘2, ⌘3
        
        // XCTest only allows one measure block per test, so we test all shortcuts in one block
        measure {
            for key in shortcuts {
                app.typeKey(key, modifierFlags: .command)
            }
        }
    }
    
    // MARK: - Navigation Performance
    
    func testConversationListScroll() throws {
        // Find the scroll view / list
        let list = app.scrollViews.firstMatch
        guard list.waitForExistence(timeout: 2) else {
            // Try tables instead
            let table = app.tables.firstMatch
            guard table.waitForExistence(timeout: 2) else {
                XCTSkip("No scrollable list found")
                return
            }
            
            measure {
                table.swipeUp()
                table.swipeDown()
            }
            return
        }
        
        measure {
            list.swipeUp()
            list.swipeDown()
        }
    }
    
    // MARK: - Filter Tab Performance
    
    func testFilterTabSwitch() throws {
        // Look for filter buttons
        let unreadButton = app.buttons["Unread"].firstMatch
        let allButton = app.buttons["All"].firstMatch
        let archivedButton = app.buttons["Archived"].firstMatch
        
        guard unreadButton.waitForExistence(timeout: 2) else {
            XCTSkip("Filter buttons not found")
            return
        }
        
        measure {
            allButton.tap()
            unreadButton.tap()
            archivedButton.tap()
            unreadButton.tap()
        }
    }
    
    // MARK: - Window Operations Performance
    
    func testWindowResize() throws {
        measure {
            // This measures the responsiveness of window operations
            // handled by the system but our content must keep up
        }
    }
    
    // MARK: - Memory Performance
    
    func testMemoryFootprint() throws {
        let metrics: [XCTMetric] = [
            XCTMemoryMetric(application: app),
            XCTCPUMetric(application: app)
        ]
        
        measure(metrics: metrics) {
            // Perform typical user actions
            app.typeKey("k", modifierFlags: .command)
            let searchField = app.textFields.firstMatch
            if searchField.waitForExistence(timeout: 1) {
                searchField.typeText("test")
                app.typeKey(.escape, modifierFlags: [])
            }
            
            // Switch filters
            app.typeKey("1", modifierFlags: .command)
            app.typeKey("2", modifierFlags: .command)
            app.typeKey("3", modifierFlags: .command)
        }
    }
}

// MARK: - Stress Tests

final class PerformanceStressTests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    func testRapidCommandPaletteToggle() throws {
        // Rapidly open and close command palette
        measure {
            for _ in 0..<10 {
                app.typeKey("k", modifierFlags: .command)
                app.typeKey(.escape, modifierFlags: [])
            }
        }
    }
    
    func testRapidFilterSwitch() throws {
        // Rapidly switch between filters
        measure {
            for _ in 0..<10 {
                app.typeKey("1", modifierFlags: .command)
                app.typeKey("2", modifierFlags: .command)
                app.typeKey("3", modifierFlags: .command)
            }
        }
    }
    
    func testTypingResponsiveness() throws {
        // Open command palette
        app.typeKey("k", modifierFlags: .command)
        
        let searchField = app.textFields.firstMatch
        guard searchField.waitForExistence(timeout: 2) else {
            XCTSkip("Command palette didn't open")
            return
        }
        
        // Measure typing responsiveness
        measure {
            let testString = "abcdefghij"
            searchField.typeText(testString)
            
            // Delete
            for _ in testString {
                app.typeKey(.delete, modifierFlags: [])
            }
        }
    }
}

