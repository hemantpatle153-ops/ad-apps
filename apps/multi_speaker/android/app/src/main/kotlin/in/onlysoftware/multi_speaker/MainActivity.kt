package `in`.onlysoftware.multi_speaker

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothStatusCodes
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.net.wifi.WifiManager
import android.os.Build
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity (from just_audio_background) keeps music playing
// with the screen off; the channel below adds the few Android calls the app
// needs (see lib/src/platform/native.dart).
class MainActivity : AudioServiceActivity() {
    companion object {
        private const val REQUEST_AUDIO = 4781
        private const val REQUEST_CAPTURE = 4782
    }

    private var wifiLock: WifiManager.WifiLock? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private val livePlayer = LivePlayer()

    // The Dart call waiting for the user to allow live capture.
    private var captureResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "in.onlysoftware.multi_speaker/native")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "holdNetwork" -> { holdNetwork(); result.success(null) }
                        "releaseNetwork" -> { releaseNetwork(); result.success(null) }
                        "openBluetoothSettings" -> {
                            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                            result.success(null)
                        }
                        "openHotspotSettings" -> { openHotspotSettings(); result.success(null) }
                        "openMediaOutput" -> { openMediaOutput(); result.success(null) }
                        "deviceName" -> result.success(deviceName())
                        "audioOutput" -> result.success(audioOutput())
                        "bluetoothFeatures" -> result.success(bluetoothFeatures())
                        "liveCaptureSupported" -> result.success(Build.VERSION.SDK_INT >= 29)
                        "liveCaptureStart" -> startCapture(result)
                        "liveCaptureStop" -> {
                            stopService(Intent(this, CaptureService::class.java))
                            result.success(null)
                        }
                        "livePlayStart" -> { livePlayer.start(); result.success(null) }
                        "livePlayPush" -> {
                            val pcm = call.argument<ByteArray>("pcm")
                            val inUs = call.argument<Number>("in")?.toLong()
                            if (pcm != null && inUs != null) livePlayer.push(pcm, inUs)
                            result.success(null)
                        }
                        "livePlayVolume" -> {
                            livePlayer.setVolume(call.argument<Number>("v")?.toFloat() ?: 1f)
                            result.success(null)
                        }
                        "livePlayStop" -> { livePlayer.stop(); result.success(null) }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("native", e.message, null)
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "in.onlysoftware.multi_speaker/capture")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    CaptureService.sink = { events.success(it) }
                }
                override fun onCancel(arguments: Any?) {
                    CaptureService.sink = null
                }
            })
    }

    override fun onDestroy() {
        livePlayer.stop()
        if (Build.VERSION.SDK_INT >= 29) stopService(Intent(this, CaptureService::class.java))
        super.onDestroy()
    }

    // Live mode: microphone-type permission first (Android requires it for
    // playback capture), then the system "Start recording or casting?"
    // prompt, then the capture service.
    private fun startCapture(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 29) { result.success(false); return }
        if (CaptureService.running) { result.success(true); return }
        captureResult?.success(false)
        captureResult = result
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_AUDIO)
        } else {
            askToCapture()
        }
    }

    private fun askToCapture() {
        val manager = getSystemService(MediaProjectionManager::class.java)
        // Whole screen: sharing a single app doesn't capture other apps' sound.
        val intent = if (Build.VERSION.SDK_INT >= 34) {
            manager.createScreenCaptureIntent(MediaProjectionConfig.createConfigForDefaultDisplay())
        } else {
            manager.createScreenCaptureIntent()
        }
        startActivityForResult(intent, REQUEST_CAPTURE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_AUDIO) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            askToCapture()
        } else {
            captureResult?.success(false)
            captureResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_CAPTURE) return
        val ok = resultCode == Activity.RESULT_OK && data != null
        if (ok && Build.VERSION.SDK_INT >= 29) {
            startForegroundService(Intent(this, CaptureService::class.java)
                .putExtra(CaptureService.EXTRA_RESULT_DATA, data))
        }
        captureResult?.success(ok)
        captureResult = null
    }

    private fun holdNetwork() {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (wifiLock == null) {
            @Suppress("DEPRECATION")
            val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                else WifiManager.WIFI_MODE_FULL_HIGH_PERF
            wifiLock = wifi.createWifiLock(mode, "multi_speaker").apply {
                setReferenceCounted(false); acquire()
            }
        }
        if (multicastLock == null) {
            multicastLock = wifi.createMulticastLock("multi_speaker").apply {
                setReferenceCounted(false); acquire()
            }
        }
    }

    private fun releaseNetwork() {
        wifiLock?.release(); wifiLock = null
        multicastLock?.release(); multicastLock = null
    }

    private fun openHotspotSettings() {
        val tether = Intent().setComponent(
            ComponentName("com.android.settings", "com.android.settings.TetherSettings"))
        try {
            startActivity(tether)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_WIRELESS_SETTINGS))
        }
    }

    // The "where is this playing" panel; on Samsung it is where Dual audio
    // ticks two speakers. Falls back to Bluetooth settings.
    private fun openMediaOutput() {
        val panel = Intent("com.android.settings.panel.action.MEDIA_OUTPUT")
            .putExtra("com.android.settings.panel.extra.PACKAGE_NAME", packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(panel)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
        }
    }

    private fun deviceName(): String =
        Settings.Global.getString(contentResolver, "device_name")?.takeIf { it.isNotBlank() }
            ?: Build.MODEL

    private fun audioOutput(): Map<String, Any?> {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val bt = mutableSetOf(
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_HEARING_AID)
        if (Build.VERSION.SDK_INT >= 31) {
            bt += AudioDeviceInfo.TYPE_BLE_HEADSET
            bt += AudioDeviceInfo.TYPE_BLE_SPEAKER
        }
        if (Build.VERSION.SDK_INT >= 33) bt += AudioDeviceInfo.TYPE_BLE_BROADCAST
        // Media goes to a connected Bluetooth speaker by default.
        val device = audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { it.type in bt }
        return mapOf("bluetooth" to (device != null), "name" to device?.productName?.toString())
    }

    private fun bluetoothFeatures(): Map<String, Any?> {
        var broadcast = false
        if (Build.VERSION.SDK_INT >= 33) {
            try {
                val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
                broadcast = adapter?.isLeAudioBroadcastSourceSupported ==
                    BluetoothStatusCodes.FEATURE_SUPPORTED
            } catch (e: Exception) {
                broadcast = false
            }
        }
        return mapOf("leAudioBroadcast" to broadcast, "maker" to Build.MANUFACTURER)
    }
}
