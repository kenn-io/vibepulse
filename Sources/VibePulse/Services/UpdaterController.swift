import Foundation
import Sparkle

final class UpdaterController: ObservableObject {
  // Only packaged builds carry a Sparkle feed. Dev builds (`swift run`) have no
  // Info.plist, and starting Sparkle there raises an error alert on every launch.
  private let controller: SPUStandardUpdaterController?

  init() {
    guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
      controller = nil
      return
    }
    let controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
    if controller.updater.automaticallyChecksForUpdates {
      controller.updater.checkForUpdatesInBackground()
    }
    self.controller = controller
  }

  var isAvailable: Bool { controller != nil }

  var canCheckForUpdates: Bool {
    controller?.updater.canCheckForUpdates ?? false
  }

  func checkForUpdates() {
    controller?.checkForUpdates(nil)
  }
}
