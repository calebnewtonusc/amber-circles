import SwiftUI

// The same signage system as the web app (DENY.md): paper, sheet, ink, and
// amber only on things you can tap. Atkinson Hyperlegible is bundled in both
// targets, because the Braille Institute drew it for exactly the readers this
// is for.
enum Amber {
    static let paper = Color(red: 242 / 255, green: 238 / 255, blue: 227 / 255)
    static let sheet = Color(red: 1, green: 252 / 255, blue: 245 / 255)
    static let ink = Color(red: 23 / 255, green: 21 / 255, blue: 15 / 255)
    static let body = Color(red: 46 / 255, green: 43 / 255, blue: 36 / 255)
    static let muted = Color(red: 92 / 255, green: 87 / 255, blue: 76 / 255)
    static let amber = Color(red: 1, green: 179 / 255, blue: 0)
    static let wash = Color(red: 1, green: 233 / 255, blue: 176 / 255)
    static let present = Color(red: 29 / 255, green: 107 / 255, blue: 63 / 255)
    static let danger = Color(red: 168 / 255, green: 50 / 255, blue: 31 / 255)

    enum Weight { case regular, bold, heavy }

    static func font(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        switch weight {
        case .regular: return .custom("AtkinsonHyperlegibleNext-Regular", size: size)
        case .bold: return .custom("AtkinsonHyperlegibleNext-Bold", size: size)
        case .heavy: return .custom("AtkinsonHyperlegibleNext-ExtraBold", size: size)
        }
    }
}

/// A block you can press: 2px ink border, hard 4px shadow, and it moves onto
/// its shadow while held. Amber fill only for the one main action.
struct BlockButton: ButtonStyle {
    var primary = false
    var full = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(Amber.font(19, .bold))
            .foregroundStyle(Amber.ink)
            .padding(.horizontal, 20)
            .frame(maxWidth: full ? .infinity : nil, minHeight: 52)
            .background(primary ? Amber.amber : Amber.sheet)
            .overlay(Rectangle().strokeBorder(Amber.ink, lineWidth: 2))
            .offset(x: pressed ? 4 : 0, y: pressed ? 4 : 0)
            .background(Rectangle().fill(Amber.ink).offset(x: 4, y: 4))
            .animation(.easeOut(duration: 0.09), value: pressed)
    }
}

extension View {
    /// A sheet surface: 2px ink border, optional hard shadow.
    func block(fill: Color = Amber.sheet, lifted: Bool = false) -> some View {
        self
            .background(fill)
            .overlay(Rectangle().strokeBorder(Amber.ink, lineWidth: 2))
            .background(Rectangle().fill(lifted ? Amber.ink : .clear).offset(x: 4, y: 4))
    }
}

/// A multi-line box you can type or talk into. The mic on the iPhone keyboard
/// is the voice input, so nothing here asks for microphone permission.
struct Composer: View {
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(Amber.font(20))
            .foregroundStyle(Amber.ink)
            .lineLimit(2...6)
            .focused(focused)
            .padding(14)
            .frame(minHeight: 84, alignment: .topLeading)
            .block()
    }
}
