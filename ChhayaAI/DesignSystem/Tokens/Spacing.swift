import SwiftUI

// MARK: - Spacing Tokens
// 4px base unit grid. Named after multiplier (space4 = 4 × 4 = 16pt).

enum Spacing {

    // MARK: Scale

    static let space0:   CGFloat = 0
    static let space1:   CGFloat = 4
    static let space1_5: CGFloat = 6
    static let space2:   CGFloat = 8
    static let space3:   CGFloat = 12
    static let space4:   CGFloat = 16
    static let space5:   CGFloat = 20
    static let space6:   CGFloat = 24
    static let space8:   CGFloat = 32
    static let space12:  CGFloat = 48

    // MARK: Screen Layout

    static let screenPaddingH: CGFloat = 24
    static let statusBarHeight: CGFloat = 25
    static let homeIndicatorHeight: CGFloat = 48
}
