import AppKit
import SwiftUI

@main
@MainActor
struct SlopupApp: App {
    @State private var store: CleanupStore

    init() {
        let store = CleanupStore.shared
        _store = State(initialValue: store)
        store.start()
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(store: store)
        } label: {
            menuBarLabel
                .accessibilityLabel("Slopup")
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        if let icon = MenuBarIcon.image {
            Image(nsImage: icon)
                .renderingMode(.template)
        } else {
            Image(systemName: "externaldrive.badge.minus")
        }
    }
}
