package com.audiometria.audiometria

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * Parte nativa de la app: genera los tonos puros con AudioTrack, detecta los
 * audífonos conectados y controla el volumen multimedia.
 */
class MainActivity : FlutterActivity() {
    private val audioManager by lazy { getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    private val mainHandler = Handler(Looper.getMainLooper())

    private var track: AudioTrack? = null
    private var savedVolume: Int? = null
    private var deviceSink: EventChannel.EventSink? = null

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) = emitDevice()
        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) = emitDevice()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "audiometria/audio").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getOutputDevice" -> result.success(currentDevice())
                    "playTone" -> {
                        playTone(
                            frequency = call.argument<Double>("frequency")!!,
                            amplitude = call.argument<Double>("amplitude")!!,
                            ear = call.argument<String>("ear")!!,
                            durationMs = call.argument<Int>("durationMs")!!,
                        )
                        result.success(null)
                    }
                    "stopTone" -> {
                        stopTone()
                        result.success(null)
                    }
                    "setMaxVolume" -> result.success(setMaxVolume())
                    "restoreVolume" -> {
                        restoreVolume()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("audio_error", e.message, null)
            }
        }

        EventChannel(messenger, "audiometria/devices").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    deviceSink = events
                    audioManager.registerAudioDeviceCallback(deviceCallback, mainHandler)
                    emitDevice()
                }

                override fun onCancel(arguments: Any?) {
                    audioManager.unregisterAudioDeviceCallback(deviceCallback)
                    deviceSink = null
                }
            }
        )
    }

    override fun onDestroy() {
        stopTone()
        restoreVolume()
        audioManager.unregisterAudioDeviceCallback(deviceCallback)
        super.onDestroy()
    }

    // ---- Detección de audífonos ----

    private fun deviceKind(type: Int): String? = when (type) {
        AudioDeviceInfo.TYPE_WIRED_HEADSET, AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired"
        AudioDeviceInfo.TYPE_USB_HEADSET -> "usb"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bluetooth"
        AudioDeviceInfo.TYPE_HEARING_AID -> "hearing_aid"
        else ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                type == AudioDeviceInfo.TYPE_BLE_HEADSET
            ) "bluetooth" else null
    }

    /** Audífonos conectados (con cable primero) o, si no hay, el altavoz. */
    private fun currentDevice(): Map<String, Any> {
        val priority = listOf("wired", "usb", "bluetooth", "hearing_aid")
        val headphones = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .mapNotNull { device -> deviceKind(device.type)?.let { it to device } }
            .minByOrNull { priority.indexOf(it.first) }
            ?: return mapOf("name" to "Altavoz del teléfono", "type" to "speaker")

        val (kind, device) = headphones
        val productName = device.productName?.toString().orEmpty()
        // Con audífonos de cable, Android suele informar el modelo del teléfono como nombre.
        val name = if (productName.isBlank() || productName == Build.MODEL) {
            if (kind == "wired") "Audífonos con cable" else "Audífonos"
        } else {
            productName
        }
        return mapOf("name" to name, "type" to kind)
    }

    private fun emitDevice() {
        deviceSink?.success(currentDevice())
    }

    // ---- Tonos puros ----

    private fun playTone(frequency: Double, amplitude: Double, ear: String, durationMs: Int) {
        stopTone()
        val frames = SAMPLE_RATE * durationMs / 1000
        val rampFrames = min(SAMPLE_RATE * RAMP_MS / 1000, frames / 2)
        val left = if (ear == "right") 0f else 1f
        val right = if (ear == "left") 0f else 1f
        val step = 2.0 * PI * frequency / SAMPLE_RATE

        // PCM en coma flotante: 16 bits no alcanza para los niveles más bajos (< -96 dBFS).
        val samples = FloatArray(frames * 2)
        for (i in 0 until frames) {
            // Rampas de coseno al inicio y al final para evitar chasquidos audibles.
            val envelope = when {
                i < rampFrames -> 0.5 * (1 - cos(PI * i / rampFrames))
                i >= frames - rampFrames -> 0.5 * (1 - cos(PI * (frames - 1 - i) / rampFrames))
                else -> 1.0
            }
            val value = (amplitude * envelope * sin(step * i)).toFloat()
            samples[2 * i] = value * left
            samples[2 * i + 1] = value * right
        }

        val newTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE)
                    .setEncoding(AudioFormat.ENCODING_PCM_FLOAT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                    .build()
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(samples.size * Float.SIZE_BYTES)
            .build()
        newTrack.write(samples, 0, samples.size, AudioTrack.WRITE_BLOCKING)
        newTrack.play()
        track = newTrack
    }

    private fun stopTone() {
        track?.let {
            try {
                it.pause()
                it.flush()
            } catch (_: IllegalStateException) {
            }
            it.release()
        }
        track = null
    }

    // ---- Volumen ----

    /** Sube el volumen multimedia al máximo; devuelve false si el sistema lo limitó. */
    private fun setMaxVolume(): Boolean {
        val stream = AudioManager.STREAM_MUSIC
        if (savedVolume == null) savedVolume = audioManager.getStreamVolume(stream)
        val max = audioManager.getStreamMaxVolume(stream)
        audioManager.setStreamVolume(stream, max, 0)
        return audioManager.getStreamVolume(stream) == max
    }

    private fun restoreVolume() {
        savedVolume?.let { audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, it, 0) }
        savedVolume = null
    }

    private companion object {
        const val SAMPLE_RATE = 48000
        const val RAMP_MS = 30
    }
}
