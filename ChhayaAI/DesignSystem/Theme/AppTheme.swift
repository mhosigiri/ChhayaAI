import SwiftUI

// MARK: - App Theme
// Central entry point for all design tokens.
// Usage: AppTheme.color.textPrimary, AppTheme.spacing.space4, etc.

enum AppTheme {
    typealias color     = SemanticColor
    typealias component = ComponentColor
    typealias spacing   = Spacing
    typealias radius    = AppRadius
    typealias shadow    = AppShadow
    typealias opacity   = AppOpacity
    typealias font      = AppFont
}
