import AppKit
import Combine
import XCTest

@testable import VibePulse

@MainActor
func showMenuWindow(containing view: NSView) -> NSWindow {
  let window = NSWindow(
    contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = view
  view.layoutSubtreeIfNeeded()
  window.makeKeyAndOrderFront(nil)
  // XCTest does not activate as an app; exercise AppKit's key-window callback directly.
  if !window.isKeyWindow { window.becomeKey() }
  return window
}

@MainActor
func waitForMenuTotal(_ cost: Double, model: AppModel) async {
  let updated = XCTestExpectation(description: "menu displays \(cost)")
  let subscription = model.$toolTotals
    .filter { $0.reduce(0) { $0 + $1.totalCost } == cost }
    .first().sink { _ in updated.fulfill() }
  let result = await XCTWaiter.fulfillment(of: [updated], timeout: 3)
  XCTAssertEqual(result, .completed)
  withExtendedLifetime(subscription) {}
}
