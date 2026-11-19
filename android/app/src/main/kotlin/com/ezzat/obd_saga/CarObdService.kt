package com.ezzat.obd_saga

import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.CarToast
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.model.Action
import androidx.car.app.model.CarColor
import androidx.car.app.model.CarText
import androidx.car.app.model.ItemList
import androidx.car.app.model.ListTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.validation.HostValidator
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/** Latest readings pushed from the Flutter side (see "carUpdate"). */
object CarData {
    @Volatile var title: String = "Car OBD"
    @Volatile var rows: List<Map<String, Any?>> = emptyList()
    @Volatile var waiting: String = "Open Car OBD on the phone"
    @Volatile var updatedAt = 0L
    var toast: ((String) -> Unit)? = null
}

/** Shows the car's live readings inside Android Auto (on the car screen). */
class CarObdService : CarAppService() {
    override fun createHostValidator(): HostValidator = HostValidator.ALLOW_ALL_HOSTS_VALIDATOR

    override fun onCreateSession(): Session = object : Session() {
        override fun onCreateScreen(intent: Intent): Screen = DashScreen(carContext)
    }
}

class DashScreen(ctx: CarContext) : Screen(ctx) {
    private val main = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            invalidate()
            main.postDelayed(this, 2000)
        }
    }

    init {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) {
                main.post(tick)
                CarData.toast = { m ->
                    main.post {
                        try { CarToast.makeText(carContext, m, CarToast.LENGTH_LONG).show() } catch (_: Exception) {}
                    }
                }
            }

            override fun onStop(owner: LifecycleOwner) {
                main.removeCallbacks(tick)
                CarData.toast = null
            }
        })
    }

    override fun onGetTemplate(): Template {
        val list = ItemList.Builder()
        val fresh = System.currentTimeMillis() - CarData.updatedAt < 10_000
        if (!fresh || CarData.rows.isEmpty()) {
            list.addItem(Row.Builder().setTitle(CarData.waiting).build())
        } else {
            for (r in CarData.rows.take(6)) {
                val title = r["title"] as? String ?: continue
                val warn = r["warn"] == true
                val b = Row.Builder()
                if (warn) {
                    val t = android.text.SpannableString(title)
                    t.setSpan(androidx.car.app.model.ForegroundCarColorSpan.create(CarColor.RED),
                        0, t.length, android.text.Spanned.SPAN_INCLUSIVE_EXCLUSIVE)
                    b.setTitle(CarText.create(t))
                } else {
                    b.setTitle(title)
                }
                (r["text"] as? String)?.takeIf { it.isNotEmpty() }?.let { b.addText(it) }
                list.addItem(b.build())
            }
        }
        return ListTemplate.Builder()
            .setTitle(CarData.title)
            .setHeaderAction(Action.APP_ICON)
            .setSingleList(list.build())
            .build()
    }
}
