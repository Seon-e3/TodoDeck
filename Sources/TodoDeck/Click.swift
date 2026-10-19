import AVFoundation
import AppKit

/// 효과음. 녹음 파일 없이 짧은 파형을 직접 만든다.
enum Click {
    private static var engine = AVAudioEngine()
    private static var node = AVAudioPlayerNode()
    private static var deviceObserver: Any?
    private static let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    // 추가·체크: 높고 짧은 틱 / 손잡이로 숨기기·꺼내기: 낮고 묵직한 톡
    private static let tickSound = tone(freq: 3400, ms: 7, decay: 900, noise: 0.45, gain: 0.30)
    private static let key = tone(freq: 520, ms: 28, decay: 220, noise: 0.20, gain: 0.55)

    static func tick() { play(tickSound) }
    static func press() { play(key) }

    private static func play(_ buffer: AVAudioPCMBuffer) {
        if node.engine == nil { setUpEngine() }
        if !engine.isRunning { try? engine.start() }
        if !node.isPlaying { node.play() }
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
    }

    /// 출력 장치가 바뀌면(에어팟 연결 등) macOS가 엔진을 멈추고 내부 연결을 끊는다.
    /// 다시 켜기만 해서는 소리가 안 나므로 그때마다 엔진을 통째로 새로 만든다.
    private static func setUpEngine() {
        engine = AVAudioEngine()
        node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        deviceObserver.map(NotificationCenter.default.removeObserver)
        deviceObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
            setUpEngine()
        }
    }

    private static func tone(freq: Double, ms: Double, decay: Double, noise: Double, gain: Double) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(format.sampleRate * ms / 1000)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        buf.frameLength = n
        let out = buf.floatChannelData![0]
        for i in 0..<Int(n) {
            let t = Double(i) / format.sampleRate
            let s = sin(2 * .pi * freq * t) * (1 - noise) + Double.random(in: -1...1) * noise
            out[i] = Float(s * exp(-t * decay) * gain)
        }
        return buf
    }
}
