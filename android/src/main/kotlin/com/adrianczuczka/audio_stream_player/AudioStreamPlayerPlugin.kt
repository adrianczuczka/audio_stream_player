package com.adrianczuczka.audio_stream_player

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
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
    private lateinit var audioManager: AudioManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private class PlayerEntry(
        val player: PcmStreamPlayer,
        val eventChannel: EventChannel,
        // False for AudioSessionConfig.manual: the app handles audio focus.
        val managesFocus: Boolean,
    ) {
        var sink: EventChannel.EventSink? = null
    }

    private val players = HashMap<Int, PlayerEntry>()

    // Transient audio focus is held while any focus-managing player is
    // playing or paused. It is abandoned with a short delay once all of them
    // are idle, so back-to-back utterances don't let other apps' audio
    // resume for a moment between them.
    private var focusHeld = false
    private var focusRequest: AudioFocusRequest? = null
    private val abandonFocusIfIdle = Runnable {
        if (managedPlayers().all { it.player.isIdle }) abandonFocus()
    }
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (Looper.myLooper() == Looper.getMainLooper()) {
            onFocusChange(change)
        } else {
            mainHandler.post { onFocusChange(change) }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        audioManager =
            binding.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        methods = MethodChannel(binding.binaryMessenger, "audio_stream_player/methods")
        methods.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        releaseAll()
        mainHandler.removeCallbacks(abandonFocusIfIdle)
        abandonFocus()
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
                "play" -> {
                    if (entry.managesFocus && !requestFocus()) {
                        result.error(
                            "audio_focus_denied",
                            "The system denied audio focus, for example during a phone call",
                            null,
                        )
                        return
                    }
                    entry.player.play()
                }
                "pause" -> entry.player.pause()
                "stop" -> entry.player.stop()
                "endOfStream" -> entry.player.endOfStream()
                "setVolume" -> entry.player.setVolume(call.argument<Double>("volume")!!)
                "bufferedDurationMicros" -> {
                    result.success(entry.player.bufferedDurationMicros())
                    return
                }
                "dispose" -> {
                    release(entry)
                    players.remove(playerId)
                    scheduleIdleCheck()
                }
                else -> {
                    result.notImplemented()
                    return
                }
            }
            result.success(null)
        } catch (e: Exception) {
            // A failed play() may leave focus held with nothing playing.
            scheduleIdleCheck()
            result.error("audio_stream_player", e.message, null)
        }
    }

    private fun create(call: MethodCall) {
        val playerId = call.argument<Int>("playerId")!!
        val sampleRate = call.argument<Int>("sampleRate")!!
        val channels = call.argument<Int>("channels")!!
        val isFloat = call.argument<String>("format") == "f32le"
        val managesFocus = call.argument<String>("audioSession") != "manual"

        // Player ids come from a Dart static that restarts at 0 on hot
        // restart, while this plugin instance and its players survive. The
        // old isolate can never dispose them, so id 0 means a fresh Dart
        // isolate: release everything left over. A reused id is released
        // either way so its AudioTrack and writer thread never leak.
        if (playerId == 0) {
            releaseAll()
        } else {
            players.remove(playerId)?.let { release(it) }
        }

        val eventChannel =
            EventChannel(binding.binaryMessenger, "audio_stream_player/events/$playerId")
        lateinit var entry: PlayerEntry
        val player = PcmStreamPlayer(sampleRate, channels, isFloat) { event ->
            // Emit synchronously when already on the main thread so state
            // events precede the method-call reply (matching iOS ordering);
            // writer-thread events hop to the main thread.
            if (Looper.myLooper() == Looper.getMainLooper()) {
                dispatch(entry, event)
            } else {
                mainHandler.post { dispatch(entry, event) }
            }
        }
        entry = PlayerEntry(player, eventChannel, managesFocus)
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

    private fun dispatch(entry: PlayerEntry, event: Map<String, Any>) {
        entry.sink?.success(event)
        if (event["event"] == "state") scheduleIdleCheck()
    }

    private fun release(entry: PlayerEntry) {
        entry.player.release()
        entry.eventChannel.setStreamHandler(null)
        entry.sink = null
    }

    private fun releaseAll() {
        for (entry in players.values) release(entry)
        players.clear()
        scheduleIdleCheck()
    }

    private fun managedPlayers() = players.values.filter { it.managesFocus }

    private fun scheduleIdleCheck() {
        mainHandler.removeCallbacks(abandonFocusIfIdle)
        if (focusHeld && managedPlayers().all { it.player.isIdle }) {
            mainHandler.postDelayed(abandonFocusIfIdle, IDLE_DELAY_MS)
        }
    }

    private fun requestFocus(): Boolean {
        mainHandler.removeCallbacks(abandonFocusIfIdle)
        if (focusHeld) return true
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = focusRequest ?: AudioFocusRequest.Builder(
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            )
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                // Ducked speech is hard to follow: pause instead.
                .setWillPauseWhenDucked(true)
                .setOnAudioFocusChangeListener(focusListener, mainHandler)
                .build()
                .also { focusRequest = it }
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK,
            )
        }
        focusHeld = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return focusHeld
    }

    private fun abandonFocus() {
        if (!focusHeld) return
        focusHeld = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
    }

    /**
     * A transient loss (a phone call, navigation prompt or notification)
     * pauses playing players, and they resume when focus returns, as Android
     * recommends. A permanent loss (another app started playback) pauses
     * them for good; the app resumes with play(), which requests focus again.
     */
    private fun onFocusChange(change: Int) {
        if (!focusHeld) return
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK ->
                for (entry in managedPlayers()) entry.player.pauseForFocusLoss(resumable = true)
            AudioManager.AUDIOFOCUS_GAIN ->
                for (entry in managedPlayers()) entry.player.resumeAfterFocusGain()
            AudioManager.AUDIOFOCUS_LOSS -> {
                for (entry in managedPlayers()) entry.player.pauseForFocusLoss(resumable = false)
                abandonFocus()
            }
        }
    }

    private companion object {
        const val IDLE_DELAY_MS = 1000L
    }
}
