# Android private delivery — 2026-09-18

Android ARM64 private delivery uses the pinned SimpleX core in a non-exported,
app-private `:simplex` process. The test-build script fetches and verifies the
runtime automatically. Contact QR and copy/paste exchange remain available
when the optional native bundle is absent. iOS embedding is not implemented.

Build with `bash scripts/build-sigil-testnet.sh android`. The generated runtime
is selected through `SIMPLEX_ANDROID_LIBS_DIR`; a missing required library makes
the build fail. The test APK contains only ARM64 native libraries, including
Flutter and the bridge. Flutter's build-type ABI defaults are explicitly
overridden for this target, while split-ABI builds retain their split settings.

## Verified upstream inputs

The official [v7.0.2 library release](https://github.com/simplex-chat/simplex-chat-libs/releases/tag/v7.0.2)
contains Linux, macOS and Windows archives, but no standalone Android archive.
The official [SimpleX Chat v7.0.2 release](https://github.com/simplex-chat/simplex-chat/releases/tag/v7.0.2)
does supply Android APKs. GitHub release metadata reports:

| APK | Bytes | SHA-256 |
| --- | ---: | --- |
| `simplex-aarch64.apk` | 87466500 | `0a3a0bb7ca1e2411854883ba1ae352b15b11146fe0e137395671fff9ed839871` |
| `simplex-armv7a.apk` | 99123728 | `48c2681bb1e96eafeab125f61a644eec49562a1cc1117d2871c35280fe2d8e45` |

The ARM64 APK was downloaded from the pinned URL on 2026-09-18 and verified
locally at exactly 87,466,500 bytes with the listed SHA-256. The release page
also lists the same digest. The downloaded APK and extracted ELF files stay in
the ignored `build/simplex-android/` tree; no binary is checked into this
repository.

Run `tools/simplex/fetch-android.sh` to reproduce the extraction. It defaults to
`build/simplex-android/cache/v7.0.2/simplex-aarch64.apk` and writes the verified
bundle below `build/simplex-android/v7.0.2/`. It verifies size and SHA-256 before
reading any APK entry, extracts only the expected ARM64 entries, and never
executes code from the APK. Use `--apk PATH` or `--dest PATH` for explicit cache
and output locations; use `--refresh` when replacing a mismatched cached APK.

Upstream's pinned [Android build script](https://github.com/simplex-chat/simplex-chat/blob/v7.0.2/scripts/android/build-android.sh)
cross-compiles the Haskell core and support library with Nix, then packages the
native libraries into its own Android application. The [Android CMake wrapper](https://github.com/simplex-chat/simplex-chat/blob/v7.0.2/apps/multiplatform/common/src/commonMain/cpp/android/CMakeLists.txt)
expects per-ABI `libsimplex.so` and `libsupport.so`, builds JNI glue, and requests
16 KiB ELF page alignment. The extracted `jniLibs/arm64-v8a/` bundle also keeps
the official `libapp-lib.so` wrapper because the current private bridge loads its
JNI-compatible exports. The other three APK JNI objects are placed under
`official-app-libs/arm64-v8a/` for provenance; they support the upstream app UI
and camera paths and are not dependencies of the core bridge.

The generated core bundle is at:

```
build/simplex-android/v7.0.2/jniLibs/arm64-v8a/
  libapp-lib.so
  libsimplex.so
  libsupport.so
```

The official v7.0.2 Android wrapper source is
[`simplex-api.c`](https://raw.githubusercontent.com/simplex-chat/simplex-chat/v7.0.2/apps/multiplatform/common/src/commonMain/cpp/android/simplex-api.c).
Its initialization calls `hs_init_with_rtsopts` with `argc = 5` and
`{"simplex", "+RTS", "-A64m", "-H64m", "-xn", NULL}`, then calls
`setLineBuffering()`. The wrapper imports the core/support pair and exposes JNI
methods that call `chat_migrate_init`, `chat_close_store`,
`chat_send_cmd_retry`, and `chat_recv_msg_wait` among the other API helpers.
The verified `libapp-lib.so` exports the JNI entry points
`Java_chat_simplex_common_platform_CoreKt_initHS`,
`Java_chat_simplex_common_platform_CoreKt_pipeStdOutToSocket`,
`Java_chat_simplex_common_platform_CoreKt_chatMigrateInit`,
`Java_chat_simplex_common_platform_CoreKt_chatCloseStore`,
`Java_chat_simplex_common_platform_CoreKt_chatSendCmdRetry`, and
`Java_chat_simplex_common_platform_CoreKt_chatRecvMsgWait` (plus the other
helpers declared in `simplex-api.c`).

The relevant C ABI declarations from the pinned source are:

```c
typedef long *chat_ctrl;
char *chat_migrate_init(const char *, const char *, const char *, chat_ctrl *);
char *chat_close_store(chat_ctrl);
char *chat_send_cmd_retry(chat_ctrl, const char *, int);
char *chat_recv_msg_wait(chat_ctrl, int);
```

The pinned `newCStringFromLazyBS` helper allocates response buffers with
`mallocBytes (len + 1)` and writes a NUL terminator; `chat_close_store` uses the
same C-string allocation family through `newCAString`. The verified ARM64
`libsimplex.so` imports `malloc@LIBC` and `free@LIBC`, so a wrapper's
`free(response)` is allocator-compatible with Android's Bionic `libc.so` for
these returned buffers. The wrapper must copy bytes before returning across JNI;
the upstream JNI bridge performs that copy but does not expose a separate
`chat_free` symbol.

The ARM64 ELF inspection of the downloaded APK found:

| Object | Size | SHA-256 | Direct NEEDED entries | Role |
| --- | ---: | --- | --- | --- |
| `libsimplex.so` | 197,610,624 | `1856cdc7e1dd3cee2dac3d7d013d1e06c3facc12879f5775ea93ba92161dbfb4` | `libm.so`, `libdl.so`, `libc.so` | Haskell SimpleX core |
| `libsupport.so` | 14,650,736 | `acbabf60244517ec227f84afdbb166c7f2d00e31274d229bbba70926ff240f36` | `libm.so`, `libc.so` | Android support FFI (`setLineBuffering`, `pipe_std_to_socket`) |
| `libapp-lib.so` | 12,016 | `346394c5c6edb1d0bb79444e93847b7be4f5c06e3a5bf4ba0334c2d8d724bd4d` | `libsimplex.so`, `libsupport.so`, `liblog.so`, `libm.so`, `libdl.so`, `libc.so` | Official JNI bridge |

All three core objects are AArch64 Android ELF files and have 0x4000 LOAD
alignment. `libsimplex.so` and `libsupport.so` retain build-path RUNPATH notes,
but `readelf -d` shows no additional non-system NEEDED object in the APK. The
Android platform supplies the listed system libraries. The separated UI/camera
objects have their own platform-only dependencies (`libandroid.so`,
`libjnigraphics.so`, `liblog.so`, `libm.so`, `libdl.so`, `libc.so`).

The pinned [Android CMake wrapper](https://raw.githubusercontent.com/simplex-chat/simplex-chat/v7.0.2/apps/multiplatform/common/src/commonMain/cpp/android/CMakeLists.txt)
imports `libsimplex.so` and `libsupport.so`, links both into `app-lib`, links
Android `log`, and passes `-Wl,-z,max-page-size=16384`. The pinned build glue
keeps the C exports alive with `-u` linker entries for the `chat_*` functions;
the ARM64 `libsimplex.so` exports the command, receive, migration, close, and
JSON helpers used by the wrapper. This is source/build provenance, not a claim
that the downloaded APK is a reproducible source build.

## Implemented lifecycle boundary

In pinned [Mobile.hs](https://github.com/simplex-chat/simplex-chat/blob/v7.0.2/src/Simplex/Chat/Mobile.hs),
`chat_close_store` calls `chatCloseStore`, which closes the chat and agent database
handles. That API alone does not terminate the controller or free its Haskell
stable pointer. A JNI wrapper that calls only this function on wallet lock is
insufficient evidence that networking and sensitive native state have stopped.

The implementation uses bounded Binder IPC and no exported service or control
socket. Native libraries load only in the child process. Lock, account/network
change, route transition and backgrounding close the scoped Dart transport;
Android additionally terminates on Activity stop, service unbind and parent
Binder death. There is no boot receiver, background worker or push service.

Every request carries a random session identifier. Stale closes cannot terminate
a replacement session. Closing removes the service binding before terminating
the child; reopening waits for Binder death, with a bounded Dart shutdown wait
that requires an app restart if termination cannot be confirmed. Returning from
the background requires explicit reopening. Commands are limited to 120,000
UTF-8 bytes and responses to 256 KiB; oversized responses close the session.
Native stdout/stderr are discarded and core dumps disabled.

The database remains app-scoped and encrypted with an independent random key
stored in the existing unlocked account/network secure store. The shared Dart
adapter reconciles durable history and preserves wallet journal replay records. Portable
contact archives do not restore SimpleX ratchets or its database encryption key.
Tor remains unavailable until the native route has been separately qualified.
Only unlocked software test/regtest accounts with a settled direct route can
activate this experiment. No incoming packet accepts a contact or authorizes
a payment.

## Distribution and qualification still required

Preserve upstream [AGPL licensing](https://github.com/simplex-chat/simplex-chat/blob/v7.0.2/LICENSE),
third-party notices and corresponding-source/build obligations for the combined
distribution. The verified upstream license text is copied at
`tools/simplex/licenses/SimpleX-Chat-v7.0.2-LICENSE` and is copied into generated
bundles at `licenses/SimpleX-Chat-v7.0.2-LICENSE`. Its SHA-256 is
`8486a10c4393cee1c25392769ddd3b2d6c242d6ec7928e1414efff7dfb2f07ef`.
The asset covers the upstream repository's top-level AGPL text. It does not
inventory every AndroidX, camera, media, or transitive dependency embedded in
the APK, and it does not establish legal release clearance or complete
corresponding-source delivery.

Native instrumentation lives at
`android/app/src/androidTest/java/com/keplr/vizor/simplex/SimplexServiceTest.java`.
Build it with `:app:assembleReleaseAndroidTest -PsimplexTestBuildType=release`
and `-Ptarget-platform=android-arm64`, using the same runtime directory as the
app. It uses disposable encrypted profiles. The relay case requires the explicit
`simplexInvitation` instrumentation argument for another disposable peer.
See `docs/SIGIL-TEST-BUILD-2026-09-18.md` for the completed checks and remaining
device-validation limits.
