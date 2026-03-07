package com.callwave.flutter.methodchannel.manager

import android.content.Context

internal class BackgroundValidatorRegistrationStore(context: Context) {
    private val sharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun load(): Registration? {
        if (!sharedPreferences.contains(KEY_DISPATCHER_HANDLE) ||
            (!sharedPreferences.contains(KEY_ACCEPT_CALLBACK_HANDLE) &&
                !sharedPreferences.contains(KEY_DECLINE_CALLBACK_HANDLE))
        ) {
            return null
        }

        val dispatcherHandle = sharedPreferences.getLong(KEY_DISPATCHER_HANDLE, 0L)
        val acceptCallbackHandle =
            sharedPreferences.getLong(KEY_ACCEPT_CALLBACK_HANDLE, 0L).takeIf { it > 0L }
        val declineCallbackHandle =
            sharedPreferences.getLong(KEY_DECLINE_CALLBACK_HANDLE, 0L).takeIf { it > 0L }
        if (dispatcherHandle <= 0L ||
            (acceptCallbackHandle == null && declineCallbackHandle == null)
        ) {
            clear()
            return null
        }

        return Registration(
            backgroundDispatcherHandle = dispatcherHandle,
            backgroundAcceptCallbackHandle = acceptCallbackHandle,
            backgroundDeclineCallbackHandle = declineCallbackHandle,
        )
    }

    fun save(
        backgroundDispatcherHandle: Long,
        backgroundAcceptCallbackHandle: Long?,
        backgroundDeclineCallbackHandle: Long?,
    ) {
        val editor = sharedPreferences.edit()
            .putLong(KEY_DISPATCHER_HANDLE, backgroundDispatcherHandle)
        if (backgroundAcceptCallbackHandle != null && backgroundAcceptCallbackHandle > 0L) {
            editor.putLong(KEY_ACCEPT_CALLBACK_HANDLE, backgroundAcceptCallbackHandle)
        } else {
            editor.remove(KEY_ACCEPT_CALLBACK_HANDLE)
        }
        if (backgroundDeclineCallbackHandle != null && backgroundDeclineCallbackHandle > 0L) {
            editor.putLong(KEY_DECLINE_CALLBACK_HANDLE, backgroundDeclineCallbackHandle)
        } else {
            editor.remove(KEY_DECLINE_CALLBACK_HANDLE)
        }
        editor.commit()
    }

    fun clear() {
        sharedPreferences.edit()
            .remove(KEY_DISPATCHER_HANDLE)
            .remove(KEY_ACCEPT_CALLBACK_HANDLE)
            .remove(KEY_DECLINE_CALLBACK_HANDLE)
            .commit()
    }

    internal data class Registration(
        val backgroundDispatcherHandle: Long,
        val backgroundAcceptCallbackHandle: Long?,
        val backgroundDeclineCallbackHandle: Long?,
    )

    companion object {
        private const val PREFS_NAME = "callwave_flutter_background_validator"
        private const val KEY_DISPATCHER_HANDLE = "dispatcher_handle"
        private const val KEY_ACCEPT_CALLBACK_HANDLE = "accept_callback_handle"
        private const val KEY_DECLINE_CALLBACK_HANDLE = "decline_callback_handle"
    }
}
