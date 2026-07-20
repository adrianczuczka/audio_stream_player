package com.adrianczuczka.audio_stream_player

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Flutter plugin entry point: routes method calls to per-id [PcmStreamPlayer]s. */
class AudioStreamPlayerPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var methods: MethodChannel
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding
    private val mainHandler = Handler(Looper.getMainLooper())

    private class PlayerEntry(
        val player: PcmStreamPlayer,
        val eventChannel: EventChannel,
    ) {
        var sink: EventChannel.EventSink? = null
    }

    private val players = HashMap<Int, PlayerEntry>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        methods = MethodChannel(binding.binaryMessenger, "audio_stream_player/methods")
        methods.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        for (entry in players.values) {
            entry.player.release()
            entry.eventChannel.setStreamHandler(null)
        }
        players.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "create") {
                create(call)
                result.success(null)
                return
            }
            val playerId = call.argument<Int>("playerId")
            val entry = players[playerId]
            if (entry == null) {
                result.error("not_found", "No player with id $playerId", null)
                return
            }
            when (call.method) {
                "feed" -> entry.player.feed(call.argument<ByteArray>("data")!!)
                "play" -> entry.player.play()
                "pause" -> entry.player.pause()
                "stop" -> entry.player.stop()
                "endOfStream" -> entry.player.endOfStream()
                "setVolume" -> entry.player.setVolume(call.argument<Double>("volume")!!)
                "bufferedDurationMicros" -> {
                    result.success(entry.player.bufferedDurationMicros())
                    return
                }
                "dispose" -> {
                    entry.player.release()
                    entry.eventChannel.setStreamHandler(null)
                    players.remove(playerId)
                }
                else -> {
                    result.notImplemented()
                    return
                }
            }
            result.success(null)
        } catch (e: Exception) {
            result.error("audio_stream_player", e.message, null)
        }
    }

    private fun create(call: MethodCall) {
        val playerId = call.argument<Int>("playerId")!!
        val sampleRate = call.argument<Int>("sampleRate")!!
        val channels = call.argument<Int>("channels")!!
        val isFloat = call.argument<String>("format") == "f32le"

        val eventChannel =
            EventChannel(binding.binaryMessenger, "audio_stream_player/events/$playerId")
        lateinit var entry: PlayerEntry
        val player = PcmStreamPlayer(sampleRate, channels, isFloat) { event ->
            // Emit synchronously when already on the main thread so state
            // events precede the method-call reply (matching iOS ordering);
            // writer-thread events hop to the main thread.
            if (Looper.myLooper() == Looper.getMainLooper()) {
                entry.sink?.success(event)
            } else {
                mainHandler.post { entry.sink?.success(event) }
            }
        }
        entry = PlayerEntry(player, eventChannel)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                entry.sink = sink
            }

            override fun onCancel(arguments: Any?) {
                entry.sink = null
            }
        })
        players[playerId] = entry
    }
}
