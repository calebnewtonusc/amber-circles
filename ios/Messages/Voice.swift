import AVFoundation
import Speech
import SwiftUI
import UIKit

/// Hold to talk, let go to send. Caleb, 2026-09-27: "a little voice button at
/// the bottom. You hold it down. Like, hey, this button here doesn't really
/// make sense." Recognition runs on the phone, so nothing is recorded or kept.
@MainActor
final class Listener: ObservableObject {
    @Published var text = ""
    @Published var isListening = false
    @Published var problem: String?

    private let engine = AVAudioEngine()
    private let feed = Feed()
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var wantsToListen = false
    /// Everything already heard. The on-device recognizer ends its task
    /// after a pause or about a minute, and each new stretch comes back on its
    /// own, so only the last chunk of a long message was being sent (Caleb,
    /// 2026-09-27). Finished stretches are kept here and a fresh task picks up.
    private var kept = ""
    private var current = ""

    /// The audio tap runs off the main thread; it feeds whichever request is
    /// live right now.
    private final class Feed: @unchecked Sendable {
        private let lock = NSLock()
        private var request: SFSpeechAudioBufferRecognitionRequest?
        func set(_ next: SFSpeechAudioBufferRecognitionRequest?) { lock.lock(); request = next; lock.unlock() }
        func append(_ buffer: AVAudioPCMBuffer) { lock.lock(); request?.append(buffer); lock.unlock() }
        func end() { lock.lock(); request?.endAudio(); lock.unlock() }
    }

    private func joined() -> String {
        [kept, current].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// A new recognition task on the same running microphone.
    private func nextStretch() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true { request.requiresOnDeviceRecognition = true }
        feed.set(request)
        task = recognizer?.recognitionTask(with: request) { result, error in
            let words = result?.bestTranscription.formattedString
            let ended = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in
                if let words {
                    // A transcript that suddenly shrinks is a new stretch
                    // starting inside the same task: keep what came before.
                    if !self.current.isEmpty, words.count < self.current.count / 2 { self.kept = self.joined(); }
                    self.current = words
                    self.text = self.joined()
                }
                if ended, self.wantsToListen, self.isListening {
                    self.kept = self.joined()
                    self.current = ""
                    self.nextStretch()
                }
            }
        }
    }

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
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = engine.inputNode
            input.removeTap(onBus: 0)
            let feed = self.feed
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                feed.append(buffer)
            }
            engine.prepare()
            try engine.start()
            text = ""
            kept = ""
            current = ""
            isListening = true
            nextStretch()
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
        feed.end()
        try? await Task.sleep(for: .milliseconds(600))
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        task?.finish()
        feed.set(nil)
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The big button. Amber, because it is the one thing on screen you press.
struct HoldToTalk: View {
    @EnvironmentObject var store: ChatStore
    @StateObject private var listener = Listener()
    var label = "Hold to talk"
    /// Pressing talk cuts Amber off at once, before the microphone opens
    /// (Chewbacca docs/VOICE-DESIGN.md, "Interrupting").
    var onPress: () -> Void = {}
    let onHeard: (String) -> Void
    @State private var pressing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: listener.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 22, weight: .bold))
                    .symbolEffect(.variableColor.iterative, isActive: listener.isListening)
                Text(listener.isListening ? "Listening. Let go to send" : label)
                    .font(Amber.font(18, .bold))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Capsule().fill(Amber.amber))
            .shadow(color: Amber.amber.opacity(listener.isListening ? 0.45 : 0.25), radius: listener.isListening ? 16 : 8, y: 4)
            .overlay(Capsule().strokeBorder(Color.white.opacity(listener.isListening ? 0.35 : 0), lineWidth: 3).padding(3))
            .scaleEffect(pressing ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: pressing)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressing else { return }
                        pressing = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onPress()
                        listener.start()
                    }
                    .onEnded { _ in
                        pressing = false
                        Task {
                            let heard = await listener.stop()
                            store.speaker.listening = false
                            // The live bubble stays until the message takes
                            // its place, so letting go does not bounce it in
                            // a second time.
                            if heard.isEmpty { store.liveSpeech = nil } else { onHeard(heard) }
                        }
                    }
            )
            .onChange(of: listener.text) { _, words in
                if listener.isListening { store.liveSpeech = words }
            }
            .onChange(of: listener.isListening) { _, on in
                if on { store.speaker.stop(); store.speaker.listening = true; store.liveSpeech = "" }
            }
            .accessibilityLabel(label)
            .accessibilityHint("Hold, say it, then let go")
            if let problem = listener.problem {
                Text(problem).font(Amber.font(16, .bold)).foregroundStyle(Amber.danger)
            }
        }
    }
}

/// Amber's replies, out loud, in the ElevenLabs voice the server picks. A
/// conversation you can have with your phone at arm's length.
@MainActor
final class Speaker: NSObject, ObservableObject, AVAudioPlayerDelegate {
    /// Always on (Caleb, 2026-09-27: "just have it so amber always talks back
    /// to save screen space").
    let isOn = true
    @Published var isSpeaking = false
    /// True while someone holds the talk pill. Speaking switches the audio
    /// session to playback, which cut the microphone off mid-sentence every
    /// time a build narrated (Caleb, 2026-09-27: long messages lost their
    /// start, and talking mid-build did not work). Amber stays quiet then;
    /// its words still arrive as texts.
    var listening = false
    private var player: AVAudioPlayer?

    func say(_ text: String, token: String) async {
        guard isOn, !text.isEmpty, !listening else { return }
        var request = URLRequest(url: API.base.appendingPathComponent("api/speak"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(token, forHTTPHeaderField: "x-amber-chat")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": String(text.prefix(700))])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, !listening else { return }
        do {
            // Plain playback, not play-and-record: iOS refuses play-and-record
            // until the microphone is allowed, so someone who only typed never
            // heard Amber at all (Caleb's phone, build 41). Playback also plays
            // with the silent switch on, which is what a reply should do.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            player = try AVAudioPlayer(data: data)
            player?.delegate = self
            isSpeaking = true
            player?.play()
        } catch {
            isSpeaking = false
        }
    }

    func stop() { player?.stop(); isSpeaking = false }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
