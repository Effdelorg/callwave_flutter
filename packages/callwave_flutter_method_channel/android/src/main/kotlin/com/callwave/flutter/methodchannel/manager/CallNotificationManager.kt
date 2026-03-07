package com.callwave.flutter.methodchannel.manager

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import com.callwave.flutter.methodchannel.CallwaveConstants
import com.callwave.flutter.methodchannel.model.CallPayload
import com.callwave.flutter.methodchannel.service.CallForegroundService

class CallNotificationManager(
    private val context: Context,
) {
    private val notificationManagerCompat = NotificationManagerCompat.from(context)

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        manager.deleteNotificationChannel(CallwaveConstants.NOTIFICATION_CHANNEL_ID_LEGACY)

        val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val ringtoneAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val channel = NotificationChannel(
            CallwaveConstants.NOTIFICATION_CHANNEL_ID,
            "Incoming Calls",
            NotificationManager.IMPORTANCE_MAX,
        ).apply {
            description = "Incoming and missed call notifications"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            setBypassDnd(true)
            setSound(ringtoneUri, ringtoneAttributes)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 1000, 500, 1000)
        }
        manager.createNotificationChannel(channel)

        val outgoingChannel = NotificationChannel(
            CallwaveConstants.NOTIFICATION_CHANNEL_ID_OUTGOING,
            "Outgoing Calls",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Outgoing call notifications"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(outgoingChannel)

        val missedChannel = NotificationChannel(
            CallwaveConstants.NOTIFICATION_CHANNEL_ID_MISSED,
            "Missed Calls",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Missed call notifications"
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(missedChannel)
    }

    fun showIncomingCall(
        payload: CallPayload,
        fullScreenIntent: PendingIntent,
        acceptIntent: PendingIntent,
        declineIntent: PendingIntent,
    ) {
        val builder = NotificationCompat.Builder(context, CallwaveConstants.NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.sym_call_incoming)
            .setContentTitle(payload.callerName)
            .setContentText("Incoming ${payload.callType} call")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(fullScreenIntent)
            .setFullScreenIntent(fullScreenIntent, true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val caller = Person.Builder()
                .setName(payload.callerName)
                .setImportant(true)
                .build()

            builder.setStyle(
                NotificationCompat.CallStyle.forIncomingCall(
                    caller,
                    declineIntent,
                    acceptIntent,
                ),
            )
        } else {
            builder.addAction(
                android.R.drawable.sym_call_outgoing,
                "Accept",
                acceptIntent,
            )
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Decline",
                declineIntent,
            )
        }

        val notification = builder.build()
        val notificationId = incomingNotificationId(payload.callId)
        CallForegroundService.start(context, notificationId, notification)
    }

    fun showOngoingCall(
        payload: CallPayload,
        openIntent: PendingIntent,
        endIntent: PendingIntent,
    ) {
        val builder = NotificationCompat.Builder(context, CallwaveConstants.NOTIFICATION_CHANNEL_ID_OUTGOING)
            .setSmallIcon(android.R.drawable.sym_call_outgoing)
            .setContentTitle("Call Ongoing")
            .setContentText("${payload.callerName} (${payload.callType})")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setAllowSystemGeneratedContextualActions(false)
            .setContentIntent(openIntent)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val caller = Person.Builder()
                .setName(payload.callerName)
                .setImportant(true)
                .build()
            builder.setStyle(
                NotificationCompat.CallStyle.forOngoingCall(
                    caller,
                    endIntent,
                ),
            )
        } else {
            builder.addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "End call",
                endIntent,
            )
        }

        val notification = builder.build()
        val notificationId = incomingNotificationId(payload.callId)
        CallForegroundService.start(context, notificationId, notification)
    }

    fun showMissedCall(
        payload: CallPayload,
        contentIntent: PendingIntent,
        callbackIntent: PendingIntent,
    ) {
        val notification = NotificationCompat.Builder(context, CallwaveConstants.NOTIFICATION_CHANNEL_ID_MISSED)
            .setSmallIcon(android.R.drawable.sym_call_missed)
            .setContentTitle("Missed call")
            .setContentText(missedCallNotificationText(payload))
            .setCategory(NotificationCompat.CATEGORY_MISSED_CALL)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .addAction(
                android.R.drawable.sym_action_call,
                "Call back",
                callbackIntent,
            )
            .build()

        notificationManagerCompat.notify(missedNotificationId(payload.callId), notification)
    }

    fun dismissIncoming(callId: String, stopForegroundService: Boolean = true) {
        notificationManagerCompat.cancel(incomingNotificationId(callId))
        if (stopForegroundService) {
            CallForegroundService.stop(context)
        }
    }

    fun dismissMissed(callId: String) {
        notificationManagerCompat.cancel(missedNotificationId(callId))
    }

    private fun incomingNotificationId(callId: String): Int = callId.hashCode()

    private fun missedNotificationId(callId: String): Int = callId.hashCode() + MISSED_NOTIFICATION_OFFSET

    private fun missedCallNotificationText(payload: CallPayload): String {
        val customText = payload.extra?.get(KEY_ANDROID_MISSED_CALL_NOTIFICATION_TEXT) as? String
        val trimmed = customText?.trim()
        if (!trimmed.isNullOrEmpty()) {
            return trimmed
        }

        return "${payload.callerName} (${payload.handle})"
    }

    companion object {
        private const val KEY_ANDROID_MISSED_CALL_NOTIFICATION_TEXT =
            "androidMissedCallNotificationText"
        private const val MISSED_NOTIFICATION_OFFSET = 40000
    }
}
