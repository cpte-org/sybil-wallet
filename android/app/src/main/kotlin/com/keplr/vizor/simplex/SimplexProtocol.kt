package com.keplr.vizor.simplex

internal object SimplexProtocol {
    const val DESCRIPTOR = "com.keplr.vizor.simplex.private.v1"
    const val ATTACH = 1
    const val OPEN = 2
    const val COMMAND = 3
    const val POLL = 4
    const val STOP = 5
    const val MAX_RESPONSE = 256 * 1024
    fun bounded(value: String, max: Int, empty: Boolean = false): String {
        require((empty || value.isNotEmpty()) && '\u0000' !in value &&
            value.length <= max && value.toByteArray(Charsets.UTF_8).size <= max)
        return value
    }
}

// Referenced only by the remote service. Never load this class in the wallet process.
internal object SimplexNative {
    init { System.loadLibrary("sigil_simplex") }
    private external fun openNative(path: ByteArray, key: ByteArray): ByteArray
    private external fun commandNative(command: ByteArray): ByteArray
    private external fun pollNative(): ByteArray
    fun open(path: String, key: String): String {
        val secret = key.toByteArray(Charsets.UTF_8)
        return try { openNative(path.toByteArray(Charsets.UTF_8), secret).toString(Charsets.UTF_8) }
        finally { secret.fill(0) }
    }
    fun command(command: String): String {
        val bytes = command.toByteArray(Charsets.UTF_8)
        return try { commandNative(bytes).toString(Charsets.UTF_8) } finally { bytes.fill(0) }
    }
    fun poll(): String = pollNative().toString(Charsets.UTF_8)
}
