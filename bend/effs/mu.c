// mugen's system calls
// =======================
//
// What mugen needs from the operating system that Base does not have,
// each a def in bend/Sys.bend importing this one file (bend guide effects).
// Every call takes a path and opens, works and closes on its own, so no
// File handle is threaded through the Bend side. All run inline on the
// event loop: they are short, and the IO helper threads (64, shared with
// Process.run and File.*) stay free for the compactors' and turns' curls.
//
// A fallible call answers Base's Result: Fail{(errno, strerror(errno))}.

#include <dirent.h>
#include <signal.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static Term mu_unit(void) {
  return term_pak(CID(Unit), 0);
}

static Term mu_errno(Env e) {
  return io_fail(e, (u32)errno, NULL);
}

// write all n bytes, retrying on EINTR and short writes
static int mu_write_all(int fd, const char* p, u64 n) {
  while (n > 0) {
    ssize_t r = write(fd, p, n);
    if (r < 0 && errno == EINTR) {
      continue;
    }
    if (r < 0) {
      return -1;
    }
    p += r;
    n -= (u64)r;
  }
  return 0;
}

static int mu_pwrite_all(int fd, const char* p, u64 n, u64 off) {
  while (n > 0) {
    ssize_t r = pwrite(fd, p, n, (off_t)off);
    if (r < 0 && errno == EINTR) {
      continue;
    }
    if (r < 0) {
      return -1;
    }
    p += r;
    n -= (u64)r;
    off += (u64)r;
  }
  return 0;
}

// read up to max bytes at off into a fresh buffer; *got is how many came
static char* mu_pread_all(int fd, u64 off, u64 max, u64* got, int* code) {
  char* buf = io_mem(malloc(max + 1));
  *got  = 0;
  *code = 0;
  while (*got < max) {
    ssize_t r = pread(fd, buf + *got, max - *got, (off_t)(off + *got));
    if (r < 0 && errno == EINTR) {
      continue;
    }
    if (r < 0) {
      *code = errno;
      break;
    }
    if (r == 0) {
      break;
    }
    *got += (u64)r;
  }
  return buf;
}

static int mu_open(Env e, Term p, int flags, Term* fail) {
  u64   n    = 0;
  char* path = io_cstr(e, p, &n);
  if (io_nul(path, n)) {
    free(path);
    *fail = io_fail(e, EILSEQ, NULL);
    return -1;
  }
  int fd;
  do {
    fd = open(path, flags | O_CLOEXEC, 0644);
  } while (fd < 0 && errno == EINTR);
  int code = errno;
  free(path);
  if (fd < 0) {
    *fail = io_fail(e, (u32)code, NULL);
  }
  errno = code;
  return fd;
}

// mu.wall: the wall clock, milliseconds since the Unix epoch (IO.now is
// monotonic, for durations).
#ifdef CID(mu.wall)
Term mu_wall_run(Env e, Term* f, IoWork* w) {
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return (Term)((u64)ts.tv_sec * 1000ull + (u64)ts.tv_nsec / 1000000ull);
}

static void __attribute__((constructor)) mu_wall_use(void) {
  io_eff(CID(mu.wall), mu_wall_run);
}
#endif

// mu.tzoff(ms): the local zone's offset from UTC at that instant, in
// minutes east, plus 1440 (so it is never negative).
#ifdef CID(mu.tzoff)
Term mu_tzoff_run(Env e, Term* f, IoWork* w) {
  time_t    t = (time_t)((u64)f[0] / 1000ull);
  struct tm tm;
  tzset();
  localtime_r(&t, &tm);
  long m = tm.tm_gmtoff / 60;
  return (Term)(u32)(m + 1440);
}

static void __attribute__((constructor)) mu_tzoff_use(void) {
  io_eff(CID(mu.tzoff), mu_tzoff_run);
}
#endif

// mu.append(path, text, sync): text's UTF-8 at the end of the file (made
// if missing), fsynced when sync is 1; answers the offset it starts at.
#ifdef CID(mu.append)
Term mu_append_run(Env e, Term* f, IoWork* w) {
  Term fail;
  int  fd = mu_open(e, f[0], O_WRONLY | O_CREAT | O_APPEND, &fail);
  if (fd < 0) {
    return fail;
  }
  u64   n    = 0;
  char* text = io_cstr(e, f[1], &n);
  struct stat st;
  int ok = fstat(fd, &st) == 0 && mu_write_all(fd, text, n) == 0
    && ((u32)f[2] == 0 || fsync(fd) == 0);
  int code = errno;
  free(text);
  close(fd);
  if (!ok) {
    return io_fail(e, (u32)code, NULL);
  }
  return io_done(e, (Term)(u64)st.st_size);
}

static void __attribute__((constructor)) mu_append_use(void) {
  io_eff(CID(mu.append), mu_append_run);
}
#endif

// mu.pread_text(path, off, max): up to max bytes at off, decoded as UTF-8
// (ill-formed bytes as U+FFFD).
#ifdef CID(mu.pread_text)
Term mu_pread_text_run(Env e, Term* f, IoWork* w) {
  Term fail;
  int  fd = mu_open(e, f[0], O_RDONLY, &fail);
  if (fd < 0) {
    return fail;
  }
  u64   got  = 0;
  int   code = 0;
  char* buf  = mu_pread_all(fd, (u64)f[1], (u64)(u32)f[2], &got, &code);
  close(fd);
  Term r = code != 0 ? io_fail(e, (u32)code, NULL)
    : io_done(e, io_str(e, buf, got));
  free(buf);
  return r;
}

static void __attribute__((constructor)) mu_pread_text_use(void) {
  io_eff(CID(mu.pread_text), mu_pread_text_run);
}
#endif

// mu.read_file(path): the whole file, decoded as UTF-8.
#ifdef CID(mu.read_file)
Term mu_read_file_run(Env e, Term* f, IoWork* w) {
  Term fail;
  int  fd = mu_open(e, f[0], O_RDONLY, &fail);
  if (fd < 0) {
    return fail;
  }
  struct stat st;
  if (fstat(fd, &st) != 0) {
    int code = errno;
    close(fd);
    return io_fail(e, (u32)code, NULL);
  }
  u64   got  = 0;
  int   code = 0;
  char* buf  = mu_pread_all(fd, 0, (u64)st.st_size, &got, &code);
  close(fd);
  Term r = code != 0 ? io_fail(e, (u32)code, NULL)
    : io_done(e, io_str(e, buf, got));
  free(buf);
  return r;
}

static void __attribute__((constructor)) mu_read_file_use(void) {
  io_eff(CID(mu.read_file), mu_read_file_run);
}
#endif

// mu.save(path, text, sync): replaces the file whole, atomically: the text
// goes to path.new (fsynced when sync is 1), which is renamed over path.
#ifdef CID(mu.save)
Term mu_save_run(Env e, Term* f, IoWork* w) {
  u64   pn   = 0;
  char* path = io_cstr(e, f[0], &pn);
  if (io_nul(path, pn)) {
    free(path);
    return io_fail(e, EILSEQ, NULL);
  }
  char* tmp = io_mem(malloc(pn + 5));
  memcpy(tmp, path, pn);
  memcpy(tmp + pn, ".new", 5);
  int fd;
  do {
    fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
  } while (fd < 0 && errno == EINTR);
  if (fd < 0) {
    int code = errno;
    free(tmp);
    free(path);
    return io_fail(e, (u32)code, NULL);
  }
  u64   n    = 0;
  char* text = io_cstr(e, f[1], &n);
  int ok = mu_write_all(fd, text, n) == 0
    && ((u32)f[2] == 0 || fsync(fd) == 0);
  int code = errno;
  free(text);
  close(fd);
  if (ok && rename(tmp, path) != 0) {
    ok   = 0;
    code = errno;
  }
  free(tmp);
  free(path);
  return ok ? io_done(e, mu_unit()) : io_fail(e, (u32)code, NULL);
}

static void __attribute__((constructor)) mu_save_use(void) {
  io_eff(CID(mu.save), mu_save_run);
}
#endif

// mu.size(path): the file's size in bytes.
#ifdef CID(mu.size)
Term mu_size_run(Env e, Term* f, IoWork* w) {
  u64   n    = 0;
  char* path = io_cstr(e, f[0], &n);
  struct stat st;
  int ok   = !io_nul(path, n) && stat(path, &st) == 0;
  int code = io_nul(path, n) ? EILSEQ : errno;
  free(path);
  return ok ? io_done(e, (Term)(u64)st.st_size) : io_fail(e, (u32)code, NULL);
}

static void __attribute__((constructor)) mu_size_use(void) {
  io_eff(CID(mu.size), mu_size_run);
}
#endif

// mu.mkdirs(path): mkdir -p.
#ifdef CID(mu.mkdirs)
Term mu_mkdirs_run(Env e, Term* f, IoWork* w) {
  u64   n    = 0;
  char* path = io_cstr(e, f[0], &n);
  if (io_nul(path, n)) {
    free(path);
    return io_fail(e, EILSEQ, NULL);
  }
  for (u64 i = 1; i <= n; i += 1) {
    if (i == n || path[i] == '/') {
      char c  = path[i];
      path[i] = 0;
      if (mkdir(path, 0755) != 0 && errno != EEXIST) {
        int code = errno;
        free(path);
        return io_fail(e, (u32)code, NULL);
      }
      path[i] = c;
    }
  }
  free(path);
  return io_done(e, mu_unit());
}

static void __attribute__((constructor)) mu_mkdirs_use(void) {
  io_eff(CID(mu.mkdirs), mu_mkdirs_run);
}
#endif

// mu.ls(dir): the names in a directory (no . and ..), sorted bytewise.
#ifdef CID(mu.ls)
static int mu_ls_cmp(const void* a, const void* b) {
  return strcmp(*(char* const*)a, *(char* const*)b);
}

Term mu_ls_run(Env e, Term* f, IoWork* w) {
  u64   n    = 0;
  char* path = io_cstr(e, f[0], &n);
  DIR*  d    = io_nul(path, n) ? NULL : opendir(path);
  int   code = io_nul(path, n) ? EILSEQ : errno;
  free(path);
  if (d == NULL) {
    return io_fail(e, (u32)code, NULL);
  }
  u64    len = 0, cap = 64;
  char** xs  = io_mem(malloc(cap * sizeof(char*)));
  struct dirent* de;
  while ((de = readdir(d)) != NULL) {
    if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0) {
      continue;
    }
    if (len == cap) {
      cap *= 2;
      xs = io_mem(realloc(xs, cap * sizeof(char*)));
    }
    xs[len++] = io_mem(strdup(de->d_name));
  }
  closedir(d);
  qsort(xs, len, sizeof(char*), mu_ls_cmp);
  Term list = term_pak(CID(Nil), 0);
  for (u64 i = len; i > 0; i -= 1) {
    list = io_node(e, CID(Con), io_str(e, xs[i - 1], strlen(xs[i - 1])), list);
    free(xs[i - 1]);
  }
  free(xs);
  return io_done(e, list);
}

static void __attribute__((constructor)) mu_ls_use(void) {
  io_eff(CID(mu.ls), mu_ls_run);
}
#endif

// mu.slots(path, first, n): the u32 words of n 16-byte index slots from slot
// `first` on, little-endian, four per slot (slots past the end read 0).
#ifdef CID(mu.slots)
Term mu_slots_run(Env e, Term* f, IoWork* w) {
  Term fail;
  int  fd = mu_open(e, f[0], O_RDONLY, &fail);
  u64  first = (u64)f[1];
  u64  count = (u64)(u32)f[2];
  if (fd < 0 && errno != ENOENT) {
    return fail;
  }
  u64   got  = 0;
  int   code = 0;
  char* buf  = fd < 0 ? io_mem(calloc(1, count * 16 + 1))
    : mu_pread_all(fd, first * 16, count * 16, &got, &code);
  if (fd >= 0) {
    close(fd);
  }
  if (code != 0) {
    free(buf);
    return io_fail(e, (u32)code, NULL);
  }
  memset(buf + got, 0, count * 16 - got);
  Term list = term_pak(CID(Nil), 0);
  for (u64 i = count * 4; i > 0; i -= 1) {
    uint8_t* p = (uint8_t*)buf + (i - 1) * 4;
    u32      v = (u32)p[0] | (u32)p[1] << 8 | (u32)p[2] << 16 | (u32)p[3] << 24;
    list = io_node(e, CID(Con), (Term)v, list);
  }
  free(buf);
  return io_done(e, list);
}

static void __attribute__((constructor)) mu_slots_use(void) {
  io_eff(CID(mu.slots), mu_slots_run);
}
#endif

// mu.slot_put(path, slot, a, b, c, d, sync): one 16-byte index slot.
#ifdef CID(mu.slot_put)
Term mu_slot_put_run(Env e, Term* f, IoWork* w) {
  Term fail;
  int  fd = mu_open(e, f[0], O_WRONLY | O_CREAT, &fail);
  if (fd < 0) {
    return fail;
  }
  uint8_t buf[16];
  for (int k = 0; k < 4; k += 1) {
    u32 v = (u32)f[2 + k];
    buf[k * 4]     = (uint8_t)v;
    buf[k * 4 + 1] = (uint8_t)(v >> 8);
    buf[k * 4 + 2] = (uint8_t)(v >> 16);
    buf[k * 4 + 3] = (uint8_t)(v >> 24);
  }
  int ok = mu_pwrite_all(fd, (const char*)buf, 16, (u64)f[1] * 16) == 0
    && ((u32)f[6] == 0 || fsync(fd) == 0);
  int code = errno;
  close(fd);
  return ok ? io_done(e, mu_unit()) : io_fail(e, (u32)code, NULL);
}

static void __attribute__((constructor)) mu_slot_put_use(void) {
  io_eff(CID(mu.slot_put), mu_slot_put_run);
}
#endif

// mu.truncate(path, size): cut a file to size bytes.
#ifdef CID(mu.truncate)
Term mu_truncate_run(Env e, Term* f, IoWork* w) {
  u64   n    = 0;
  char* path = io_cstr(e, f[0], &n);
  int ok   = !io_nul(path, n) && truncate(path, (off_t)(u64)f[1]) == 0;
  int code = io_nul(path, n) ? EILSEQ : errno;
  free(path);
  return ok ? io_done(e, mu_unit()) : io_fail(e, (u32)code, NULL);
}

static void __attribute__((constructor)) mu_truncate_use(void) {
  io_eff(CID(mu.truncate), mu_truncate_run);
}
#endif

// mu.lock(path): flock(LOCK_EX | LOCK_NB) on path (made if missing). The
// descriptor stays open, so the lock lasts as long as the process.
#ifdef CID(mu.lock)
Term mu_lock_run(Env e, Term* f, IoWork* w) {
  Term fail;
  int  fd = mu_open(e, f[0], O_WRONLY | O_CREAT, &fail);
  if (fd < 0) {
    return fail;
  }
  int r;
  do {
    r = flock(fd, LOCK_EX | LOCK_NB);
  } while (r != 0 && errno == EINTR);
  if (r != 0) {
    int code = errno;
    close(fd);
    return io_fail(e, (u32)code, NULL);
  }
  return io_done(e, mu_unit());
}

static void __attribute__((constructor)) mu_lock_use(void) {
  io_eff(CID(mu.lock), mu_lock_run);
}
#endif

// mu.isatty(fd): 1 when the descriptor is a terminal, else 0.
#ifdef CID(mu.isatty)
Term mu_isatty_run(Env e, Term* f, IoWork* w) {
  return (Term)(u32)(isatty((int)(u32)f[0]) ? 1 : 0);
}

static void __attribute__((constructor)) mu_isatty_use(void) {
  io_eff(CID(mu.isatty), mu_isatty_run);
}
#endif

// mu.host(): the machine's host name.
#ifdef CID(mu.host)
Term mu_host_run(Env e, Term* f, IoWork* w) {
  char buf[256];
  if (gethostname(buf, sizeof buf - 1) != 0) {
    strcpy(buf, "localhost");
  }
  buf[sizeof buf - 1] = 0;
  return io_str(e, buf, strlen(buf));
}

static void __attribute__((constructor)) mu_host_use(void) {
  io_eff(CID(mu.host), mu_host_run);
}
#endif

// mu.kill(pid, group, sig): signal sig to a process (group 0) or its process
// group (group 1); 0 when sent, else the errno.
#ifdef CID(mu.kill)
Term mu_kill_run(Env e, Term* f, IoWork* w) {
  pid_t pid = (pid_t)(u32)f[0];
  int   sig = (int)(u32)f[2];
  int   r   = (u32)f[1] ? kill(-pid, sig) : kill(pid, sig);
  return (Term)(u32)(r == 0 ? 0 : errno);
}

static void __attribute__((constructor)) mu_kill_use(void) {
  io_eff(CID(mu.kill), mu_kill_run);
}
#endif

// mu.put(path, text): the file written whole in place (made 0644 if missing,
// its mode kept if not), as a tool's write does; not atomic, never synced.
#ifdef CID(mu.put)
Term mu_put_run(Env e, Term* f, IoWork* w) {
  u64   pn   = 0;
  char* path = io_cstr(e, f[0], &pn);
  if (io_nul(path, pn)) {
    free(path);
    return io_fail(e, EILSEQ, NULL);
  }
  int fd;
  do {
    fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
  } while (fd < 0 && errno == EINTR);
  int code = errno;
  free(path);
  if (fd < 0) {
    return io_fail(e, (u32)code, NULL);
  }
  u64   n    = 0;
  char* text = io_cstr(e, f[1], &n);
  int ok = mu_write_all(fd, text, n) == 0;
  code = errno;
  free(text);
  close(fd);
  return ok ? io_done(e, mu_unit()) : io_fail(e, (u32)code, NULL);
}

static void __attribute__((constructor)) mu_put_use(void) {
  io_eff(CID(mu.put), mu_put_run);
}
#endif

// mu.unlink(path): the file removed.
#ifdef CID(mu.unlink)
Term mu_unlink_run(Env e, Term* f, IoWork* w) {
  u64   n    = 0;
  char* path = io_cstr(e, f[0], &n);
  int ok   = !io_nul(path, n) && unlink(path) == 0;
  int code = io_nul(path, n) ? EILSEQ : errno;
  free(path);
  return ok ? io_done(e, mu_unit()) : io_fail(e, (u32)code, NULL);
}

static void __attribute__((constructor)) mu_unlink_use(void) {
  io_eff(CID(mu.unlink), mu_unlink_run);
}
#endif

// mu.units(path): the length of the file's text in UTF-16 units, read as
// UTF-8: a character of 4 bytes is two, any other one (a byte that is not a
// continuation byte starts one).
#ifdef CID(mu.units)
Term mu_units_run(Env e, Term* f, IoWork* w) {
  u64   n    = 0;
  char* path = io_cstr(e, f[0], &n);
  int fd = -1;
  if (!io_nul(path, n)) {
    do {
      fd = open(path, O_RDONLY | O_CLOEXEC);
    } while (fd < 0 && errno == EINTR);
  }
  int code = io_nul(path, n) ? EILSEQ : errno;
  free(path);
  if (fd < 0) {
    return io_fail(e, (u32)code, NULL);
  }
  unsigned char buf[65536];
  u64 units = 0;
  for (;;) {
    ssize_t r = read(fd, buf, sizeof buf);
    if (r < 0 && errno == EINTR) {
      continue;
    }
    if (r <= 0) {
      code = r < 0 ? errno : 0;
      break;
    }
    for (ssize_t k = 0; k < r; k += 1) {
      unsigned char b = buf[k];
      units += (b & 0xC0) == 0x80 ? 0 : b >= 0xF0 ? 2 : 1;
    }
  }
  close(fd);
  return code == 0 ? io_done(e, (Term)units) : io_fail(e, (u32)code, NULL);
}

static void __attribute__((constructor)) mu_units_use(void) {
  io_eff(CID(mu.units), mu_units_run);
}
#endif

// mu.exec(program, args): this process becomes program (looked up on PATH)
// with args, its terminal and environment kept, SIGPIPE back to its default
// (the runtime ignores it); answers only if that failed: the errno.
#ifdef CID(mu.exec)
Term mu_exec_run(Env e, Term* f, IoWork* w) {
  u64    len  = 0;
  u32    cap  = 8;
  u32    argc = 0;
  char** argv = calloc(cap, sizeof(char*));
  argv[argc++] = io_cstr(e, f[0], &len);
  Term xs = f[1];
  while (term_aux(xs) == CID(Con)) {
    Term pair[2];
    spare_free(e, cls_fit(2), ctr_take(e, xs, 2, pair));
    if (argc + 1 >= cap) {
      cap *= 2;
      argv = realloc(argv, cap * sizeof(char*));
    }
    argv[argc++] = io_cstr(e, pair[0], &len);
    xs = pair[1];
  }
  argv[argc] = NULL;
  fflush(stdout);
  fflush(stderr);
  signal(SIGPIPE, SIG_DFL);
  execvp(argv[0], argv);
  int code = errno;
  signal(SIGPIPE, SIG_IGN);
  for (u32 i = 0; i < argc; i++) {
    free(argv[i]);
  }
  free(argv);
  return (Term)(u32)code;
}

static void __attribute__((constructor)) mu_exec_use(void) {
  io_eff(CID(mu.exec), mu_exec_run);
}
#endif
