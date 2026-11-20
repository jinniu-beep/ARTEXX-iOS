import AVFoundation
import Foundation
import UIKit

/// 后台保活：iOS 默认会在 App 进入后台约 30 秒后挂起进程，冻结所有线程——内置 Go 后端
/// 的渗透任务 goroutine 会随之停住。这里用 `audio` 后台模式 + 循环播放一段【静音】音频，
/// 让系统以为 App 在放音乐而不挂起它，从而让后台任务继续跑;并用 beginBackgroundTask 作
/// 为切换瞬间的缓冲。
///
/// 代价（如实）：Apple 不允许此用法上架（侧载不过审，故可用）；明显耗电；来电或别的 App
/// 抢占音频焦点时可能被打断；系统内存紧张仍可能回收 App。不是 100% 永久后台。
final class BackgroundKeeper {
    static let shared = BackgroundKeeper()

    private var player: AVAudioPlayer?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    private var started = false
    private let defaultsKey = "artex.backgroundKeepAlive"

    /// 是否启用（默认开；用户可通过 setEnabled 关掉省电）。
    var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: defaultsKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: defaultsKey)
        if !on { stopAudio() }
    }

    /// 在 App 启动时调用一次：配置音频会话、挂生命周期监听。
    func start() {
        guard !started else { return }
        started = true
        configureSession()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(didEnterBackground),
                       name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(willEnterForeground),
                       name: UIApplication.willEnterForegroundNotification, object: nil)
        // 音频被电话等打断后，结束时恢复播放。
        nc.addObserver(self, selector: #selector(handleInterruption),
                       name: AVAudioSession.interruptionNotification, object: nil)
    }

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        // .playback + .mixWithOthers：后台可发声且不打断用户正在听的音乐。
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    @objc private func didEnterBackground() {
        guard isEnabled else { return }
        beginBg()
        startAudio()
    }

    @objc private func willEnterForeground() {
        endBg()
        // 回到前台任务本就在跑，停掉静音播放省电。
        stopAudio()
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard isEnabled,
              let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .ended {
            try? AVAudioSession.sharedInstance().setActive(true)
            if UIApplication.shared.applicationState != .active { startAudio() }
        }
    }

    private func beginBg() {
        endBg()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "artex.keepalive") { [weak self] in
            self?.endBg()
        }
    }

    private func endBg() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }

    private func startAudio() {
        if player == nil { player = makeSilentPlayer() }
        guard let p = player else { return }
        p.numberOfLoops = -1
        p.volume = 0
        if !p.isPlaying { p.play() }
    }

    private func stopAudio() {
        player?.stop()
    }

    /// 内存里合成一段 1 秒静音 WAV（16-bit PCM 单声道），不必往 bundle 里塞音频文件。
    private func makeSilentPlayer() -> AVAudioPlayer? {
        let data = BackgroundKeeper.silentWAV(seconds: 1)
        let p = try? AVAudioPlayer(data: data)
        p?.prepareToPlay()
        return p
    }

    private static func silentWAV(seconds: Int) -> Data {
        let sampleRate = 8000
        let numSamples = sampleRate * max(1, seconds)
        let dataSize = numSamples * 2 // 16-bit mono
        func le32(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }
        func le16(_ v: UInt16) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 2) }
        var d = Data()
        d.append("RIFF".data(using: .ascii)!)
        d.append(le32(UInt32(36 + dataSize)))
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!)
        d.append(le32(16))                       // PCM fmt chunk size
        d.append(le16(1))                        // audio format = PCM
        d.append(le16(1))                        // channels = mono
        d.append(le32(UInt32(sampleRate)))       // sample rate
        d.append(le32(UInt32(sampleRate * 2)))   // byte rate
        d.append(le16(2))                        // block align
        d.append(le16(16))                       // bits per sample
        d.append("data".data(using: .ascii)!)
        d.append(le32(UInt32(dataSize)))
        d.append(Data(count: dataSize))          // silence
        return d
    }
}
