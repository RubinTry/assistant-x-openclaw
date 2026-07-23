package com.macbear.m3_video_bridge

import android.content.Context
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** M3VideoBridgePlugin */
class M3VideoBridgePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    
    private data class PlayerData(
        var mediaPlayer: MediaPlayer? = null,
        var surfaceTexture: SurfaceTexture? = null,
        var surface: Surface? = null,
        var frameAvailable: Boolean = false
    ) {
        fun release() {
            mediaPlayer?.stop()
            mediaPlayer?.release()
            surface?.release()
            surfaceTexture?.release()
        }
    }

    private val players = mutableMapOf<Int, PlayerData>()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.macbear.angle_test/video")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val textureId = call.argument<Int>("textureId") ?: 0
        when (call.method) {
            "registerSurface" -> {
                val assetPath = call.argument<String>("assetPath") ?: ""
                try {
                    val isSuccess = setupVideo(textureId, assetPath)
                    result.success(isSuccess)
                } catch (e: Exception) {
                    result.error("VIDEO_ERROR", e.message, null)
                }
            }
            "updateSurface" -> {
                try {
                    val player = players[textureId]
                    if (player != null && player.frameAvailable) {
                        player.frameAvailable = false
                        player.surfaceTexture?.updateTexImage()
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                } catch (e: Exception) {
                    android.util.Log.e("M3VideoBridge", "Update error: ${e.message}")
                    result.error("UPDATE_ERROR", e.message, null)
                }
            }
            "release" -> {
                releaseVideo(textureId)
                result.success(true)
            }
            "play" -> {
                players[textureId]?.mediaPlayer?.start()
                result.success(true)
            }
            "pause" -> {
                players[textureId]?.mediaPlayer?.pause()
                result.success(true)
            }
            "seekTo" -> {
                val seconds = call.argument<Double>("seconds") ?: 0.0
                players[textureId]?.mediaPlayer?.seekTo((seconds * 1000).toInt())
                result.success(true)
            }
            "getDuration" -> {
                val duration = (players[textureId]?.mediaPlayer?.duration ?: 0) / 1000.0
                result.success(duration)
            }
            "getPosition" -> {
                val position = (players[textureId]?.mediaPlayer?.currentPosition ?: 0) / 1000.0
                result.success(position)
            }
            else -> result.notImplemented()
        }
    }

    private fun setupVideo(textureId: Int, assetPath: String): Boolean {
        return try {
            releaseVideo(textureId)

            val player = PlayerData()
            player.surfaceTexture = SurfaceTexture(textureId).apply {
                setOnFrameAvailableListener { player.frameAvailable = true }
            }
            player.surface = Surface(player.surfaceTexture)

            player.mediaPlayer = MediaPlayer().apply {
                setSurface(player.surface)
                isLooping = true
                setVolume(0f, 0f) // Mute

                val lowerPath = assetPath.lowercase()
                if (lowerPath.startsWith("http://") || lowerPath.startsWith("https://")) {
                    android.util.Log.d("M3VideoBridge", "Setting network data source: $assetPath")
                    setDataSource(assetPath)
                } else {
                    android.util.Log.d("M3VideoBridge", "Setting asset data source: $assetPath")
                    val assetManager = context.assets
                    val afd = assetManager.openFd("flutter_assets/$assetPath")
                    setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                    afd.close()
                }

                prepare()
                start()
            }
            players[textureId] = player
            true
        } catch (e: Exception) {
            android.util.Log.e("M3VideoBridge", "Setup video err: ${e.message}")
            e.printStackTrace()
            false
        }
    }

    private fun releaseVideo(textureId: Int) {
        players[textureId]?.release()
        players.remove(textureId)
    }

    private fun releaseAll() {
        players.values.forEach { it.release() }
        players.clear()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        releaseAll()
    }
}
