package com.callwave.flutter.methodchannel.manager

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.callwave.flutter.methodchannel.CallwaveConstants
import com.callwave.flutter.methodchannel.model.CallPayload

class CallNotificationManager(
    private val context: Context,
) {
    private val notificationManagerCompat = NotificationManagerCompat.from(context)

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CallwaveConstants.NOTIFICATION_CHANNEL_ID,
            "Callwave Calls",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Incoming and missed call notifications"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    fun showIncomingCall(
        payload: CallPayload,
        fullScreenIntent: PendingIntent,
        acceptIntent: PendingIntent,
        declineIntent: PendingIntent,
    ) {
        val notification = NotificationCompat.Builder(context, CallwaveConstants.NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(payload.callerName)
            .setContentText("Incoming ${payload.callType} call")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(fullScreenIntent, true)
            .addAction(
                android.R.drawable.sym_call_outgoing,
                "Accept",
                acceptIntent,
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Decline",
                declineIntent,
            )
            .build()

        notificationManagerCompat.notify(incomingNotificationId(payload.callId), notification)
    }

    fun showOutgoingCall(payload: CallPayload) {
        val notification = NotificationCompat.Builder(context, CallwaveConstants.NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_outgoing)
            .setContentTitle("Calling ${payload.callerName}")
            .setContentText(payload.handle)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOngoing(true)
            .build()

        notificationManagerCompat.notify(incomingNotificationId(payload.callId), notification)
    }

    fun showMissedCall(payload: CallPayload, callbackIntent: PendingIntent) {
        val notification = NotificationCompat.Builder(context, CallwaveConstants.NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_missed)
            .setContentTitle("Missed call")
            .setContentText("${payload.callerName} (${payload.handle})")
            .setCategory(NotificationCompat.CATEGORY_MISSED_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .addAction(
                android.R.drawable.sym_action_call,
                "Call back",
                callbackIntent,
            )
            .build()

        notificationManagerCompat.notify(missedNotificationId(payload.callId), notification)
    }

    fun dismissIncoming(callId: String) {
        notificationManagerCompat.cancel(incomingNotificationId(callId))
    }

    fun dismissMissed(callId: String) {
        notificationManagerCompat.cancel(missedNotificationId(callId))
    }

    private fun incomingNotificationId(callId: String): Int = callId.hashCode()

    private fun missedNotificationId(callId: String): Int = callId.hashCode() + MISSED_NOTIFICATION_OFFSET

    companion object {
        private const val MISSED_NOTIFICATION_OFFSET = 40000
    }
}
