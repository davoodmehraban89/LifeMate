package ir.lifeguide.app

import java.util.UUID

/** Pending local write ownership lives for the whole Android process. */
object LocalWriteGuard {
    private var pendingToken: String? = null

    @Synchronized
    fun getBlocked(): Boolean = pendingToken != null

    @Synchronized
    fun beginWrite(): String? {
        if (pendingToken != null) return null
        val token = UUID.randomUUID().toString()
        pendingToken = token
        return token
    }

    @Synchronized
    fun completeWrite(token: String): Boolean {
        if (pendingToken == null || pendingToken != token) return false
        pendingToken = null
        return true
    }
}
