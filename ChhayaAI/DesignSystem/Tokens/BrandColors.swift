import SwiftUI

// MARK: - Brand (Primitive) Colors
// Tier 1: Raw color values — the single source of truth.
// These are never used directly in views. They are consumed
// only through semantic aliases (Tier 2).

enum BrandColor {

    // MARK: Teal

    static let teal50  = Color(red: 237/255, green: 248/255, blue: 247/255)
    static let teal500 = Color(red: 42/255,  green: 157/255, blue: 144/255)
    static let teal700 = Color(red: 32/255,  green: 121/255, blue: 111/255)

    // MARK: Neutral

    static let neutral25  = Color(red: 252/255, green: 253/255, blue: 253/255)
    static let neutral50  = Color(red: 243/255, green: 246/255, blue: 246/255)
    static let neutral200 = Color(red: 226/255, green: 233/255, blue: 233/255)
    static let neutral500 = Color(red: 103/255, green: 126/255, blue: 126/255)
    static let neutral900 = Color(red: 34/255,  green: 42/255,  blue: 42/255)

    // MARK: Base

    static let white = Color.white
    static let black = Color.black

    // MARK: Status

    static let green500 = Color(red: 33/255,  green: 196/255, blue: 93/255)
    static let red500   = Color(red: 220/255, green: 40/255,  blue: 40/255)
    static let amber500 = Color(red: 219/255, green: 119/255, blue: 6/255)
}
