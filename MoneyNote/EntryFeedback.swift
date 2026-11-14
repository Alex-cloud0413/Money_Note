import UIKit

/// Reuse a crisp light impact and prepare it for successive entry actions.
@MainActor
enum EntryFeedback {
    private static let generator = UIImpactFeedbackGenerator(style: .light)

    static func prepare() {
        generator.prepare()
    }

    static func tap() {
        generator.impactOccurred()
        generator.prepare()
    }
}
