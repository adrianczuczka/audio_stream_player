package com.adrianczuczka.audiostreamplayer

import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.PluginRegistry.Registrar
import android.net.Uri
import com.google.android.exoplayer2.*
import com.google.android.exoplayer2.source.ExtractorMediaSource
import com.google.android.exoplayer2.source.MediaSource
import com.google.android.exoplayer2.upstream.DefaultHttpDataSourceFactory
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector

class AudioStreamPlayerPlugin private constructor(private val registrar: Registrar) : MethodCallHandler {
    private var player: SimpleExoPlayer? = null
    private var playWhenReady = true
    private var playbackPosition = 0L
    private var volumeBeforeMuted = 0F
    private var muted = false

    companion object {
        @JvmStatic
        fun registerWith(registrar: Registrar) {
            val channel = MethodChannel(registrar.messenger(), "audio_stream_player")
            channel.setMethodCallHandler(AudioStreamPlayerPlugin(registrar))
        }
    }

    override fun onMethodCall(call: MethodCall, response: Result) {
        when (call.method) {
            "play" -> {
                play(call.argument<Any>("url").toString())
                response.success(null)
            }
            "pause" -> {
                pause()
                response.success(null)
            }
            "stop" -> {
                stop()
                response.success(null)
            }
            "mute" -> {
                mute()
                response.success(null)
            }
        }
    }

    private fun initializePlayer(url: String) {
        player = ExoPlayerFactory.newSimpleInstance(
                DefaultRenderersFactory(registrar.context().applicationContext),
                DefaultTrackSelector(), DefaultLoadControl())

        player!!.playWhenReady = true
        player!!.seekTo(playbackPosition)
        val uri = Uri.parse(url)
        val mediaSource = buildMediaSource(uri)
        player!!.prepare(mediaSource, true, false)
    }

    private fun buildMediaSource(uri: Uri): MediaSource {
        return ExtractorMediaSource.Factory(
                DefaultHttpDataSourceFactory("audio-stream-player")).createMediaSource(uri)
    }

    private fun play(url: String) {
        if (player == null) {
            initializePlayer(url)
        } else {
            player!!.playWhenReady = true
        }
    }

    private fun pause() {
        if (player != null) {
            player!!.playWhenReady = false
        }
    }

    private fun stop() {
        if (player != null) {
            playbackPosition = player!!.currentPosition
            playWhenReady = player!!.playWhenReady
            player?.release()
            player = null
        }
    }

    private fun mute() {
        if (player != null) {
            if(muted){
                player!!.volume = volumeBeforeMuted
                muted = false
            }
            else{
                volumeBeforeMuted = player!!.volume
                muted = true
            }
        }
    }
}
