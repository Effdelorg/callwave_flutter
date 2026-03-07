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
import com.callwave.flutter.methodchannel.activity.ValidatedAcceptBridgeActivity
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
    private val pendingStartupActionStore = PendingStartupActionStore(context)
    private val ongoingCallStore = OngoingCallStore(context)
    private val payloadStore = HashMap<String, CallPayload>()
    private val openedIncomingCalls = HashSet<String>()
    private val pendingAcceptedCalls = HashSet<String>()
    private val confirmedAcceptedCalls = HashSet<String>()
    private val pendingDeclinedCalls = HashSet<String>()
    private val pendingLaunchAfterConfirm = HashSet<String>()
    private val launchActionOverrides = HashMap<String, String>()
    private val outgoingCalls = HashSet<String>()
    private val connectedAtByCallId = HashMap<String, Long>()
    private val backgroundValidator = AndroidBackgroundValidator(context)
    private val backgroundValidatorRegistrationStore =
        BackgroundValidatorRegistrationStore(context)
    var activity: Activity? = null
    private var postCallBehavior = PostCallBehavior.STAY_OPEN
    private var backgroundDispatcherHandle: Long? = null
    private var backgroundAcceptCallbackHandle: Long? = null
    private var backgroundDeclineCallbackHandle: Long? = null

    private enum class BackgroundValidationStartResult {
        STARTED,
        DEFERRED_TO_LIVE_LISTENER,
        UNAVAILABLE,
    }

    init {
        restoreBackgroundIncomingCallValidatorRegistration()
        restorePersistedOngoingCall()
    }

    fun initialize() {
        notificationManager.ensureChannel()
    }

    fun showIncomingCall(payload: CallPayload) {
        Log.d(
            TAG,
            "showIncomingCall(callId=${payload.callId}, strategy=${payload.incomingAcceptStrategy})",
        )
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
        pendingAcceptedCalls.remove(payload.callId)
        confirmedAcceptedCalls.remove(payload.callId)
        pendingDeclinedCalls.remove(payload.callId)
        pendingLaunchAfterConfirm.remove(payload.callId)
        launchActionOverrides.remove(payload.callId)
        outgoingCalls.remove(payload.callId)
        connectedAtByCallId.remove(payload.callId)

        notificationManager.showIncomingCall(
            payload = payload,
            fullScreenIntent = fullScreenIntent(payload),
            acceptIntent = acceptIntent(payload),
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
        openedIncomingCalls.remove(payload.callId)
        pendingAcceptedCalls.remove(payload.callId)
        confirmedAcceptedCalls.remove(payload.callId)
        pendingDeclinedCalls.remove(payload.callId)
        pendingLaunchAfterConfirm.remove(payload.callId)
        launchActionOverrides.remove(payload.callId)
        outgoingCalls.add(payload.callId)
        connectedAtByCallId.remove(payload.callId)
        notificationManager.showOngoingCall(
            payload = payload,
            openIntent = openOngoingIntent(payload),
            endIntent = actionIntent(
                action = CallwaveConstants.ACTION_END,
                callId = payload.callId,
                extra = payload.extra,
                payload = payload,
            ),
        )
        persistOngoingCall(
            payload = payload,
            eventType = CallwaveConstants.EVENT_STARTED,
        )
        emitEvent(payload.callId, CallwaveConstants.EVENT_STARTED, payload.extra)
    }

    fun endCall(callId: String) {
        clearCallRuntimeState(callId, dismissMissed = true)
        val extra = payloadStore.remove(callId)?.extra
        emitEvent(callId, CallwaveConstants.EVENT_ENDED, extra)
        applyPostCallBehavior()
    }

    fun markMissed(callId: String, extra: Map<String, Any?>? = null) {
        Log.d(TAG, "markMissed(callId=$callId)")
        val payload = payloadStore.remove(callId) ?: fallbackPayload(callId)
        val missedExtra = eventExtra(
            payload = payload,
            fallbackExtra = extra,
        )
        clearCallRuntimeState(callId, dismissMissed = false)
        notificationManager.showMissedCall(
            payload = payload.copy(extra = missedExtra),
            contentIntent = missedCallOpenIntent(payload.copy(extra = missedExtra)),
            callbackIntent = actionIntent(
                action = CallwaveConstants.ACTION_CALLBACK,
                callId = callId,
                extra = missedExtra,
                payload = payload.copy(extra = missedExtra),
            ),
        )
        emitEvent(callId, CallwaveConstants.EVENT_MISSED, missedExtra)
    }

    fun acceptCall(callId: String): Boolean {
        val payload = payloadStore[callId] ?: return false
        onAccept(callId, payload.extra)
        return true
    }

    fun confirmAcceptedCall(callId: String): Boolean {
        if (!pendingAcceptedCalls.contains(callId) && !confirmedAcceptedCalls.contains(callId)) {
            return false
        }
        val payload = payloadStore[callId] ?: return false
        pendingAcceptedCalls.remove(callId)
        confirmedAcceptedCalls.add(callId)
        launchActionOverrides.remove(callId)
        notificationManager.showOngoingCall(
            payload = payload,
            openIntent = openOngoingIntent(payload),
            endIntent = actionIntent(
                action = CallwaveConstants.ACTION_END,
                callId = callId,
                extra = payload.extra,
                payload = payload,
            ),
        )
        persistOngoingCall(
            payload = payload,
            eventType = CallwaveConstants.EVENT_ACCEPTED,
        )
        if (pendingLaunchAfterConfirm.remove(callId)) {
            launchHostApp(CallwaveConstants.ACTION_OPEN_ONGOING, payload)
        }
        return true
    }

    fun registerBackgroundIncomingCallValidator(
        backgroundDispatcherHandle: Long,
        backgroundAcceptCallbackHandle: Long?,
        backgroundDeclineCallbackHandle: Long?,
    ) {
        this.backgroundDispatcherHandle = backgroundDispatcherHandle
        this.backgroundAcceptCallbackHandle = backgroundAcceptCallbackHandle
        this.backgroundDeclineCallbackHandle = backgroundDeclineCallbackHandle
        backgroundValidatorRegistrationStore.save(
            backgroundDispatcherHandle = backgroundDispatcherHandle,
            backgroundAcceptCallbackHandle = backgroundAcceptCallbackHandle,
            backgroundDeclineCallbackHandle = backgroundDeclineCallbackHandle,
        )
    }

    fun clearBackgroundIncomingCallValidator() {
        backgroundDispatcherHandle = null
        backgroundAcceptCallbackHandle = null
        backgroundDeclineCallbackHandle = null
        backgroundValidatorRegistrationStore.clear()
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

        if (intent?.action == CallwaveConstants.ACTION_OPEN_ONGOING ||
            launchAction == CallwaveConstants.ACTION_OPEN_ONGOING
        ) {
            val callId = intent.getStringExtra(CallwaveConstants.EXTRA_CALL_ID) ?: return false
            val extraFromIntent = CallPayload.fromIntentExtras(
                intent.getStringExtra(CallwaveConstants.EXTRA_EXTRA),
            )
            val fallbackPayload = payloadFromActionIntent(intent, callId, extraFromIntent)
            return onOpenOngoing(callId, extraFromIntent, fallbackPayload)
        }

        if (intent?.getBooleanExtra(CallwaveConstants.EXTRA_SKIP_STARTUP_ACTION_HANDOFF, false) ==
            true
        ) {
            return true
        }

        if (intent?.action == CallwaveConstants.ACTION_OPEN_MISSED_CALL ||
            launchAction == CallwaveConstants.ACTION_OPEN_MISSED_CALL
        ) {
            return handleMissedCallStartupIntent(
                type = CallwaveConstants.STARTUP_ACTION_OPEN_MISSED_CALL,
                launchAction = CallwaveConstants.ACTION_OPEN_MISSED_CALL,
                intent = intent,
            )
        }

        if (intent?.action == CallwaveConstants.ACTION_CALLBACK ||
            launchAction == CallwaveConstants.ACTION_CALLBACK
        ) {
            return handleMissedCallStartupIntent(
                type = CallwaveConstants.STARTUP_ACTION_CALLBACK,
                launchAction = CallwaveConstants.ACTION_CALLBACK,
                intent = intent,
            )
        }

        if (intent?.action != CallwaveConstants.ACTION_OPEN_INCOMING) {
            return false
        }

        val callId = intent.getStringExtra(CallwaveConstants.EXTRA_CALL_ID) ?: return false
        if (pendingAcceptedCalls.contains(callId) || confirmedAcceptedCalls.contains(callId)) {
            return true
        }
        if (pendingDeclinedCalls.contains(callId)) {
            return true
        }
        if (!openedIncomingCalls.add(callId)) {
            return true
        }
        outgoingCalls.remove(callId)

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
        launchActionOverrides[callId] = CallwaveConstants.ACTION_OPEN_INCOMING
        val mergedExtra = incomingEventExtra(
            callId = callId,
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
        shouldOpenAfterConfirm: Boolean = false,
        requireBackgroundValidationForValidatedAccept: Boolean = false,
        onBackgroundValidationResolved: (() -> Unit)? = null,
    ): AcceptResult {
        Log.d(
            TAG,
            "onAccept(callId=$callId, hasFallbackPayload=${fallbackPayload != null}, " +
                "requireBackgroundValidation=$requireBackgroundValidationForValidatedAccept)",
        )
        if (pendingAcceptedCalls.contains(callId) || confirmedAcceptedCalls.contains(callId)) {
            Log.d(TAG, "onAccept ignored for $callId because it is already accepted.")
            return AcceptResult.IGNORED
        }
        if (pendingDeclinedCalls.contains(callId)) {
            Log.d(TAG, "onAccept ignored for $callId because decline is in flight.")
            return AcceptResult.IGNORED
        }
        pendingAcceptedCalls.add(callId)

        val payload = resolvePayloadForAccept(callId, fallbackPayload)
        if (payload == null) {
            Log.d(TAG, "onAccept could not resolve payload for $callId.")
            pendingAcceptedCalls.remove(callId)
            confirmedAcceptedCalls.remove(callId)
            pendingLaunchAfterConfirm.remove(callId)
            outgoingCalls.remove(callId)
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
            return AcceptResult.IGNORED
        }

        timeoutScheduler.cancel(callId)
        notificationManager.dismissIncoming(
            callId = callId,
            stopForegroundService = false,
        )
        openedIncomingCalls.remove(callId)
        launchActionOverrides.remove(callId)
        outgoingCalls.remove(callId)
        if (payload.incomingAcceptStrategy ==
            CallwaveConstants.INCOMING_ACCEPT_STRATEGY_DEFER_OPEN_UNTIL_CONFIRMED
        ) {
            Log.d(TAG, "onAccept entering validated flow for $callId.")
            if (shouldOpenAfterConfirm) {
                pendingLaunchAfterConfirm.add(callId)
            }
            val validationStartResult = maybeRunBackgroundValidation(
                payload = payload,
                onResolved = onBackgroundValidationResolved,
            )
            when (validationStartResult) {
                BackgroundValidationStartResult.STARTED -> {
                    Log.d(TAG, "onAccept background validation started for $callId.")
                    return AcceptResult.VALIDATION_PENDING
                }
                BackgroundValidationStartResult.DEFERRED_TO_LIVE_LISTENER -> {
                    Log.d(
                        TAG,
                        "onAccept deferring validated flow to live listener for $callId.",
                    )
                    emitEvent(
                        callId,
                        CallwaveConstants.EVENT_ACCEPTED,
                        acceptedEventExtra(
                            payload = payload,
                            fallbackExtra = extra,
                        ),
                    )
                }
                BackgroundValidationStartResult.UNAVAILABLE -> {
                    Log.d(
                        TAG,
                        "onAccept could not start validated flow for $callId.",
                    )
                    if (requireBackgroundValidationForValidatedAccept) {
                        markMissed(
                            callId,
                            extra = eventExtra(
                                payload = payload,
                                fallbackExtra = extra,
                            ).toMutableMap().apply {
                                put(CallwaveConstants.EXTRA_OUTCOME_REASON, "failed")
                            },
                        )
                        onBackgroundValidationResolved?.invoke()
                    } else {
                        emitEvent(
                            callId,
                            CallwaveConstants.EVENT_ACCEPTED,
                            acceptedEventExtra(
                                payload = payload,
                                fallbackExtra = extra,
                            ),
                        )
                    }
                }
            }
            return AcceptResult.HANDLED
        }

        emitEvent(
            callId,
            CallwaveConstants.EVENT_ACCEPTED,
            acceptedEventExtra(
                payload = payload,
                fallbackExtra = extra,
            ),
        )
        confirmAcceptedCall(callId)
        return AcceptResult.LAUNCH_NOW
    }

    private fun onOpenOngoing(
        callId: String,
        extra: Map<String, Any?>?,
        fallbackPayload: CallPayload?,
    ): Boolean {
        if (!activeCallRegistry.contains(callId)) {
            return false
        }

        val payload = payloadStore[callId] ?: fallbackPayload ?: return false
        payloadStore[callId] = payload
        openedIncomingCalls.remove(callId)
        launchActionOverrides.remove(callId)
        val acceptanceState = acceptedStateFor(callId)
        val isAcceptedIncomingCall = acceptanceState != null
        val eventType = if (isAcceptedIncomingCall) {
            timeoutScheduler.cancel(callId)
            CallwaveConstants.EVENT_ACCEPTED
        } else {
            outgoingCalls.add(callId)
            CallwaveConstants.EVENT_STARTED
        }

        emitEvent(
            callId,
            eventType,
            appendLaunchAction(
                if (eventType == CallwaveConstants.EVENT_ACCEPTED) {
                    acceptedEventExtra(
                        payload = payload,
                        fallbackExtra = extra,
                        callId = callId,
                        acceptanceState = acceptanceState,
                    )
                } else {
                    eventExtra(
                        payload = payload,
                        fallbackExtra = extra,
                        callId = callId,
                    )
                },
                CallwaveConstants.ACTION_OPEN_ONGOING,
            ),
        )
        return true
    }

    fun onDecline(
        callId: String,
        extra: Map<String, Any?>?,
        fallbackPayload: CallPayload? = null,
        preferHeadlessReporting: Boolean = false,
    ) {
        if (pendingAcceptedCalls.contains(callId) || confirmedAcceptedCalls.contains(callId)) {
            // Ignore stale decline actions after a successful accept.
            return
        }
        if (pendingDeclinedCalls.contains(callId)) {
            return
        }
        finalizeDecline(
            callId = callId,
            extra = extra,
            fallbackPayload = fallbackPayload,
            preferHeadlessReporting = preferHeadlessReporting,
        )
    }

    fun onTimeout(callId: String) {
        if (!activeCallRegistry.contains(callId)) {
            // Ignore stale timeout broadcasts after call cleanup.
            return
        }
        if (pendingAcceptedCalls.contains(callId) || confirmedAcceptedCalls.contains(callId)) {
            // Ignore stale timeout broadcasts that race with an accepted call.
            return
        }
        if (pendingDeclinedCalls.contains(callId)) {
            // Ignore stale timeout broadcasts while headless decline reporting is in flight.
            return
        }
        val extra = payloadStore[callId]?.extra
        emitEvent(callId, CallwaveConstants.EVENT_TIMEOUT, extra)
        markMissed(callId)
    }

    fun onCallback(callId: String, extra: Map<String, Any?>?) {
        notificationManager.dismissMissed(callId)
        val payload = payloadStore[callId] ?: fallbackPayload(callId)
        val mergedExtra = eventExtra(
            payload = payload,
            fallbackExtra = extra,
        )
        if (eventSinkBridge.hasListener()) {
            emitEvent(
                callId,
                CallwaveConstants.EVENT_CALLBACK,
                appendLaunchAction(mergedExtra, CallwaveConstants.ACTION_CALLBACK),
            )
        } else {
            pendingStartupActionStore.save(
                type = CallwaveConstants.STARTUP_ACTION_CALLBACK,
                payload = payload.copy(extra = mergedExtra),
            )
        }
        launchHostApp(
            action = CallwaveConstants.ACTION_CALLBACK,
            payload = payload.copy(extra = mergedExtra),
            skipStartupActionHandoff = true,
        )
    }

    private fun finalizeDecline(
        callId: String,
        extra: Map<String, Any?>?,
        fallbackPayload: CallPayload?,
        preferHeadlessReporting: Boolean,
    ) {
        val payload = payloadStore[callId] ?: fallbackPayload
        if (!preferHeadlessReporting || payload == null) {
            emitDeclined(callId, extra, payload)
            return
        }

        when (maybeRunBackgroundDeclineReport(payload, extra)) {
            BackgroundValidationStartResult.STARTED -> return
            BackgroundValidationStartResult.DEFERRED_TO_LIVE_LISTENER,
            BackgroundValidationStartResult.UNAVAILABLE
            -> {
                emitDeclined(callId, extra, payload)
            }
        }
    }

    private fun emitDeclined(
        callId: String,
        extra: Map<String, Any?>?,
        payload: CallPayload?,
    ) {
        clearCallRuntimeState(callId, dismissMissed = false)
        payloadStore.remove(callId)
        emitEvent(callId, CallwaveConstants.EVENT_DECLINED, extra ?: payload?.extra)
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

    fun takePendingStartupAction(): Map<String, Any?>? {
        return pendingStartupActionStore.take()
    }

    fun getActiveCallEventSnapshots(): List<Map<String, Any?>> {
        val snapshots = mutableListOf<Map<String, Any?>>()
        val activeCallIds = activeCallRegistry.getActiveCallIds()
        for (callId in activeCallIds) {
            if (pendingDeclinedCalls.contains(callId)) {
                continue
            }
            val payload = payloadStore[callId]
            val type = when {
                pendingAcceptedCalls.contains(callId) ||
                    confirmedAcceptedCalls.contains(callId) -> CallwaveConstants.EVENT_ACCEPTED
                outgoingCalls.contains(callId) -> CallwaveConstants.EVENT_STARTED
                else -> CallwaveConstants.EVENT_INCOMING
            }
            val extra = if (type == CallwaveConstants.EVENT_ACCEPTED) {
                acceptedEventExtra(
                    payload = payload,
                    fallbackExtra = payload?.extra,
                    callId = callId,
                )
            } else if (type == CallwaveConstants.EVENT_INCOMING) {
                incomingEventExtra(
                    callId = callId,
                    payload = payload,
                    fallbackExtra = payload?.extra,
                    consumeLaunchActionOverride = true,
                )
            } else {
                eventExtra(
                    payload = payload,
                    fallbackExtra = payload?.extra,
                    callId = callId,
                )
            }
            snapshots.add(
                CallEventPayload.now(
                    callId = callId,
                    type = type,
                    extra = extra,
                ).toMap(),
            )
        }
        return snapshots
    }

    fun syncActiveCallsToEvents() {
        val activeCallIds = activeCallRegistry.getActiveCallIds()
        for (callId in activeCallIds) {
            if (pendingDeclinedCalls.contains(callId)) {
                continue
            }
            val payload = payloadStore[callId]
            val type = when {
                pendingAcceptedCalls.contains(callId) ||
                    confirmedAcceptedCalls.contains(callId) -> CallwaveConstants.EVENT_ACCEPTED
                outgoingCalls.contains(callId) -> CallwaveConstants.EVENT_STARTED
                else -> CallwaveConstants.EVENT_INCOMING
            }
            emitEvent(
                callId,
                type,
                if (type == CallwaveConstants.EVENT_ACCEPTED) {
                    acceptedEventExtra(
                        payload = payload,
                        fallbackExtra = payload?.extra,
                        callId = callId,
                    )
                } else if (type == CallwaveConstants.EVENT_INCOMING) {
                    incomingEventExtra(
                        callId = callId,
                        payload = payload,
                        fallbackExtra = payload?.extra,
                        consumeLaunchActionOverride = true,
                    )
                } else {
                    eventExtra(
                        payload = payload,
                        fallbackExtra = payload?.extra,
                        callId = callId,
                    )
                },
            )
        }
    }

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

    fun syncCallConnectedState(callId: String, connectedAtMs: Long) {
        if (!activeCallRegistry.contains(callId)) {
            return
        }
        connectedAtByCallId[callId] = connectedAtMs
        ongoingCallStore.updateConnectedAt(callId, connectedAtMs)
    }

    fun clearCallState(callId: String) {
        clearCallRuntimeState(callId, dismissMissed = true)
        payloadStore.remove(callId)
    }

    fun shouldOpenImmediatelyOnAccept(payload: CallPayload?): Boolean {
        return payload?.incomingAcceptStrategy !=
            CallwaveConstants.INCOMING_ACCEPT_STRATEGY_DEFER_OPEN_UNTIL_CONFIRMED
    }

    fun shouldHandleValidatedAcceptInBridge(payload: CallPayload?): Boolean {
        return payload != null &&
            payload.incomingAcceptStrategy ==
            CallwaveConstants.INCOMING_ACCEPT_STRATEGY_DEFER_OPEN_UNTIL_CONFIRMED &&
            !eventSinkBridge.hasListener()
    }

    fun launchValidatedAcceptBridge(payload: CallPayload) {
        Log.d(TAG, "launchValidatedAcceptBridge(callId=${payload.callId})")
        val intent = validatedAcceptBridgeIntent(payload).apply {
            putExtra(CallwaveConstants.EXTRA_LAUNCH_ACTION, CallwaveConstants.ACTION_ACCEPT)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_NO_ANIMATION,
            )
        }
        context.startActivity(intent)
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

    private fun restorePersistedOngoingCall() {
        val snapshot = ongoingCallStore.restore() ?: return
        val payload = snapshot.payload
        if (!activeCallRegistry.tryStart(payload.callId)) {
            ongoingCallStore.clear(payload.callId)
            return
        }
        payloadStore[payload.callId] = payload
        openedIncomingCalls.remove(payload.callId)
        pendingAcceptedCalls.remove(payload.callId)
        confirmedAcceptedCalls.remove(payload.callId)
        pendingDeclinedCalls.remove(payload.callId)
        pendingLaunchAfterConfirm.remove(payload.callId)
        launchActionOverrides.remove(payload.callId)
        outgoingCalls.remove(payload.callId)
        when (snapshot.eventType) {
            CallwaveConstants.EVENT_ACCEPTED -> {
                confirmedAcceptedCalls.add(payload.callId)
            }
            CallwaveConstants.EVENT_STARTED -> {
                outgoingCalls.add(payload.callId)
            }
            else -> {
                ongoingCallStore.clear(payload.callId)
                clearCallRuntimeState(payload.callId, dismissMissed = true)
                payloadStore.remove(payload.callId)
                return
            }
        }
        snapshot.connectedAtMs?.let { connectedAtByCallId[payload.callId] = it }
    }

    private fun persistOngoingCall(
        payload: CallPayload,
        eventType: String,
    ) {
        ongoingCallStore.save(
            payload = payload,
            eventType = eventType,
            connectedAtMs = connectedAtByCallId[payload.callId],
        )
    }

    private fun handleMissedCallStartupIntent(
        type: String,
        launchAction: String,
        intent: Intent?,
    ): Boolean {
        val safeIntent = intent ?: return false
        val callId = safeIntent.getStringExtra(CallwaveConstants.EXTRA_CALL_ID) ?: return false
        val extraFromIntent = CallPayload.fromIntentExtras(
            safeIntent.getStringExtra(CallwaveConstants.EXTRA_EXTRA),
        )
        val payload = payloadFromActionIntent(safeIntent, callId, extraFromIntent)
            ?: fallbackPayload(callId).copy(extra = extraFromIntent)
        val mergedExtra = eventExtra(
            payload = payload,
            fallbackExtra = extraFromIntent,
        )
        if (eventSinkBridge.hasListener()) {
            emitEvent(
                callId,
                if (type == CallwaveConstants.STARTUP_ACTION_CALLBACK) {
                    CallwaveConstants.EVENT_CALLBACK
                } else {
                    CallwaveConstants.EVENT_MISSED
                },
                appendLaunchAction(mergedExtra, launchAction),
            )
            return true
        }
        pendingStartupActionStore.save(
            type = type,
            payload = payload.copy(extra = mergedExtra),
        )
        return true
    }

    private fun fullScreenIntent(payload: CallPayload): PendingIntent {
        val launchIntent = hostLaunchIntentForAction(CallwaveConstants.ACTION_OPEN_INCOMING)?.apply {
            putPayloadExtras(payload)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }

        val intent = launchIntent ?: Intent(context, FullScreenCallActivity::class.java).apply {
            putPayloadExtras(payload)
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
                putPayloadExtras(payload)
            }
        }

        return PendingIntent.getBroadcast(
            context,
            action.hashCode() + callId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun acceptIntent(payload: CallPayload): PendingIntent {
        if (payload.incomingAcceptStrategy ==
            CallwaveConstants.INCOMING_ACCEPT_STRATEGY_DEFER_OPEN_UNTIL_CONFIRMED
        ) {
            val intent = validatedAcceptBridgeIntent(payload).apply {
                putExtra(CallwaveConstants.EXTRA_LAUNCH_ACTION, CallwaveConstants.ACTION_ACCEPT)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_NO_ANIMATION,
                )
            }
            return PendingIntent.getActivity(
                context,
                payload.callId.hashCode() + PENDING_INTENT_REQUEST_CODE_OFFSET_ACCEPT_AND_OPEN,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val launchIntent = hostLaunchIntentForAction(CallwaveConstants.ACTION_ACCEPT_AND_OPEN)?.apply {
            putPayloadExtras(payload)
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

    private fun openOngoingIntent(payload: CallPayload): PendingIntent {
        val launchIntent = (
            hostLaunchIntentForAction(CallwaveConstants.ACTION_OPEN_ONGOING)
                ?: hostLaunchIntentForAction(CallwaveConstants.ACTION_OPEN_INCOMING)
                ?: Intent(context, FullScreenCallActivity::class.java)
            ).apply {
            putPayloadExtras(payload)
            putExtra(CallwaveConstants.EXTRA_LAUNCH_ACTION, CallwaveConstants.ACTION_OPEN_ONGOING)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }

        return PendingIntent.getActivity(
            context,
            payload.callId.hashCode() + PENDING_INTENT_REQUEST_CODE_OFFSET_OPEN_ONGOING,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun missedCallOpenIntent(payload: CallPayload): PendingIntent {
        val launchIntent = (
            hostLaunchIntentForAction(CallwaveConstants.ACTION_OPEN_MISSED_CALL)
                ?: hostLaunchIntentForAction(CallwaveConstants.ACTION_OPEN_INCOMING)
                ?: Intent(context, FullScreenCallActivity::class.java)
            ).apply {
            putPayloadExtras(payload)
            putExtra(
                CallwaveConstants.EXTRA_LAUNCH_ACTION,
                CallwaveConstants.ACTION_OPEN_MISSED_CALL,
            )
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }

        return PendingIntent.getActivity(
            context,
            payload.callId.hashCode() + PENDING_INTENT_REQUEST_CODE_OFFSET_OPEN_MISSED_CALL,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun hostLaunchIntentForAction(action: String): Intent? {
        // Reuse the currently bound host activity when the app process is alive.
        // This avoids spinning up a second FlutterActivity/engine for accept/open.
        val boundActivityIntent = activity
            ?.takeUnless { it.isFinishing || it.isDestroyed }
            ?.let { currentActivity ->
                Intent(action).apply {
                    setClassName(currentActivity.packageName, currentActivity.javaClass.name)
                }
            }
        if (boundActivityIntent != null) {
            return boundActivityIntent
        }

        val actionIntent = Intent(action).apply {
            `package` = context.packageName
            addCategory(Intent.CATEGORY_DEFAULT)
        }
        val resolved = resolveActivityInfo(actionIntent)
        if (resolved != null) {
            return Intent(action).apply {
                setClassName(resolved.packageName, resolved.name)
            }
        }

        val launcherIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (launcherIntent != null) {
            launcherIntent.action = action
            return launcherIntent
        }

        val mainIntent = Intent(Intent.ACTION_MAIN).apply {
            `package` = context.packageName
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val mainResolved = resolveActivityInfo(mainIntent) ?: return null
        return Intent(action).apply {
            setClassName(mainResolved.packageName, mainResolved.name)
        }
    }

    private fun resolveActivityInfo(intent: Intent): android.content.pm.ActivityInfo? {
        val resolved = context.packageManager.resolveActivity(
            intent,
            PackageManager.MATCH_DEFAULT_ONLY,
        )?.activityInfo
        if (resolved != null) {
            return resolved
        }
        return context.packageManager.queryIntentActivities(
            intent,
            PackageManager.MATCH_DEFAULT_ONLY,
        ).firstOrNull()?.activityInfo
    }

    private fun clearCallRuntimeState(callId: String, dismissMissed: Boolean) {
        timeoutScheduler.cancel(callId)
        notificationManager.dismissIncoming(callId)
        if (dismissMissed) {
            notificationManager.dismissMissed(callId)
        }
        activeCallRegistry.remove(callId)
        openedIncomingCalls.remove(callId)
        pendingAcceptedCalls.remove(callId)
        confirmedAcceptedCalls.remove(callId)
        pendingDeclinedCalls.remove(callId)
        pendingLaunchAfterConfirm.remove(callId)
        launchActionOverrides.remove(callId)
        outgoingCalls.remove(callId)
        connectedAtByCallId.remove(callId)
        ongoingCallStore.clear(callId)
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
            incomingAcceptStrategy = CallwaveConstants.INCOMING_ACCEPT_STRATEGY_OPEN_IMMEDIATELY,
            backgroundDispatcherHandle = null,
            backgroundCallbackHandle = null,
            backgroundDeclineCallbackHandle = null,
        )
    }

    private fun incomingEventExtra(
        callId: String,
        payload: CallPayload?,
        fallbackExtra: Map<String, Any?>?,
        callerName: String? = null,
        handle: String? = null,
        avatarUrl: String? = null,
        callType: String? = null,
        consumeLaunchActionOverride: Boolean = false,
    ): Map<String, Any?> {
        val extra = eventExtra(
            payload = payload,
            fallbackExtra = fallbackExtra,
            callerName = callerName,
            handle = handle,
            avatarUrl = avatarUrl,
            callType = callType,
        )
        val launchAction = launchActionOverride(
            callId = callId,
            consume = consumeLaunchActionOverride,
        )
        return if (launchAction == null) {
            extra
        } else {
            appendLaunchAction(extra, launchAction)
        }
    }

    private fun eventExtra(
        payload: CallPayload?,
        fallbackExtra: Map<String, Any?>?,
        callId: String? = payload?.callId,
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
        val connectedAtMs = callId?.let(connectedAtByCallId::get)
        if (connectedAtMs != null) {
            merged[CallwaveConstants.EXTRA_CONNECTED_AT_MS] = connectedAtMs
        } else {
            merged.remove(CallwaveConstants.EXTRA_CONNECTED_AT_MS)
        }
        return merged
    }

    private fun acceptedEventExtra(
        payload: CallPayload?,
        fallbackExtra: Map<String, Any?>?,
        callId: String? = payload?.callId,
        acceptanceState: String? = null,
    ): Map<String, Any?> {
        val merged = eventExtra(
            payload = payload,
            fallbackExtra = fallbackExtra,
            callId = callId,
        ).toMutableMap()
        merged[CallwaveConstants.EXTRA_ACCEPTANCE_STATE] =
            acceptanceState ?: acceptedStateFor(callId)
        return merged
    }

    private fun acceptedStateFor(callId: String?): String? {
        if (callId == null) {
            return null
        }
        return when {
            confirmedAcceptedCalls.contains(callId) -> CallwaveConstants.ACCEPTANCE_STATE_CONFIRMED
            pendingAcceptedCalls.contains(callId) ->
                CallwaveConstants.ACCEPTANCE_STATE_PENDING_VALIDATION
            else -> null
        }
    }

    private fun appendLaunchAction(
        extra: Map<String, Any?>,
        launchAction: String,
    ): Map<String, Any?> {
        val merged = HashMap(extra)
        merged[CallwaveConstants.EXTRA_LAUNCH_ACTION] = launchAction
        return merged
    }

    private fun launchActionOverride(callId: String, consume: Boolean): String? {
        val launchAction = launchActionOverrides[callId]
        if (consume && launchAction != null) {
            launchActionOverrides.remove(callId)
        }
        return launchAction
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
            incomingAcceptStrategy = intent.getStringExtra(
                CallwaveConstants.EXTRA_INCOMING_ACCEPT_STRATEGY,
            ) ?: CallwaveConstants.INCOMING_ACCEPT_STRATEGY_OPEN_IMMEDIATELY,
            backgroundDispatcherHandle =
                intent.takeIf {
                    it.hasExtra(CallwaveConstants.EXTRA_BACKGROUND_DISPATCHER_HANDLE)
                }?.getLongExtra(CallwaveConstants.EXTRA_BACKGROUND_DISPATCHER_HANDLE, 0L)
                    ?.takeIf { it > 0L },
            backgroundCallbackHandle =
                intent.takeIf {
                    it.hasExtra(CallwaveConstants.EXTRA_BACKGROUND_CALLBACK_HANDLE)
                }?.getLongExtra(CallwaveConstants.EXTRA_BACKGROUND_CALLBACK_HANDLE, 0L)
                    ?.takeIf { it > 0L },
            backgroundDeclineCallbackHandle =
                intent.takeIf {
                    it.hasExtra(CallwaveConstants.EXTRA_BACKGROUND_DECLINE_CALLBACK_HANDLE)
                }?.getLongExtra(CallwaveConstants.EXTRA_BACKGROUND_DECLINE_CALLBACK_HANDLE, 0L)
                    ?.takeIf { it > 0L },
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
            intent.hasExtra(CallwaveConstants.EXTRA_CALL_TYPE) ||
            intent.hasExtra(CallwaveConstants.EXTRA_INCOMING_ACCEPT_STRATEGY)
    }

    private fun maybeRunBackgroundValidation(
        payload: CallPayload,
        onResolved: (() -> Unit)? = null,
    ): BackgroundValidationStartResult {
        if (eventSinkBridge.hasListener()) {
            Log.d(
                TAG,
                "maybeRunBackgroundValidation skipped for ${payload.callId} because a live listener exists.",
            )
            return BackgroundValidationStartResult.DEFERRED_TO_LIVE_LISTENER
        }
        val registration = backgroundIncomingCallValidatorRegistrationFor(payload)
        if (registration == null) {
            Log.d(
                TAG,
                "maybeRunBackgroundValidation skipped for ${payload.callId} because no validator registration is available.",
            )
            return BackgroundValidationStartResult.UNAVAILABLE
        }
        Log.d(
            TAG,
            "maybeRunBackgroundValidation starting for ${payload.callId}.",
        )
        val callbackHandle = registration.backgroundAcceptCallbackHandle
            ?: return BackgroundValidationStartResult.UNAVAILABLE
        backgroundValidator.validateAccept(
            backgroundDispatcherHandle = registration.backgroundDispatcherHandle,
            backgroundCallbackHandle = callbackHandle,
            payload = payload,
        ) { decision ->
            try {
                Log.d(
                    TAG,
                    "background validation resolved for ${payload.callId}: allowed=${decision.isAllowed}, reason=${decision.reason}",
                )
                if (!activeCallRegistry.contains(payload.callId)) {
                    return@validateAccept
                }
                if (decision.isAllowed) {
                    confirmAcceptedCall(payload.callId)
                } else {
                    markMissed(
                        payload.callId,
                        extra = eventExtra(
                            payload = payload,
                            fallbackExtra = decision.extra,
                        ).toMutableMap().apply {
                            put(
                                CallwaveConstants.EXTRA_OUTCOME_REASON,
                                decision.reason ?: "failed",
                            )
                        },
                    )
                }
            } finally {
                onResolved?.invoke()
            }
        }
        return BackgroundValidationStartResult.STARTED
    }

    private fun maybeRunBackgroundDeclineReport(
        payload: CallPayload,
        fallbackExtra: Map<String, Any?>?,
    ): BackgroundValidationStartResult {
        if (shouldDeferDeclineToLiveListener()) {
            Log.d(
                TAG,
                "maybeRunBackgroundDeclineReport skipped for ${payload.callId} because Flutter is foreground-active.",
            )
            return BackgroundValidationStartResult.DEFERRED_TO_LIVE_LISTENER
        }
        val registration = backgroundIncomingCallValidatorRegistrationFor(payload)
        val callbackHandle = registration?.backgroundDeclineCallbackHandle
        if (registration == null || callbackHandle == null) {
            Log.d(
                TAG,
                "maybeRunBackgroundDeclineReport skipped for ${payload.callId} because no decline reporter is available.",
            )
            return BackgroundValidationStartResult.UNAVAILABLE
        }

        pendingDeclinedCalls.add(payload.callId)
        timeoutScheduler.cancel(payload.callId)
        notificationManager.dismissIncoming(payload.callId)
        openedIncomingCalls.remove(payload.callId)
        pendingAcceptedCalls.remove(payload.callId)
        confirmedAcceptedCalls.remove(payload.callId)
        pendingLaunchAfterConfirm.remove(payload.callId)
        launchActionOverrides.remove(payload.callId)
        outgoingCalls.remove(payload.callId)

        backgroundValidator.reportDecline(
            backgroundDispatcherHandle = registration.backgroundDispatcherHandle,
            backgroundCallbackHandle = callbackHandle,
            payload = payload,
        ) { decision ->
            if (!activeCallRegistry.contains(payload.callId) || !pendingDeclinedCalls.contains(payload.callId)) {
                return@reportDecline
            }
            if (decision.isAllowed) {
                clearCallRuntimeState(payload.callId, dismissMissed = false)
                payloadStore.remove(payload.callId)
                return@reportDecline
            }
            markMissed(
                payload.callId,
                extra = eventExtra(
                    payload = payload,
                    fallbackExtra = decision.extra ?: fallbackExtra,
                ).toMutableMap().apply {
                    put(
                        CallwaveConstants.EXTRA_OUTCOME_REASON,
                        decision.reason ?: "failed",
                    )
                },
            )
        }
        return BackgroundValidationStartResult.STARTED
    }

    private fun shouldDeferDeclineToLiveListener(): Boolean {
        if (!eventSinkBridge.hasListener()) {
            return false
        }
        val currentActivity = activity ?: return false
        if (currentActivity.isFinishing || currentActivity.isDestroyed) {
            return false
        }
        return currentActivity.hasWindowFocus()
    }

    private fun restoreBackgroundIncomingCallValidatorRegistration() {
        val registration = backgroundValidatorRegistrationStore.load() ?: return
        backgroundDispatcherHandle = registration.backgroundDispatcherHandle
        backgroundAcceptCallbackHandle = registration.backgroundAcceptCallbackHandle
        backgroundDeclineCallbackHandle = registration.backgroundDeclineCallbackHandle
    }

    private fun currentBackgroundIncomingCallValidatorRegistration():
        BackgroundValidatorRegistrationStore.Registration? {
        val dispatcherHandle = backgroundDispatcherHandle
        val acceptCallbackHandle = backgroundAcceptCallbackHandle
        val declineCallbackHandle = backgroundDeclineCallbackHandle
        if (dispatcherHandle != null &&
            (acceptCallbackHandle != null || declineCallbackHandle != null)
        ) {
            return BackgroundValidatorRegistrationStore.Registration(
                backgroundDispatcherHandle = dispatcherHandle,
                backgroundAcceptCallbackHandle = acceptCallbackHandle,
                backgroundDeclineCallbackHandle = declineCallbackHandle,
            )
        }

        val restored = backgroundValidatorRegistrationStore.load() ?: return null
        backgroundDispatcherHandle = restored.backgroundDispatcherHandle
        backgroundAcceptCallbackHandle = restored.backgroundAcceptCallbackHandle
        backgroundDeclineCallbackHandle = restored.backgroundDeclineCallbackHandle
        return restored
    }

    private fun backgroundIncomingCallValidatorRegistrationFor(
        payload: CallPayload,
    ): BackgroundValidatorRegistrationStore.Registration? {
        val payloadDispatcherHandle = payload.backgroundDispatcherHandle
        val payloadAcceptCallbackHandle = payload.backgroundCallbackHandle
        val payloadDeclineCallbackHandle = payload.backgroundDeclineCallbackHandle
        if (payloadDispatcherHandle != null &&
            (payloadAcceptCallbackHandle != null || payloadDeclineCallbackHandle != null)
        ) {
            return BackgroundValidatorRegistrationStore.Registration(
                backgroundDispatcherHandle = payloadDispatcherHandle,
                backgroundAcceptCallbackHandle = payloadAcceptCallbackHandle,
                backgroundDeclineCallbackHandle = payloadDeclineCallbackHandle,
            )
        }
        return currentBackgroundIncomingCallValidatorRegistration()
    }

    fun launchHostApp(
        action: String,
        payload: CallPayload,
        skipStartupActionHandoff: Boolean = false,
    ) {
        val launchIntent = hostLaunchIntentForAction(action) ?: return
        launchIntent.putPayloadExtras(payload)
        launchIntent.putExtra(CallwaveConstants.EXTRA_LAUNCH_ACTION, action)
        launchIntent.putExtra(
            CallwaveConstants.EXTRA_SKIP_STARTUP_ACTION_HANDOFF,
            skipStartupActionHandoff,
        )
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP,
        )
        context.startActivity(launchIntent)
    }

    private fun validatedAcceptBridgeIntent(payload: CallPayload): Intent {
        return Intent(context, ValidatedAcceptBridgeActivity::class.java).apply {
            putPayloadExtras(payload)
        }
    }

    private fun Intent.putPayloadExtras(payload: CallPayload) {
        putExtra(CallwaveConstants.EXTRA_CALL_ID, payload.callId)
        putExtra(CallwaveConstants.EXTRA_CALLER_NAME, payload.callerName)
        putExtra(CallwaveConstants.EXTRA_HANDLE, payload.handle)
        putExtra(CallwaveConstants.EXTRA_AVATAR_URL, payload.avatarUrl)
        putExtra(CallwaveConstants.EXTRA_TIMEOUT_SECONDS, payload.timeoutSeconds)
        putExtra(CallwaveConstants.EXTRA_CALL_TYPE, payload.callType)
        putExtra(CallwaveConstants.EXTRA_EXTRA, toExtraJson(payload.extra))
        putExtra(
            CallwaveConstants.EXTRA_INCOMING_ACCEPT_STRATEGY,
            payload.incomingAcceptStrategy,
        )
        putExtra(
            CallwaveConstants.EXTRA_BACKGROUND_DISPATCHER_HANDLE,
            payload.backgroundDispatcherHandle,
        )
        putExtra(
            CallwaveConstants.EXTRA_BACKGROUND_CALLBACK_HANDLE,
            payload.backgroundCallbackHandle,
        )
        putExtra(
            CallwaveConstants.EXTRA_BACKGROUND_DECLINE_CALLBACK_HANDLE,
            payload.backgroundDeclineCallbackHandle,
        )
    }

    companion object {
        private const val TAG = "CallwaveFlutter"
        private const val REQUEST_NOTIFICATIONS = 4512
        private const val PENDING_INTENT_REQUEST_CODE_OFFSET_FULL_SCREEN = 10000
        private const val PENDING_INTENT_REQUEST_CODE_OFFSET_ACCEPT_AND_OPEN = 30000
        private const val PENDING_INTENT_REQUEST_CODE_OFFSET_OPEN_ONGOING = 35000
        private const val PENDING_INTENT_REQUEST_CODE_OFFSET_OPEN_MISSED_CALL = 36000
    }
}

enum class AcceptResult {
    HANDLED,
    LAUNCH_NOW,
    VALIDATION_PENDING,
    IGNORED,
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
