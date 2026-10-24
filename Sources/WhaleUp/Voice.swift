import AppKit
import AVFoundation
import CryptoKit
import WhaleUpCore

/// 桌宠的声音：优先用微软在线语音（edge-tts，二次元一点的少女音），生成的音频按句缓存；
/// 没装、没网、或者 6 秒内没生成出来，就改用系统语音，保证一定有声音。
@MainActor
final class Voice: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    /// 可选的声音：(id, 名字)。id 为 system 时用系统语音
    static let choices: [(id: String, name: String)] = [
        ("zh-CN-XiaoyiNeural", "晓伊（活泼少女，推荐）"),
        ("zh-CN-XiaoxiaoNeural", "晓晓（温柔）"),
        ("zh-CN-liaoning-XiaobeiNeural", "晓北（东北话）"),
        ("zh-TW-HsiaoYuNeural", "曉雨（台湾腔）"),
        ("system", "系统语音（离线）"),
    ]

    nonisolated static var supportDir: URL { Config.fileURL.deletingLastPathComponent() }
    nonisolated static var cli: URL { supportDir.appendingPathComponent("tts/bin/edge-tts") }
    nonisolated static var cacheDir: URL { supportDir.appendingPathComponent("voice-cache") }
    static var onlineAvailable: Bool { FileManager.default.isExecutableFile(atPath: cli.path) }

    var voiceID = "zh-CN-XiaoyiNeural"
    var onStart: () -> Void = {}
    var onFinish: () -> Void = {}

    private var player: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()
    /// 每次说话 +1；生成慢了、已经有新的话要说时，丢掉旧的
    private var token = 0

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        stop()
        token += 1
        let current = token
        guard voiceID != "system", Self.onlineAvailable else { return systemSpeak(text) }
        let file = Self.cacheFile(text: text, voice: voiceID)
        if FileManager.default.fileExists(atPath: file.path) { return play(file) }
        let voice = voiceID
        Task.detached {
            let ok = Self.generate(text: text, voice: voice, to: file)
            await MainActor.run {
                guard current == self.token else { return }
                if ok { self.play(file) } else { self.systemSpeak(text) }
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        onFinish()
    }

    private func play(_ file: URL) {
        guard let p = try? AVAudioPlayer(contentsOf: file) else { return }
        p.delegate = self
        player = p
        p.play()
        onStart()
    }

    private func systemSpeak(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.pitchMultiplier = 1.4
        u.rate = 0.52
        synth.speak(u)
    }

    nonisolated static func cacheFile(text: String, voice: String) -> URL {
        let digest = SHA256.hash(data: Data("\(voice)|+12Hz|+8%|\(text)".utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(String(digest.prefix(32)) + ".mp3")
    }

    /// 调用 edge-tts 生成音频；6 秒没完成就放弃
    nonisolated static func generate(text: String, voice: String, to file: URL) -> Bool {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let tmp = file.deletingPathExtension().appendingPathExtension("part.mp3")
        let p = Process()
        p.executableURL = cli
        p.arguments = ["--voice", voice, "--pitch=+12Hz", "--rate=+8%", "--text", text, "--write-media", tmp.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        let deadline = Date().addingTimeInterval(6)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { p.terminate(); return false }
        guard p.terminationStatus == 0,
              let size = (try? FileManager.default.attributesOfItem(atPath: tmp.path))?[.size] as? Int, size > 1000 else {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
        try? FileManager.default.removeItem(at: file)
        return (try? FileManager.default.moveItem(at: tmp, to: file)) != nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.onFinish() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        Task { @MainActor in self.onStart() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish() }
    }
}
