package com.keplr.vizor.simplex

import android.app.Service
import android.content.Intent
import android.os.*
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/** Bound only during explicit foreground activation. A process exit is the native
 * controller destructor: close_store alone leaves Haskell networking alive. */
class SimplexService : Service() {
    @Volatile private var session: String? = null
    @Volatile private var owner: IBinder? = null
    private val opening = AtomicBoolean(false)
    private val sending = AtomicBoolean(false)
    private val receiving = AtomicBoolean(false)
    @Volatile private var ready = false
    private val ownerDeath = IBinder.DeathRecipient { terminate() }
    private fun terminate(): Nothing {
        ready = false
        Process.killProcess(Process.myPid())
        throw IllegalStateException("SimpleX process did not exit")
    }
    private val endpoint = object : Binder() {
        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
            if (code == INTERFACE_TRANSACTION) { reply?.writeString(SimplexProtocol.DESCRIPTOR); return true }
            if (Binder.getCallingUid() != Process.myUid()) throw SecurityException()
            data.enforceInterface(SimplexProtocol.DESCRIPTOR)
            if (data.dataSize() > 300000) throw IllegalArgumentException("IPC request too large")
            val id = SimplexProtocol.bounded(data.readString() ?: "", 128)
            try {
                if (code == SimplexProtocol.ATTACH) {
                    synchronized(this@SimplexService) {
                        check(session == null)
                        val parent = data.readStrongBinder() ?: error("Missing parent")
                        parent.linkToDeath(ownerDeath, 0)
                        owner = parent
                        session = id
                    }
                    reply?.writeNoException()
                    return true
                }
                check(id == session && owner?.isBinderAlive == true)
                if (code == SimplexProtocol.STOP) terminate()
                val response = when (code) {
                    SimplexProtocol.OPEN -> {
                        check(opening.compareAndSet(false, true))
                        val path = SimplexProtocol.bounded(data.readString() ?: "", 4096)
                        val key = SimplexProtocol.bounded(data.readString() ?: "", 1024)
                        // Canonical containment excludes traversal and symlink escapes.
                        val root = applicationInfo.dataDir.let(::File).canonicalFile
                        val db = File(path).canonicalFile
                        require(db.path.startsWith(root.path + File.separator))
                        require(db.parentFile?.isDirectory == true)
                        SimplexNative.open(db.path, key).also { ready = true }
                    }
                    SimplexProtocol.COMMAND -> {
                        check(ready && sending.compareAndSet(false, true))
                        try { SimplexNative.command(SimplexProtocol.bounded(data.readString() ?: "", 120000)) }
                        finally { sending.set(false) }
                    }
                    SimplexProtocol.POLL -> {
                        check(ready && receiving.compareAndSet(false, true))
                        try { SimplexNative.poll() } finally { receiving.set(false) }
                    }
                    else -> return false
                }
                check(id == session && owner?.isBinderAlive == true)
                SimplexProtocol.bounded(response, SimplexProtocol.MAX_RESPONSE, empty = true)
                reply?.writeNoException()
                // UTF-8 bytes keep the Binder bound independent of UTF-16 expansion.
                reply?.writeByteArray(response.toByteArray(Charsets.UTF_8))
            } catch (_: Exception) {
                reply?.writeException(IllegalStateException("SimpleX operation failed"))
            }
            return true
        }
    }
    override fun onBind(intent: Intent): IBinder = endpoint
    override fun onUnbind(intent: Intent): Boolean { terminate() }
    override fun onDestroy() { terminate() }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY
}
