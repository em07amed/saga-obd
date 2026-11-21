package dev.caraalink.road

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.RelativeSizeSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import dev.caraalink.R
import dev.caraalink.settings.AppSettings

/**
 * Drawn over Android Auto on the car screen: a limit sign, your speed (red
 * when over), the next camera, and a short note after an action. It sits in
 * the same view tree that is encoded to the car, so it needs no help from
 * Android Auto. Only the badges take touches -- tap to mute, long-press the
 * speed to save a camera here, long-press the camera banner to remove it.
 * Everywhere else, touches fall through to Android Auto.
 */
@SuppressLint("ViewConstructor")
class RoadOverlay(context: Context) : FrameLayout(context) {

    private val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    private val radar = label()
    private val row = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        layoutDirection = View.LAYOUT_DIRECTION_LTR // sign then speed, in any language
    }
    private val sign = label().apply { setTextColor(Color.BLACK) }
    private val speed = label()
    private val note = label()

    private var unit = 0f
    private var last = RoadState()
    private val listener: (RoadState) -> Unit = { s -> post { render(s) } }

    init {
        val corner = AppSettings.roadOverlayCorner(context)
        val left = corner.endsWith("left")
        val vertical = if (corner.startsWith("bottom")) Gravity.BOTTOM else Gravity.TOP
        val horizontal = if (left) Gravity.LEFT else Gravity.RIGHT
        column.gravity = horizontal
        row.addView(sign)
        row.addView(speed)
        column.addView(radar)
        column.addView(row)
        column.addView(note)
        addView(column, LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, vertical or horizontal))

        row.setOnClickListener { RoadAlerts.toggleMute() }
        row.setOnLongClickListener { RoadAlerts.addCameraHere(); true }
        radar.setOnClickListener { RoadAlerts.toggleMute() }
        radar.setOnLongClickListener { RoadAlerts.removeNextCamera(); true }
        render(last)
    }

    private fun label() = TextView(context).apply {
        setTextColor(Color.WHITE)
        gravity = Gravity.CENTER
        typeface = Typeface.DEFAULT_BOLD
        includeFontPadding = false
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        RoadAlerts.addListener(listener)
    }

    override fun onDetachedFromWindow() {
        RoadAlerts.removeListener(listener)
        super.onDetachedFromWindow()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        // Everything scales with the short side of the car screen (720 px on a 1920x720 panel).
        val u = minOf(w, h) / 100f
        if (u <= 0f || u == unit) return
        unit = u
        post { applySizes() }
    }

    private fun applySizes() {
        val u = unit
        val gap = (u * 1.5f).toInt()
        val m = (u * 3f).toInt()
        (column.layoutParams as LayoutParams).setMargins(m, m, m, m)
        column.requestLayout()

        val d = (u * 16f).toInt()
        sign.layoutParams = LinearLayout.LayoutParams(d, d).apply { rightMargin = gap }
        sign.setTextSize(TypedValue.COMPLEX_UNIT_PX, u * 7f)

        speed.setTextSize(TypedValue.COMPLEX_UNIT_PX, u * 8f)
        speed.minWidth = d
        speed.minHeight = d
        speed.setPadding(gap * 2, gap, gap * 2, gap)

        radar.setTextSize(TypedValue.COMPLEX_UNIT_PX, u * 5.5f)
        radar.setPadding(gap * 2, gap, gap * 2, gap)
        radar.layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            .apply { bottomMargin = gap }

        note.setTextSize(TypedValue.COMPLEX_UNIT_PX, u * 4.5f)
        note.setPadding(gap * 2, gap, gap * 2, gap)
        note.layoutParams = LinearLayout.LayoutParams(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            .apply { topMargin = gap }
        note.background = rounded(0xCC111111.toInt())

        render(last)
    }

    private fun rounded(color: Int) = GradientDrawable().apply {
        cornerRadius = unit * 3f
        setColor(color)
    }

    private fun render(s: RoadState) {
        last = s
        val u = unit

        // Limit sign: red ring for the road's own limit, grey for the driver's fallback.
        val limit = s.limit
        sign.visibility = if (limit != null && s.speedKmh != null) View.VISIBLE else View.GONE
        if (limit != null) {
            sign.text = limit.toString()
            sign.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.WHITE)
                setStroke((u * 1.8f).toInt().coerceAtLeast(2), if (s.limitFromRoad) RED else GREY)
            }
        }

        val kmh = s.speedKmh
        row.visibility = if (kmh != null) View.VISIBLE else View.GONE
        if (kmh != null) {
            val text = SpannableStringBuilder(kmh.toString())
            val unitText = "\n" + context.getString(R.string.road_kmh) + if (s.muted) " 🔇" else ""
            val from = text.length
            text.append(unitText)
            text.setSpan(RelativeSizeSpan(0.38f), from, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            speed.text = text
            speed.background = rounded(if (s.over) RED else DARK)
        }

        val cam = s.cameraM
        radar.visibility = if (cam != null && cam <= 1000) View.VISIBLE else View.GONE
        if (cam != null) {
            val rounded10 = (cam + 5) / 10 * 10
            radar.text = context.getString(R.string.road_camera_banner, rounded10) +
                (s.cameraLimit?.let { "  •  $it" } ?: "")
            radar.background = rounded(RED)
        }

        note.visibility = if (s.note != null) View.VISIBLE else View.GONE
        note.text = s.note ?: ""

        column.visibility =
            if (row.visibility == View.VISIBLE || radar.visibility == View.VISIBLE || note.visibility == View.VISIBLE) View.VISIBLE
            else View.GONE
    }

    private companion object {
        val RED = 0xFFE53935.toInt()
        val GREY = 0xFF9E9E9E.toInt()
        val DARK = 0xCC111111.toInt()
    }
}
