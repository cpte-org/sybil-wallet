// Process-scoped adapter for SimpleX Chat v7.0.2's C API. The upstream APK's
// app-lib supplies its own Android compatibility shims; never emulate symbols.
#include <jni.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/resource.h>
#include <sys/prctl.h>

#define RESPONSE_MAX (256 * 1024)
static void *controller;
static char *(*migrate)(const char *, const char *, const char *, void **);
static char *(*send_command)(void *, const char *);
static char *(*receive_message)(void *, int);
static int initialized;

static void wipe(void *p, size_t n) {
    volatile unsigned char *bytes = p;
    while (n--) *bytes++ = 0;
}
static void fail(JNIEnv *env) {
    (*env)->ThrowNew(env, (*env)->FindClass(env, "java/lang/IllegalStateException"),
                    "SimpleX native operation failed");
}
static char *input(JNIEnv *env, jbyteArray value, size_t limit) {
    if (!value) { fail(env); return NULL; }
    jsize n = (*env)->GetArrayLength(env, value);
    if (n <= 0 || (size_t)n > limit) { fail(env); return NULL; }
    char *result = malloc((size_t)n + 1);
    if (!result) { fail(env); return NULL; }
    (*env)->GetByteArrayRegion(env, value, 0, n, (jbyte *)result);
    if ((*env)->ExceptionCheck(env) || memchr(result, 0, (size_t)n)) {
        wipe(result, (size_t)n); free(result); fail(env); return NULL;
    }
    result[n] = 0;
    return result;
}
static jbyteArray output(JNIEnv *env, char *value) {
    if (!value) { fail(env); return NULL; }
    size_t n = strnlen(value, RESPONSE_MAX + 1);
    if (n > RESPONSE_MAX) {
        // Do not return a partial protocol response. Parent terminates session.
        wipe(value, n); free(value); fail(env); return NULL;
    }
    jbyteArray result = (*env)->NewByteArray(env, (jsize)n);
    if (result) (*env)->SetByteArrayRegion(env, result, 0, (jsize)n, (jbyte *)value);
    wipe(value, n); free(value);
    return result;
}
static int initialize(JNIEnv *env) {
    if (initialized) { fail(env); return 0; }
    initialized = 1;
    // No application payloads or key material may reach Android log collectors.
    int sink = open("/dev/null", O_WRONLY | O_CLOEXEC);
    if (sink < 0 || dup2(sink, STDOUT_FILENO) < 0 || dup2(sink, STDERR_FILENO) < 0) {
        if (sink >= 0) close(sink);
        fail(env); return 0;
    }
    close(sink);
    struct rlimit no_core = {0, 0};
    if (setrlimit(RLIMIT_CORE, &no_core) != 0 || prctl(PR_SET_DUMPABLE, 0) != 0) {
        fail(env); return 0;
    }
    void *library = dlopen("libapp-lib.so", RTLD_NOW | RTLD_GLOBAL);
    if (!library) { fail(env); return 0; }
    void (*init)(int *, char ***) = dlsym(library, "hs_init_with_rtsopts");
    void (*line_buffering)(void) = dlsym(library, "setLineBuffering");
    migrate = dlsym(library, "chat_migrate_init");
    send_command = dlsym(library, "chat_send_cmd");
    receive_message = dlsym(library, "chat_recv_msg_wait");
    if (!init || !line_buffering || !migrate || !send_command || !receive_message) {
        fail(env); return 0;
    }
    // Exact RTS settings from the pinned upstream Android simplex-api.c initHS.
    int argc = 5;
    char *args[] = {"simplex", "+RTS", "-A64m", "-H64m", "-xn", NULL};
    char **argv = args;
    init(&argc, &argv);
    line_buffering();
    return 1;
}
JNIEXPORT jbyteArray JNICALL
Java_com_keplr_vizor_simplex_SimplexNative_openNative(JNIEnv *env, jobject self,
                                                    jbyteArray path, jbyteArray key) {
    (void)self;
    char *p = input(env, path, 4096);
    if (!p) return NULL;
    char *k = input(env, key, 1024);
    if (!k) { wipe(p, strlen(p)); free(p); return NULL; }
    char *response = NULL;
    if (initialize(env)) response = migrate(p, k, "yesUp", &controller);
    wipe(k, strlen(k)); free(k); wipe(p, strlen(p)); free(p);
    if ((*env)->ExceptionCheck(env)) return NULL;
    return output(env, response);
}
JNIEXPORT jbyteArray JNICALL
Java_com_keplr_vizor_simplex_SimplexNative_commandNative(JNIEnv *env, jobject self,
                                                       jbyteArray command) {
    (void)self;
    if (!controller) { fail(env); return NULL; }
    char *cmd = input(env, command, 120000);
    if (!cmd) return NULL;
    char *response = send_command(controller, cmd);
    wipe(cmd, strlen(cmd)); free(cmd);
    return output(env, response);
}
JNIEXPORT jbyteArray JNICALL
Java_com_keplr_vizor_simplex_SimplexNative_pollNative(JNIEnv *env, jobject self) {
    (void)self;
    if (!controller) { fail(env); return NULL; }
    return output(env, receive_message(controller, 1000));
}
