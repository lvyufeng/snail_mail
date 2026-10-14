import CoreText
import SwiftUI
import UIKit

/// The retail build's own lettering, handed to SwiftUI as a registered face.
///
/// The 2005 game lettered its menus with the single strip it ships,
/// `OBJECTS/FONT/FONT-MENU-HOVER.TGA`, which `tools/make_font.py` turns back
/// into TrueType outlines. `tools/import_art.py` writes that face next to the
/// other retail art as `Art/Objects/SnailMailRetail.ttf`, and this registers it
/// with CoreText when the app first draws, so every label can be written in the
/// original's own letterforms through ordinary `Text` — wrapping, tinting and
/// letter spacing included.
enum RetailFont {

    /// The family name the generated face reports.
    static let family = "Snail Mail Retail"

    /// True when the face is in the bundle and CoreText took it, which needs
    /// the retail assets to be installed. Resolved once.
    static let available: Bool = register()

    /// The retail face at a point size, or the rounded system face of the same
    /// weight when the retail art is not installed.
    ///
    /// The strip carries cap heights of 20 px over a 28 px em, so the face set
    /// at a point size measures like the system face set at the same size and
    /// every existing label keeps its proportions.
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard available else { return .system(size: size, weight: weight, design: .rounded) }
        return .custom(family, size: size)
    }

    private static func register() -> Bool {
        guard let url = RetailAssets.url("Art/Objects/SnailMailRetail.ttf") else { return false }
        var error: Unmanaged<CFError>?
        // `false` also covers an already-registered face, so the check that
        // follows is what decides rather than this return value.
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        return UIFont(name: family, size: 12) != nil
    }
}

extension Font {
    /// Shorthand for `RetailFont.text(_:weight:)` at the call site.
    static func retail(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        RetailFont.text(size, weight: weight)
    }
}
