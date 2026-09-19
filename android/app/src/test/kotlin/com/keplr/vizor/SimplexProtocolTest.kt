package com.keplr.vizor

import com.keplr.vizor.simplex.SimplexProtocol
import org.junit.Assert.*
import org.junit.Test

class SimplexProtocolTest {
    @Test fun boundsAreUtf8NotCharacters() {
        assertEquals("é", SimplexProtocol.bounded("é", 2))
        assertThrows(IllegalArgumentException::class.java) { SimplexProtocol.bounded("é", 1) }
        assertThrows(IllegalArgumentException::class.java) { SimplexProtocol.bounded("a\u0000b", 20) }
        assertThrows(IllegalArgumentException::class.java) { SimplexProtocol.bounded("", 20) }
        assertEquals("", SimplexProtocol.bounded("", 20, empty = true))
    }
}
