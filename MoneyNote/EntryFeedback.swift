import UIKit

/// Reuse and prepare one gentle impact generator for successive entry actions.
@MainActor
enum EntryFeedback {
    private static let generator = UIImpactFeedbackGenerator(style: .soft)

    static func prepare() {
        generator.prepare()
    }

    static func tap() {
        generator.impactOccurred(intensity: 0.55)
        generator.prepare()
    }
}
