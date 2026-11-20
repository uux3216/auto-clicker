package __PKG__

import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.NoiseSuppressor
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ConcurrentLinkedQueue

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    private val rate = 16000
    private val frame = 320 // 20 ms of 16 kHz mono

    private var recorder: AudioRecord? = null
    private var recThread: Thread? = null
    @Volatile private var recording = false
    private var aec: AcousticEchoCanceler? = null
    private var ns: NoiseSuppressor? = null

    private var track: AudioTrack? = null
    private var mixThread: Thread? = null
    @Volatile private var playing = false
    private val queues = ConcurrentHashMap<String, ConcurrentLinkedQueue<ShortArray>>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "hl/mic").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })

        MethodChannel(messenger, "hl/media").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val ok = try {
                        startAudio(call.argument<Boolean>("speaker") ?: false)
                    } catch (e: Exception) {
                        false
                    }
                    result.success(ok)
                }
                "stop" -> {
                    stopAudio()
                    result.success(null)
                }
                "speaker" -> {
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    am.isSpeakerphoneOn = call.argument<Boolean>("on") ?: false
                    result.success(null)
                }
                "play" -> {
                    val id = call.argument<String>("id")
                    val data = call.argument<ByteArray>("data")
                    if (id != null && data != null) play(id, data)
                    result.success(null)
                }
                "jpeg" -> {
                    try {
                        val jpg = toJpeg(
                            call.argument<Int>("w")!!, call.argument<Int>("h")!!,
                            call.argument<ByteArray>("y")!!, call.argument<ByteArray>("u")!!,
                            call.argument<ByteArray>("v")!!, call.argument<Int>("ys")!!,
                            call.argument<Int>("uvs")!!, call.argument<Int>("uvp")!!,
                            call.argument<Int>("q") ?: 45
                        )
                        result.success(jpg)
                    } catch (e: Exception) {
                        result.error("jpeg", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startAudio(speaker: Boolean): Boolean {
        stopAudio()
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        am.mode = AudioManager.MODE_IN_COMMUNICATION
        am.isSpeakerphoneOn = speaker

        val minOut = AudioTrack.getMinBufferSize(
            rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        val t = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(rate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(maxOf(minOut, frame * 2 * 4))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        track = t
        t.play()
        playing = true
        mixThread = Thread { mixLoop() }.also { it.start() }

        val minIn = AudioRecord.getMinBufferSize(
            rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT
        )
        val rec = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION, rate,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
            maxOf(minIn, frame * 2 * 4)
        )
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            rec.release()
            stopAudio()
            return false
        }
        recorder = rec
        if (AcousticEchoCanceler.isAvailable()) {
            aec = AcousticEchoCanceler.create(rec.audioSessionId)
            aec?.enabled = true
        }
        if (NoiseSuppressor.isAvailable()) {
            ns = NoiseSuppressor.create(rec.audioSessionId)
            ns?.enabled = true
        }
        rec.startRecording()
        recording = true
        recThread = Thread { micLoop(rec) }.also { it.start() }
        return true
    }

    private fun micLoop(rec: AudioRecord) {
        val buf = ShortArray(frame)
        while (recording) {
            var n = 0
            while (n < frame && recording) {
                val r = rec.read(buf, n, frame - n)
                if (r <= 0) break
                n += r
            }
            if (n == frame && recording) {
                val bytes = ByteArray(frame * 2)
                for (i in 0 until frame) {
                    bytes[2 * i] = (buf[i].toInt() and 0xff).toByte()
                    bytes[2 * i + 1] = (buf[i].toInt() shr 8).toByte()
                }
                mainHandler.post { sink?.success(bytes) }
            }
        }
    }

    private fun mixLoop() {
        val out = ShortArray(frame)
        val acc = IntArray(frame)
        val primed = HashSet<String>()
        while (playing) {
            java.util.Arrays.fill(acc, 0)
            for ((id, q) in queues) {
                if (!primed.contains(id)) {
                    if (q.size >= 3) primed.add(id) else continue
                }
                val f = q.poll()
                if (f == null) {
                    primed.remove(id)
                    continue
                }
                val n = minOf(frame, f.size)
                for (i in 0 until n) acc[i] += f[i].toInt()
            }
            for (i in 0 until frame) out[i] = acc[i].coerceIn(-32768, 32767).toShort()
            val t = track ?: break
            try {
                t.write(out, 0, frame) // blocks ~20 ms, so this loop runs in real time
            } catch (e: Exception) {
                break
            }
        }
    }

    private fun play(id: String, data: ByteArray) {
        val n = data.size / 2
        val s = ShortArray(n)
        for (i in 0 until n) {
            s[i] = ((data[2 * i].toInt() and 0xff) or (data[2 * i + 1].toInt() shl 8)).toShort()
        }
        val q = queues.getOrPut(id) { ConcurrentLinkedQueue<ShortArray>() }
        if (q.size > 12) q.poll()
        q.add(s)
    }

    private fun stopAudio() {
        recording = false
        playing = false
        try { recorder?.stop() } catch (e: Exception) {}
        try { recThread?.join(400) } catch (e: Exception) {}
        try { mixThread?.join(400) } catch (e: Exception) {}
        recorder?.release()
        recorder = null
        aec?.release()
        aec = null
        ns?.release()
        ns = null
        try { track?.stop() } catch (e: Exception) {}
        track?.release()
        track = null
        queues.clear()
        try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.isSpeakerphoneOn = false
            am.mode = AudioManager.MODE_NORMAL
        } catch (e: Exception) {}
    }

    private fun toJpeg(
        w: Int, h: Int, y: ByteArray, u: ByteArray, v: ByteArray,
        ys: Int, uvs: Int, uvp: Int, q: Int
    ): ByteArray {
        val nv21 = ByteArray(w * h * 3 / 2)
        var pos = 0
        for (row in 0 until h) {
            val off = row * ys
            val len = minOf(w, y.size - off)
            if (len > 0) System.arraycopy(y, off, nv21, pos, len)
            pos += w
        }
        val ch = h / 2
        val cw = w / 2
        for (row in 0 until ch) {
            for (col in 0 until cw) {
                val idx = row * uvs + col * uvp
                nv21[pos++] = if (idx < v.size) v[idx] else 128.toByte()
                nv21[pos++] = if (idx < u.size) u[idx] else 128.toByte()
            }
        }
        val img = YuvImage(nv21, ImageFormat.NV21, w, h, null)
        val out = ByteArrayOutputStream()
        img.compressToJpeg(Rect(0, 0, w, h), q, out)
        return out.toByteArray()
    }

    override fun onDestroy() {
        stopAudio()
        super.onDestroy()
    }
}
