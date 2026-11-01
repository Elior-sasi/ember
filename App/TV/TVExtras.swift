import AVFoundation
import MediaPlayer
import Speech
import ActivityKit
import UIKit

/// The iPhone's own volume buttons change the TV's volume while the remote is open.
@MainActor
final class TVVolumeKeys: NSObject {
    static let shared = TVVolumeKeys()
    private var watch: NSKeyValueObservation?
    private let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 10, height: 10))
    private var base: Float = 0.5
    private var resetting = false

    func start() {
        guard watch == nil else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.ambient, options: [.mixWithOthers])
        try? s.setActive(true)
        if view.superview == nil, let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first { w.addSubview(view) }
        setVolume(0.5)
        watch = s.observe(\.outputVolume, options: [.new, .old]) { [weak self] _, ch in
            Task { @MainActor in
                guard let self, !self.resetting, let n = ch.newValue else { return }
                let up = n > self.base
                try? await TVRemote.shared.key(up ? 24 : 25)
                self.setVolume(0.5)
            }
        }
    }

    func stop() { watch?.invalidate(); watch = nil; view.removeFromSuperview() }

    private func setVolume(_ v: Float) {
        guard let slider = view.subviews.compactMap({ $0 as? UISlider }).first else { return }
        resetting = true; base = v
        slider.value = v
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.resetting = false }
    }
}

/// Hebrew dictation for the TV's search box.
@MainActor
final class TVDictation {
    static let shared = TVDictation()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var text = ""
    var onPartial: ((String) -> Void)?

    func start() async throws {
        let ok: Bool = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        guard ok, let rec = SFSpeechRecognizer(locale: Locale(identifier: "he-IL")), rec.isAvailable else { throw TVError.refused("speech") }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else { throw TVError.refused("mic") }
        stopNow()
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.record, mode: .measurement, options: .duckOthers)
        try s.setActive(true, options: .notifyOthersOnDeactivation)
        let req = SFSpeechAudioBufferRecognitionRequest(); req.shouldReportPartialResults = true
        request = req; text = ""
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in req.append(buf) }
        engine.prepare(); try engine.start()
        task = rec.recognitionTask(with: req) { [weak self] r, _ in
            guard let r else { return }
            let t = r.bestTranscription.formattedString
            Task { @MainActor in self?.text = t; self?.onPartial?(t) }
        }
    }

    func stop() async -> String {
        request?.endAudio()
        try? await Task.sleep(nanoseconds: 600_000_000)
        stopNow()
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        return text
    }

    private func stopNow() {
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        task?.cancel(); task = nil; request = nil
    }
}

/// The remote on the lock screen / Dynamic Island.
@MainActor
enum TVLive {
    static func set(_ on: Bool, name: String) async {
        for a in Activity<TVActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        guard on, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let st = TVActivityAttributes.ContentState(on: TVRemote.shared.powered ?? true, app: "")
        _ = try? Activity.request(attributes: TVActivityAttributes(name: name), content: .init(state: st, staleDate: nil))
    }
    static var isOn: Bool { !Activity<TVActivityAttributes>.activities.isEmpty }
}
