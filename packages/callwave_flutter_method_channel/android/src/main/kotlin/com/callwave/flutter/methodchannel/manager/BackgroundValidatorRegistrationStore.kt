package com.callwave.flutter.methodchannel.manager

import android.content.Context

internal class BackgroundValidatorRegistrationStore(context: Context) {
    private val sharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun load(): Registration? {
        if (!sharedPreferences.contains(KEY_DISPATCHER_HANDLE) ||
            !sharedPreferences.contains(KEY_CALLBACK_HANDLE)
        ) {
            return null
        }

        val dispatcherHandle = sharedPreferences.getLong(KEY_DISPATCHER_HANDLE, 0L)
        val callbackHandle = sharedPreferences.getLong(KEY_CALLBACK_HANDLE, 0L)
        if (dispatcherHandle <= 0L || callbackHandle <= 0L) {
            clear()
            return null
        }

        return Registration(
            backgroundDispatcherHandle = dispatcherHandle,
            backgroundCallbackHandle = callbackHandle,
        )
    }

    fun save(
        backgroundDispatcherHandle: Long,
        backgroundCallbackHandle: Long,
    ) {
        sharedPreferences.edit()
            .putLong(KEY_DISPATCHER_HANDLE, backgroundDispatcherHandle)
            .putLong(KEY_CALLBACK_HANDLE, backgroundCallbackHandle)
            .commit()
    }

    fun clear() {
        sharedPreferences.edit()
            .remove(KEY_DISPATCHER_HANDLE)
            .remove(KEY_CALLBACK_HANDLE)
            .commit()
    }

    internal data class Registration(
        val backgroundDispatcherHandle: Long,
        val backgroundCallbackHandle: Long,
    )

    companion object {
        private const val PREFS_NAME = "callwave_flutter_background_validator"
        private const val KEY_DISPATCHER_HANDLE = "dispatcher_handle"
        private const val KEY_CALLBACK_HANDLE = "callback_handle"
    }
}
