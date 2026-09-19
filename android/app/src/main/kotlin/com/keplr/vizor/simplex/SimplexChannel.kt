package com.keplr.vizor.simplex

import android.content.*
import android.os.*
import io.flutter.plugin.common.*
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Wallet-process endpoint: no native symbols are loaded here. */
class SimplexChannel(private val context: Context, messenger: BinaryMessenger) {
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "com.keplr.vizor/simplex")
    private val commandWorker = Executors.newSingleThreadExecutor()
    private val pollWorker = Executors.newSingleThreadExecutor()
    private val owner = Binder()
    private var foreground = false
    private var disposed = false
    private var active: Session? = null
    private inner class Session(val id: String, val openResult: MethodChannel.Result) {
        var binder: IBinder? = null
        var closing = false
        var openFinished = false
        val commandBusy = AtomicBoolean(false)
        val pollBusy = AtomicBoolean(false)
        val closes = mutableListOf<MethodChannel.Result>()
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, service: IBinder) {
                if (active !== this@Session) return
                binder = service
                try { service.linkToDeath({ main.post { died(this@Session) } }, 0) }
                catch (_: Exception) { died(this@Session); return }
                commandWorker.execute {
                    try {
                        request(service, SimplexProtocol.ATTACH, id) { it.writeStrongBinder(owner) }
                        main.post {
                            if (active !== this@Session) return@post
                            if (closing || !foreground || disposed) stop(this@Session)
                            else startOpen(this@Session)
                        }
                    } catch (_: Exception) { main.post { stop(this@Session) } }
                }
            }
            override fun onServiceDisconnected(name: ComponentName) {
                if (binder?.isBinderAlive == true) stop(this@Session) else died(this@Session)
            }
            override fun onBindingDied(name: ComponentName) {
                if (binder?.isBinderAlive == true) stop(this@Session) else died(this@Session)
            }
            override fun onNullBinding(name: ComponentName) { died(this@Session) }
        }
        var path = ""
        var key = ""
    }
    init { channel.setMethodCallHandler(::handle) }
    fun resume() { foreground = true }
    fun background() { foreground = false; active?.let(::stop) }
    fun dispose() {
        disposed = true
        background()
        channel.setMethodCallHandler(null)
        if (active == null) { commandWorker.shutdown(); pollWorker.shutdown() }
    }
    private fun fail(result: MethodChannel.Result) {
        // Engine teardown must never prevent the independent process shutdown.
        runCatching { result.error("simplex_error", "SimpleX session unavailable or operation failed.", null) }
    }
    private fun available(): Boolean = listOf("libsigil_simplex.so", "libsimplex.so", "libsupport.so", "libapp-lib.so").all {
        File(context.applicationInfo.nativeLibraryDir, it).isFile
    }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            if (call.method == "availability") { result.success(available()); return }
            val id = SimplexProtocol.bounded(call.argument<String>("sessionId") ?: "", 128)
            if (call.method == "close") {
                val s = active
                if (s == null || s.id != id) result.success(null)
                else { s.closes.add(result); stop(s) }
                return
            }
            check(foreground && !disposed)
            if (call.method == "open") {
                check(active == null && available())
                val s = Session(id, result)
                s.path = SimplexProtocol.bounded(call.argument<String>("databasePath") ?: "", 4096)
                s.key = SimplexProtocol.bounded(call.argument<String>("databaseKey") ?: "", 1024)
                active = s
                val bound = runCatching {
                    context.bindService(Intent(context, SimplexService::class.java), s.connection, Context.BIND_AUTO_CREATE)
                }.getOrDefault(false)
                if (!bound) {
                    active = null
                    s.path = ""; s.key = ""
                    s.openFinished = true
                    fail(result)
                    return
                }
                // A stalled bind/init cannot leave the native session running indefinitely.
                main.postDelayed({ if (active === s && !s.openFinished) stop(s) }, 30000)
                return
            }
            val s = active ?: error("No session")
            check(s.id == id && !s.closing && s.openFinished)
            val code = when(call.method) { "command" -> SimplexProtocol.COMMAND; "poll" -> SimplexProtocol.POLL; else -> { result.notImplemented(); return } }
            val command = if (code == SimplexProtocol.COMMAND) SimplexProtocol.bounded(call.argument<String>("command") ?: "", 120000) else null
            val busy = if (command == null) s.pollBusy else s.commandBusy
            check(busy.compareAndSet(false, true))
            val executor = if (command == null) pollWorker else commandWorker
            executor.execute {
                val response = runCatching { request(s.binder!!, code, id) { if (command != null) it.writeString(command) } }
                main.post {
                    busy.set(false)
                    if (active === s && !s.closing && foreground && response.isSuccess) result.success(response.getOrNull())
                    else { fail(result); if (active === s && response.isFailure) stop(s) }
                }
            }
        } catch (_: Exception) { fail(result) }
    }
    private fun startOpen(s: Session) {
        commandWorker.execute {
            val response = runCatching { request(s.binder!!, SimplexProtocol.OPEN, s.id) { it.writeString(s.path); it.writeString(s.key) } }
            s.path = ""
            s.key = ""
            main.post {
                if (!s.openFinished) {
                    s.openFinished = true
                    if (active === s && !s.closing && foreground && response.isSuccess) s.openResult.success(response.getOrNull())
                    else { fail(s.openResult); stop(s) }
                }
            }
        }
    }
    private fun stop(s: Session) {
        s.closing = true
        s.path = ""
        s.key = ""
        if (!s.openFinished) { s.openFinished = true; fail(s.openResult) }
        val binder = s.binder ?: return // Wait for connect, then kill; never race a new process.
        // Remove AUTO_CREATE first so Android cannot recreate a killed service.
        runCatching { context.unbindService(s.connection) }
        val data = Parcel.obtain()
        try {
            data.writeInterfaceToken(SimplexProtocol.DESCRIPTOR)
            data.writeString(s.id)
            binder.transact(SimplexProtocol.STOP, data, null, IBinder.FLAG_ONEWAY)
        } catch (_: Exception) {
            // Unbind already requests service teardown. A transport failure is
            // not proof of process death: retain the tombstone if still alive.
            if (!binder.isBinderAlive) died(s)
        }
        finally { data.recycle() }
        // Do not reopen until Binder death proves native threads are gone.
    }
    private fun died(s: Session) {
        if (active !== s) return
        active = null
        s.path = ""; s.key = ""
        runCatching { context.unbindService(s.connection) }
        if (!s.openFinished) { s.openFinished = true; fail(s.openResult) }
        s.closes.forEach { it.success(null) }
        s.closes.clear()
        if (disposed) { commandWorker.shutdown(); pollWorker.shutdown() }
    }
    private fun request(binder: IBinder, code: Int, id: String, write: (Parcel) -> Unit): String {
        val data = Parcel.obtain(); val reply = Parcel.obtain()
        try {
            data.writeInterfaceToken(SimplexProtocol.DESCRIPTOR); data.writeString(id); write(data)
            check(binder.transact(code, data, reply, 0))
            reply.readException()
            if (code == SimplexProtocol.ATTACH) return ""
            check(reply.dataAvail() <= SimplexProtocol.MAX_RESPONSE + 8)
            val bytes = reply.createByteArray() ?: error("Missing response")
            check(bytes.size <= SimplexProtocol.MAX_RESPONSE)
            return bytes.toString(Charsets.UTF_8)
        } finally { data.recycle(); reply.recycle() }
    }
}
