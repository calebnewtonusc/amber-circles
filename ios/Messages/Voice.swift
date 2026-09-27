import AVFoundation
import Speech
import SwiftUI

/// Hold to talk, let go to send. Caleb, 2026-09-27: "a little voice button at
/// the bottom. You hold it down. Like, hey, this button here doesn't really
/// make sense." Recognition runs on the phone, so nothing is recorded or kept.
@MainActor
final class Listener: ObservableObject {
    @Published var text = ""
    @Published var isListening = false
    @Published var problem: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var wantsToListen = false

    func start() {
        wantsToListen = true
        problem = nil
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.problem = "To talk, turn on Speech Recognition for Amber in Settings."
                    return
                }
                AVAudioApplication.requestRecordPermission { allowed in
                    Task { @MainActor in
                        guard allowed else {
                            self.problem = "To talk, turn on the microphone for Amber in Settings."
                            return
                        }
                        if self.wantsToListen { self.begin() }
                    }
                }
            }
        }
    }

    private func begin() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer?.supportsOnDeviceRecognition == true { request.requiresOnDeviceRecognition = true }
            self.request = request
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
            text = ""
            isListening = true
            task = recognizer?.recognitionTask(with: request) { result, _ in
                guard let words = result?.bestTranscription.formattedString else { return }
                Task { @MainActor in self.text = words }
            }
        } catch {
            problem = "The microphone didn't start. Try again."
            isListening = false
        }
    }

    /// Stops listening and hands back what was heard, after a beat for the
    /// last words to land.
    func stop() async -> String {
        wantsToListen = false
        guard isListening else { return "" }
        request?.endAudio()
        try? await Task.sleep(for: .milliseconds(600))
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        task?.finish()
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The big button. Amber, because it is the one thing on screen you press.
struct HoldToTalk: View {
    @StateObject private var listener = Listener()
    var label = "Hold to talk"
    let onHeard: (String) -> Void
    @State private var pressing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: listener.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 22, weight: .bold))
                    .symbolEffect(.variableColor.iterative, isActive: listener.isListening)
                Text(listener.isListening ? (listener.text.isEmpty ? "Listening…" : listener.text) : label)
                    .font(Amber.font(19, .bold))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Amber.ink)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(listener.isListening ? Amber.wash : Amber.amber)
            .overlay(Rectangle().strokeBorder(Amber.ink, lineWidth: 2))
            .offset(x: pressing ? 4 : 0, y: pressing ? 4 : 0)
            .background(Rectangle().fill(Amber.ink).offset(x: 4, y: 4))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressing else { return }
                        pressing = true
                        listener.start()
                    }
                    .onEnded { _ in
                        pressing = false
                        Task {
                            let heard = await listener.stop()
                            if !heard.isEmpty { onHeard(heard) }
                        }
                    }
            )
            .accessibilityLabel(label)
            .accessibilityHint("Hold, say it, then let go")
            if let problem = listener.problem {
                Text(problem).font(Amber.font(16, .bold)).foregroundStyle(Amber.danger)
            }
        }
    }
}
