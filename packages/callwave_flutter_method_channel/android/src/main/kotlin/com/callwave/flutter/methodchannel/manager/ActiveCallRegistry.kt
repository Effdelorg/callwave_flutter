package com.callwave.flutter.methodchannel.manager

class ActiveCallRegistry {
    private val activeCalls = LinkedHashSet<String>()

    @Synchronized
    fun tryStart(callId: String): Boolean {
        if (activeCalls.isEmpty() || activeCalls.contains(callId)) {
            activeCalls.add(callId)
            return true
        }
        return false
    }

    @Synchronized
    fun remove(callId: String) {
        activeCalls.remove(callId)
    }

    @Synchronized
    fun getActiveCallIds(): List<String> {
        return activeCalls.toList()
    }
}
