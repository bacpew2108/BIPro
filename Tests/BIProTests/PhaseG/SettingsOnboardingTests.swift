import AppKit
import Foundation
import SwiftUI
import Testing
@testable import BIPro

@Suite("PhaseG — Settings & Onboarding UI")
@MainActor
struct SettingsOnboardingTests {
    private static let outputDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build/g-out/ui", isDirectory: true)

    @Test("Kết xuất SettingsView và OnboardingView ở Sáng/Tối và Việt/Anh ra PNG hợp lệ")
    func renderLightAndDarkSnapshots() throws {
        try FileManager.default.createDirectory(at: Self.outputDir, withIntermediateDirectories: true)

        let suite = "bipro.test.ui.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = AppPreferences(defaults: defaults)

        let cases: [(String, AppAppearance, AppLanguage, AnyView)] = [
            ("settings-light-vi.png", .light, .vi, AnyView(SettingsView(preferences: prefs))),
            ("settings-dark-en.png", .dark, .en, AnyView(SettingsView(preferences: prefs))),
            ("onboarding-light-vi.png", .light, .vi, AnyView(OnboardingView(preferences: prefs, onDismiss: {}))),
            ("onboarding-dark-en.png", .dark, .en, AnyView(OnboardingView(preferences: prefs, onDismiss: {}))),
        ]

        for (fileName, appearance, language, view) in cases {
            prefs.appearance = appearance
            prefs.language = language
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, appearance == .dark ? .dark : .light))
            renderer.scale = 2.0
            guard let cgImage = renderer.cgImage else {
                Issue.record("ImageRenderer trả nil cho \(fileName)")
                continue
            }
            #expect(cgImage.width > 400)
            #expect(cgImage.height > 200)
            let rep = NSBitmapImageRep(cgImage: cgImage)
            let data = try #require(rep.representation(using: .png, properties: [:]))
            #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
            try data.write(to: Self.outputDir.appendingPathComponent(fileName))
        }
    }
}
