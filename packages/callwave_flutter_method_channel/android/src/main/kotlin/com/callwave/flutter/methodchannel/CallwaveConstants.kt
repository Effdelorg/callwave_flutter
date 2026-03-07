package com.callwave.flutter.methodchannel

object CallwaveConstants {
    const val METHOD_CHANNEL = "callwave_flutter/methods"
    const val EVENT_CHANNEL = "callwave_flutter/events"
    const val NOTIFICATION_CHANNEL_ID = "callwave_flutter_calls_v2"
    const val NOTIFICATION_CHANNEL_ID_MISSED = "callwave_flutter_missed_calls"
    const val NOTIFICATION_CHANNEL_ID_OUTGOING = "callwave_flutter_outgoing_calls"
    const val NOTIFICATION_CHANNEL_ID_LEGACY = "callwave_flutter_calls"

    const val ACTION_ACCEPT = "com.callwave.flutter.methodchannel.ACTION_ACCEPT"
    const val ACTION_DECLINE = "com.callwave.flutter.methodchannel.ACTION_DECLINE"
    const val ACTION_END = "com.callwave.flutter.methodchannel.ACTION_END"
    const val ACTION_TIMEOUT = "com.callwave.flutter.methodchannel.ACTION_TIMEOUT"
    const val ACTION_CALLBACK = "com.callwave.flutter.methodchannel.ACTION_CALLBACK"
    const val ACTION_OPEN_INCOMING = "com.callwave.flutter.methodchannel.ACTION_OPEN_INCOMING"
    const val ACTION_OPEN_ONGOING = "com.callwave.flutter.methodchannel.ACTION_OPEN_ONGOING"
    const val ACTION_OPEN_MISSED_CALL =
        "com.callwave.flutter.methodchannel.ACTION_OPEN_MISSED_CALL"
    const val ACTION_ACCEPT_AND_OPEN = "com.callwave.flutter.methodchannel.ACTION_ACCEPT_AND_OPEN"

    const val EXTRA_CALL_ID = "callId"
    const val EXTRA_CALLER_NAME = "callerName"
    const val EXTRA_HANDLE = "handle"
    const val EXTRA_AVATAR_URL = "avatarUrl"
    const val EXTRA_TIMEOUT_SECONDS = "timeoutSeconds"
    const val EXTRA_CALL_TYPE = "callType"
    const val EXTRA_POST_CALL_BEHAVIOR = "postCallBehavior"
    const val EXTRA_EXTRA = "extra"
    const val EXTRA_LAUNCH_ACTION = "launchAction"
    const val EXTRA_ACCEPTANCE_STATE = "acceptanceState"
    const val EXTRA_CONNECTED_AT_MS = "connectedAtMs"
    const val EXTRA_OUTCOME_REASON = "outcomeReason"
    const val EXTRA_INCOMING_ACCEPT_STRATEGY = "incomingAcceptStrategy"
    const val EXTRA_BACKGROUND_DISPATCHER_HANDLE = "backgroundDispatcherHandle"
    const val EXTRA_BACKGROUND_CALLBACK_HANDLE = "backgroundCallbackHandle"
    const val EXTRA_STARTUP_ACTION_TYPE = "startupActionType"
    const val EXTRA_SKIP_STARTUP_ACTION_HANDOFF = "skipStartupActionHandoff"

    const val BACKGROUND_CHANNEL = "callwave_flutter/background"
    const val METHOD_VALIDATE_BACKGROUND_INCOMING_CALL = "validateBackgroundIncomingCall"
    const val METHOD_BACKGROUND_DISPATCHER_READY = "backgroundDispatcherReady"
    const val EXTRA_CALL_DATA = "callData"

    const val ACCEPTANCE_STATE_PENDING_VALIDATION = "pendingValidation"
    const val ACCEPTANCE_STATE_CONFIRMED = "confirmed"
    const val INCOMING_ACCEPT_STRATEGY_OPEN_IMMEDIATELY = "openImmediately"
    const val INCOMING_ACCEPT_STRATEGY_DEFER_OPEN_UNTIL_CONFIRMED =
        "deferOpenUntilConfirmed"

    const val EVENT_INCOMING = "incoming"
    const val EVENT_ACCEPTED = "accepted"
    const val EVENT_DECLINED = "declined"
    const val EVENT_ENDED = "ended"
    const val EVENT_TIMEOUT = "timeout"
    const val EVENT_MISSED = "missed"
    const val EVENT_CALLBACK = "callback"
    const val EVENT_STARTED = "started"

    const val STARTUP_ACTION_OPEN_MISSED_CALL = "openMissedCall"
    const val STARTUP_ACTION_CALLBACK = "callback"
}
