// AllYouNeedQuickLook/App.swift
import SwiftUI

@main
struct AllYouNeedQuickLookApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                WelcomeView()
                    .tabItem {
                        Label("Welcome", systemImage: "hand.wave")
                    }
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                PreviewView()
                    .tabItem {
                        Label("Preview", systemImage: "eye")
                    }
            }
            .frame(minWidth: 700, minHeight: 500)
        }
        .windowResizability(.contentMinSize)
    }
}
