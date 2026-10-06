package `in`.onlysoftware.video_player

import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import android.util.Rational
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity keeps the Flutter engine alive for background audio.
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null
    private var autoPip = false
    private var aspect = Rational(16, 9)
    private var pendingUri: String? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingUri = viewUri(intent)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "in.onlysoftware.video_player/system",
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "pipSupported" -> result.success(pipSupported())
                    "enterPip" -> {
                        setAspect(call.argument<Int>("w"), call.argument<Int>("h"))
                        result.success(enterPip())
                    }
                    "setAutoPip" -> {
                        autoPip = call.argument<Boolean>("enabled") == true
                        setAspect(call.argument<Int>("w"), call.argument<Int>("h"))
                        applyPipParams()
                        result.success(null)
                    }
                    "moveToBack" -> result.success(moveTaskToBack(true))
                    "holdNetwork" -> {
                        holdNetwork()
                        result.success(null)
                    }
                    "releaseNetwork" -> {
                        releaseNetwork()
                        result.success(null)
                    }
                    "deviceName" -> result.success(
                        Settings.Global.getString(contentResolver, "device_name")
                            ?.takeIf { it.isNotBlank() } ?: Build.MODEL
                    )
                    "takeOpenedUri" -> {
                        result.success(pendingUri)
                        pendingUri = null
                    }
                    "speechEnergy" -> {
                        val uri = call.argument<String>("uri")
                        val start = call.argument<Number>("startMs")?.toLong() ?: 0L
                        val length = call.argument<Number>("durationMs")?.toLong() ?: 0L
                        val frame = call.argument<Int>("frameMs") ?: 100
                        if (uri == null || length <= 0) {
                            result.error("args", "uri and durationMs are needed", null)
                        } else {
                            Thread {
                                try {
                                    val e = SpeechEnergy.read(applicationContext, uri, start, length, frame)
                                    runOnUiThread { result.success(e) }
                                } catch (ex: Exception) {
                                    runOnUiThread { result.error("decode", ex.message, null) }
                                }
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // A cached engine may already be running Dart, which then never asks
        // for the uri again, so offer it directly too.
        pendingUri?.let { uri ->
            channel?.invokeMethod("openUri", uri, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    pendingUri = null
                }

                override fun error(code: String, message: String?, details: Any?) {}

                override fun notImplemented() {}
            })
        }
    }

    // Watch parties: keep Wi-Fi fast and listening to beacons.
    private fun holdNetwork() {
        try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            if (wifiLock == null) {
                @Suppress("DEPRECATION")
                val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                    else WifiManager.WIFI_MODE_FULL_HIGH_PERF
                wifiLock = wifi.createWifiLock(mode, "video_player").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
            if (multicastLock == null) {
                multicastLock = wifi.createMulticastLock("video_player").apply {
                    setReferenceCounted(false)
                    acquire()
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun releaseNetwork() {
        wifiLock?.release()
        wifiLock = null
        multicastLock?.release()
        multicastLock = null
    }

    // "Open with" from a file manager or another app.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val uri = viewUri(intent) ?: return
        channel?.invokeMethod("openUri", uri)
    }

    private fun viewUri(intent: Intent?): String? =
        if (intent?.action == Intent.ACTION_VIEW) intent.data?.toString() else null

    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun setAspect(w: Int?, h: Int?) {
        if (w == null || h == null || w <= 0 || h <= 0) return
        // Android only accepts ratios between 1:2.39 and 2.39:1.
        val r = (w.toDouble() / h).coerceIn(1 / 2.39 + 0.01, 2.39 - 0.01)
        aspect = Rational((r * 1000).toInt(), 1000)
    }

    private fun pipParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val builder = PictureInPictureParams.Builder().setAspectRatio(aspect)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoPip)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun applyPipParams() {
        if (!pipSupported()) return
        try {
            pipParams()?.let { setPictureInPictureParams(it) }
        } catch (_: Exception) {
        }
    }

    private fun enterPip(): Boolean {
        if (!pipSupported()) return false
        return try {
            pipParams()?.let { enterPictureInPictureMode(it) } ?: false
        } catch (_: Exception) {
            false
        }
    }

    // Android 8 to 11 have no auto-enter flag, so enter on the home button.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoPip && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) enterPip()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }
}
