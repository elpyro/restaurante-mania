package com.example.app

import android.app.NotificationManager
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import android.util.Log

/**
 * Elimina el canal único heredado `rm_pos_alerts`.
 *
 * Los canales actuales se crean desde Dart, uno por tipo de aviso
 * (`rm_pos_alerts_<tipo>_<importancia>`), sin sonido de canal: MIUI/HyperOS
 * restaura el sonido elegido por el usuario y la ROM lo ignora. El audio lo
 * reproduce `NotificationSoundPlugin` con el tono configurado para la
 * categoría. Este provider se ejecuta al iniciar el proceso, también cuando
 * FCM arranca el isolate de segundo plano.
 */
class NotificationChannelInitializer : ContentProvider() {
    override fun onCreate(): Boolean {
        val context = context ?: return false
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return false
        manager.deleteNotificationChannel(LEGACY_CHANNEL_ID)
        Log.i(TAG, "canal heredado $LEGACY_CHANNEL_ID eliminado; los canales por tipo los crea Dart")
        return true
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun query(
        uri: Uri,
        projection: Array<String>?,
        selection: String?,
        selectionArgs: Array<String>?,
        sortOrder: String?,
    ): Cursor? = null
    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<String>?,
    ): Int = 0
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int = 0
    override fun getType(uri: Uri): String? = null

    private companion object {
        const val TAG = "QASound"
        const val LEGACY_CHANNEL_ID = "rm_pos_alerts"
    }
}
