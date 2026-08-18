import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
      let icon = NSImage(contentsOf: iconURL)
    else { return }

    NSApplication.shared.applicationIconImage = icon
  }
}

@main
struct DotenvxGUIApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup("dotenvx GUI") {
      ContentView(model: model)
        .frame(minWidth: 900, minHeight: 600)
    }
    .defaultSize(width: 1100, height: 750)
    .commands {
      CommandGroup(replacing: .help) {
        Button("dotenvx Guide") {
          NotificationCenter.default.post(name: .showDotenvxGuide, object: nil)
        }
        .keyboardShortcut("/", modifiers: .command)
      }
    }
  }
}

extension Notification.Name {
  static let showDotenvxGuide = Notification.Name("showDotenvxGuide")
}
