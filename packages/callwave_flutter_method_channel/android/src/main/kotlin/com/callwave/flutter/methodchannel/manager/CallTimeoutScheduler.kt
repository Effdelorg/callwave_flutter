package com.callwave.flutter.methodchannel.manager

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.callwave.flutter.methodchannel.CallwaveConstants
import com.callwave.flutter.methodchannel.receiver.CallActionReceiver

class CallTimeoutScheduler(
    private val context: Context,
) {
    fun schedule(callId: String, timeoutSeconds: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = timeoutPendingIntentForUpdate(callId)
        val triggerAt = System.currentTimeMillis() + timeoutSeconds.coerceAtLeast(1) * 1000L
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarmManager.canScheduleExactAlarms()) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        } else {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
        }
    }

    fun cancel(callId: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = timeoutPendingIntentForLookup(callId) ?: return
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    fun isScheduled(callId: String): Boolean {
        return timeoutPendingIntentForLookup(callId) != null
    }

    private fun timeoutPendingIntentForUpdate(callId: String): PendingIntent {
        val intent = Intent(context, CallActionReceiver::class.java).apply {
            action = CallwaveConstants.ACTION_TIMEOUT
            putExtra(CallwaveConstants.EXTRA_CALL_ID, callId)
        }

        return PendingIntent.getBroadcast(
            context,
            timeoutRequestCode(callId),
            intent,
            flagsUpdateCurrent(),
        )!!
    }

    private fun timeoutPendingIntentForLookup(callId: String): PendingIntent? {
        val intent = Intent(context, CallActionReceiver::class.java).apply {
            action = CallwaveConstants.ACTION_TIMEOUT
            putExtra(CallwaveConstants.EXTRA_CALL_ID, callId)
        }

        return PendingIntent.getBroadcast(
            context,
            timeoutRequestCode(callId),
            intent,
            flagsNoCreate(),
        )
    }

    private fun timeoutRequestCode(callId: String): Int = callId.hashCode() + 200000

    private fun flagsUpdateCurrent(): Int {
        return PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    }

    private fun flagsNoCreate(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_NO_CREATE
        }
    }
}
