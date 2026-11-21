package dev.caraalink.road

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RoadMathTest {

    /** A point [north] / [east] metres away from [o]. */
    private fun offset(o: LatLon, north: Double, east: Double): LatLon {
        val dLat = north / 111_320.0
        val dLon = east / (111_320.0 * Math.cos(Math.toRadians(o.lat)))
        return LatLon(o.lat + dLat, o.lon + dLon)
    }

    private val cairo = LatLon(30.0444, 31.2357)

    @Test
    fun parsesMaxspeedForms() {
        assertEquals(60, RoadMath.parseMaxspeed("60"))
        assertEquals(80, RoadMath.parseMaxspeed("80 km/h"))
        assertEquals(64, RoadMath.parseMaxspeed("40 mph"))
        assertNull(RoadMath.parseMaxspeed("EG:urban"))
        assertNull(RoadMath.parseMaxspeed("none"))
        assertNull(RoadMath.parseMaxspeed(null))
    }

    @Test
    fun parsesDirections() {
        assertEquals(90.0, RoadMath.parseDirection("90")!!, 0.001)
        assertEquals(45.0, RoadMath.parseDirection("ne")!!, 0.001)
        assertEquals(350.0, RoadMath.parseDirection("-10")!!, 0.001)
        assertNull(RoadMath.parseDirection("forward"))
    }

    @Test
    fun distanceAndBearing() {
        val north = offset(cairo, 1000.0, 0.0)
        assertEquals(1000.0, RoadMath.distanceM(cairo, north), 2.0)
        assertEquals(0.0, RoadMath.bearing(cairo, north), 0.5)
        assertEquals(90.0, RoadMath.bearing(cairo, offset(cairo, 0.0, 500.0)), 0.5)
        assertEquals(-20.0, RoadMath.angleDiff(350.0, 10.0), 0.001)
        assertEquals(20.0, RoadMath.angleDiff(10.0, 350.0), 0.001)
    }

    @Test
    fun picksRoadAlongOurDirectionNotTheCrossingOne() {
        // East-west road at 60 (two-way), north-south crossing road at 40.
        val ew = Road(1, listOf(offset(cairo, 0.0, -300.0), offset(cairo, 0.0, 300.0)), 60, 60, false)
        val ns = Road(2, listOf(offset(cairo, -300.0, 2.0), offset(cairo, 300.0, 2.0)), 40, 40, false)
        val at = offset(cairo, 3.0, 0.0)
        assertEquals(1L, RoadMath.matchRoad(listOf(ew, ns), at, 90.0)!!.road.id)
        assertEquals(2L, RoadMath.matchRoad(listOf(ew, ns), at, 0.0)!!.road.id)
    }

    @Test
    fun usesTheLimitForOurDirection() {
        val r = Road(1, listOf(offset(cairo, 0.0, -300.0), offset(cairo, 0.0, 300.0)), 80, 60, false)
        assertEquals(80, RoadMath.matchRoad(listOf(r), cairo, 90.0)!!.limit) // driving east = forward
        assertEquals(60, RoadMath.matchRoad(listOf(r), cairo, 270.0)!!.limit)
    }

    @Test
    fun ignoresOneWayRoadDrivenTheWrongWayAndFarRoads() {
        val oneway = Road(1, listOf(offset(cairo, 0.0, -300.0), offset(cairo, 0.0, 300.0)), 60, 60, true)
        assertNull(RoadMath.matchRoad(listOf(oneway), cairo, 270.0))
        assertNull(RoadMath.matchRoad(listOf(oneway), offset(cairo, 50.0, 0.0), 90.0))
    }

    @Test
    fun cameraAheadOnOurLineOnly() {
        val ahead = SpeedCamera(1, offset(cairo, 400.0, 0.0), 60, null)
        val behind = SpeedCamera(2, offset(cairo, -200.0, 0.0), 60, null)
        val parallel = SpeedCamera(3, offset(cairo, 300.0, 80.0), 60, null)
        val other = SpeedCamera(4, offset(cairo, 250.0, 0.0), 60, 180.0) // watches southbound traffic
        val hit = RoadMath.cameraAhead(listOf(ahead, behind, parallel, other), cairo, 0.0, moving = true)
        assertNotNull(hit)
        assertEquals(1L, hit!!.camera.id)
        assertEquals(400.0, hit.meters, 3.0)
    }

    @Test
    fun farCamerasReArm() {
        val far = SpeedCamera(1, offset(cairo, 2000.0, 0.0), null, null)
        far.farSaid = true
        far.nearSaid = true
        assertNull(RoadMath.cameraAhead(listOf(far), cairo, 0.0, moving = true))
        assertFalse(far.farSaid)
        assertFalse(far.nearSaid)
        assertTrue(SpeedCamera(-5, cairo, null, null).mine)
    }
}
