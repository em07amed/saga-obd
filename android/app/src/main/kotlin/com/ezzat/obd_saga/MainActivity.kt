package com.ezzat.obd_saga

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Bluetooth Classic (SPP / RFCOMM) bridge for ELM327 adapters.
 *
 * MethodChannel "obd/bt":
 *   isEnabled() -> Boolean
 *   bondedDevices() -> List<{name, address}>
 *   connect({address}) -> true
 *   write({data})
 *   disconnect()
 *
 * EventChannel "obd/bt/events": raw ASCII chunks from the adapter.
 * A chunk equal to "\u0000DISCONNECTED" means the link dropped.
 */
class MainActivity : FlutterActivity() {
    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()

    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var out: OutputStream? = null
    @Volatile private var generation = 0
    private var sink: EventChannel.EventSink? = null

    private fun adapter(): BluetoothAdapter? =
        (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "obd/bt/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })

        MethodChannel(messenger, "obd/bt").setMethodCallHandler { call, result ->
            when (call.method) {
                "isEnabled" -> result.success(adapter()?.isEnabled == true)
                "bondedDevices" -> bondedDevices(result)
                "connect" -> {
                    val address = call.argument<String>("address")
                    if (address == null) result.error("ARG", "address is required", null)
                    else connect(address, result)
                }
                "write" -> {
                    val data = call.argument<String>("data")
                    if (data == null) result.error("ARG", "data is required", null)
                    else write(data, result)
                }
                "startKeepAlive" -> {
                    try {
                        ObdKeepAliveService.start(
                            this,
                            call.argument<String>("title") ?: "Car OBD",
                            call.argument<String>("text") ?: ""
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE", e.message, null)
                    }
                }
                "notify" -> {
                    alert(
                        call.argument<String>("title") ?: "",
                        call.argument<String>("text") ?: "",
                        call.argument<Boolean>("sound") ?: true
                    )
                    result.success(null)
                }
                "speak" -> {
                    speak(call.argument<String>("text") ?: "", call.argument<String>("lang") ?: "ar")
                    result.success(null)
                }
                "stopKeepAlive" -> {
                    ObdKeepAliveService.stop(this)
                    result.success(null)
                }
                "disconnect" -> {
                    io.execute { closeSocket() }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun bondedDevices(result: MethodChannel.Result) {
        try {
            val list = adapter()?.bondedDevices?.map {
                mapOf("name" to (it.name ?: it.address), "address" to it.address)
            } ?: emptyList()
            result.success(list)
        } catch (e: SecurityException) {
            result.error("PERMISSION", e.message, null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun connect(address: String, result: MethodChannel.Result) {
        io.execute {
            closeSocket()
            try {
                val ad = adapter() ?: throw IllegalStateException("Bluetooth not available")
                if (!ad.isEnabled) throw IllegalStateException("Bluetooth is off")
                // cancelDiscovery() needs BLUETOOTH_SCAN on Android 12+; we never
                // scan (paired devices only), so skip it if not permitted.
                try { ad.cancelDiscovery() } catch (_: SecurityException) {}
                val device = ad.getRemoteDevice(address)
                val s = openSocket(device)
                socket = s
                out = s.outputStream
                val gen = ++generation
                startReader(s.inputStream, gen)
                main.post { result.success(true) }
            } catch (e: Exception) {
                closeSocket()
                main.post { result.error("CONNECT", e.message ?: e.toString(), null) }
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun openSocket(device: BluetoothDevice): BluetoothSocket {
        val first = device.createRfcommSocketToServiceRecord(sppUuid)
        try {
            first.connect()
            return first
        } catch (e: Exception) {
            try { first.close() } catch (_: Exception) {}
        }
        // Fallback used by many cheap ELM327 clones.
        val fallback = device.javaClass
            .getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
            .invoke(device, 1) as BluetoothSocket
        fallback.connect()
        return fallback
    }

    private fun startReader(input: InputStream, gen: Int) {
        Thread {
            val buf = ByteArray(1024)
            try {
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    if (n > 0) {
                        val text = String(buf, 0, n, Charsets.US_ASCII)
                        main.post { if (gen == generation) sink?.success(text) }
                    }
                }
            } catch (_: Exception) {
            }
            main.post { if (gen == generation) sink?.success("\u0000DISCONNECTED") }
        }.apply {
            isDaemon = true
            start()
        }
    }

    private fun write(data: String, result: MethodChannel.Result) {
        val o = out
        if (o == null) {
            result.error("NOT_CONNECTED", "not connected", null)
            return
        }
        io.execute {
            try {
                o.write(data.toByteArray(Charsets.US_ASCII))
                o.flush()
                main.post { result.success(null) }
            } catch (e: Exception) {
                main.post { result.error("WRITE", e.message ?: e.toString(), null) }
            }
        }
    }

    private var alertId = 100

    // ---- spoken alerts (Android TextToSpeech, no plugin needed) ----
    private var tts: android.speech.tts.TextToSpeech? = null
    private var ttsReady = false
    private val pendingSpeech = mutableListOf<Pair<String, String>>()

    private fun speak(text: String, lang: String) {
        if (text.isBlank()) return
        val engine = tts
        if (engine == null) {
            pendingSpeech.add(text to lang)
            tts = android.speech.tts.TextToSpeech(applicationContext) { status ->
                ttsReady = status == android.speech.tts.TextToSpeech.SUCCESS
                if (ttsReady) {
                    tts?.setAudioAttributes(
                        android.media.AudioAttributes.Builder()
                            .setUsage(android.media.AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
                            .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build()
                    )
                    pendingSpeech.forEach { (t, l) -> say(t, l) }
                }
                pendingSpeech.clear()
            }
            return
        }
        if (ttsReady) say(text, lang) else pendingSpeech.add(text to lang)
    }

    private fun say(text: String, lang: String) {
        val engine = tts ?: return
        val wanted = java.util.Locale(lang)
        val ok = engine.isLanguageAvailable(wanted) >= android.speech.tts.TextToSpeech.LANG_AVAILABLE
        engine.language = if (ok) wanted else java.util.Locale.ENGLISH
        engine.speak(text, android.speech.tts.TextToSpeech.QUEUE_ADD, null, "alert${System.nanoTime()}")
    }

    private fun alert(title: String, text: String, sound: Boolean) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        val channel = if (sound) "obd_alerts" else "obd_info"
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                android.app.NotificationChannel(
                    channel,
                    if (sound) "Car alerts" else "Reminders",
                    if (sound) android.app.NotificationManager.IMPORTANCE_HIGH
                    else android.app.NotificationManager.IMPORTANCE_DEFAULT
                ).apply { enableVibration(sound) }
            )
        }
        val builder = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, channel)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(this).apply {
                if (sound) setDefaults(android.app.Notification.DEFAULT_ALL)
            }
        }
        val n = builder
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(android.app.Notification.BigTextStyle().bigText(text))
            .setSmallIcon(R.mipmap.ic_launcher)
            .setAutoCancel(true)
            .build()
        try { nm.notify(alertId++, n) } catch (_: SecurityException) {}
    }

    private fun closeSocket() {
        try { socket?.close() } catch (_: Exception) {}
        socket = null
        out = null
    }

    override fun onDestroy() {
        tts?.shutdown()
        tts = null
        ObdKeepAliveService.stop(this)
        generation++
        closeSocket()
        super.onDestroy()
    }
}
