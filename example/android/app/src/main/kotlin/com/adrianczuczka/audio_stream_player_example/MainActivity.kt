package com.adrianczuczka.audio_stream_player_example

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var focusRequest: AudioFocusRequest? = null
    private val focusListener = AudioManager.OnAudioFocusChangeListener {}

    // Test hook for integration_test/audio_focus_test.dart. Requesting focus
    // from here takes it from the plugin as another app would, since Android
    // tracks focus per listener, not per process.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "audio_stream_player_example/focus",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "request" -> {
                    val gain = call.argument<Int>("gain")!!
                    result.success(requestFocus(audioManager, gain))
                }
                "abandon" -> {
                    abandonFocus(audioManager)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestFocus(audioManager: AudioManager, gain: Int): Int {
        abandonFocus(audioManager)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(gain)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setOnAudioFocusChangeListener(focusListener)
                .build()
            focusRequest = request
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, gain)
        }
    }

    private fun abandonFocus(audioManager: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
    }
}
