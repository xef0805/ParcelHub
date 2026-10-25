import SwiftUI
import UIKit

@main
@MainActor
struct ParcelHubApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: ParcelStore
    @StateObject private var sync: OfficialSyncController
    init() {
        let store = ParcelStore()
        _store = StateObject(wrappedValue: store)
        _sync = StateObject(wrappedValue: OfficialSyncController(store: store))
    }
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store).environmentObject(sync).tint(Palette.blue)
                .buttonStyle(PressFeedbackStyle())
                .background {
                    // 独立官方清单页面沿用 WebKit 会话；不切换用户正在看的身份码页面。
                    OfficialPickupWebView(session: sync.session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
                }
                .onAppear { sync.setActive(scenePhase == .active) }
                .onChange(of: scenePhase) { _, phase in sync.setActive(phase == .active) }
                .onChange(of: store.autoSyncEnabled) { _, _ in sync.setActive(scenePhase == .active) }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ParcelHub.official-session-changed"))) { _ in
                    if store.autoSyncEnabled { sync.refresh(force: true) }
                }
        }
    }
}

enum Palette {
    static let blue = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.36, green: 0.65, blue: 1, alpha: 1)
            : UIColor(red: 0.08, green: 0.35, blue: 0.86, alpha: 1)
    })
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color.primary
}
