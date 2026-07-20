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

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
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
                #if os(iOS)
                    try Self.activateAudioSessionIfNeeded()
                #endif
                try entry.player.play()
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
                entry.player.release()
                entry.eventChannel.setStreamHandler(nil)
                players.removeValue(forKey: playerId)
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

        #if os(iOS)
            if (args["configureAudioSession"] as? Bool) ?? true {
                Self.configureSession = true
                try AVAudioSession.sharedInstance().setCategory(
                    .playback, mode: .spokenAudio)
            } else {
                Self.configureSession = false
            }
        #endif

        let handler = EventStreamHandler()
        let eventChannel = FlutterEventChannel(
            name: "audio_stream_player/events/\(playerId)",
            binaryMessenger: messenger)
        eventChannel.setStreamHandler(handler)
        let player = try PcmStreamPlayer(
            sampleRate: sampleRate, channels: channels, isFloat: isFloat
        ) { [weak handler] event in
            handler?.sink?(event)
        }
        players[playerId] = PlayerEntry(
            player: player, eventChannel: eventChannel, handler: handler)
    }

    #if os(iOS)
        private static var configureSession = true

        private static func activateAudioSessionIfNeeded() throws {
            if configureSession {
                try AVAudioSession.sharedInstance().setActive(true)
            }
        }
    #endif
}
