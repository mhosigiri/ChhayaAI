import SwiftUI

// MARK: - Alias (Semantic) Colors
// Tier 2: Assigns meaning to brand primitives.
// Views should reference these tokens instead of raw brand values.
// Each property resolves through the brand tier, so swapping a
// brand primitive cascades everywhere automatically.

enum SemanticColor {

    // MARK: Text

    static let textPrimary   = BrandColor.neutral900
    static let textSecondary = BrandColor.neutral500
    static let textInverse   = BrandColor.white
    static let textAccent    = BrandColor.teal700

    // MARK: Backgrounds

    static let bgPrimary   = BrandColor.white
    static let bgSecondary = BrandColor.neutral25
    static let bgTertiary  = BrandColor.neutral50
    static let bgTinted    = BrandColor.teal50

    // MARK: Borders & Dividers

    static let borderDefault = BrandColor.neutral200

    // MARK: Icons

    static let iconPrimary   = BrandColor.neutral900
    static let iconSecondary = BrandColor.neutral500
    static let iconAccent    = BrandColor.teal500

    // MARK: Actions

    static let actionPrimary     = BrandColor.teal500
    static let actionPrimaryText = BrandColor.white

    // MARK: Status

    static let statusSuccess = BrandColor.green500
    static let statusError   = BrandColor.red500
    static let statusWarning = BrandColor.amber500
}
