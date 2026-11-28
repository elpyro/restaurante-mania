package com.example.app.notificationsound

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Reproduce el aviso sonoro directamente desde la app.
 *
 * MIUI/HyperOS vuelve a aplicar la configuración que el usuario eligió para el
 * canal de notificaciones, así que el sonido del canal no es confiable: la
 * notificación llega pero no suena. Este plugin usa `SoundPool` con los OGG/WAV
 * de la propia APK y permite elegir el tono por categoría. Dart ya deduplica,
 * así que suena una sola vez por evento. Respeta Silencio/No molestar y volumen 0.
 */
class NotificationSoundPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private val mainHandler = Handler(Looper.getMainLooper())
    private var soundPool: SoundPool? = null
    private val soundIds = mutableMapOf<String, Int>()
    private val toneBySampleId = mutableMapOf<Int, String>()
    private var pendingTone: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val pool = SoundPool.Builder().setMaxStreams(2).setAudioAttributes(attributes).build()
        soundPool = pool
        pool.setOnLoadCompleteListener { _, sampleId, status ->
            val loadedTone = toneBySampleId[sampleId] ?: return@setOnLoadCompleteListener
            if (status != 0) {
                Log.w(TAG, "no se pudo cargar tone=$loadedTone status=$status")
                return@setOnLoadCompleteListener
            }
            Log.i(TAG, "sonido cargado tone=$loadedTone sampleId=$sampleId")
            if (pendingTone == loadedTone) {
                pendingTone = null
                playNow(loadedTone)
            }
        }
        loadSound("classic")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        soundPool?.release()
        soundPool = null
        soundIds.clear()
        toneBySampleId.clear()
        pendingTone = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "play") {
            val tone = canonical(call.argument<String>("tone"))
            mainHandler.post { play(tone) }
            result.success(true)
        } else {
            result.notImplemented()
        }
    }

    private fun canonical(tone: String?): String = when (tone) {
        "chime", "double", "soft" -> tone
        else -> "classic"
    }

    private fun resourceFor(tone: String): Int = when (tone) {
        "chime" -> R.raw.tone_chime
        "double" -> R.raw.tone_double
        "soft" -> R.raw.tone_soft
        else -> R.raw.alert_sound
    }

    private fun loadSound(tone: String) {
        val pool = soundPool ?: return
        if (soundIds.containsKey(tone)) return
        val sampleId = pool.load(context, resourceFor(tone), 1)
        soundIds[tone] = sampleId
        toneBySampleId[sampleId] = tone
    }

    private fun play(tone: String) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (audioManager.ringerMode == AudioManager.RINGER_MODE_SILENT ||
            notificationManager.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_NONE ||
            audioManager.getStreamVolume(AudioManager.STREAM_NOTIFICATION) == 0
        ) {
            Log.i(TAG, "sonido omitido: silencio/DND/volumen 0")
            return
        }
        if (!soundIds.containsKey(tone)) {
            pendingTone = tone
            loadSound(tone)
            Log.i(TAG, "sonido pendiente de carga tone=$tone")
            return
        }
        playNow(tone)
    }

    private fun playNow(tone: String) {
        val pool = soundPool ?: return
        val sampleId = soundIds[tone] ?: return
        val playing = pool.play(sampleId, 1f, 1f, 1, 0, 1f)
        Log.i(TAG, "play() -> $playing tone=$tone")
    }

    private companion object {
        const val TAG = "QASound"
        const val CHANNEL = "com.example.app/notification_sound"
    }
}
