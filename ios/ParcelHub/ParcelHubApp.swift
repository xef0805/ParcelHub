import SwiftUI
import UIKit

@main
struct ParcelHubApp: App {
    @StateObject private var store = ParcelStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store).tint(Palette.blue)
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
