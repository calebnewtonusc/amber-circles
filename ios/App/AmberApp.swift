import SwiftUI

// The app itself only points at Messages: Amber lives in the thread, not here.
@main
struct AmberApp: App {
    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        Circle().fill(Amber.amber)
                            .frame(width: 24, height: 24)
                        Text("Amber").font(Amber.font(26, .heavy)).foregroundStyle(Amber.ink)
                    }
                    Text("Amber lives in Messages.").font(Amber.font(38, .heavy)).foregroundStyle(Amber.ink)
                    step(1, "Open any group chat, or a chat with one person.")
                    step(2, "Tap the plus next to the message box, then More, then Amber.")
                    step(3, "Say what the chat needs. Everyone in it can open it and change it.")
                }
                .padding(24)
            }
            .background(Amber.paper.ignoresSafeArea())
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)").font(Amber.font(28, .heavy)).foregroundStyle(Amber.ink)
                .frame(width: 44, height: 44).background(Circle().fill(Amber.wash))
            Text(text).font(Amber.font(20)).foregroundStyle(Amber.body)
        }
    }
}
