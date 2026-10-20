#if os(iOS)
    import Flutter
    import UIKit
#elseif os(macOS)
    import FlutterMacOS
#endif
import AVFoundation

/// Flutter plugin entry point: routes method calls to per-id `PcmStreamPlayer`s.
public class AudioStreamPlayerPlugin: NSObject, FlutterPlugin {
    private class EventStreamHandler: NSObject, FlutterStreamHandler {
        var sink: FlutterEventSink?

        func onListen(
            withArguments arguments: Any?,
            eventSink events: @escaping FlutterEventSink
        ) -> FlutterError? {
            sink = events
            return nil
        }

        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            sink = nil
            return nil
        }
    }

    private class PlayerEntry {
        let player: PcmStreamPlayer
        let eventChannel: FlutterEventChannel
        let handler: EventStreamHandler

        init(
            player: PcmStreamPlayer, eventChannel: FlutterEventChannel,
            handler: EventStreamHandler
        ) {
            self.player = player
            self.eventChannel = eventChannel
            self.handler = handler
        }
    }

    private var players = [Int: PlayerEntry]()
    private var messenger: FlutterBinaryMessenger
    // Pending idle check that stops idle engines and deactivates the session.
    // Delayed so back-to-back utterances don't let other apps' audio resume
    // for a moment between them.
    private var idleWork: DispatchWorkItem?
    private static let idleDelay: TimeInterval = 1.0

    #if os(iOS)
        // How the most recent `create` asked for the shared session to be
        // managed: "playback", "voiceChat" or "manual".
        private var sessionConfig = "playback"
        private var managesSession: Bool { sessionConfig != "manual" }
        private var sessionActive = false
        private var interruptionObserver: NSObjectProtocol?
    #endif

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
        #if os(iOS)
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(), queue: .main
            ) { [weak self] note in
                self?.handleInterruption(note)
            }
        #endif
    }

    deinit {
        #if os(iOS)
            if let observer = interruptionObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        #endif
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        #if os(macOS)
            let messenger = registrar.messenger
        #else
            let messenger = registrar.messenger()
        #endif
        let channel = FlutterMethodChannel(
            name: "audio_stream_player/methods", binaryMessenger: messenger)
        let instance = AudioStreamPlayerPlugin(messenger: messenger)
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.publish(instance)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        releaseAll()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        do {
            if call.method == "create" {
                try create(args)
                result(nil)
                return
            }
            guard let playerId = args["playerId"] as? Int,
                let entry = players[playerId]
            else {
                result(
                    FlutterError(
                        code: "not_found",
                        message: "No player with id \(args["playerId"] ?? "nil")",
                        details: nil))
                return
            }
            switch call.method {
            case "feed":
                let data = (args["data"] as! FlutterStandardTypedData).data
                try entry.player.feed(data)
            case "play":
                idleWork?.cancel()
                idleWork = nil
                do {
                    #if os(iOS)
                        try activateSessionIfManaged()
                    #endif
                    try entry.player.play()
                } catch {
                    scheduleIdleCheck()
                    throw error
                }
            case "pause":
                entry.player.pause()
            case "stop":
                entry.player.stop()
            case "endOfStream":
                entry.player.endOfStream()
            case "setVolume":
                entry.player.setVolume(args["volume"] as! Double)
            case "bufferedDurationMicros":
                result(entry.player.bufferedDurationMicros())
                return
            case "dispose":
                release(entry)
                players.removeValue(forKey: playerId)
                scheduleIdleCheck()
            default:
                result(FlutterMethodNotImplemented)
                return
            }
            result(nil)
        } catch {
            result(
                FlutterError(
                    code: "audio_stream_player",
                    message: "\(error)", details: nil))
        }
    }

    private func create(_ args: [String: Any]) throws {
        let playerId = args["playerId"] as! Int
        let sampleRate = args["sampleRate"] as! Int
        let channels = args["channels"] as! Int
        let isFloat = (args["format"] as? String) == "f32le"

        // Player ids come from a Dart static that restarts at 0 on hot
        // restart, while this plugin instance and its players survive. The
        // old isolate can never dispose them, so id 0 means a fresh Dart
        // isolate: release everything left over. A reused id is released
        // either way so its engine never leaks.
        if playerId == 0 {
            releaseAll()
        } else if let stale = players.removeValue(forKey: playerId) {
            release(stale)
        }

        #if os(iOS)
            sessionConfig = (args["audioSession"] as? String) ?? "playback"
            let session = AVAudioSession.sharedInstance()
            switch sessionConfig {
            case "voiceChat":
                // The iOS 26 SDK (Swift 6.2) renamed .allowBluetooth; both
                // names map to the same option on every iOS version.
                #if compiler(>=6.2)
                    let bluetooth = AVAudioSession.CategoryOptions.allowBluetoothHFP
                #else
                    let bluetooth = AVAudioSession.CategoryOptions.allowBluetooth
                #endif
                try session.setCategory(
                    .playAndRecord, mode: .voiceChat,
                    options: [.defaultToSpeaker, bluetooth])
            case "manual":
                break
            default:
                try session.setCategory(.playback, mode: .spokenAudio)
            }
        #endif

        let handler = EventStreamHandler()
        let eventChannel = FlutterEventChannel(
            name: "audio_stream_player/events/\(playerId)",
            binaryMessenger: messenger)
        eventChannel.setStreamHandler(handler)
        let player = try PcmStreamPlayer(
            sampleRate: sampleRate, channels: channels, isFloat: isFloat
        ) { [weak self, weak handler] event in
            handler?.sink?(event)
            if event["event"] as? String == "state" {
                self?.scheduleIdleCheck()
            }
        }
        players[playerId] = PlayerEntry(
            player: player, eventChannel: eventChannel, handler: handler)
    }

    private func release(_ entry: PlayerEntry) {
        entry.player.release()
        entry.eventChannel.setStreamHandler(nil)
    }

    private func releaseAll() {
        for entry in players.values {
            release(entry)
        }
        players.removeAll()
        scheduleIdleCheck()
    }

    /// Once every player is idle, stops their engines and, in `playback`
    /// mode, deactivates the session so other apps' audio resumes.
    private func scheduleIdleCheck() {
        idleWork?.cancel()
        idleWork = nil
        guard players.values.allSatisfy({ $0.player.isIdle }) else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.handleIdle()
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.idleDelay, execute: work)
    }

    private func handleIdle() {
        idleWork = nil
        guard players.values.allSatisfy({ $0.player.isIdle }) else { return }
        // Map before checking so every idle engine stops, not just the ones
        // before the first that keeps running.
        let enginesStopped = players.values
            .map { $0.player.stopEngineIfIdle() }
            .allSatisfy { $0 }
        #if os(iOS)
            // Deactivating stops every running audio object in the app, not
            // just ours. In voiceChat mode a recorder is expected to outlive
            // each utterance, so the session stays active until the app
            // deactivates it. A player with audio fed ahead of play() keeps
            // its engine running, and deactivating would stop it and could
            // drop that audio, so the session stays active until it drains
            // or stops.
            guard sessionActive && sessionConfig == "playback"
                && enginesStopped
            else { return }
            sessionActive = false
            // The session is inactive even when this throws isBusy, so the
            // error carries nothing to undo.
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        #else
            _ = enginesStopped
        #endif
    }

    #if os(iOS)
        private func activateSessionIfManaged() throws {
            guard managesSession else { return }
            try AVAudioSession.sharedInstance().setActive(true)
            sessionActive = true
        }

        /// A phone call, Siri or another app's non-mixable audio took the
        /// session. The system has already stopped every engine, so playing
        /// players move to paused instead of reporting `playing` in silence.
        ///
        /// When the interruption ends with `.shouldResume`, the players it
        /// paused resume by themselves. Apple recommends this, and the app
        /// has no other way to learn when the interruption ended. Without
        /// `.shouldResume`, or when the app manages the session itself, they
        /// stay paused until the app calls `play()`.
        private func handleInterruption(_ note: Notification) {
            guard let info = note.userInfo,
                let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: rawType)
            else { return }
            switch type {
            case .began:
                sessionActive = false
                for entry in players.values {
                    entry.player.interruptionBegan()
                }
            case .ended:
                let rawOptions =
                    info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(
                    rawValue: rawOptions
                ).contains(.shouldResume)
                let interrupted = players.values.filter {
                    $0.player.pausedByInterruption
                }
                guard shouldResume && managesSession && !interrupted.isEmpty
                else {
                    for entry in interrupted {
                        entry.player.clearInterruption()
                    }
                    return
                }
                do {
                    idleWork?.cancel()
                    idleWork = nil
                    try activateSessionIfManaged()
                } catch {
                    for entry in interrupted {
                        entry.player.clearInterruption()
                        entry.player.emitError(
                            "Could not reactivate the audio session: \(error)")
                    }
                    return
                }
                for entry in interrupted {
                    entry.player.resumeAfterInterruption()
                }
            @unknown default:
                break
            }
        }
    #endif
}
