import SwiftUI

// MARK: - Typography Tokens
// All text in the design uses Inter. On iOS the system font
// (SF Pro) is the closest match and is already optimised for
// the platform. To use Inter literally, add the .ttf/.otf files
// to the bundle and register them in Info.plist, then change
// `fontName` below.

enum AppFont {
    static let familyName: String? = nil // nil = SF Pro (system)

    // MARK: Raw Scale

    enum Size {
        static let display:   CGFloat = 40
        static let headingXL: CGFloat = 30
        static let headingLG: CGFloat = 28
        static let headingMD: CGFloat = 20
        static let headingSM: CGFloat = 18
        static let bodyLG:    CGFloat = 18
        static let body:      CGFloat = 16
        static let label:     CGFloat = 14
        static let caption:   CGFloat = 12
    }

    enum LineHeight {
        static let display:   CGFloat = 44
        static let headingXL: CGFloat = 36
        static let headingLG: CGFloat = 33.6
        static let headingMD: CGFloat = 26
        static let headingSM: CGFloat = 28
        static let bodyLG:    CGFloat = 27
        static let body:      CGFloat = 24
        static let label:     CGFloat = 19.6
        static let caption:   CGFloat = 16.8
    }

    enum LetterSpacing {
        static let display:   CGFloat = -0.8
        static let headingXL: CGFloat = 1.5
        static let headingLG: CGFloat = -0.28
        static let standard:  CGFloat = 0
    }
}

// MARK: - Text Style View Modifier

struct AppTextStyle: ViewModifier {
    let font: Font
    let lineHeight: CGFloat
    let fontSize: CGFloat
    let letterSpacing: CGFloat

    func body(content: Content) -> some View {
        content
            .font(font)
            .lineSpacing(lineHeight - fontSize)
            .tracking(letterSpacing)
            .padding(.vertical, (lineHeight - fontSize) / 2)
    }
}

// MARK: - Semantic Text Styles

extension View {

    func textStyle(_ style: TextStyle) -> some View {
        modifier(style.modifier)
    }
}

enum TextStyle {
    case display
    case headingXL
    case headingLG
    case headingMD
    case headingSM
    case bodyLarge
    case body
    case bodyMedium
    case label
    case labelBold
    case labelSemibold
    case caption
    case captionMedium
    case captionSemibold

    var modifier: AppTextStyle {
        switch self {
        case .display:
            return AppTextStyle(
                font: .system(size: AppFont.Size.display, weight: .bold),
                lineHeight: AppFont.LineHeight.display,
                fontSize: AppFont.Size.display,
                letterSpacing: AppFont.LetterSpacing.display
            )
        case .headingXL:
            return AppTextStyle(
                font: .system(size: AppFont.Size.headingXL, weight: .heavy),
                lineHeight: AppFont.LineHeight.headingXL,
                fontSize: AppFont.Size.headingXL,
                letterSpacing: AppFont.LetterSpacing.headingXL
            )
        case .headingLG:
            return AppTextStyle(
                font: .system(size: AppFont.Size.headingLG, weight: .semibold),
                lineHeight: AppFont.LineHeight.headingLG,
                fontSize: AppFont.Size.headingLG,
                letterSpacing: AppFont.LetterSpacing.headingLG
            )
        case .headingMD:
            return AppTextStyle(
                font: .system(size: AppFont.Size.headingMD, weight: .semibold),
                lineHeight: AppFont.LineHeight.headingMD,
                fontSize: AppFont.Size.headingMD,
                letterSpacing: AppFont.LetterSpacing.standard
            )
        case .headingSM:
            return AppTextStyle(
                font: .system(size: AppFont.Size.headingSM, weight: .bold),
                lineHeight: AppFont.LineHeight.headingSM,
                fontSize: AppFont.Size.headingSM,
                letterSpacing: AppFont.LetterSpacing.standard
            )
        case .bodyLarge:
            return AppTextStyle(
                font: .system(size: AppFont.Size.bodyLG, weight: .regular),
                lineHeight: AppFont.LineHeight.bodyLG,
                fontSize: AppFont.Size.bodyLG,
                letterSpacing: AppFont.LetterSpacing.standard
            )
        case .body:
            return AppTextStyle(
                font: .system(size: AppFont.Size.body, weight: .regular),
                lineHeight: AppFont.LineHeight.body,
                fontSize: AppFont.Size.body,
                letterSpacing: AppFont.LetterSpacing.standard
            )
        case .bodyMedium:
            return AppTextStyle(
                font: .system(size: AppFont.Size.body, weight: .medium),
                lineHeight: AppFont.LineHeight.body,
                fontSize: AppFont.Size.body,
                letterSpacing: AppFont.LetterSpacing.standard
            )
        case .label:
            return AppTextStyle(
                font: .system(size: AppFont.Size.label, weight: .medium),
                lineHeight: AppFont.LineHeight.label,
                fontSize: AppFont.Size.label,
                letterSpacing: AppFont.LetterSpacing.standard
            )
        case .labelBold:
            return AppTextStyle(
                font: .system(size: AppFont.Size.label, weight: .bold),
                lineHeight: AppFont.LineHeight.label,
                fontSize: AppFont.Size.label,
                letterSpacing: AppFont.LetterSpacing.standard
            )
        case .labelSemibold:
            return AppTextStyle(
                font: .system(size: AppFont.Size.label, weight: .semibold),
                lineHeight: AppFont.LineHeight.label,
                fontSize: AppFont.Size.label,
                letterSpacing: AppFont.LetterSpacing.standard
            )
        case .caption:
            return AppTextStyle(
                font: .system(size: AppFont.Size.caption, weight: .regular),
                lineHeight: AppFont.LineHeight.caption,
                fontSize: AppFont.Size.caption,
                letterSpacing: AppFont.LetterSpacing.standard
            )
        case .captionMedium:
            return AppTextStyle(
                font: .system(size: AppFont.Size.caption, weight: .medium),
                lineHeight: AppFont.LineHeight.caption,
                fontSize: AppFont.Size.caption,
                letterSpacing: AppFont.LetterSpacing.standard
            )
        case .captionSemibold:
            return AppTextStyle(
                font: .system(size: AppFont.Size.caption, weight: .semibold),
                lineHeight: AppFont.LineHeight.caption,
                fontSize: AppFont.Size.caption,
                letterSpacing: AppFont.LetterSpacing.standard
            )
        }
    }
}
