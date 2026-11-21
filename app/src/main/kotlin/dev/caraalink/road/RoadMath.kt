package dev.caraalink.road

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

data class LatLon(val lat: Double, val lon: Double)

/** A speed camera: an OSM node (positive id) or one the driver added (negative id). */
class SpeedCamera(
    val id: Long,
    val at: LatLon,
    val limit: Int?,
    /** Direction of travel the camera watches, in degrees, when known. */
    val heading: Double?,
) {
    var farSaid = false
    var nearSaid = false
    val mine: Boolean get() = id < 0
}

/** An OSM way with its limit each way (null = unknown). */
class Road(
    val id: Long,
    val pts: List<LatLon>,
    val fwd: Int?,
    val back: Int?,
    val oneway: Boolean,
)

data class RoadMatch(val road: Road, val forward: Boolean) {
    val limit: Int? get() = if (forward) road.fwd else road.back
}

data class CameraAhead(val camera: SpeedCamera, val meters: Double)

/**
 * Geometry and matching for road limits and speed cameras. No Android
 * dependencies, so it is unit-tested on the JVM. Ported from Saga OBD's
 * road_service.dart.
 */
object RoadMath {
    private const val EARTH_M = 6_371_000.0

    /** Drivable roads within 1 km and cameras within 4 km, with geometry. */
    fun overpassQuery(at: LatLon): String =
        "[out:json][timeout:25];(" +
            "way(around:1000,${at.lat},${at.lon})[\"highway\"~\"^(motorway|trunk|primary|secondary|tertiary|" +
            "unclassified|residential|living_street|service)(_link)?$\"];" +
            "node(around:4000,${at.lat},${at.lon})[\"highway\"=\"speed_camera\"];" +
            ");out geom tags;"

    /** "60", "60 km/h", "40 mph" → km/h; anything without a number ("EG:urban", "none") → null. */
    fun parseMaxspeed(v: String?): Int? {
        if (v == null) return null
        val m = Regex("""(\d+(?:\.\d+)?)""").find(v) ?: return null
        val n = m.groupValues[1].toDouble()
        val kmh = if (v.contains("mph")) n * 1.609 else n
        return kmh.roundToInt().takeIf { it in 5..200 }
    }

    private val cardinal = mapOf(
        "N" to 0.0, "NNE" to 22.5, "NE" to 45.0, "ENE" to 67.5, "E" to 90.0, "ESE" to 112.5,
        "SE" to 135.0, "SSE" to 157.5, "S" to 180.0, "SSW" to 202.5, "SW" to 225.0, "WSW" to 247.5,
        "W" to 270.0, "WNW" to 292.5, "NW" to 315.0, "NNW" to 337.5,
    )

    /** OSM `direction`: degrees ("90") or a compass point ("NE"); "forward"/"both" etc. → null. */
    fun parseDirection(v: String?): Double? {
        val s = v?.trim()?.uppercase() ?: return null
        return s.toDoubleOrNull()?.let { ((it % 360) + 360) % 360 } ?: cardinal[s]
    }

    fun distanceM(a: LatLon, b: LatLon): Double {
        val p1 = a.lat * PI / 180
        val p2 = b.lat * PI / 180
        val dp = p2 - p1
        val dl = (b.lon - a.lon) * PI / 180
        val h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * EARTH_M * asin(sqrt(h.coerceIn(0.0, 1.0)))
    }

    /** Initial bearing from [a] to [b], 0..360 degrees. */
    fun bearing(a: LatLon, b: LatLon): Double {
        val p1 = a.lat * PI / 180
        val p2 = b.lat * PI / 180
        val dl = (b.lon - a.lon) * PI / 180
        val y = sin(dl) * cos(p2)
        val x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        return (atan2(y, x) * 180 / PI + 360) % 360
    }

    /** Signed difference a - b, folded into -180..180. */
    fun angleDiff(a: Double, b: Double): Double = ((a - b + 540) % 360) - 180

    /** Metres from [p] to segment [a]-[b] (local flat approximation). */
    fun toSegmentM(p: LatLon, a: LatLon, b: LatLon): Double {
        val k = cos(p.lat * PI / 180)
        fun x(q: LatLon) = q.lon * PI / 180 * EARTH_M * k
        fun y(q: LatLon) = q.lat * PI / 180 * EARTH_M
        val px = x(p); val py = y(p)
        val ax = x(a); val ay = y(a)
        val dx = x(b) - ax; val dy = y(b) - ay
        val len2 = dx * dx + dy * dy
        val t = if (len2 == 0.0) 0.0 else (((px - ax) * dx + (py - ay) * dy) / len2).coerceIn(0.0, 1.0)
        val cx = ax + t * dx; val cy = ay + t * dy
        return sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
    }

    /**
     * The road under the car: close to the centre line AND pointing the way
     * we drive, so a parallel service road or a crossing street doesn't win.
     * [heading] is NaN when unknown (stopped), and then distance alone decides.
     */
    fun matchRoad(roads: List<Road>, at: LatLon, heading: Double): RoadMatch? {
        val hasDir = !heading.isNaN()
        var best: RoadMatch? = null
        var bestScore = Double.MAX_VALUE
        for (r in roads) {
            for (i in 1 until r.pts.size) {
                val d = toSegmentM(at, r.pts[i - 1], r.pts[i])
                if (d > 22) continue
                var score = d
                var fwd = true
                if (hasDir) {
                    val diff = abs(angleDiff(heading, bearing(r.pts[i - 1], r.pts[i])))
                    fwd = diff <= 90
                    val off = if (fwd) diff else 180 - diff
                    if (off > 35) continue // crossing road, not ours
                    if (r.oneway && !fwd) continue // wrong way on a one-way
                    score += off * 0.4
                }
                if (score < bestScore) {
                    bestScore = score
                    best = RoadMatch(r, fwd)
                }
            }
        }
        return best
    }

    /**
     * Nearest camera within 1 km that is on the line we're driving: ahead,
     * at most ~35 m to the side, and (when its direction is known) watching
     * our direction of travel. Cameras more than 1 km away are re-armed so
     * they announce again next time.
     */
    fun cameraAhead(cameras: List<SpeedCamera>, at: LatLon, heading: Double, moving: Boolean): CameraAhead? {
        var best: CameraAhead? = null
        for (c in cameras) {
            val d = distanceM(at, c.at)
            if (d > 1000) {
                c.farSaid = false
                c.nearSaid = false
                continue
            }
            if (moving && !heading.isNaN()) {
                val diff = abs(angleDiff(bearing(at, c.at), heading))
                if (diff > 60) continue
                if (d * sin(diff * PI / 180) > 35) continue
                val ch = c.heading
                if (ch != null && abs(angleDiff(ch, heading)) > 60) continue
            }
            if (best == null || d < best.meters) best = CameraAhead(c, d)
        }
        return best
    }
}
