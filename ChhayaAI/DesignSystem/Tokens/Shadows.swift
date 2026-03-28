import SwiftUI

// MARK: - Elevation / Shadow Tokens

enum AppShadow {
    case card
    case elevated

    var color: Color {
        switch self {
        case .card:     return .black.opacity(0.06)
        case .elevated: return .black.opacity(0.08)
        }
    }

    var radius: CGFloat {
        switch self {
        case .card:     return 8
        case .elevated: return 16
        }
    }

    var x: CGFloat { 0 }

    var y: CGFloat {
        switch self {
        case .card:     return 2
        case .elevated: return 4
        }
    }
}

// MARK: - Shadow View Modifier

struct AppShadowModifier: ViewModifier {
    let shadow: AppShadow

    func body(content: Content) -> some View {
        content.shadow(
            color: shadow.color,
            radius: shadow.radius,
            x: shadow.x,
            y: shadow.y
        )
    }
}

extension View {
    func appShadow(_ shadow: AppShadow) -> some View {
        modifier(AppShadowModifier(shadow: shadow))
    }
}
