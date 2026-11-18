package com.ezzat.obd_saga

import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService

/**
 * Only used to learn the caller's number (no call-log permission needed).
 * Every call is allowed through untouched.
 */
class CallerIdService : CallScreeningService() {
    override fun onScreenCall(details: Call.Details) {
        val incoming = Build.VERSION.SDK_INT < 29 ||
            details.callDirection == Call.Details.DIRECTION_INCOMING
        if (incoming) {
            lastNumber = details.handle?.schemeSpecificPart
            listener?.invoke(lastNumber)
        }
        respondToCall(details, CallResponse.Builder().build())
    }

    companion object {
        @Volatile var lastNumber: String? = null
        var listener: ((String?) -> Unit)? = null
    }
}
