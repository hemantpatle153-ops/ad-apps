package `in`.onlysoftware.multi_speaker

import android.annotation.SuppressLint
import android.annotation.TargetApi
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioPlaybackCaptureConfiguration
import android.media.AudioRecord
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper

// Live mode on the host: records what other apps are playing (Android 10+
// playback capture) and hands it to Dart in 20 ms chunks, which sends it to
// the speakers. Android only allows this from a foreground service that
// holds the user's "Start now" screen-cast consent.
@TargetApi(29)
class CaptureService : Service() {
    companion object {
        const val EXTRA_RESULT_DATA = "data"
        const val SAMPLE_RATE = 48000
        const val CHUNK_BYTES = 960 * 4 // 20 ms of 16-bit stereo.
        private const val CHANNEL_ID = "live"
        private const val NOTIFICATION_ID = 4780

        // Set by MainActivity while Dart listens; called on the main thread.
        // An empty chunk tells Dart the capture stopped.
        @Volatile var sink: ((ByteArray) -> Unit)? = null
        @Volatile var running = false
    }

    private val main = Handler(Looper.getMainLooper())
    private var projection: MediaProjection? = null
    private var record: AudioRecord? = null
    private var thread: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (running) return START_NOT_STICKY
        @Suppress("DEPRECATION")
        val data = intent?.getParcelableExtra<Intent>(EXTRA_RESULT_DATA)
        if (data == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        // Must be in the foreground before asking for the projection.
        startForeground(NOTIFICATION_ID, notification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        try {
            val manager = getSystemService(MediaProjectionManager::class.java)
            val p = manager.getMediaProjection(Activity.RESULT_OK, data)
            projection = p
            // Android 14 needs a callback before capturing; it also fires
            // when the user stops casting from the system.
            p.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() { stopSelf() }
            }, main)
            startCapture(p)
        } catch (e: Exception) {
            stopSelf()
        }
        return START_NOT_STICKY
    }

    @SuppressLint("MissingPermission") // MainActivity checks RECORD_AUDIO first.
    private fun startCapture(p: MediaProjection) {
        val config = AudioPlaybackCaptureConfiguration.Builder(p)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .build()
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(SAMPLE_RATE)
            .setChannelMask(AudioFormat.CHANNEL_IN_STEREO)
            .build()
        val min = AudioRecord.getMinBufferSize(SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        val r = AudioRecord.Builder()
            .setAudioFormat(format)
            .setBufferSizeInBytes(maxOf(min, CHUNK_BYTES * 8))
            .setAudioPlaybackCaptureConfig(config)
            .build()
        record = r
        r.startRecording()
        running = true
        thread = Thread({
            while (running) {
                val chunk = ByteArray(CHUNK_BYTES)
                var got = 0
                while (running && got < CHUNK_BYTES) {
                    val n = r.read(chunk, got, CHUNK_BYTES - got, AudioRecord.READ_BLOCKING)
                    if (n < 0) { running = false; break }
                    got += n
                }
                if (got == CHUNK_BYTES) main.post { sink?.invoke(chunk) }
            }
        }, "live-capture").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    override fun onDestroy() {
        running = false
        thread?.join(500)
        thread = null
        record?.let {
            try { it.stop() } catch (e: Exception) {}
            it.release()
        }
        record = null
        projection?.stop()
        projection = null
        main.post { sink?.invoke(ByteArray(0)) }
        super.onDestroy()
    }

    private fun notification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(
            CHANNEL_ID, "Live sound", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_speaker)
            .setContentTitle("Sending this phone's sound")
            .setContentText("Every speaker in your party plays what this phone plays.")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }
}
