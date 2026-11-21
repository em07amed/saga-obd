package dev.caraalink.road

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.annotation.StringRes
import androidx.core.content.ContextCompat
import dev.caraalink.R
import dev.caraalink.diagnostics.DiagnosticLogger
import dev.caraalink.settings.AppSettings
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/** What the car-screen overlay shows. */
data class RoadState(
    val speedKmh: Int? = null,
    /** Limit in force: the road's own when known, else the driver's manual one; null = none. */
    val limit: Int? = null,
    val limitFromRoad: Boolean = false,
    val over: Boolean = false,
    /** Metres to the next camera on our line, when one is within 1 km. */
    val cameraM: Int? = null,
    val cameraLimit: Int? = null,
    val muted: Boolean = false,
    /** Short confirmation shown for a few seconds ("Camera saved here"). */
    val note: String? = null,
)

/**
 * Speed warnings and speed-camera alerts while Android Auto is on the car
 * screen. Uses the phone's GPS, road limits and cameras from OpenStreetMap
 * (Overpass API), and speaks through the phone, which reaches the car over
 * Bluetooth like the rest of Android Auto's audio. Ported from Saga OBD's
 * road_service.dart / alerts.dart.
 *
 * All road state lives on one background thread ("road-alerts"); listeners
 * are called on that thread and must post to their own.
 */
object RoadAlerts {
    private const val UA = "AABridge-RoadAlerts/1.0 (+https://github.com/alimorgaan/AA-Bridge)"
    private val ENDPOINTS = listOf(
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    )
    private const val FIXES = "road_alerts"

    private val listeners = CopyOnWriteArraySet<(RoadState) -> Unit>()

    @Volatile
    var state = RoadState()
        private set

    fun addListener(l: (RoadState) -> Unit) {
        listeners += l
        l(state)
    }

    fun removeListener(l: (RoadState) -> Unit) {
        listeners -= l
    }

    private var users = 0
    private var app: Context? = null
    private var thread: HandlerThread? = null
    @Volatile private var handler: Handler? = null
    private val net = Executors.newSingleThreadExecutor()
    private var logger: DiagnosticLogger? = null

    private var tts: TextToSpeech? = null
    @Volatile private var ttsReady = false
    private var tone: ToneGenerator? = null
    private var focus: AudioFocusRequest? = null

    // ---- road-alerts thread only ----
    private var roads: List<Road> = emptyList()
    private var osmCams: List<SpeedCamera> = emptyList()
    private var myCams = mutableListOf<SpeedCamera>()
    private var hidden = mutableSetOf<Long>()
    private var cameras: List<SpeedCamera> = emptyList()
    private var fetchedAt: LatLon? = null
    private var fetchedTime = 0L
    private var lastAttempt = 0L
    private var fetching = false

    private var last: LatLon? = null
    private var lastFixAt = 0L
    private var speedKmh: Double? = null
    private var heading = Double.NaN

    private var roadId: Long? = null
    private var roadLimit: Int? = null
    private var candidate: Long? = null
    private var roadSeen = 0L

    private var next: CameraAhead? = null
    private var speeding = false
    private var lastNag = 0L
    private var muted = false
    private var note: String? = null
    private var noteUntil = 0L

    // ---------- lifecycle ----------

    @Synchronized
    fun start(context: Context) {
        users++
        if (users > 1) return
        val ctx = context.applicationContext
        app = ctx
        logger = DiagnosticLogger(ctx, "road-alerts")
        val t = HandlerThread("road-alerts").also { it.start() }
        thread = t
        val h = Handler(t.looper)
        handler = h
        h.post {
            loadFixes()
            startGps()
            tick()
        }
        tts = TextToSpeech(ctx) { status -> h.post { onTtsInit(status) } }
        logger?.log("started")
    }

    @Synchronized
    fun stop() {
        if (users == 0) return
        users--
        if (users > 0) return
        handler?.post {
            stopGps()
            speeding = false
            next = null
            speedKmh = null
            publish()
        }
        thread?.quitSafely()
        thread = null
        handler = null
        tts?.shutdown()
        tts = null
        ttsReady = false
        runCatching { tone?.release() }
        tone = null
        logger?.log("stopped")
    }

    /** Car-screen actions (long-press / tap on the overlay). */
    fun addCameraHere() {
        handler?.post {
            val at = last ?: return@post
            myCams += SpeedCamera(-System.currentTimeMillis(), at, null, heading.takeUnless { it.isNaN() })
            saveFixes()
            mergeCams()
            showNote(R.string.road_note_camera_added)
        }
    }

    fun removeNextCamera() {
        handler?.post {
            val c = next?.camera ?: return@post
            if (c.mine) {
                myCams.removeAll { it.id == c.id }
            } else {
                hidden += c.id
            }
            saveFixes()
            mergeCams()
            next = null
            showNote(R.string.road_note_camera_removed)
        }
    }

    fun toggleMute() {
        handler?.post {
            muted = !muted
            if (muted) runCatching { tts?.stop() }
            showNote(if (muted) R.string.road_note_muted else R.string.road_note_unmuted)
        }
    }

    // ---------- GPS ----------

    /** All four methods implemented: on Android 10 they are not default methods yet. */
    private val gps = object : LocationListener {
        override fun onLocationChanged(location: Location) = onFix(location)
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }

    private fun startGps() {
        val ctx = app ?: return
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            logger?.log("no location permission -- alerts off")
            return
        }
        val lm = ctx.getSystemService(LocationManager::class.java) ?: return
        val looper = handler?.looper ?: return
        try {
            lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000L, 0f, gps, looper)
        } catch (e: Exception) {
            logger?.log("GPS start failed: $e")
        }
    }

    private fun stopGps() {
        runCatching { app?.getSystemService(LocationManager::class.java)?.removeUpdates(gps) }
    }

    private fun onFix(loc: Location) {
        val ctx = app ?: return
        val at = LatLon(loc.latitude, loc.longitude)
        last = at
        lastFixAt = System.currentTimeMillis()
        speedKmh = if (loc.hasSpeed()) loc.speed * 3.6 else null
        if (loc.hasBearing() && loc.speed > 2f) heading = loc.bearing.toDouble()

        val f = fetchedAt
        val now = System.currentTimeMillis()
        if (f == null || RoadMath.distanceM(f, at) > 600 || now - fetchedTime > 15 * 60_000) fetch(at)

        matchRoad(at)
        val (limit, _) = currentLimit(ctx)
        checkSpeed(ctx, limit)
        checkCameras(ctx, at, limit)
        publish()
    }

    /** Republishes every 2 s so a lost GPS fix clears the speed on screen. */
    private fun tick() {
        val h = handler ?: return
        if (System.currentTimeMillis() - lastFixAt > 5_000 && speedKmh != null) {
            speedKmh = null
            speeding = false
        }
        publish()
        h.postDelayed({ tick() }, 2_000)
    }

    // ---------- limits ----------

    /** (limit, fromRoad): the road's limit when known and enabled, else the manual one (null = off). */
    private fun currentLimit(ctx: Context): Pair<Int?, Boolean> {
        val road = roadLimit
        return if (AppSettings.roadUseOsmLimit(ctx) && road != null) road to true
        else AppSettings.roadManualLimit(ctx) to false
    }

    /** Only switches road after the new one wins twice, so a bridge or a side street can't flicker it. */
    private fun matchRoad(at: LatLon) {
        val m = RoadMath.matchRoad(roads, at, heading)
        val now = System.currentTimeMillis()
        if (m != null) {
            val current = roadId
            if (current != null && m.road.id != current && candidate != m.road.id) {
                candidate = m.road.id
                return
            }
            candidate = null
            roadId = m.road.id
            roadLimit = m.limit
            roadSeen = now
        } else if (now - roadSeen > 15_000) {
            roadId = null
            roadLimit = null
        }
    }

    private fun checkSpeed(ctx: Context, limit: Int?) {
        val kmh = speedKmh
        if (!AppSettings.roadSpeedAlerts(ctx) || kmh == null || limit == null) {
            speeding = false
            return
        }
        val over = limit + AppSettings.roadTolerance(ctx)
        val now = System.currentTimeMillis()
        if (kmh > over) {
            if (!speeding) {
                speeding = true
                lastNag = now + 3_000 // let the sentence finish
                say(ctx.getString(R.string.road_say_speeding, kmh.roundToInt(), limit))
            } else if (now - lastNag >= 8_000) {
                lastNag = now
                beep()
            }
        } else if (kmh < over - 3) {
            speeding = false
        }
    }

    // ---------- cameras ----------

    private fun checkCameras(ctx: Context, at: LatLon, limit: Int?) {
        if (!AppSettings.roadCameraAlerts(ctx)) {
            next = null
            return
        }
        val kmh = speedKmh ?: 0.0
        val moving = kmh > 10 && !heading.isNaN()
        val hit = RoadMath.cameraAhead(cameras, at, heading, moving)
        next = hit
        if (hit == null || !moving) return
        val c = hit.camera
        val camLimit = c.limit ?: limit
        if (!c.farSaid && hit.meters <= 600) {
            c.farSaid = true
            val m = (hit.meters / 50).roundToInt() * 50
            say(
                if (camLimit != null) ctx.getString(R.string.road_say_camera_far, m, camLimit)
                else ctx.getString(R.string.road_say_camera_far_nolimit, m),
            )
        } else if (!c.nearSaid && hit.meters <= 200 && camLimit != null && kmh > camLimit) {
            c.nearSaid = true
            say(ctx.getString(R.string.road_say_camera_near, camLimit))
        }
    }

    private fun mergeCams() {
        val old = cameras.associateBy { it.id }
        cameras = (osmCams + myCams).filter { it.id !in hidden }.map { old[it.id] ?: it }
    }

    private fun loadFixes() {
        val p = app?.getSharedPreferences(FIXES, Context.MODE_PRIVATE) ?: return
        try {
            val mine = JSONArray(p.getString("my_cameras", "[]"))
            myCams = (0 until mine.length()).map { i ->
                val o = mine.getJSONObject(i)
                SpeedCamera(
                    o.getLong("id"),
                    LatLon(o.getDouble("lat"), o.getDouble("lon")),
                    if (o.has("limit")) o.getInt("limit") else null,
                    if (o.has("heading")) o.getDouble("heading") else null,
                )
            }.toMutableList()
            val h = JSONArray(p.getString("hidden_cameras", "[]"))
            hidden = (0 until h.length()).map { h.getLong(it) }.toMutableSet()
        } catch (e: Exception) {
            logger?.log("fixes unreadable: $e")
        }
        mergeCams()
    }

    private fun saveFixes() {
        val p = app?.getSharedPreferences(FIXES, Context.MODE_PRIVATE) ?: return
        val mine = JSONArray()
        for (c in myCams) {
            val o = JSONObject().put("id", c.id).put("lat", c.at.lat).put("lon", c.at.lon)
            c.limit?.let { o.put("limit", it) }
            c.heading?.let { o.put("heading", it) }
            mine.put(o)
        }
        p.edit()
            .putString("my_cameras", mine.toString())
            .putString("hidden_cameras", JSONArray(hidden.toList()).toString())
            .apply()
    }

    // ---------- OpenStreetMap ----------

    private fun fetch(at: LatLon) {
        val now = System.currentTimeMillis()
        if (fetching || now - lastAttempt < 20_000) return
        val h = handler ?: return
        fetching = true
        lastAttempt = now
        net.execute {
            val result = runCatching { download(RoadMath.overpassQuery(at)) }
            h.post {
                fetching = false
                result.onSuccess { (r, c) ->
                    roads = r
                    osmCams = c
                    mergeCams()
                    fetchedAt = at
                    fetchedTime = System.currentTimeMillis()
                    logger?.log("OSM: ${r.size} roads, ${c.size} cameras")
                }.onFailure {
                    // Offline or Overpass busy: keep the last data and retry in a minute.
                    logger?.log("OSM fetch failed: $it")
                    fetchedTime = System.currentTimeMillis() - 14 * 60_000
                }
            }
        }
    }

    private fun download(query: String): Pair<List<Road>, List<SpeedCamera>> {
        var error: Exception? = null
        for (endpoint in ENDPOINTS) {
            try {
                val c = URL(endpoint).openConnection() as HttpURLConnection
                c.connectTimeout = 15_000
                c.readTimeout = 30_000
                c.requestMethod = "POST"
                c.doOutput = true
                c.setRequestProperty("User-Agent", UA)
                c.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                c.outputStream.use { it.write(("data=" + URLEncoder.encode(query, "UTF-8")).toByteArray()) }
                if (c.responseCode != 200) throw IOException("HTTP ${c.responseCode} from $endpoint")
                val body = c.inputStream.bufferedReader().use { it.readText() }
                c.disconnect()
                return parse(body)
            } catch (e: Exception) {
                error = e
            }
        }
        throw error ?: IOException("no endpoint")
    }

    private fun parse(body: String): Pair<List<Road>, List<SpeedCamera>> {
        val els = JSONObject(body).getJSONArray("elements")
        val roads = ArrayList<Road>()
        val cams = ArrayList<SpeedCamera>()
        for (i in 0 until els.length()) {
            val e = els.getJSONObject(i)
            val tags = e.optJSONObject("tags") ?: JSONObject()
            fun tag(k: String): String? = if (tags.has(k)) tags.optString(k) else null
            when (e.optString("type")) {
                "node" -> cams += SpeedCamera(
                    e.getLong("id"),
                    LatLon(e.getDouble("lat"), e.getDouble("lon")),
                    RoadMath.parseMaxspeed(tag("maxspeed")),
                    RoadMath.parseDirection(tag("direction") ?: tag("camera:direction")),
                )
                "way" -> {
                    val g = e.optJSONArray("geometry") ?: continue
                    val pts = (0 until g.length()).mapNotNull { j ->
                        g.optJSONObject(j)?.let { LatLon(it.getDouble("lat"), it.getDouble("lon")) }
                    }
                    if (pts.size < 2) continue
                    val all = RoadMath.parseMaxspeed(tag("maxspeed"))
                    val oneway = tag("oneway") == "yes" || tag("junction") == "roundabout" || tag("highway") == "motorway"
                    roads += Road(
                        e.getLong("id"),
                        pts,
                        RoadMath.parseMaxspeed(tag("maxspeed:forward")) ?: all,
                        RoadMath.parseMaxspeed(tag("maxspeed:backward")) ?: all,
                        oneway,
                    )
                }
            }
        }
        return roads to cams
    }

    // ---------- sound ----------

    private fun onTtsInit(status: Int) {
        val t = tts ?: return
        val ctx = app ?: return
        if (status != TextToSpeech.SUCCESS) {
            logger?.log("TTS init failed ($status) -- beeps only")
            return
        }
        // Speak in the app's language; the sentences come from its strings.
        val lang = ctx.resources.configuration.locales[0]
        val r = t.setLanguage(lang)
        ttsReady = r != TextToSpeech.LANG_MISSING_DATA && r != TextToSpeech.LANG_NOT_SUPPORTED
        if (!ttsReady) logger?.log("TTS has no voice for $lang -- beeps only")
        t.setAudioAttributes(navAudio)
        t.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) = releaseFocus()
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) = releaseFocus()
        })
    }

    private val navAudio: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()

    private fun say(text: String) {
        val ctx = app ?: return
        if (muted) return
        when (AppSettings.roadAlertSound(ctx)) {
            "off" -> return
            "beep" -> beep()
            else -> {
                val t = tts
                if (t == null || !ttsReady) {
                    beep()
                    return
                }
                logger?.log("say: $text")
                requestFocus()
                t.speak(text, TextToSpeech.QUEUE_FLUSH, null, "road-${System.currentTimeMillis()}")
            }
        }
    }

    private fun beep() {
        val ctx = app ?: return
        if (muted || AppSettings.roadAlertSound(ctx) == "off") return
        try {
            val g = tone ?: ToneGenerator(AudioManager.STREAM_MUSIC, 90).also { tone = it }
            g.startTone(ToneGenerator.TONE_PROP_BEEP2, 400)
        } catch (e: RuntimeException) {
            logger?.log("beep failed: $e")
        }
    }

    /** Lowers the music while a warning is spoken. */
    private fun requestFocus() {
        val am = app?.getSystemService(AudioManager::class.java) ?: return
        val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(navAudio)
            .build()
        focus = req
        runCatching { am.requestAudioFocus(req) }
    }

    private fun releaseFocus() {
        val req = focus ?: return
        focus = null
        runCatching { app?.getSystemService(AudioManager::class.java)?.abandonAudioFocusRequest(req) }
    }

    // ---------- state ----------

    private fun showNote(@StringRes res: Int) {
        note = app?.getString(res)
        noteUntil = System.currentTimeMillis() + 3_000
        publish()
        handler?.postDelayed({ publish() }, 3_100)
    }

    private fun publish() {
        val ctx = app ?: return
        val (limit, fromRoad) = currentLimit(ctx)
        val kmh = speedKmh
        val cam = next?.takeIf { AppSettings.roadCameraAlerts(ctx) }
        val s = RoadState(
            speedKmh = kmh?.roundToInt(),
            limit = limit,
            limitFromRoad = fromRoad,
            over = kmh != null && limit != null && kmh > limit + AppSettings.roadTolerance(ctx),
            cameraM = cam?.meters?.roundToInt(),
            cameraLimit = cam?.camera?.limit ?: cam?.let { limit },
            muted = muted,
            note = note?.takeIf { System.currentTimeMillis() < noteUntil },
        )
        state = s
        for (l in listeners) runCatching { l(s) }
    }
}
