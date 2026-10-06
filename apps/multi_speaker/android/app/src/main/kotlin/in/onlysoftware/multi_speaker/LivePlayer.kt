package `in`.onlysoftware.multi_speaker

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTimestamp
import android.media.AudioTrack
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

// Live mode on a speaker phone: plays the host's sound so that each chunk
// comes out at the moment Dart asked for. The player's own timestamps say
// when the next written frame will be heard; when that drifts more than a
// few ms from the plan, frames are skipped or silence is added.
class LivePlayer {
    private class Chunk(val pcm: ByteArray, val atNs: Long)

    private val rate = CaptureService.SAMPLE_RATE
    private val bytesPerFrame = 4
    private val toleranceNs = 15_000_000L
    private val queue = LinkedBlockingQueue<Chunk>()
    @Volatile private var running = false
    @Volatile private var volume = 1f
    private var track: AudioTrack? = null
    private var thread: Thread? = null

    @Synchronized
    fun start() {
        if (running) return
        val min = AudioTrack.getMinBufferSize(rate,
            AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        val t = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build())
            .setAudioFormat(AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setSampleRate(rate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                .build())
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setBufferSizeInBytes(maxOf(min, rate * bytesPerFrame / 10)) // 100 ms
            .build()
        t.setVolume(volume)
        t.play()
        track = t
        queue.clear()
        running = true
        thread = Thread({ loop(t) }, "live-play").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    /** Queues [pcm] to be heard [inUs] microseconds from now. */
    fun push(pcm: ByteArray, inUs: Long) {
        if (!running) return
        queue.offer(Chunk(pcm, System.nanoTime() + inUs * 1000))
        // Never build up more than a couple of seconds.
        while (queue.size > 100) queue.poll()
    }

    fun setVolume(v: Float) {
        volume = v.coerceIn(0f, 1f)
        track?.setVolume(volume)
    }

    @Synchronized
    fun stop() {
        running = false
        thread?.join(500)
        thread = null
        track?.let {
            try { it.pause(); it.flush(); it.stop() } catch (e: Exception) {}
            it.release()
        }
        track = null
        queue.clear()
    }

    private fun loop(t: AudioTrack) {
        val ts = AudioTimestamp()
        var written = 0L // Frames written since start.
        val bufferNs = t.bufferSizeInFrames * 1_000_000_000L / rate
        while (running) {
            val c = queue.poll(100, TimeUnit.MILLISECONDS) ?: continue
            var offset = 0
            // When the next frame written now will be heard.
            val heardAt = if (t.getTimestamp(ts)) {
                ts.nanoTime + (written - ts.framePosition) * 1_000_000_000L / rate
            } else {
                // Not playing yet: assume the buffer's length.
                System.nanoTime() + bufferNs
            }
            val err = heardAt - c.atNs
            if (err > toleranceNs) {
                // Running late: skip the start of this chunk.
                val skip = (err * rate / 1_000_000_000L).toInt() * bytesPerFrame
                if (skip >= c.pcm.size) continue
                offset = skip
            } else if (err < -toleranceNs) {
                // Running early: wait with silence.
                val frames = minOf(-err * rate / 1_000_000_000L, rate.toLong() / 2).toInt()
                written += writeFully(t, ByteArray(frames * bytesPerFrame), 0) / bytesPerFrame
            }
            written += writeFully(t, c.pcm, offset) / bytesPerFrame
        }
    }

    private fun writeFully(t: AudioTrack, data: ByteArray, from: Int): Int {
        var pos = from
        while (running && pos < data.size) {
            val n = t.write(data, pos, data.size - pos)
            if (n <= 0) break
            pos += n
        }
        return pos - from
    }
}
