package `in`.onlysoftware.video_player

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import java.nio.ByteOrder
import kotlin.math.exp
import kotlin.math.log10

// Decodes part of a video's sound and returns its loudness per frame, so the
// app can line subtitles up with speech. Runs on a background thread.
object SpeechEnergy {
    private const val TIMEOUT_US = 10_000L

    fun read(context: Context, uri: String, startMs: Long, durationMs: Long, frameMs: Int): FloatArray {
        val frames = (durationMs / frameMs).toInt().coerceAtLeast(1)
        val power = DoubleArray(frames)
        val counts = IntArray(frames)
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            when {
                uri.startsWith("content://") -> extractor.setDataSource(context, Uri.parse(uri), null)
                uri.startsWith("file://") -> extractor.setDataSource(Uri.parse(uri).path!!)
                uri.startsWith("http") -> extractor.setDataSource(uri, emptyMap())
                else -> extractor.setDataSource(uri)
            }
            var track = -1
            var format: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                if (f.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) {
                    track = i
                    format = f
                    break
                }
            }
            if (track < 0 || format == null) throw IllegalStateException("no audio track")
            extractor.selectTrack(track)
            extractor.seekTo(startMs * 1000, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)

            val dec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = dec
            dec.configure(format, null, null, 0)
            dec.start()

            var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT).coerceAtLeast(1)
            var floatPcm = false
            // One-pole high-pass near 200 Hz keeps voices and drops bass and
            // rumble, which otherwise drown speech in action scenes.
            var alpha = exp(-2 * Math.PI * 200 / sampleRate)
            var prevIn = 0.0
            var prevOut = 0.0

            val endUs = (startMs + durationMs) * 1000
            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false
            val deadline = System.currentTimeMillis() + 90_000
            while (!outputDone && System.currentTimeMillis() < deadline) {
                if (!inputDone) {
                    val i = dec.dequeueInputBuffer(TIMEOUT_US)
                    if (i >= 0) {
                        val buf = dec.getInputBuffer(i)!!
                        val n = extractor.readSampleData(buf, 0)
                        val t = extractor.sampleTime
                        if (n < 0 || t > endUs) {
                            dec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            dec.queueInputBuffer(i, 0, n, t, 0)
                            extractor.advance()
                        }
                    }
                }
                val o = dec.dequeueOutputBuffer(info, TIMEOUT_US)
                if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val f = dec.outputFormat
                    sampleRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT).coerceAtLeast(1)
                    floatPcm = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                        f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
                    alpha = exp(-2 * Math.PI * 200 / sampleRate)
                } else if (o >= 0) {
                    if (info.size > 0) {
                        val out = dec.getOutputBuffer(o)!!.duplicate().order(ByteOrder.LITTLE_ENDIAN)
                        out.position(info.offset)
                        out.limit(info.offset + info.size)
                        val bytes = if (floatPcm) 4 else 2
                        val n = info.size / (bytes * channels)
                        val samplesPerFrame = sampleRate.toLong() * frameMs / 1000
                        val firstSample = (info.presentationTimeUs / 1000 - startMs) * sampleRate / 1000
                        for (k in 0 until n) {
                            var s = 0.0
                            for (c in 0 until channels) {
                                s += if (floatPcm) out.float.toDouble() else out.short / 32768.0
                            }
                            s /= channels
                            val hp = alpha * (prevOut + s - prevIn)
                            prevIn = s
                            prevOut = hp
                            val at = firstSample + k
                            val idx = if (at < 0) -1 else (at / samplesPerFrame).toInt()
                            if (idx in 0 until frames) {
                                power[idx] += hp * hp
                                counts[idx]++
                            }
                        }
                    }
                    dec.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
                }
            }
        } finally {
            try {
                codec?.stop()
            } catch (_: Exception) {
            }
            codec?.release()
            extractor.release()
        }
        // -1000 marks frames with nothing decoded (past the end of the file).
        return FloatArray(frames) {
            if (counts[it] == 0) -1000f else (10 * log10(power[it] / counts[it] + 1e-12)).toFloat()
        }
    }
}
