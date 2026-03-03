package com.callwave.flutter.methodchannel.manager

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import com.callwave.flutter.methodchannel.CallwaveConstants
import com.callwave.flutter.methodchannel.activity.FullScreenCallActivity
import com.callwave.flutter.methodchannel.events.EventSinkBridge
import com.callwave.flutter.methodchannel.model.CallEventPayload
import com.callwave.flutter.methodchannel.model.CallPayload
import com.callwave.flutter.methodchannel.model.CallPayload.Companion.toExtraJson
import com.callwave.flutter.methodchannel.receiver.CallActionReceiver

class AndroidCallManager(
    private val context: Context,
    private val notificationManager: CallNotificationManager,
    private val timeoutScheduler: CallTimeoutScheduler,
    private val activeCallRegistry: ActiveCallRegistry,
    private val eventSinkBridge: EventSinkBridge,
) {
    private val payloadStore = HashMap<String, CallPayload>()
    private val openedIncomingCalls = HashSet<String>()
    private val acceptedCalls = HashSet<String>()
    var activity: Activity? = null
    private var postCallBehavior = PostCallBehavior.STAY_OPEN

    fun initialize() {
        notificationManager.ensureChannel()
    }

    fun showIncomingCall(payload: CallPayload) {
        if (!activeCallRegistry.tryStart(payload.callId)) {
            emitEvent(payload.callId, CallwaveConstants.EVENT_DECLINED, payload.extra)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (!manager.canUseFullScreenIntent()) {
                Log.w(
                    TAG,
                    "USE_FULL_SCREEN_INTENT not granted. " +
                        "Call requestFullScreenIntentPermission() during onboarding.",
                )
            }
        }

        payloadStore[payload.callId] = payload
        openedIncomingCalls.remove(payload.callId)
        acceptedCalls.remove(payload.callId)

        notificationManager.showIncomingCall(
            payload = payload,
            fullScreenIntent = fullScreenIntent(payload),
            acceptIntent = acceptAndOpenIntent(payload),
            declineIntent = actionIntent(
                action = CallwaveConstants.ACTION_DECLINE,
                callId = payload.callId,
                extra = payload.extra,
                payload = payload,
            ),
        )
        timeoutScheduler.schedule(payload.callId, payload.timeoutSeconds)
    }

    fun showOutgoingCall(payload: CallPayload) {
        if (!activeCallRegistry.tryStart(payload.callId)) {
            emitEvent(payload.callId, CallwaveConstants.EVENT_DECLINED, payload.extra)
            return
        }
        payloadStore[payload.callId] = payload
        acceptedCalls.remove(payload.callId)
        notificationManager.showOutgoingCall(payload)
        emitEvent(payload.callId, CallwaveConstants.EVENT_STARTED, payload.extra)
    }

    fun endCall(callId: String) {
        timeoutScheduler.cancel(callId)
        notificationManager.dismissIncoming(callId)
        notificationManager.dismissMissed(callId)
        activeCallRegistry.remove(callId)
        openedIncomingCalls.remove(callId)
        acceptedCalls.remove(callId)
        val extra = payloadStore.remove(callId)?.extra
        emitEvent(callId, CallwaveConstants.EVENT_ENDED, extra)
        applyPostCallBehavior()
    }

    fun markMissed(callId: String) {
        val payload = payloadStore[callId] ?: fallbackPayload(callId)
        timeoutScheduler.cancel(callId)
        notificationManager.dismissIncoming(callId)
        activeCallRegistry.remove(callId)
        openedIncomingCalls.remove(callId)
        acceptedCalls.remove(callId)
        notificationManager.showMissedCall(
            payload = payload,
            callbackIntent = actionIntent(
                action = CallwaveConstants.ACTION_CALLBACK,
                callId = callId,
                extra = payload.extra,
                payload = payload,
            ),
        )
        emitEvent(callId, CallwaveConstants.EVENT_MISSED, payload.extra)
    }

    fun acceptCall(callId: String): Boolean {
        val payload = payloadStore[callId] ?: return false
        onAccept(callId, payload.extra)
        return true
    }

    fun declineCall(callId: String): Boolean {
        val payload = payloadStore[callId] ?: return false
        onDecline(callId, payload.extra)
        return true
    }

    fun handleIncomingCallIntent(intent: Intent?): Boolean {
        val launchAction = intent?.getStringExtra(CallwaveConstants.EXTRA_LAUNCH_ACTION)
        if (intent?.action == CallwaveConstants.ACTION_ACCEPT_AND_OPEN ||
            launchAction == CallwaveConstants.ACTION_ACCEPT_AND_OPEN
        ) {
            val callId = intent.getStringExtra(CallwaveConstants.EXTRA_CALL_ID) ?: return false
            val extraFromIntent = CallPayload.fromIntentExtras(
                intent.getStringExtra(CallwaveConstants.EXTRA_EXTRA),
            )
            val fallbackPayload = payloadFromActionIntent(intent, callId, extraFromIntent)
            onAccept(callId, extraFromIntent, fallbackPayload)
            return true
        }

        if (intent?.action != CallwaveConstants.ACTION_OPEN_INCOMING) {
            return false
        }

        val callId = intent.getStringExtra(CallwaveConstants.EXTRA_CALL_ID) ?: return false
        if (acceptedCalls.contains(callId)) {
            return true
        }
        if (!openedIncomingCalls.add(callId)) {
            return true
        }

        val extraFromIntent = CallPayload.fromIntentExtras(
            intent.getStringExtra(CallwaveConstants.EXTRA_EXTRA),
        )
        var payload = payloadStore[callId]
        if (payload == null) {
            val restoredPayload = payloadFromIntent(callId, intent, extraFromIntent)
            if (!activeCallRegistry.tryStart(callId)) {
                openedIncomingCalls.remove(callId)
                emitEvent(callId, CallwaveConstants.EVENT_DECLINED, restoredPayload.extra)
                return true
            }
            if (!timeoutScheduler.isScheduled(callId)) {
                timeoutScheduler.schedule(callId, restoredPayload.timeoutSeconds)
            }
            payloadStore[callId] = restoredPayload
            payload = restoredPayload
        }

        val resolvedPayload = payload
            ?: return true
        val mergedExtra = incomingEventExtra(
            payload = resolvedPayload,
            fallbackExtra = extraFromIntent,
            callerName = intent.getStringExtra(CallwaveConstants.EXTRA_CALLER_NAME),
            handle = intent.getStringExtra(CallwaveConstants.EXTRA_HANDLE),
            avatarUrl = intent.getStringExtra(CallwaveConstants.EXTRA_AVATAR_URL),
            callType = intent.getStringExtra(CallwaveConstants.EXTRA_CALL_TYPE),
        )
        emitEvent(callId, CallwaveConstants.EVENT_INCOMING, mergedExtra)
        return true
    }

    fun onAccept(
        callId: String,
        extra: Map<String, Any?>?,
        fallbackPayload: CallPayload? = null,
    ): Boolean {
        if (!acceptedCalls.add(callId)) {
            return false
        }

        val payload = resolvePayloadForAccept(callId, fallbackPayload)
        if (payload == null) {
            acceptedCalls.remove(callId)
            if (fallbackPayload != null) {
                timeoutScheduler.cancel(callId)
                notificationManager.dismissIncoming(callId)
                openedIncomingCalls.remove(callId)
                emitEvent(
                    callId,
                    CallwaveConstants.EVENT_DECLINED,
                    eventExtra(
                        payload = fallbackPayload,
                        fallbackExtra = extra,
                    ),
                )
            }
            return false
        }

        timeoutScheduler.cancel(callId)
        notificationManager.dismissIncoming(callId)
        openedIncomingCalls.remove(callId)
        notificationManager.showOngoingCall(payload)
        emitEvent(
            callId,
            CallwaveConstants.EVENT_ACCEPTED,
            eventExtra(
                payload = payload,
                fallbackExtra = extra,
            ),
        )
        return true
    }

    fun onDecline(callId: String, extra: Map<String, Any?>?) {
        timeoutScheduler.cancel(callId)
        notificationManager.dismissIncoming(callId)
        activeCallRegistry.remove(callId)
        openedIncomingCalls.remove(callId)
        acceptedCalls.remove(callId)
        payloadStore.remove(callId)
        emitEvent(callId, CallwaveConstants.EVENT_DECLINED, extra)
    }

    fun onTimeout(callId: String) {
        openedIncomingCalls.remove(callId)
        acceptedCalls.remove(callId)
        val extra = payloadStore[callId]?.extra
        emitEvent(callId, CallwaveConstants.EVENT_TIMEOUT, extra)
        markMissed(callId)
    }

    fun onCallback(callId: String, extra: Map<String, Any?>?) {
        notificationManager.dismissMissed(callId)
        emitEvent(callId, CallwaveConstants.EVENT_CALLBACK, extra ?: payloadStore[callId]?.extra)
    }

    fun payloadFromActionIntent(
        intent: Intent,
        callId: String,
        fallbackExtra: Map<String, Any?>?,
    ): CallPayload? {
        if (!intentHasPayloadData(intent) && fallbackExtra == null) {
            return null
        }
        return payloadFromIntent(callId, intent, fallbackExtra)
    }

    fun getActiveCallIds(): List<String> = activeCallRegistry.getActiveCallIds()

    fun requestNotificationPermission(activity: Activity?): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }

        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED

        if (!granted && activity != null) {
            activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
        }
        return granted
    }

    fun requestFullScreenIntentPermission(activity: Activity?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            return
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.canUseFullScreenIntent()) {
            return
        }
        val target = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        if (activity != null) {
            activity.startActivity(target)
        } else {
            context.startActivity(target)
        }
    }

    fun setPostCallBehavior(rawBehavior: String?) {
        postCallBehavior = PostCallBehavior.fromWireValue(rawBehavior)
    }

    private fun emitEvent(callId: String, type: String, extra: Map<String, Any?>?) {
        eventSinkBridge.emit(
            CallEventPayload.now(
                callId = callId,
                type = type,
                extra = extra,
            ),
        )
    }

    private fun applyPostCallBehavior() {
        if (postCallBehavior != PostCallBehavior.BACKGROUND_ON_ENDED) {
            return
        }
        val currentActivity = activity ?: return
        currentActivity.runOnUiThread {
            currentActivity.moveTaskToBack(true)
        }
    }

    private fun fullScreenIntent(payload: CallPayload): PendingIntent {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            action = CallwaveConstants.ACTION_OPEN_INCOMING
            putExtra(CallwaveConstants.EXTRA_CALL_ID, payload.callId)
            putExtra(CallwaveConstants.EXTRA_CALLER_NAME, payload.callerName)
            putExtra(CallwaveConstants.EXTRA_HANDLE, payload.handle)
            putExtra(CallwaveConstants.EXTRA_AVATAR_URL, payload.avatarUrl)
            putExtra(CallwaveConstants.EXTRA_TIMEOUT_SECONDS, payload.timeoutSeconds)
            putExtra(CallwaveConstants.EXTRA_CALL_TYPE, payload.callType)
            putExtra(CallwaveConstants.EXTRA_EXTRA, toExtraJson(payload.extra))
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }

        val intent = launchIntent ?: Intent(context, FullScreenCallActivity::class.java).apply {
            putExtra(CallwaveConstants.EXTRA_CALL_ID, payload.callId)
            putExtra(CallwaveConstants.EXTRA_CALLER_NAME, payload.callerName)
            putExtra(CallwaveConstants.EXTRA_HANDLE, payload.handle)
            putExtra(CallwaveConstants.EXTRA_AVATAR_URL, payload.avatarUrl)
            putExtra(CallwaveConstants.EXTRA_TIMEOUT_SECONDS, payload.timeoutSeconds)
            putExtra(CallwaveConstants.EXTRA_CALL_TYPE, payload.callType)
            putExtra(CallwaveConstants.EXTRA_EXTRA, toExtraJson(payload.extra))
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }

        return PendingIntent.getActivity(
            context,
            payload.callId.hashCode() + PENDING_INTENT_REQUEST_CODE_OFFSET_FULL_SCREEN,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun actionIntent(
        action: String,
        callId: String,
        extra: Map<String, Any?>?,
        payload: CallPayload? = null,
    ): PendingIntent {
        val intent = Intent(context, CallActionReceiver::class.java).apply {
            this.action = action
            putExtra(CallwaveConstants.EXTRA_CALL_ID, callId)
            putExtra(CallwaveConstants.EXTRA_EXTRA, toExtraJson(extra))
            if (payload != null) {
                putExtra(CallwaveConstants.EXTRA_CALLER_NAME, payload.callerName)
                putExtra(CallwaveConstants.EXTRA_HANDLE, payload.handle)
                putExtra(CallwaveConstants.EXTRA_AVATAR_URL, payload.avatarUrl)
                putExtra(CallwaveConstants.EXTRA_TIMEOUT_SECONDS, payload.timeoutSeconds)
                putExtra(CallwaveConstants.EXTRA_CALL_TYPE, payload.callType)
            }
        }

        return PendingIntent.getBroadcast(
            context,
            action.hashCode() + callId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun acceptAndOpenIntent(payload: CallPayload): PendingIntent {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            putExtra(CallwaveConstants.EXTRA_CALL_ID, payload.callId)
            putExtra(CallwaveConstants.EXTRA_CALLER_NAME, payload.callerName)
            putExtra(CallwaveConstants.EXTRA_HANDLE, payload.handle)
            putExtra(CallwaveConstants.EXTRA_AVATAR_URL, payload.avatarUrl)
            putExtra(CallwaveConstants.EXTRA_TIMEOUT_SECONDS, payload.timeoutSeconds)
            putExtra(CallwaveConstants.EXTRA_CALL_TYPE, payload.callType)
            putExtra(CallwaveConstants.EXTRA_EXTRA, toExtraJson(payload.extra))
            putExtra(CallwaveConstants.EXTRA_LAUNCH_ACTION, CallwaveConstants.ACTION_ACCEPT_AND_OPEN)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }

        if (launchIntent == null) {
            return actionIntent(
                action = CallwaveConstants.ACTION_ACCEPT,
                callId = payload.callId,
                extra = payload.extra,
                payload = payload,
            )
        }

        return PendingIntent.getActivity(
            context,
            payload.callId.hashCode() + PENDING_INTENT_REQUEST_CODE_OFFSET_ACCEPT_AND_OPEN,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun fallbackPayload(callId: String): CallPayload {
        return CallPayload(
            callId = callId,
            callerName = "Unknown",
            handle = "",
            avatarUrl = null,
            timeoutSeconds = 30,
            callType = "audio",
            extra = null,
        )
    }

    private fun incomingEventExtra(
        payload: CallPayload?,
        fallbackExtra: Map<String, Any?>?,
        callerName: String?,
        handle: String?,
        avatarUrl: String?,
        callType: String?,
    ): Map<String, Any?> {
        return eventExtra(
            payload = payload,
            fallbackExtra = fallbackExtra,
            callerName = callerName,
            handle = handle,
            avatarUrl = avatarUrl,
            callType = callType,
        )
    }

    private fun eventExtra(
        payload: CallPayload?,
        fallbackExtra: Map<String, Any?>?,
        callerName: String? = null,
        handle: String? = null,
        avatarUrl: String? = null,
        callType: String? = null,
    ): Map<String, Any?> {
        val merged = HashMap<String, Any?>()
        if (fallbackExtra != null) {
            merged.putAll(fallbackExtra)
        }
        if (payload?.extra != null) {
            merged.putAll(payload.extra)
        }

        merged[CallwaveConstants.EXTRA_CALLER_NAME] = payload?.callerName
            ?: callerName
            ?: merged[CallwaveConstants.EXTRA_CALLER_NAME]
            ?: "Unknown"
        merged[CallwaveConstants.EXTRA_HANDLE] = payload?.handle
            ?: handle
            ?: merged[CallwaveConstants.EXTRA_HANDLE]
            ?: ""
        merged[CallwaveConstants.EXTRA_AVATAR_URL] = payload?.avatarUrl
            ?: avatarUrl
            ?: merged[CallwaveConstants.EXTRA_AVATAR_URL]
        merged[CallwaveConstants.EXTRA_CALL_TYPE] = payload?.callType
            ?: callType
            ?: merged[CallwaveConstants.EXTRA_CALL_TYPE]
            ?: "audio"
        return merged
    }

    private fun payloadFromIntent(
        callId: String,
        intent: Intent,
        fallbackExtra: Map<String, Any?>?,
    ): CallPayload {
        return CallPayload(
            callId = callId,
            callerName = intent.getStringExtra(CallwaveConstants.EXTRA_CALLER_NAME) ?: "Unknown",
            handle = intent.getStringExtra(CallwaveConstants.EXTRA_HANDLE) ?: "",
            avatarUrl = intent.getStringExtra(CallwaveConstants.EXTRA_AVATAR_URL),
            timeoutSeconds = intent.getIntExtra(CallwaveConstants.EXTRA_TIMEOUT_SECONDS, 30),
            callType = intent.getStringExtra(CallwaveConstants.EXTRA_CALL_TYPE) ?: "audio",
            extra = fallbackExtra,
        )
    }

    private fun resolvePayloadForAccept(callId: String, fallbackPayload: CallPayload?): CallPayload? {
        val existingPayload = payloadStore[callId]
        if (existingPayload != null) {
            return existingPayload
        }

        if (fallbackPayload == null) {
            return null
        }

        if (!activeCallRegistry.tryStart(callId)) {
            return null
        }

        payloadStore[callId] = fallbackPayload
        return fallbackPayload
    }

    private fun intentHasPayloadData(intent: Intent): Boolean {
        return intent.hasExtra(CallwaveConstants.EXTRA_CALLER_NAME) ||
            intent.hasExtra(CallwaveConstants.EXTRA_HANDLE) ||
            intent.hasExtra(CallwaveConstants.EXTRA_AVATAR_URL) ||
            intent.hasExtra(CallwaveConstants.EXTRA_TIMEOUT_SECONDS) ||
            intent.hasExtra(CallwaveConstants.EXTRA_CALL_TYPE)
    }

    companion object {
        private const val TAG = "CallwaveFlutter"
        private const val REQUEST_NOTIFICATIONS = 4512
        private const val PENDING_INTENT_REQUEST_CODE_OFFSET_FULL_SCREEN = 10000
        private const val PENDING_INTENT_REQUEST_CODE_OFFSET_ACCEPT_AND_OPEN = 30000
    }
}

private enum class PostCallBehavior(val wireValue: String) {
    STAY_OPEN("stayOpen"),
    BACKGROUND_ON_ENDED("backgroundOnEnded"),
    ;

    companion object {
        fun fromWireValue(rawValue: String?): PostCallBehavior {
            if (rawValue == null) {
                return STAY_OPEN
            }
            return entries.firstOrNull { it.wireValue == rawValue } ?: STAY_OPEN
        }
    }
}
