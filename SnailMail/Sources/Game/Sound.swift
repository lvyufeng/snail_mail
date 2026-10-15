import AVFoundation

/// The game's audio.
///
/// When `tools/import_art.py` has decoded the retail installer into the bundle
/// the game plays the 2005 build's own music, effects and snail voice — the
/// `.ogg` files the original shipped, re-encoded to AAC. On a checkout without
/// that folder every lookup here fails and the synthesised bank takes over, so
/// the remake is never silent.
///
/// The original's `Voice/_Voice.txt` sets the balance between the three buses:
/// `NormalizeMusic:50`, `NormalizeSfx:40`, `NormalizeVoice:100`, and asks for a
/// spoken line roughly every `Frequency:20` seconds. Both are honoured below.
final class Sound {
    static let shared = Sound()

    /// Which background track a screen wants. The retail build keeps four race
    /// tracks plus a menu and an intro theme.
    enum Music: Equatable {
        case menu, intro, race(Int)

        var retailPath: String {
            switch self {
            case .menu: "Audio/Music/mainmenu.m4a"
            case .intro: "Audio/Music/introtext.m4a"
            case .race(let track): "Audio/Music/\(abs(track) % 4 + 1).m4a"
            }
        }
    }

    enum Effect {
        case shoot(Int)       // the shot mesh the rung picked, 1...3
        case enemyFire
        case collect          // parcel picked up
        case deliver          // parcels handed over at the post office
        case upgrade(Int)     // power-up ring, indexed by the rung reached
        case hit              // fence, pillar, slug, salt
        case asteroid
        case boost
        case jetpack
        case skid
        case heart
        case extraLife
        case slow             // slow ring
        case explodeRing
        case invincible
        case trampoline
        case select
        case highlight
        case servo            // star-map cursor
        case win
        case perfect          // the whole quota handed over without a scratch
        case lose
        case fall
    }

    /// The snail's spoken lines, one case per set `Voice/_Voice.txt` declares.
    enum Voice {
        case start, victory, damage, ouch, dying, fall, package
        case powerup, slow, enemies, postal, misc, wormTunnel, superTramp, slugged

        var lines: [String] {
            switch self {
            case .start:
                ["allowsixtoeightminutes", "bringiton", "ifeeltheneedforspeed", "justryandstopme",
                 "thisisajob", "turbosthename", "watchout", "zoomzoom",
                 "snailmailalwaysontime", "snailmailinthirtyminutes"]
            case .victory:
                ["howsthatforexpressservice", "ideserveapromotion", "ideservearaise", "igotahotfoot",
                 "imthesnail", "ontimeandfeelingfine", "somebodypinchme"]
            case .damage:
                ["heyijustwaxed", "imgonnaneedanewshell", "itburns", "myeyes",
                 "thatsgonnaleaveamark", "uhoh"]
            case .dying:
                ["abandonshell", "imfallingandicantgetup", "ineedanewjob", "notcool",
                 "thisisnotmyday"]
            // `Set:Slugged` — the lines Turbo keeps for dying to a slug rather
            // than to the track, hence the smaller set shared with `Dying`.
            case .slugged:
                ["ineedanewjob", "notcool", "thisisnotmyday"]
            case .ouch:
                ["ow1", "ow2", "ow3", "ow4"]
            case .fall:
                ["fall1", "fall2", "fall3"]
            case .package:
                ["postagedue", "somebodycallforadelivery", "specialdelivery", "speedydelivery"]
            case .powerup:
                ["fullyloaded", "hellinashell", "imonfire", "imonfirebaby", "impackin",
                 "mynewmailingtechnique", "myshellistrickedout", "smokin", "somebodystopme",
                 "trailblazer", "thatwasawesome"]
            case .slow:
                ["amievenmoving", "anyslower", "comeon", "fasterisbetter", "icandobetter",
                 "fasterwouldbebetter", "isleepfasterthanthis"]
            case .enemies:
                ["alwaystipyourmailcarrier", "alwaystipyourpostalworker", "backoff",
                 "backoffslugs", "comingthrough", "makeway"]
            case .postal:
                ["imgoingpostal", "imgoingpostal2", "imgoingpostal3"]
            case .wormTunnel:
                ["whoahdude", "zippidydoodah", "whohohohoah"]
            case .superTramp:
                ["whoahdude", "woohoo", "whohohohoah"]
            case .misc:
                ["checkmeout", "donthateme", "footache", "gotmail", "isurecoulduse",
                 "itsnotjustashell", "mynameisturbo", "partfootparttummy", "snailsinspace",
                 "thatwascool", "hellinashell", "trailblazer", "escargot"]
            }
        }
    }

    /// The slugs' own voice, which the retail build never lists in
    /// `_Voice.txt` — the eleven `slug-*.ogg` clips are hard-wired to slug
    /// events in the executable. The snail taunts them and they answer: they
    /// call out when they lunge, they grunt and die when shot, and they gloat
    /// when one of them takes Turbo down.
    enum SlugVoice {
        case attack   // a slug has the snail in its sights
        case killed   // struck by the snail's fire and dying
        case gloat    // the slug that took Turbo down, crowing over it

        var lines: [String] {
            switch self {
            case .attack: ["slug-snailalert", "slug-gothim", "slug-hestoofast"]
            case .killed: ["slug-hit1", "slug-hit2", "slug-hit3",
                           "slug-destroy", "slug-death1", "slug-death2"]
            case .gloat:  ["slug-victory", "slug-victory2"]
            }
        }
    }

    private let engine = AVAudioEngine()
    /// The synthesised bank's buses.
    private let sfxNode = AVAudioPlayerNode()
    private let musicNode = AVAudioPlayerNode()
    /// The retail sample buses. Effects fire often enough to overlap, so they
    /// round-robin over a small pool instead of cutting each other off.
    private let retailMixer = AVAudioMixerNode()
    private let voiceNode = AVAudioPlayerNode()
    /// The slugs talk on their own node so a slug's line and the snail's can
    /// stack, exactly as two separate speakers do in the retail mix.
    private let slugVoiceNode = AVAudioPlayerNode()
    /// The "going postal" alarm loops on its own node, so it can run under the
    /// shots and voices and be cut off the moment the meter climbs back.
    private let postalNode = AVAudioPlayerNode()
    private var retailNodes: [AVAudioPlayerNode] = []
    private var retailCursor = 0
    private var postalAlarmOn = false

    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private let musicFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

    private var effects: [String: AVAudioPCMBuffer] = [:]
    private var sounds: [String: AVAudioPCMBuffer] = [:]
    private var musicSelection: Music?
    private var musicBuffer: AVAudioPCMBuffer?
    private var flips: [String: Int] = [:]
    private var ready = false
    /// The store the levels were read from, so a write lands where the read
    /// came from instead of always in `.standard`.
    private let defaults: UserDefaults
    /// Whether the session observers have been installed, so `start()` can be
    /// called on every appearance without stacking them up.
    private var observing = false

    private(set) var muted = false

    /// User-facing volume levels, 0...1, scaling the balanced defaults the
    /// retail `_Voice.txt` asks for. The Options screen's "Sounds Volume"
    /// (`0x4df958`) and "Music Volume" (`0x4df95c`) rows drive these, and they
    /// persist between launches. A fresh `SnailMail.cfg` ships both at
    /// `0x3f19999a` (0.6), and the rows step them by 0.2.
    private(set) var musicLevel: Double
    private(set) var sfxLevel: Double

    private static let synthMusic: Float = 0.32
    private static let synthSfx: Float = 0.9
    /// NormalizeMusic:50 / NormalizeSfx:40 / NormalizeVoice:100 of `_Voice.txt`,
    /// scaled to sit at the same loudness as the synthesised bank.
    private static let retailMusic: Float = 0.55
    private static let retailSfx: Float = 0.8
    private static let voice: Float = 1.0
    /// `Frequency:20` — how often the original lets the snail speak.
    private static let voiceInterval: TimeInterval = 20
    /// How long Turbo stays quiet before idle banter (see `chatter()`).
    private static let chatterInterval: TimeInterval = 26

    private var voiceBusy = false
    private var lastVoiceAt: TimeInterval = -1000
    private var lastVoiceLine: String?

    /// The slug bank keeps its own clock and its own "already saying" flag: the
    /// snail's line must not swallow a slug's, nor a slug's the snail's.
    private static let slugVoiceInterval: TimeInterval = 1.2
    private var slugVoiceBusy = false
    private var lastSlugVoiceAt: TimeInterval = -1000
    private var lastSlugVoiceLine: String?

    private enum Key {
        static let music = "audio.musicLevel"
        static let sfx = "audio.sfxLevel"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedMusic = defaults.object(forKey: Key.music) as? Double
        let storedSfx = defaults.object(forKey: Key.sfx) as? Double
        musicLevel = storedMusic ?? 0.6
        sfxLevel = storedSfx ?? 0.6
        retailNodes = (0..<6).map { _ in AVAudioPlayerNode() }
    }

    /// Starts the engine. Safe to call on every appearance; it only boots once.
    /// Fails silently on machines without audio.
    func start() {
        guard !ready else {
            // A call, Siri, a route change or a media-services reset stops the
            // engine out from under us, and every node goes quiet with it. The
            // observers below mark the engine dead; rebooting it here means the
            // next screen to ask for sound gets a working one.
            if !engine.isRunning { reboot(); return }
            if let buffer = musicBuffer, !musicNode.isPlaying { scheduleMusic(buffer) }
            return
        }
        observeSession()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        engine.attach(sfxNode)
        engine.attach(musicNode)
        engine.attach(retailMixer)
        engine.attach(voiceNode)
        engine.attach(slugVoiceNode)
        engine.attach(postalNode)
        engine.connect(sfxNode, to: engine.mainMixerNode, format: format)
        engine.connect(musicNode, to: engine.mainMixerNode, format: musicFormat)
        engine.connect(retailMixer, to: engine.mainMixerNode, format: format)
        engine.connect(voiceNode, to: engine.mainMixerNode, format: format)
        engine.connect(slugVoiceNode, to: engine.mainMixerNode, format: format)
        // The alarm rides the effects bus, so the Options screen's sound level
        // and the mute toggle both reach it without extra bookkeeping.
        engine.connect(postalNode, to: retailMixer, format: format)
        for node in retailNodes {
            engine.attach(node)
            engine.connect(node, to: retailMixer, format: format)
        }
        engine.mainMixerNode.outputVolume = 0.7

        buildEffects()
        applyVolumes()
        do { try engine.start() } catch { return }
        ready = true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-audiotest") { runSelfTest() }
        #endif
    }

    /// Watch the session so a silence the system imposed can be undone. The
    /// engine posts its own configuration-change notice when the hardware moves
    /// under it, which is the case a route change does not cover.
    private func observeSession() {
        guard !observing else { return }
        observing = true
        let centre = NotificationCenter.default
        centre.addObserver(forName: AVAudioSession.interruptionNotification,
                           object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard let raw, AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self?.reboot()
        }
        centre.addObserver(forName: AVAudioSession.routeChangeNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.reboot()
        }
        centre.addObserver(forName: .AVAudioEngineConfigurationChange,
                           object: engine, queue: .main) { [weak self] _ in
            self?.reboot()
        }
    }

    /// Re-arm the engine and every node that was playing on it. The nodes keep
    /// their scheduled buffers, so restarting the engine resumes the track where
    /// it was instead of resynthesising it.
    private func reboot() {
        guard ready, !engine.isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
        do { try engine.start() } catch { return }
        // A node only plays its queue from the moment `play()` is called, and a
        // stopped engine forgets that it was playing at all.
        if let buffer = musicBuffer, !musicNode.isPlaying { scheduleMusic(buffer) }
        if postalAlarmOn, !postalNode.isPlaying { postalNode.play() }
    }

#if DEBUG
    /// `-audiotest` decodes every clip the game can ask for and writes a report
    /// beside the app's temporary files. The simulator has no speakers to check
    /// by ear, so this is how the retail audio path gets verified: a wrong
    /// bundle path or a converter that refuses a file shows up as MISSING.
    private func runSelfTest() {
        var lines = ["retail: \(RetailAssets.installed ? "installed" : "missing")"]
        for music in [Music.menu, .intro, .race(0), .race(1), .race(2), .race(3)] {
            lines.append("music \(music.retailPath): \(describe(retail(music.retailPath, format: musicFormat)))")
        }
        let effects: [Effect] = [.shoot(1), .shoot(2), .shoot(3), .enemyFire, .collect, .deliver,
                                 .upgrade(1), .upgrade(7), .hit, .asteroid, .boost, .jetpack,
                                 .skid, .heart, .extraLife, .slow, .explodeRing, .invincible,
                                 .trampoline, .select, .highlight, .servo, .win, .perfect]
        for effect in effects {
            let name = retailName(effect)
            let buffer = name.flatMap { retail($0, format: format) }
            lines.append("sfx \(name ?? "-"): \(describe(buffer))")
        }
        lines.append("sfx postalloop: \(describe(retail("Audio/Sfx/postalloop.m4a", format: format)))")
        var spoken = 0
        var missing: [String] = []
        for voice in [Voice.start, .victory, .damage, .ouch, .dying, .fall, .package, .powerup,
                      .slow, .enemies, .postal, .misc, .wormTunnel, .superTramp, .slugged] {
            for line in voice.lines {
                spoken += 1
                if retail("Audio/Voice/\(line).m4a", format: format) == nil { missing.append(line) }
            }
        }
        for voice in [SlugVoice.attack, .killed, .gloat] {
            for line in voice.lines {
                spoken += 1
                if retail("Audio/Voice/\(line).m4a", format: format) == nil { missing.append(line) }
            }
        }
        for line in TrackData.tutorialVoice.compactMap({ $0 }) {
            spoken += 1
            if retail("Audio/Voice/\(line).m4a", format: format) == nil { missing.append(line) }
        }
        lines.append("voice: \(spoken) lines, \(missing.count) missing \(missing.joined(separator: ","))")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audiotest.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func describe(_ buffer: AVAudioPCMBuffer?) -> String {
        guard let buffer else { return "MISSING" }
        return String(format: "ok %.2fs %dch %gHz",
                      Double(buffer.frameLength) / buffer.format.sampleRate,
                      Int(buffer.format.channelCount),
                      buffer.format.sampleRate)
    }
#endif

    func setMuted(_ value: Bool) {
        muted = value
        applyVolumes()
    }

    func setMusicLevel(_ value: Double) {
        musicLevel = max(0, min(1, value))
        defaults.set(musicLevel, forKey: Key.music)
        applyVolumes()
    }

    func setSfxLevel(_ value: Double) {
        sfxLevel = max(0, min(1, value))
        defaults.set(sfxLevel, forKey: Key.sfx)
        applyVolumes()
    }

    private func applyVolumes() {
        let installed = hasRetailAudio
        musicNode.volume = muted ? 0 : (installed ? Self.retailMusic : Self.synthMusic) * Float(musicLevel)
        sfxNode.volume = muted ? 0 : Self.synthSfx * Float(sfxLevel)
        retailMixer.volume = muted ? 0 : Self.retailSfx * Float(sfxLevel)
        voiceNode.volume = muted ? 0 : Self.voice * Float(sfxLevel)
        slugVoiceNode.volume = muted ? 0 : Self.voice * Float(sfxLevel)
    }

    // MARK: - Music

    /// Swaps the background track. Asking for the track that is already playing
    /// is a no-op, so a screen can name its theme on every appearance.
    func playMusic(_ music: Music) {
        if musicSelection == music, let buffer = musicBuffer {
            if ready, !musicNode.isPlaying { scheduleMusic(buffer) }
            return
        }
        musicSelection = music
        musicBuffer = retail(music.retailPath, format: musicFormat) ?? buildMusic()
        guard ready, let buffer = musicBuffer else { return }
        musicNode.stop()
        scheduleMusic(buffer)
    }

    private func scheduleMusic(_ buffer: AVAudioPCMBuffer) {
        musicNode.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        if !musicNode.isPlaying { musicNode.play() }
    }

    // MARK: - Effects

    func play(_ effect: Effect) {
        guard ready, !muted else { return }
        if let name = retailName(effect), let buffer = retail(name, format: format) {
            let node = retailNodes[retailCursor % retailNodes.count]
            retailCursor += 1
            // Queued, not interrupting: the pool exists so that shots landing
            // close together overlap. With `.interrupts` the node the round
            // robin comes back to would cut off whatever it was still playing,
            // which is exactly the case the pool is here to cover.
            node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            if !node.isPlaying { node.play() }
            return
        }
        guard let buffer = effects[synthKey(effect)] else { return }
        sfxNode.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        if !sfxNode.isPlaying { sfxNode.play() }
    }

    /// The "going postal" alarm. The tutorial warns that too much damage sends
    /// Turbo postal, and the retail build loops `postalloop` under a meter in
    /// the red until he claws it back. `on` is edge-triggered, so it is safe to
    /// call every frame.
    func setPostalAlarm(_ on: Bool) {
        guard ready, on != postalAlarmOn else { return }
        // The latch is only committed once the alarm has actually been started
        // or deliberately left off. Setting it first would record "alarm on"
        // for a call that the muted branch turns straight back off, so unmuting
        // mid-red would find `on == postalAlarmOn` and never sound it.
        let buffer = (on && !muted) ? retail("Audio/Sfx/postalloop.m4a", format: format) : nil
        postalAlarmOn = buffer != nil
        guard let buffer else {
            postalNode.stop()
            return
        }
        postalNode.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        postalNode.play()
    }

    /// Plays one of the snail's spoken lines, no more often than the original's
    /// twenty seconds and never cutting off the line already speaking.
    func speak(_ voice: Voice) {
        guard ready, !muted, hasRetailAudio else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastVoiceAt >= Self.voiceInterval else { return }
        let lines = voice.lines
        guard !lines.isEmpty else { return }
        var line = lines[Int.random(in: 0..<lines.count)]
        if lines.count > 1, line == lastVoiceLine {
            line = lines[Int.random(in: 0..<lines.count)]
        }
        playVoiceLine(line)
    }

    /// Turbo's idle banter — the retail's `Misc` set, the one line list no
    /// event claims. `Frequency:20` is the script's *target* rate, not a quota
    /// to fill at any cost, so this waits out a longer silence (roughly the
    /// twenty seconds plus the length of a typical line) before chipping in:
    /// in a busy stretch the events already supply the chatter, and only a
    /// genuinely quiet run needs `Misc` to keep Turbo talking.
    func chatter() {
        guard ready, !muted, hasRetailAudio else { return }
        guard ProcessInfo.processInfo.systemUptime - lastVoiceAt >= Self.chatterInterval else {
            return
        }
        speak(.misc)
    }

    /// Plays the tutorial's own voice-over.  Each scripted line names one
    /// recording (`tut1`…`tut18`) rather than drawing from a set, and the
    /// track files give it its own `Duration`, so the twenty-second chatter
    /// limit does not apply; only the "don't cut off the current line" rule
    /// does.
    func speak(tutorialLine name: String) {
        guard ready, !muted, hasRetailAudio else { return }
        playVoiceLine(name)
    }

    /// Plays one of the slugs' own lines. Their clips are not part of the
    /// snail's `_Voice.txt` chatter, so none of its rules apply: a slug speaks
    /// promptly when it acts instead of waiting out the twenty-second
    /// `Frequency`, and it talks over the snail rather than replacing it. Only
    /// a short guard stops twenty slugs from all shouting at once.
    func speakSlug(_ voice: SlugVoice) {
        guard ready, !muted, hasRetailAudio else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard !slugVoiceBusy, now - lastSlugVoiceAt >= Self.slugVoiceInterval else { return }
        let lines = voice.lines
        guard !lines.isEmpty else { return }
        var line = lines[Int.random(in: 0..<lines.count)]
        if lines.count > 1, line == lastSlugVoiceLine {
            line = lines[Int.random(in: 0..<lines.count)]
        }
        guard let buffer = retail("Audio/Voice/\(line).m4a", format: format) else { return }
        lastSlugVoiceLine = line
        lastSlugVoiceAt = ProcessInfo.processInfo.systemUptime
        slugVoiceBusy = true
        slugVoiceNode.scheduleBuffer(buffer, at: nil, options: [.interrupts],
                                     completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.slugVoiceBusy = false }
        }
        if !slugVoiceNode.isPlaying { slugVoiceNode.play() }
    }

    private func playVoiceLine(_ line: String) {
        guard !voiceBusy else { return }
        guard let buffer = retail("Audio/Voice/\(line).m4a", format: format) else { return }
        lastVoiceLine = line
        lastVoiceAt = ProcessInfo.processInfo.systemUptime
        voiceBusy = true
        voiceNode.scheduleBuffer(buffer, at: nil, options: [.interrupts],
                                 completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { self?.voiceBusy = false }
        }
        if !voiceNode.isPlaying { voiceNode.play() }
    }

    private var hasRetailAudio: Bool { RetailAssets.installed }

    private func retailName(_ effect: Effect) -> String? {
        switch effect {
        case .shoot(let tier):
            // The mesh the rung picked decides the family here: the blaster's
            // and the laser's own recordings, and the launcher's three tubes
            // for the rocket. Sustained fire rotates through the trio the same
            // way the paired impacts and servos alternate below.
            switch tier {
            case 1: return "Audio/Sfx/laser1.m4a"
            case 2: return "Audio/Sfx/laser\(flip("laser", of: 2) + 2).m4a"
            default: return "Audio/Sfx/rocket\(flip("rocket", of: 3) + 1).m4a"
            }
        case .enemyFire:   return "Audio/Sfx/enemyfire.m4a"
        case .collect:     return "Audio/Sfx/packagecount.m4a"
        case .deliver:     return "Audio/Sfx/placepackage.m4a"
        // `0x4457e6` indexes the jingle by the rung the snail just reached and
        // clamps at seven, so the two top rungs both ring `pw7`.
        case .upgrade(let rung): return "Audio/Sfx/pw\(max(1, min(7, rung))).m4a"
        case .hit:         return "Audio/Sfx/wallhit.m4a"
        case .asteroid:    return "Audio/Sfx/asteroidimpact\(flip("impact", of: 2) + 1).m4a"
        case .boost:       return "Audio/Sfx/turbofire\(flip("turbofire", of: 2) + 1).m4a"
        case .jetpack:     return "Audio/Sfx/jetpack.m4a"
        case .skid:        return "Audio/Sfx/skidstop.m4a"
        case .heart:       return "Audio/Sfx/heart.m4a"
        case .extraLife:   return "Audio/Sfx/extralife.m4a"
        case .slow:        return "Audio/Sfx/slowring.m4a"
        case .explodeRing: return "Audio/Sfx/explodering.m4a"
        case .invincible:  return "Audio/Sfx/invincible.m4a"
        case .trampoline:  return "Audio/Sfx/boing.m4a"
        case .select:      return "Audio/Sfx/select.m4a"
        case .highlight:   return "Audio/Sfx/highlight.m4a"
        case .servo:       return "Audio/Sfx/servo\(flip("servo", of: 2) + 1).m4a"
        case .win:         return "Audio/Sfx/cheers.m4a"
        case .perfect:     return "Audio/Sfx/perfect.m4a"
        case .lose:        return nil
        case .fall:        return nil
        }
    }

    private func synthKey(_ effect: Effect) -> String {
        switch effect {
        case .shoot: "shoot"
        case .enemyFire: "enemyFire"
        case .collect, .deliver, .heart: "collect"
        case .upgrade, .extraLife, .invincible: "upgrade"
        case .hit, .asteroid, .skid, .explodeRing: "hit"
        case .boost, .jetpack, .trampoline, .slow: "boost"
        case .select, .highlight, .servo: "select"
        case .win, .perfect: "win"
        case .lose: "lose"
        case .fall: "fall"
        }
    }

    /// Walks a counter so paired samples alternate, the way the original's
    /// two-variant impacts and servos do.
    private func flip(_ key: String, of count: Int) -> Int {
        let index = (flips[key] ?? 0) % max(1, count)
        flips[key] = index + 1
        return index
    }

    // MARK: - Retail samples

    private func retail(_ path: String, format target: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard hasRetailAudio else { return nil }
        let key = "\(path)|\(target.channelCount)"
        if let hit = sounds[key] { return hit }
        guard let url = RetailAssets.url(path), let buffer = decode(url, to: target) else { return nil }
        sounds[key] = buffer
        return buffer
    }

    /// Reads a retail `.m4a` and converts it to the bus's format, so every
    /// buffer can be scheduled on a node connected once at start-up.
    private func decode(_ url: URL, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let source = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: frames),
              (try? file.read(into: input)) != nil else { return nil }
        if source.sampleRate == target.sampleRate,
           source.channelCount == target.channelCount,
           source.commonFormat == target.commonFormat {
            return input
        }
        guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
        let ratio = target.sampleRate / source.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 4096)
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed {
                status.pointee = .endOfStream
                return nil
            }
            fed = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, output.frameLength > 0 else { return nil }
        return output
    }

    // MARK: - Synthesis

    private func buffer(duration: Double, format: AVAudioFormat,
                        _ sample: (Double) -> Double) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let frames = AVAudioFrameCount(max(1, duration * sr))
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channels = Int(format.channelCount)
        let data = buffer.floatChannelData!
        for i in 0..<Int(frames) {
            let value = Float(max(-1, min(1, sample(Double(i) / sr))))
            for channel in 0..<channels { data[channel][i] = value }
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
        return buffer(duration: duration, format: format) { t in
            let f = from + (to - from) * (t / duration)
            phase += f / sr
            let env = decay ? pow(1 - t / duration, 1.6) : 1
            return square(phase) * volume * env
        }
    }

    private func noise(duration: Double, volume: Double) -> AVAudioPCMBuffer {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        return buffer(duration: duration, format: format) { t in
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let r = Double((seed >> 33) & 0xFFFF) / 32768.0 - 1
            return r * volume * pow(1 - t / duration, 2)
        }
    }

    private func buildEffects() {
        effects["shoot"] = sweep(from: 1200, to: 420, duration: 0.09, volume: 0.28)
        // The evil's vapour laser: a lower, sourer zap than the snail's own so
        // the two trade shots on different notes.
        effects["enemyFire"] = sweep(from: 760, to: 240, duration: 0.13, volume: 0.26)
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
        return buffer(duration: total, format: format) { t in
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
        return buffer(duration: total, format: musicFormat) { t in
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
