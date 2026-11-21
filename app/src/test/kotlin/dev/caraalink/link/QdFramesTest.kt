package dev.caraalink.link

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class QdFramesTest {
    private fun hex(s: String) = s.split(" ").map { it.toInt(16).toByte() }.toByteArray()

    @Test
    fun framesMatchTheProtocolNotes() {
        val hb = QdFrames.json(QdFrames.TYPE_CMD, """{"CMD":"HEARTBEAT"}""")
        assertEquals(512, hb.size)
        assertArrayEquals(hex("35 41 35 41 00 00 00 23 00 00 00 00 00 01 00 00"), hb.copyOf(16))

        val ext = QdFrames.videoExt(1280, 720, 3, 30, 4_000_000, 2)
        val video = QdFrames.frame(QdFrames.TYPE_VIDEO, QdFrames.FORMAT_H264, ByteArray(1000), ext)
        assertEquals(1536, video.size)
        val expected = "35 41 35 41 00 00 04 18 00 20 01 00 00 02 00 00 " +
            "00 20 01 00 00 00 05 00 00 00 02 d0 00 5a 01 03 " +
            "00 00 00 1e 00 3d 09 00 00 00 00 02 01 00 00 00"
        assertArrayEquals(hex(expected), video.copyOf(48))
    }

    @Test
    fun readerHandlesPaddedSplitAndUnpaddedFrames() {
        val got = mutableListOf<Pair<Int, Int>>()
        val junk = mutableListOf<Int>()
        val reader = QdReader({ type, _, payload -> got += type to payload.size }) { junk += it.size }
        val padded = QdFrames.frame(QdFrames.TYPE_VIDEO, QdFrames.FORMAT_H264, ByteArray(700))
        reader.feed(padded.copyOfRange(0, 512), 512)
        reader.feed(padded.copyOfRange(512, 1024), 512)
        val small = QdFrames.json(QdFrames.TYPE_CMD, """{"CMD":"CAR_INFO"}""")
        val unpadded = small.copyOf(16 + 18)
        reader.feed(hex("01 02") + unpadded + unpadded, 4 + 2 * unpadded.size)
        assertEquals(listOf(1 to 700, 0 to 18, 0 to 18), got)
        assertEquals(listOf(2), junk)
    }

    @Test
    fun watchdogEndsOnlySessionsTheCarStoppedServing() {
        fun w(now: Long, lastRead: Long = now, spoke: Boolean = true, info: Boolean = true, writeSince: Long = 0) =
            QdTransport.watchdog(now, startedAt = 0, lastReadAt = lastRead, carSpoke = spoke, carInfo = info, writeSince = writeSince)
        assertNull(w(60_000, lastRead = 46_000))
        assertNotNull(w(60_000, lastRead = 45_000))
        // A car that never spoke is left to the handshake timeout.
        assertNull(w(60_000, lastRead = 0, spoke = false))
        // A stuck write survives while the car still talks, up to 20 s.
        assertNull(w(60_000, writeSince = 49_000))
        assertNotNull(w(60_000, writeSince = 49_000, lastRead = 54_000))
        assertNotNull(w(60_000, writeSince = 39_000))
        assertNull(w(11_000, info = false))
        assertNotNull(w(12_000, info = false))
    }
}
