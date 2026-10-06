package `in`.onlysoftware.doc_scanner

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hands PDFs and photos that other apps "Open with" or "Share to" Doc
 * Scanner to Flutter (copied into the app's cache), and opens this app's
 * settings page when camera access was turned off.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: List<Map<String, String>> = emptyList()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pending = readShared(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "in.onlysoftware.doc_scanner/system").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeSharedFiles" -> {
                        result.success(pending)
                        pending = emptyList()
                    }
                    "openAppSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val files = readShared(intent)
        if (files.isNotEmpty()) channel?.invokeMethod("shared", files)
    }

    private fun readShared(intent: Intent?): List<Map<String, String>> {
        if (intent == null) return emptyList()
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it) }
            Intent.ACTION_SEND -> streamExtra(intent)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> uris.addAll(streamListExtra(intent))
        }
        // Only handle each launch intent once.
        intent.action = null
        return uris.mapNotNull { copy(it) }
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableExtra(Intent.EXTRA_STREAM)

    @Suppress("DEPRECATION")
    private fun streamListExtra(intent: Intent): List<Uri> =
        (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)) ?: emptyList()

    private fun copy(uri: Uri): Map<String, String>? = try {
        val mime = contentResolver.getType(uri) ?: ""
        var name = uri.lastPathSegment?.substringAfterLast('/') ?: "file"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst() && !c.isNull(0)) name = c.getString(0)
        }
        name = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
        val dir = File(cacheDir, "shared").apply { mkdirs() }
        val out = File(dir, "${System.currentTimeMillis()}_$name")
        contentResolver.openInputStream(uri)?.use { input -> out.outputStream().use { input.copyTo(it) } }
        mapOf("path" to out.absolutePath, "mime" to mime, "name" to name)
    } catch (e: Exception) {
        null
    }
}
