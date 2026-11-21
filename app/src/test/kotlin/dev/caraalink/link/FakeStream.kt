package dev.caraalink.link

/**
 * Headless stand-in for [AdbTransport.Stream] -- no USB accessory, no
 * ADB framing, just what [MirrorStream] promises. Captures every
 * `write()` so a test can assert on the exact reply bytes a channel sent.
 */
class FakeStream(override val localId: Int = 1) : MirrorStream {
    val written = mutableListOf<ByteArray>()
    override var closed = false
        private set

    override fun write(data: ByteArray) {
        written.add(data)
    }

    override fun backlogAgeMs(): Long = 0

    override fun clearBacklog() {}

    fun close() {
        closed = true
    }
}
