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

    const val EVENT_INCOMING = "incoming"
    const val EVENT_ACCEPTED = "accepted"
    const val EVENT_DECLINED = "declined"
    const val EVENT_ENDED = "ended"
    const val EVENT_TIMEOUT = "timeout"
    const val EVENT_MISSED = "missed"
    const val EVENT_CALLBACK = "callback"
    const val EVENT_STARTED = "started"
}
