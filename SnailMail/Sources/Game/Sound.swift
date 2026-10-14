import AVFoundation

/// A tiny procedural audio bank. Music and every effect are synthesised into
/// PCM buffers at runtime, so the project still ships no audio assets — the
/// sound side of the remake stays original like the art.
final class Sound {
    static let shared = Sound()

    enum Effect {
        case shoot, collect, upgrade, hit, boost, select, win, lose, fall
    }

    private let engine = AVAudioEngine()
    private let sfxNode = AVAudioPlayerNode()
    private let musicNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var effects: [String: AVAudioPCMBuffer] = [:]
    private var music: AVAudioPCMBuffer?
    private var ready = false

    private(set) var muted = false

    private init() {}

    /// Starts the engine and the looping background track. Safe to call on every
    /// appearance; it only boots once. Fails silently on machines without audio.
    func start() {
        guard !ready else { if !musicNode.isPlaying { startMusic() }; return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        engine.attach(sfxNode)
        engine.attach(musicNode)
        engine.connect(sfxNode, to: engine.mainMixerNode, format: format)
        engine.connect(musicNode, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.7
        sfxNode.volume = 0.9
        musicNode.volume = 0.32

        buildEffects()
        music = buildMusic()
        do { try engine.start() } catch { return }
        ready = true
        startMusic()
    }

    func setMuted(_ value: Bool) {
        muted = value
        musicNode.volume = value ? 0 : 0.32
        sfxNode.volume = value ? 0 : 0.9
    }

    func play(_ effect: Effect) {
        guard ready, !muted, let buffer = effects[key(effect)] else { return }
        sfxNode.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        if !sfxNode.isPlaying { sfxNode.play() }
    }

    private func startMusic() {
        guard ready, let music, !musicNode.isPlaying else { return }
        musicNode.scheduleBuffer(music, at: nil, options: [.loops], completionHandler: nil)
        musicNode.play()
    }

    private func key(_ effect: Effect) -> String {
        switch effect {
        case .shoot: "shoot"
        case .collect: "collect"
        case .upgrade: "upgrade"
        case .hit: "hit"
        case .boost: "boost"
        case .select: "select"
        case .win: "win"
        case .lose: "lose"
        case .fall: "fall"
        }
    }

    // MARK: - Synthesis

    private func buffer(duration: Double, _ sample: (Double) -> Double) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(max(1, duration * sr))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            channel[i] = Float(max(-1, min(1, sample(Double(i) / sr))))
        }
        return buffer
    }

    /// Square wave, close enough to the chiptune feel of the era.
    private func square(_ phase: Double) -> Double {
        (phase.truncatingRemainder(dividingBy: 1) < 0.5) ? 1 : -1
    }

    /// A tone that sweeps from `from` to `to` Hz with a simple decay envelope.
    private func sweep(from: Double, to: Double, duration: Double,
                       volume: Double, decay: Bool = true) -> AVAudioPCMBuffer {
        var phase = 0.0
        let sr = format.sampleRate
        return buffer(duration: duration) { t in
            let f = from + (to - from) * (t / duration)
            phase += f / sr
            let env = decay ? pow(1 - t / duration, 1.6) : 1
            return square(phase) * volume * env
        }
    }

    private func noise(duration: Double, volume: Double) -> AVAudioPCMBuffer {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        return buffer(duration: duration) { t in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r = Double((seed >> 33) & 0xFFFF) / 32768.0 - 1
            return r * volume * pow(1 - t / duration, 2)
        }
    }

    private func buildEffects() {
        effects["shoot"] = sweep(from: 1200, to: 420, duration: 0.09, volume: 0.28)
        effects["collect"] = sweep(from: 660, to: 1180, duration: 0.13, volume: 0.34)
        effects["upgrade"] = sweep(from: 520, to: 1560, duration: 0.26, volume: 0.36)
        effects["hit"] = noise(duration: 0.22, volume: 0.5)
        effects["boost"] = sweep(from: 300, to: 1100, duration: 0.3, volume: 0.3, decay: false)
        effects["select"] = sweep(from: 1400, to: 1400, duration: 0.05, volume: 0.24)
        effects["win"] = arpeggio([523.25, 659.25, 783.99, 1046.5], step: 0.11, volume: 0.32)
        effects["lose"] = arpeggio([523.25, 415.3, 329.6, 196.0], step: 0.14, volume: 0.32)
        // Falling down a hole: a long slide downward under a puff of dust.
        effects["fall"] = sweep(from: 900, to: 90, duration: 0.7, volume: 0.34, decay: false)
    }

    private func arpeggio(_ notes: [Double], step: Double, volume: Double) -> AVAudioPCMBuffer {
        let total = step * Double(notes.count)
        return buffer(duration: total) { t in
            let index = min(notes.count - 1, Int(t / step))
            let local = t - Double(index) * step
            let env = pow(max(0, 1 - local / step), 1.4)
            return square(t * notes[index]) * volume * env
        }
    }

    /// A four-bar loop: a driving bass, an arpeggio lead and a soft kick.
    private func buildMusic() -> AVAudioPCMBuffer {
        let bpm = 138.0
        let beat = 60.0 / bpm
        let bars = 4
        let total = beat * 4 * Double(bars)
        let roots = [110.0, 110.0, 146.83, 164.81]          // A A D E
        let arp = [440.0, 554.37, 659.25, 554.37, 493.88, 659.25, 880.0, 659.25]
        return buffer(duration: total) { t in
            let bar = min(bars - 1, Int(t / (beat * 4)))
            let root = roots[bar]
            let step = Int(t / (beat / 2)) % arp.count
            let bassPhase = t * root
            let leadPhase = t * arp[step]
            let beatPhase = t.truncatingRemainder(dividingBy: beat) / beat
            let kick = exp(-beatPhase * 12) * sin(2 * .pi * 55 * t)
            return square(bassPhase) * 0.16 + square(leadPhase) * 0.09 + kick * 0.25
        }
    }
}
