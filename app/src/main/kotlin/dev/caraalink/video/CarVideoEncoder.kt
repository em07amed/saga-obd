package dev.caraalink.video

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Process
import android.view.Surface

/**
 * Surface-input H.264 encoder. Whatever is drawn to [inputSurface] (our car
 * home screen or Android Auto) comes out as Annex-B NAL units,
 * which is what the head unit's mirror data channel carries.
 */
class CarVideoEncoder(
    val width: Int,
    val height: Int,
    private val fps: Int,
    private val bitRate: Int,
    private val onFrame: (data: ByteArray, isConfig: Boolean, isKey: Boolean) -> Unit,
    /** The session log file; some phones (vivo) cut off the app's logcat seconds after launch. */
    private val log: (String) -> Unit,
) {
    private val thread = HandlerThread("CarVideoEncoder", Process.THREAD_PRIORITY_URGENT_DISPLAY).also { it.start() }
    private val codec: MediaCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
    lateinit var inputSurface: Surface
        private set
    @Volatile private var released = false

    fun start() {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            // CarbitLink's values: a keyframe every 3 s, and repeats only on a screen static for 100 ms.
            // Repeating every frame interval can slip copies between AA's frames and overflow the pull queue.
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 3)
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 100_000L)
            setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
            // 1920-wide frames exceed Level 3.1. QDLink 1.9.8 switches to 4.0 there too.
            val level = if (maxOf(width, height) >= 1920) MediaCodecInfo.CodecProfileLevel.AVCLevel4 else MediaCodecInfo.CodecProfileLevel.AVCLevel31
            setInteger(MediaFormat.KEY_LEVEL, level)
            setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            // No KEY_PRIORITY / KEY_OPERATING_RATE / QTI low-latency: 1.2.0 added them and two users' encoders
            // then never output a frame, so the car hung on initializing. 1.1.1 ran without them.
        }
        val callback = object : MediaCodec.Callback() {
            override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {}

            override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
                if (released) return
                try {
                    val buf = codec.getOutputBuffer(index)
                    if (buf != null && info.size > 0) {
                        val bytes = ByteArray(info.size)
                        buf.position(info.offset)
                        buf.get(bytes)
                        val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                        val isKey = info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0
                        onFrame(bytes, isConfig, isKey)
                    }
                    codec.releaseOutputBuffer(index, false)
                } catch (e: IllegalStateException) {
                    if (!released) log("encoder output failed: $e")
                }
            }

            override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
                log("encoder error: $e ${e.diagnosticInfo} recoverable=${e.isRecoverable} transient=${e.isTransient}")
            }

            override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
                log("encoder format: $format")
            }
        }
        val handler = Handler(thread.looper)
        codec.setCallback(callback, handler)
        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        } catch (e: Exception) {
            // Some encoders reject the baseline/level/low-latency hints; retry plain.
            log("encoder configure with hints failed, retrying plain: $e")
            listOf(MediaFormat.KEY_PROFILE, MediaFormat.KEY_LEVEL, MediaFormat.KEY_LOW_LATENCY).forEach { format.removeKey(it) }
            codec.reset()
            codec.setCallback(callback, handler)
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        }
        inputSurface = codec.createInputSurface()
        codec.start()
        log("encoder started: ${codec.name} ${width}x$height ${fps}fps ${bitRate}bps")
    }

    fun requestKeyFrame() {
        if (released) return
        runCatching { codec.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) }) }
    }

    fun release() {
        if (released) return
        released = true
        runCatching { codec.stop() }
        runCatching { codec.release() }
        runCatching { inputSurface.release() }
        thread.quitSafely()
    }
}
