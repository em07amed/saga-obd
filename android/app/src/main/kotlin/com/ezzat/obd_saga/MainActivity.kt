package com.ezzat.obd_saga

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.Intent
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

        channel = MethodChannel(messenger, "obd/bt")
        channel!!.setMethodCallHandler { call, result ->
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
                "nowPlaying" -> result.success(nowPlaying())
                "setPipAllowed" -> {
                    pipAllowed = call.argument<Boolean>("allowed") ?: false
                    result.success(null)
                }
                "openGoogleMaps" -> {
                    val lat = call.argument<Double>("lat")
                    val lng = call.argument<Double>("lng")
                    result.success(openGoogleMaps(lat, lng))
                }
                "mediaControl" -> {
                    mediaControl(call.argument<String>("action") ?: "play_pause")
                    result.success(null)
                }
                "openNotificationAccess" -> {
                    try {
                        startActivity(Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                    } catch (_: Exception) {}
                    result.success(null)
                }
                "contacts" -> io.execute {
                    val list = try { contacts() } catch (_: Exception) { emptyList() }
                    main.post { result.success(list) }
                }
                "call" -> {
                    val number = call.argument<String>("number") ?: ""
                    try {
                        startActivity(
                            Intent(Intent.ACTION_CALL, android.net.Uri.parse("tel:" + android.net.Uri.encode(number)))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CALL", e.message, null)
                    }
                }
                "mediaKey" -> {
                    mediaKey(call.argument<String>("key") ?: "play_pause")
                    result.success(null)
                }
                "launch" -> {
                    result.success(launch(call.argument<String>("kind") ?: ""))
                }
                "beep" -> {
                    beep()
                    result.success(null)
                }
                "speak" -> {
                    speak(
                        call.argument<String>("text") ?: "",
                        call.argument<String>("lang") ?: "ar",
                        call.argument<Boolean>("flush") ?: false
                    )
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

    // ---- floating window over other apps (Picture-in-Picture) ----
    private var channel: MethodChannel? = null
    private var pipAllowed = false

    private fun enterPip(): Boolean {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.O) return false
        return try {
            enterPictureInPictureMode(
                android.app.PictureInPictureParams.Builder()
                    .setAspectRatio(android.util.Rational(16, 9))
                    .build()
            )
        } catch (_: Exception) {
            false
        }
    }

    /** Leaving drive mode for another app (Home, Recents): float instead. */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipAllowed) enterPip()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pip", isInPictureInPictureMode)
    }

    /** Google Maps turn-by-turn to a point, or just the app; then float. */
    private fun openGoogleMaps(lat: Double?, lng: Double?): Boolean {
        val uri = if (lat != null && lng != null)
            android.net.Uri.parse("google.navigation:q=$lat,$lng&mode=d")
        else android.net.Uri.parse("geo:0,0?q=")
        val intent = Intent(Intent.ACTION_VIEW, uri)
            .setPackage("com.google.android.apps.maps")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            if (pipAllowed) enterPip()
            startActivity(intent)
            true
        } catch (_: Exception) {
            // Google Maps missing: any maps app, without guidance.
            try {
                startActivity(Intent(Intent.ACTION_VIEW,
                    if (lat != null && lng != null) android.net.Uri.parse("geo:$lat,$lng?q=$lat,$lng")
                    else android.net.Uri.parse("geo:0,0?q="))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            } catch (_: Exception) { false }
        }
    }

    // ---- spoken alerts (Android TextToSpeech, no plugin needed) ----
    private var tts: android.speech.tts.TextToSpeech? = null
    private var ttsReady = false
    private val pendingSpeech = mutableListOf<Pair<String, String>>()
    private var flushNext = false

    private fun speak(text: String, lang: String, flush: Boolean = false) {
        flushNext = flush
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

    // ---- now playing (needs notification access) ----

    private fun hasNotificationAccess(): Boolean {
        val flat = android.provider.Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners") ?: return false
        return flat.contains(packageName)
    }

    private fun activeController(): android.media.session.MediaController? {
        if (!hasNotificationAccess()) return null
        return try {
            val msm = getSystemService(Context.MEDIA_SESSION_SERVICE) as android.media.session.MediaSessionManager
            val sessions = msm.getActiveSessions(
                android.content.ComponentName(this, MediaListenerService::class.java))
            sessions.firstOrNull {
                it.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING
            } ?: sessions.firstOrNull()
        } catch (_: Exception) {
            null
        }
    }

    private fun nowPlaying(): Map<String, Any?> {
        if (!hasNotificationAccess()) return mapOf("access" to false)
        val c = activeController() ?: return mapOf("access" to true)
        val md = c.metadata
        val art = md?.getBitmap(android.media.MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: md?.getBitmap(android.media.MediaMetadata.METADATA_KEY_ART)
        var artBytes: ByteArray? = null
        if (art != null) {
            val scaled = android.graphics.Bitmap.createScaledBitmap(art, 256, 256, true)
            val out = java.io.ByteArrayOutputStream()
            scaled.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, out)
            artBytes = out.toByteArray()
        }
        val appName = try {
            packageManager.getApplicationLabel(
                packageManager.getApplicationInfo(c.packageName, 0)).toString()
        } catch (_: Exception) { c.packageName }
        return mapOf(
            "access" to true,
            "title" to md?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE),
            "artist" to (md?.getString(android.media.MediaMetadata.METADATA_KEY_ARTIST)
                ?: md?.getString(android.media.MediaMetadata.METADATA_KEY_ALBUM_ARTIST)),
            "app" to appName,
            "playing" to (c.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING),
            "art" to artBytes
        )
    }

    private fun mediaControl(action: String) {
        val c = activeController()
        if (c == null) {
            mediaKey(action)
            return
        }
        val t = c.transportControls
        when (action) {
            "next" -> t.skipToNext()
            "prev" -> t.skipToPrevious()
            else -> if (c.playbackState?.state == android.media.session.PlaybackState.STATE_PLAYING) t.pause() else t.play()
        }
    }

    // ---- contacts ----

    private fun contacts(): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        val seen = HashSet<String>()
        val uri = android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI
        val cols = arrayOf(
            android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER,
            android.provider.ContactsContract.CommonDataKinds.Phone.STARRED
        )
        contentResolver.query(uri, cols, null, null,
            android.provider.ContactsContract.CommonDataKinds.Phone.STARRED + " DESC, " +
                android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC"
        )?.use { cur ->
            while (cur.moveToNext() && out.size < 2000) {
                val name = cur.getString(0) ?: continue
                val number = cur.getString(1) ?: continue
                val key = name + number.filter { it.isDigit() }.takeLast(9)
                if (!seen.add(key)) continue
                out.add(mapOf("name" to name, "number" to number, "starred" to (cur.getInt(2) == 1)))
            }
        }
        return out
    }

    /** Play/pause/next/previous for whatever music app is playing. */
    private fun mediaKey(key: String) {
        val code = when (key) {
            "next" -> android.view.KeyEvent.KEYCODE_MEDIA_NEXT
            "prev" -> android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
        }
        val am = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
        am.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, code))
        am.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, code))
    }

    /** Opens maps, the dialer, the music app or the voice assistant. */
    private fun launch(kind: String): Boolean {
        val intent = when (kind) {
            "maps" -> Intent(Intent.ACTION_VIEW, android.net.Uri.parse("geo:0,0?q="))
            "dialer" -> Intent(Intent.ACTION_DIAL)
            "music" -> Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_MUSIC)
            "assistant" -> Intent(Intent.ACTION_VOICE_COMMAND)
            else -> return false
        }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /** Two short warning beeps, no words. */
    private fun beep() {
        try {
            val tg = android.media.ToneGenerator(android.media.AudioManager.STREAM_ALARM, 100)
            tg.startTone(android.media.ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD, 600)
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({ tg.release() }, 900)
        } catch (_: Exception) {
        }
    }

    private fun say(text: String, lang: String) {
        val engine = tts ?: return
        val wanted = java.util.Locale(lang)
        val ok = engine.isLanguageAvailable(wanted) >= android.speech.tts.TextToSpeech.LANG_AVAILABLE
        engine.language = if (ok) wanted else java.util.Locale.ENGLISH
        val mode = if (flushNext) android.speech.tts.TextToSpeech.QUEUE_FLUSH
                   else android.speech.tts.TextToSpeech.QUEUE_ADD
        engine.speak(text, mode, null, "alert${System.nanoTime()}")
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
