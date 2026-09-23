// Sybil desktop host for the upstream AGPL SimpleX core.
// Private inherited pipes only: no TCP listener, shell, or wallet spending keys.
#define _POSIX_C_SOURCE 200809L
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <werapi.h>
#include <fcntl.h>
#include <io.h>
#else
#include <dlfcn.h>
#include <sys/resource.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void wipe(char *p, size_t n) {
  volatile char *v = p;
  while (n--) *v++ = 0;
}
static int line(char *buf, size_t cap) {
  if (!fgets(buf, (int)cap, stdin)) return 0;
  size_t n = strlen(buf);
  if (!n || buf[n-1] != '\n') return 0;
  buf[n-1] = 0;
  return 1;
}
static void output(char *value) {
  if (!value || strlen(value) > 1024 * 1024) _Exit(3);
  puts(*value ? value : "{}");
  fflush(stdout);
  wipe(value, strlen(value));
  free(value);
}
#ifdef _WIN32
int wmain(int argc, wchar_t **argv) {
#else
int main(int argc, char **argv) {
#endif
  if (argc != 2) return 2;
#ifdef _WIN32
  // Avoid crash dialogs and heap collection by Windows Error Reporting.
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
  WerSetFlags(WER_FAULT_REPORTING_FLAG_NOHEAP);
  _setmode(_fileno(stdin), _O_BINARY);
  _setmode(_fileno(stdout), _O_BINARY);
  // Restrict dependent DLL loading to this pinned library directory and Windows.
  HMODULE lib = LoadLibraryExW(argv[1], NULL,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!lib) return 2;
#define HOST_SYMBOL(name) GetProcAddress(lib, name)
#else
  struct rlimit limit = {0, 0};
  if (setrlimit(RLIMIT_CORE, &limit) != 0) return 2;
  setvbuf(stdin, NULL, _IONBF, 0);
  void *lib = dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL);
  if (!lib) return 2;
#define HOST_SYMBOL(name) dlsym(lib, name)
#endif
  setvbuf(stdin, NULL, _IONBF, 0);
  void (*init)(int *, char ***) = (void (*)(int *, char ***))HOST_SYMBOL("hs_init_with_rtsopts");
  char *(*migrate)(const char *, const char *, const char *, void **) =
      (char *(*)(const char *, const char *, const char *, void **))HOST_SYMBOL("chat_migrate_init");
  char *(*command)(void *, const char *) = (char *(*)(void *, const char *))HOST_SYMBOL("chat_send_cmd");
  char *(*receive)(void *, int) = (char *(*)(void *, int))HOST_SYMBOL("chat_recv_msg_wait");
  if (!init || !migrate || !command || !receive) return 2;
  int n = 6;
  char *args[] = {"sybil-simplex", "+RTS", "-A64m", "-H64m", "-xn",
                  "--install-signal-handlers=no", NULL};
  char **rts = args;
  init(&n, &rts);
  char path[4096], key[256];
  if (!line(path, sizeof(path)) || !line(key, sizeof(key)) || !*key) return 2;
  void *ctrl = NULL;
  char *status = migrate(path, key, "yesUp", &ctrl);
  wipe(key, sizeof(key));
  output(status);
  if (!ctrl) return 2;
  char *buf = malloc(128 * 1024);
  if (!buf) return 2;
  while (line(buf, 128 * 1024)) {
    if (!strcmp(buf, "POLL")) output(receive(ctrl, 1000));
    else if (!strncmp(buf, "CMD ", 4)) output(command(ctrl, buf + 4));
    else break;
    wipe(buf, 128 * 1024);
  }
  wipe(buf, 128 * 1024);
  free(buf);
  // The parent terminates this dedicated process on lock/account changes.
  // OS process teardown also discards the core's retained runtime/key state.
  _Exit(0);
}
