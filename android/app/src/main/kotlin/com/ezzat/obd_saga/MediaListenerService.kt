package com.ezzat.obd_saga

import android.service.notification.NotificationListenerService

/**
 * Exists only so the user can grant "notification access", which Android
 * requires before an app may read other apps' media sessions (now playing).
 */
class MediaListenerService : NotificationListenerService()
