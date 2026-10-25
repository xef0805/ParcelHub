import SwiftUI

@main
struct ParcelHubApp: App {
    @StateObject private var store = ParcelStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store).tint(Palette.green)
        }
    }
}

enum Palette {
    static let green = Color(red: 0.13, green: 0.33, blue: 0.27)
    static let paper = Color(red: 0.96, green: 0.96, blue: 0.93)
    static let ink = Color(red: 0.14, green: 0.20, blue: 0.17)
}
