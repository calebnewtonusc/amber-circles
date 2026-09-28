import SwiftUI

// The v0 look, taken from Vercel's own system in ux-engine
// (systems/vercel/DESIGN.md), not eyeballed: Geist at 400/500/600 and never
// heavier, ink on white over a #fafafa page, #ebebeb hairlines, soft stacked
// shadows and never one heavy drop, and black pills for the main action.
// Caleb, 2026-09-27: "it should feel exactly like v0 by vercel". The first
// pass here was printed signage (2px borders, hard offset shadows, amber
// slabs), and in a phone chat it read as clunky: "why the UI/UX style so ugly".
// Sizes stay larger than Vercel's because the people using this may be older.
enum Amber {
    static let paper = Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255)
    static let sheet = Color.white
    static let ink = Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255)
    static let body = Color(red: 77 / 255, green: 77 / 255, blue: 77 / 255)
    /// Vercel's #888888 fails WCAG AA on white at small sizes; #666666 clears
    /// 5.7:1, which older eyes need more than the lighter grey.
    static let muted = Color(red: 102 / 255, green: 102 / 255, blue: 102 / 255)
    static let hairline = Color(red: 235 / 255, green: 235 / 255, blue: 235 / 255)
    static let wash = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
    /// Amber carries the actions now (Caleb: "amber color into the app, it
    /// shows more contrast with the apps being made, and it should still look
    /// like an Apple product"). #E8820C is deep enough for white 17pt bold
    /// text at 3:1, and close to Apple's own system orange.
    static let amber = Color(red: 232 / 255, green: 130 / 255, blue: 12 / 255)
    static let amberSoft = Color(red: 1, green: 244 / 255, blue: 229 / 255)
    static let link = Color(red: 0, green: 112 / 255, blue: 243 / 255)
    static let present = Color(red: 0, green: 112 / 255, blue: 243 / 255)
    /// iMessage's own bubble colours, for the conversation.
    static let iMessageBlue = Color(red: 10 / 255, green: 124 / 255, blue: 1)
    static let iMessageGrey = Color(red: 233 / 255, green: 233 / 255, blue: 235 / 255)
    static let danger = Color(red: 238 / 255, green: 0, blue: 0)

    enum Weight { case regular, bold, heavy }

    static func font(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        switch weight {
        case .regular: return .custom("Geist-Regular", size: size)
        case .bold: return .custom("Geist-Medium", size: size)
        case .heavy: return .custom("Geist-SemiBold", size: size)
        }
    }
}

extension View {
    /// Vercel headings track tight: -2.4px at 48, about -5% of the size.
    func headline() -> some View { self.tracking(-0.8) }
}

/// Vercel's buttons: a black pill for the one main action, a white pill with
/// a hairline for everything else. Pressing dims and shrinks it slightly.
struct BlockButton: ButtonStyle {
    var primary = false
    var full = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Amber.font(17, .bold))
            .foregroundStyle(primary ? Color.white : Amber.ink)
            .padding(.horizontal, 20)
            .frame(maxWidth: full ? .infinity : nil, minHeight: 50)
            .background(Capsule().fill(primary ? Amber.amber : Amber.sheet))
            .overlay(Capsule().strokeBorder(primary ? Color.clear : Amber.hairline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// A card: white, 12px corners, a hairline, and when lifted Vercel's
    /// stacked shadow (1px at 2% and 2px at 4%) instead of one heavy drop.
    func block(fill: Color = Amber.sheet, lifted: Bool = false) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Amber.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(lifted ? 0.02 : 0), radius: 0.5, x: 0, y: 1)
            .shadow(color: .black.opacity(lifted ? 0.04 : 0), radius: 1, x: 0, y: 2)
    }
}

/// A multi-line box you can type into, shaped like v0's prompt box.
struct Composer: View {
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(Amber.font(19))
            .foregroundStyle(Amber.ink)
            .lineLimit(2...6)
            .focused(focused)
            .padding(16)
            .frame(minHeight: 96, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Amber.sheet))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Amber.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 2)
    }
}
