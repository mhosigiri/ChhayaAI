import SwiftUI

// MARK: - Mapped (Component) Colors
// Tier 3: Binds semantic tokens to specific component contexts.
// This is the layer components actually consume. Contextual
// theming (e.g. emergency mode) is handled here by switching
// which semantic alias each token resolves to.

enum ComponentColor {

    // MARK: Buttons

    enum Button {
        static let primaryBg   = SemanticColor.actionPrimary
        static let primaryText = SemanticColor.actionPrimaryText

        static let secondaryBg   = SemanticColor.bgTertiary
        static let secondaryText = SemanticColor.textPrimary

        static let outlineBorder = SemanticColor.borderDefault
        static let outlineText   = SemanticColor.textPrimary
    }

    // MARK: Cards

    enum Card {
        static let bg      = SemanticColor.bgPrimary
        static let border  = SemanticColor.borderDefault
        static let divider = SemanticColor.borderDefault
    }

    // MARK: Screen

    enum Screen {
        static let bg = SemanticColor.bgSecondary
    }

    // MARK: Status Badges

    enum StatusBadge {
        static let successBg   = SemanticColor.statusSuccess.opacity(0.1)
        static let successText = SemanticColor.statusSuccess

        static let warningBg   = SemanticColor.statusWarning.opacity(0.1)
        static let warningText = SemanticColor.statusWarning

        static let errorBg   = SemanticColor.statusError.opacity(0.3)
        static let errorText = SemanticColor.statusError
    }

    // MARK: Guidance

    enum Guidance {
        static let doIconBg    = SemanticColor.statusSuccess.opacity(0.1)
        static let avoidIconBg = SemanticColor.statusWarning.opacity(0.1)
        static let border      = SemanticColor.borderDefault
    }

    // MARK: Navigation

    enum Nav {
        static let activeTint = SemanticColor.actionPrimary
        static let iconDefault = SemanticColor.iconSecondary
    }
}
