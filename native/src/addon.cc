/**
 * addon.cc â€” animind mpv embedded backend
 *
 * ARCHITECTURE: Dedicated MPV thread with Win32 message pump.
 *
 * Root cause of black screen: mpv's WGL (OpenGL) context must be created and
 * used on a thread that runs a Win32 message loop (PeekMessage/DispatchMessage).
 * Node's event loop thread has no such pump, so any mpv call that touches the
 * VO from that thread either silently fails or crashes.
 *
 * Fix: spawn one persistent "mpv thread" at initialize() time.  That thread:
 *   1. Calls mpv_initialize() with the HWND already set as wid option.
 *   2. Runs a tight loop: process posted work items + pump Win32 messages.
 *   3. All subsequent mpv calls (open, play, pause, seek â€¦) are posted to this
 *      thread and executed synchronously there.
 *
 * The Node-facing API functions post a lambda to the mpv thread, wait for it
 * to complete (with a timeout), and return the result.  This keeps the JS API
 * fully synchronous from the caller's perspective while being thread-safe.
 */

#include <napi.h>
#include <windows.h>
#include <cstring>
#include <vector>
#include <mutex>
#include <condition_variable>
#include <functional>
#include <string>
#include <queue>
#include <atomic>
#include <thread>
#include <chrono>

// â”€â”€â”€ mpv type definitions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
typedef struct mpv_handle mpv_handle;

#define MPV_FORMAT_STRING 1
#define MPV_FORMAT_FLAG   3
#define MPV_FORMAT_INT64  4
#define MPV_FORMAT_DOUBLE 5

typedef mpv_handle* (*mpv_create_fn)(void);
typedef int         (*mpv_initialize_fn)(mpv_handle*);
typedef int         (*mpv_set_property_fn)(mpv_handle*, const char*, int, void*);
typedef int         (*mpv_get_property_fn)(mpv_handle*, const char*, int, void*);
typedef int         (*mpv_command_fn)(mpv_handle*, const char**);
typedef void        (*mpv_terminate_destroy_fn)(mpv_handle*);
typedef char*       (*mpv_get_property_string_fn)(mpv_handle*, const char*);
typedef void        (*mpv_free_fn)(void*);
typedef int         (*mpv_set_option_string_fn)(mpv_handle*, const char*, const char*);
typedef int         (*mpv_set_option_fn)(mpv_handle*, const char*, int, void*);
typedef const char* (*mpv_error_string_fn)(int);

static HMODULE g_libmpv = nullptr;
static mpv_create_fn              mpv_create_ptr              = nullptr;
static mpv_initialize_fn          mpv_initialize_ptr          = nullptr;
static mpv_set_property_fn        mpv_set_property_ptr        = nullptr;
static mpv_get_property_fn        mpv_get_property_ptr        = nullptr;
static mpv_command_fn             mpv_command_ptr             = nullptr;
static mpv_terminate_destroy_fn   mpv_terminate_destroy_ptr   = nullptr;
static mpv_get_property_string_fn mpv_get_property_string_ptr = nullptr;
static mpv_free_fn                mpv_free_ptr                = nullptr;
static mpv_set_option_string_fn   mpv_set_option_string_ptr   = nullptr;
static mpv_set_option_fn          mpv_set_option_ptr          = nullptr;
static mpv_error_string_fn        mpv_error_string_ptr        = nullptr;

static bool load_libmpv() {
  if (g_libmpv) return true;
  const char* candidates[] = {
    "libmpv-2.dll",
    "vendor\\mpv\\win-x64\\libmpv-2.dll",
    "..\\..\\..\\vendor\\mpv\\win-x64\\libmpv-2.dll",
    "..\\vendor\\mpv\\win-x64\\libmpv-2.dll",
    nullptr
  };
  for (int i = 0; candidates[i]; ++i) {
    g_libmpv = LoadLibraryA(candidates[i]);
    if (g_libmpv) {
      fprintf(stderr, "[MPV addon] Loaded libmpv from: %s\n", candidates[i]);
      fflush(stderr);
      break;
    }
  }
  if (!g_libmpv) return false;
#define LOAD(n) n##_ptr = (n##_fn)GetProcAddress(g_libmpv, #n)
  LOAD(mpv_create); LOAD(mpv_initialize); LOAD(mpv_set_property);
  LOAD(mpv_get_property); LOAD(mpv_command); LOAD(mpv_terminate_destroy);
  LOAD(mpv_get_property_string); LOAD(mpv_free);
  LOAD(mpv_set_option_string); LOAD(mpv_set_option); LOAD(mpv_error_string);
#undef LOAD
  return mpv_create_ptr && mpv_initialize_ptr && mpv_set_property_ptr &&
         mpv_get_property_ptr && mpv_command_ptr && mpv_terminate_destroy_ptr;
}

static const char* get_mpv_err(int code) {
  if (mpv_error_string_ptr) return mpv_error_string_ptr(code);
  return "unknown libmpv error";
}

// RAII helper for libmpv strings
struct MpvString {
  char* ptr;
  MpvString(char* p) : ptr(p) {}
  ~MpvString() { if (ptr && mpv_free_ptr) mpv_free_ptr(ptr); }
  operator const char*() const { return ptr; }
  bool empty() const { return !ptr || !ptr[0]; }
  std::string str() const { return ptr ? ptr : ""; }
};

// â”€â”€â”€ MPV worker thread â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

struct WorkItem {
  std::function<void()> fn;
  std::mutex            mu;
  std::condition_variable cv;
  bool                  done = false;
  bool                  ok   = false;
  std::string           err;
};

static mpv_handle*        g_mpv         = nullptr;
static bool               g_initialized = false;
static std::thread*       g_mpv_thread  = nullptr;
static std::atomic<bool>  g_thread_running{false};
static std::atomic<int64_t> g_heartbeat{0};

// Queue for work items posted to the mpv thread
static std::queue<WorkItem*> g_work_queue;
static std::mutex            g_queue_mu;

// Custom window message to wake the mpv thread's message loop
#define WM_MPV_WORK (WM_USER + 1)
static HWND g_msg_hwnd = nullptr; // invisible helper HWND owned by mpv thread

static void process_work_queue() {
  g_heartbeat.fetch_add(1);
  while (true) {
    WorkItem* item = nullptr;
    {
      std::lock_guard<std::mutex> lk(g_queue_mu);
      if (g_work_queue.empty()) break;
      item = g_work_queue.front();
      g_work_queue.pop();
    }

    try {
      item->fn();
      item->ok = true;
    } catch (const std::exception& e) {
      item->ok = false;
      item->err = e.what();
    } catch (...) {
      item->ok = false;
      item->err = "unknown error in work item";
    }

    {
      std::lock_guard<std::mutex> itemLk(item->mu);
      item->done = true;
    }
    item->cv.notify_one();
  }
}

static void fail_pending_work_items(const char* reason) {
  while (true) {
    WorkItem* item = nullptr;
    {
      std::lock_guard<std::mutex> lk(g_queue_mu);
      if (g_work_queue.empty()) break;
      item = g_work_queue.front();
      g_work_queue.pop();
    }

    {
      std::lock_guard<std::mutex> itemLk(item->mu);
      item->done = true;
      item->ok = false;
      item->err = reason ? reason : "mpv thread stopped";
    }
    item->cv.notify_one();
  }
}

static void mpv_thread_fn(int64_t wid) {
  fprintf(stderr, "[MPV thread] started\n"); fflush(stderr);
  g_initialized = false;

  WNDCLASSEXA wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = DefWindowProcA;
  wc.hInstance = GetModuleHandleA(nullptr);
  wc.lpszClassName = "AnimindMpvMsgWnd";
  RegisterClassExA(&wc);
  g_msg_hwnd = CreateWindowExA(0, "AnimindMpvMsgWnd", nullptr, 0,
                                0, 0, 0, 0, HWND_MESSAGE, nullptr,
                                GetModuleHandleA(nullptr), nullptr);
  if (!g_msg_hwnd) {
    fprintf(stderr, "[MPV thread] ERROR: CreateWindowEx failed: %lu\n", GetLastError());
    fflush(stderr);
    g_initialized = false;
    g_thread_running.store(false);
    return;
  }

  // VO fallback chain: angle -> d3d11 -> direct3d -> gpu-next -> gpu(auto)
  // gpu-context=win (raw WGL) conflicts with Chromium's ANGLE compositor
  // and produces audio-only / black-screen. We try safer backends first.
  struct VoCand { const char* vo; const char* ctx; const char* api; };
  static const VoCand cands[] = {
    { "gpu",      "angle",   "opengl" },
    { "gpu",      "d3d11",   nullptr  },
    { "direct3d", nullptr,   nullptr  },
    { "gpu-next", nullptr,   nullptr  },
    { "gpu",      nullptr,   nullptr  },
  };

  int ret = -1;
  for (int ci = 0; ci < 5; ++ci) {
    if (g_mpv) {
      mpv_terminate_destroy_ptr(g_mpv);
      g_mpv = nullptr;
    }
    g_mpv = mpv_create_ptr();
    if (!g_mpv) {
      fprintf(stderr, "[MPV thread] ERROR: mpv_create() failed on retry %d\n", ci);
      fflush(stderr);
      g_initialized = false;
      g_thread_running.store(false);
      return;
    }

    if (mpv_set_option_ptr)
      mpv_set_option_ptr(g_mpv, "wid", MPV_FORMAT_INT64, &wid);
    
    if (mpv_set_option_string_ptr) {
      mpv_set_option_string_ptr(g_mpv, "vo", cands[ci].vo);
      if (cands[ci].ctx) mpv_set_option_string_ptr(g_mpv, "gpu-context", cands[ci].ctx);
      if (cands[ci].api) mpv_set_option_string_ptr(g_mpv, "gpu-api", cands[ci].api);
      mpv_set_option_string_ptr(g_mpv, "hwdec", "no");
      mpv_set_option_string_ptr(g_mpv, "keepaspect", "yes");
      mpv_set_option_string_ptr(g_mpv, "msg-level", "all=warn");
      // Prevent mpv from creating its own window if wid fails
      mpv_set_option_string_ptr(g_mpv, "force-window", "no");
    }

    fprintf(stderr, "[MPV thread] trying vo=%s ctx=%s\n",
            cands[ci].vo, cands[ci].ctx ? cands[ci].ctx : "auto");
    fflush(stderr);

    ret = mpv_initialize_ptr(g_mpv);
    if (ret == 0) {
      fprintf(stderr, "[MPV thread] mpv_initialize OK: vo=%s ctx=%s\n",
              cands[ci].vo, cands[ci].ctx ? cands[ci].ctx : "auto");
      fflush(stderr);
      break;
    }
    fprintf(stderr, "[MPV thread] vo=%s failed: %s (%d), trying next\n", 
            cands[ci].vo, get_mpv_err(ret), ret);
    fflush(stderr);
  }

  if (ret < 0) {
    fprintf(stderr, "[MPV thread] ERROR: all VO candidates failed\n"); fflush(stderr);
    if (g_mpv) { mpv_terminate_destroy_ptr(g_mpv); g_mpv = nullptr; }
    g_initialized = false;
    g_thread_running.store(false);
    return;
  }

  // Give VO time to attach to HWND before first loadfile
  std::this_thread::sleep_for(std::chrono::milliseconds(200));
  g_initialized = true;

  MSG msg = {};
  while (g_thread_running.load()) {
    // Check heartbeat and process any "background" work that might have missed the event
    process_work_queue();

    BOOL gm = GetMessageA(&msg, nullptr, 0, 0);
    if (gm <= 0) break;
    if (msg.message == WM_MPV_WORK) {
      process_work_queue();
      continue;
    }
    TranslateMessage(&msg);
    DispatchMessageA(&msg);
    process_work_queue();
  }

  g_thread_running.store(false);
  fail_pending_work_items("mpv thread stopped");

  if (g_mpv) {
    mpv_terminate_destroy_ptr(g_mpv);
    g_mpv = nullptr;
  }
  if (g_msg_hwnd) {
    DestroyWindow(g_msg_hwnd);
    g_msg_hwnd = nullptr;
  }
  g_initialized = false;
  fprintf(stderr, "[MPV thread] exiting\n"); fflush(stderr);
}
// Post a lambda to the mpv thread and block until it completes (max 5 s).
// Returns true on success; on failure sets errOut.
static bool post_to_mpv_thread(std::function<void()> fn, std::string* errOut = nullptr) {
  if (!g_thread_running.load() || !g_msg_hwnd) {
    if (errOut) *errOut = "mpv thread not running";
    return false;
  }
  WorkItem item;
  item.fn = std::move(fn);
  {
    std::lock_guard<std::mutex> lk(g_queue_mu);
    g_work_queue.push(&item);
  }
  // Wake the mpv thread's message loop
  PostMessageA(g_msg_hwnd, WM_MPV_WORK, 0, 0);

  std::unique_lock<std::mutex> lk(item.mu);
  item.cv.wait_for(lk, std::chrono::seconds(5), [&]{ return item.done; });
  if (!item.done) {
    if (errOut) *errOut = "timeout waiting for mpv thread";
    return false;
  }
  if (!item.ok && errOut) *errOut = item.err;
  return item.ok;
}

static void stop_mpv_thread() {
  g_thread_running.store(false);
  if (g_msg_hwnd) PostMessageA(g_msg_hwnd, WM_QUIT, 0, 0);
  if (g_mpv_thread) {
    if (g_mpv_thread->joinable()) g_mpv_thread->join();
    delete g_mpv_thread;
    g_mpv_thread = nullptr;
  }
  g_initialized = false;
}

// â”€â”€â”€ HWND helper â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
static bool ReadHwndArg(const Napi::Value& value, int64_t* out) {
  if (value.IsBigInt()) {
    bool lossless = false;
    *out = value.As<Napi::BigInt>().Int64Value(&lossless);
    return lossless;
  }
  if (value.IsNumber()) { *out = value.As<Napi::Number>().Int64Value(); return true; }
  return false;
}

// â”€â”€â”€ Exported functions â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

Napi::Boolean IsAvailable(const Napi::CallbackInfo& info) {
  return Napi::Boolean::New(info.Env(), load_libmpv());
}

Napi::Boolean Initialize(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!load_libmpv()) {
    Napi::Error::New(env, "Failed to load libmpv-2.dll").ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }

  int64_t wid = 0;
  if (info.Length() < 1 || !ReadHwndArg(info[0], &wid)) {
    Napi::TypeError::New(env, "initialize(hwnd): HWND required").ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }
  fprintf(stderr, "[MPV addon] initialize(wid=%lld)\n", (long long)wid); fflush(stderr);

  // If already running, just update wid
  if (g_thread_running.load() && g_initialized) {
    std::string err;
    bool ok = post_to_mpv_thread([wid]{
      mpv_set_property_ptr(g_mpv, "wid", MPV_FORMAT_INT64, const_cast<int64_t*>(&wid));
    }, &err);
    if (!ok) fprintf(stderr, "[MPV addon] wid update: %s\n", err.c_str());
    return Napi::Boolean::New(env, ok);
  }

  // Stop any stale thread
  stop_mpv_thread();
  g_initialized = false;

  // Launch the dedicated mpv thread â€” it will call mpv_initialize internally
  g_thread_running.store(true);
  g_mpv_thread = new std::thread(mpv_thread_fn, wid);

  // Wait up to 5 s for mpv_initialize to complete inside the thread
  auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  while (std::chrono::steady_clock::now() < deadline) {
    if (g_initialized) break;
    if (!g_thread_running.load()) break; // thread exited with error
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }

  if (!g_initialized) {
    stop_mpv_thread();
    Napi::Error::New(env, "mpv_initialize() failed or timed out").ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }

  fprintf(stderr, "[MPV addon] initialized OK on dedicated thread\n"); fflush(stderr);
  return Napi::Boolean::New(env, true);
}

Napi::Boolean SetWindowId(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  int64_t wid = 0;
  if (info.Length() < 1 || !ReadHwndArg(info[0], &wid)) {
    Napi::TypeError::New(env, "Expected HWND").ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }
  std::string err;
  bool ok = post_to_mpv_thread([wid]{
    mpv_set_property_ptr(g_mpv, "wid", MPV_FORMAT_INT64, const_cast<int64_t*>(&wid));
  }, &err);
  if (!ok) Napi::Error::New(env, err).ThrowAsJavaScriptException();
  return Napi::Boolean::New(env, ok);
}

Napi::Boolean Open(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!g_initialized) {
    Napi::Error::New(env, "mpv not initialized").ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }
  if (info.Length() < 1 || !info[0].IsString()) {
    Napi::TypeError::New(env, "Expected url string").ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }
  std::string url = info[0].As<Napi::String>().Utf8Value();
  fprintf(stderr, "[MPV addon] open(%s)\n", url.c_str()); fflush(stderr);
  std::string err;
  bool ok = post_to_mpv_thread([url]{
    const char* cmd[] = { "loadfile", url.c_str(), nullptr };
    int r = mpv_command_ptr(g_mpv, cmd);
    if (r < 0) throw std::runtime_error("loadfile failed: " + std::to_string(r));
  }, &err);
  if (!ok) Napi::Error::New(env, err).ThrowAsJavaScriptException();
  return Napi::Boolean::New(env, ok);
}

Napi::Boolean Play(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  std::string err;
  bool ok = post_to_mpv_thread([]{
    int val = 0;
    mpv_set_property_ptr(g_mpv, "pause", MPV_FORMAT_FLAG, &val);
  }, &err);
  if (!ok) Napi::Error::New(env, err).ThrowAsJavaScriptException();
  return Napi::Boolean::New(env, ok);
}

Napi::Boolean Pause(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  std::string err;
  bool ok = post_to_mpv_thread([]{
    int val = 1;
    mpv_set_property_ptr(g_mpv, "pause", MPV_FORMAT_FLAG, &val);
  }, &err);
  if (!ok) Napi::Error::New(env, err).ThrowAsJavaScriptException();
  return Napi::Boolean::New(env, ok);
}

Napi::Boolean Seek(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!info[0].IsNumber()) {
    Napi::TypeError::New(env, "Expected seconds").ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }
  double t = info[0].As<Napi::Number>().DoubleValue();
  std::string err;
  bool ok = post_to_mpv_thread([t]{
    double tv = t;
    mpv_set_property_ptr(g_mpv, "time-pos", MPV_FORMAT_DOUBLE, &tv);
  }, &err);
  if (!ok) Napi::Error::New(env, err).ThrowAsJavaScriptException();
  return Napi::Boolean::New(env, ok);
}

Napi::Object GetState(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  Napi::Object out = Napi::Object::New(env);
  int paused = 1; double timePos = 0, duration = 0;
  if (g_initialized) {
    post_to_mpv_thread([&]{
      mpv_get_property_ptr(g_mpv, "pause",    MPV_FORMAT_FLAG,   &paused);
      mpv_get_property_ptr(g_mpv, "time-pos", MPV_FORMAT_DOUBLE, &timePos);
      mpv_get_property_ptr(g_mpv, "duration", MPV_FORMAT_DOUBLE, &duration);
    });
  }
  out.Set("paused",   Napi::Boolean::New(env, paused != 0));
  out.Set("timePos",  Napi::Number::New(env, timePos  < 0 ? 0 : timePos));
  out.Set("duration", Napi::Number::New(env, duration < 0 ? 0 : duration));
  return out;
}

Napi::Boolean SetVolume(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!info[0].IsNumber()) { Napi::TypeError::New(env, "Expected number").ThrowAsJavaScriptException(); return Napi::Boolean::New(env, false); }
  double vol = std::max(0.0, std::min(100.0, info[0].As<Napi::Number>().DoubleValue()));
  std::string err;
  bool ok = post_to_mpv_thread([vol]{
    double v = vol;
    mpv_set_property_ptr(g_mpv, "volume", MPV_FORMAT_DOUBLE, &v);
  }, &err);
  if (!ok) Napi::Error::New(env, err).ThrowAsJavaScriptException();
  return Napi::Boolean::New(env, ok);
}

Napi::Boolean SetMuted(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!info[0].IsBoolean()) { Napi::TypeError::New(env, "Expected boolean").ThrowAsJavaScriptException(); return Napi::Boolean::New(env, false); }
  int val = info[0].As<Napi::Boolean>().Value() ? 1 : 0;
  std::string err;
  bool ok = post_to_mpv_thread([val]{
    int v = val;
    mpv_set_property_ptr(g_mpv, "mute", MPV_FORMAT_FLAG, &v);
  }, &err);
  if (!ok) Napi::Error::New(env, err).ThrowAsJavaScriptException();
  return Napi::Boolean::New(env, ok);
}

Napi::Object GetAudioState(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  Napi::Object out = Napi::Object::New(env);
  double vol = 100; int muted = 0;
  if (g_initialized) {
    post_to_mpv_thread([&]{
      mpv_get_property_ptr(g_mpv, "volume", MPV_FORMAT_DOUBLE, &vol);
      mpv_get_property_ptr(g_mpv, "mute",   MPV_FORMAT_FLAG,   &muted);
    });
  }
  out.Set("volume", Napi::Number::New(env, vol));
  out.Set("muted",  Napi::Boolean::New(env, muted != 0));
  return out;
}

Napi::Boolean SetAudioTrack(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!info[0].IsNumber()) { Napi::TypeError::New(env, "Expected track id").ThrowAsJavaScriptException(); return Napi::Boolean::New(env, false); }
  int64_t id = info[0].As<Napi::Number>().Int64Value();
  std::string err;
  bool ok = post_to_mpv_thread([id]{
    int64_t v = id;
    mpv_set_property_ptr(g_mpv, "aid", MPV_FORMAT_INT64, &v);
  }, &err);
  if (!ok) Napi::Error::New(env, err).ThrowAsJavaScriptException();
  return Napi::Boolean::New(env, ok);
}

Napi::Boolean SetSubtitleTrack(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (info.Length() < 1) { Napi::TypeError::New(env, "Expected id or 'no'").ThrowAsJavaScriptException(); return Napi::Boolean::New(env, false); }
  std::string err;
  bool ok;
  if (info[0].IsString()) {
    std::string s = info[0].As<Napi::String>().Utf8Value();
    ok = post_to_mpv_thread([s]{
      const char* p = s.c_str();
      mpv_set_property_ptr(g_mpv, "sid", MPV_FORMAT_STRING, (void*)p);
    }, &err);
  } else {
    int64_t id = info[0].As<Napi::Number>().Int64Value();
    ok = post_to_mpv_thread([id]{
      int64_t v = id;
      mpv_set_property_ptr(g_mpv, "sid", MPV_FORMAT_INT64, &v);
    }, &err);
  }
  if (!ok) Napi::Error::New(env, err).ThrowAsJavaScriptException();
  return Napi::Boolean::New(env, ok);
}

Napi::Boolean AddSubtitleFile(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!info[0].IsString()) { Napi::TypeError::New(env, "Expected file path").ThrowAsJavaScriptException(); return Napi::Boolean::New(env, false); }
  std::string p = info[0].As<Napi::String>().Utf8Value();
  std::string err;
  bool ok = post_to_mpv_thread([p]{
    const char* cmd[] = { "sub-add", p.c_str(), "select", nullptr };
    mpv_command_ptr(g_mpv, cmd);
  }, &err);
  if (!ok) Napi::Error::New(env, err).ThrowAsJavaScriptException();
  return Napi::Boolean::New(env, ok);
}

Napi::Array GetTrackList(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  Napi::Array result = Napi::Array::New(env);
  if (!g_initialized || !mpv_get_property_string_ptr) return result;

  std::string src;
  int64_t current_aid = 0, current_sid = 0;
  post_to_mpv_thread([&]{
    MpvString raw(mpv_get_property_string_ptr(g_mpv, "track-list"));
    if (!raw.empty()) src = raw.str();
    mpv_get_property_ptr(g_mpv, "aid", MPV_FORMAT_INT64, &current_aid);
    mpv_get_property_ptr(g_mpv, "sid", MPV_FORMAT_INT64, &current_sid);
  });

  if (src.empty()) return result;

  // Manual JSON-ish parser for track-list. 
  // mpv's track-list is an array of objects: [ { "id": 1, "type": "video", ... }, ... ]
  uint32_t arrayIdx = 0;
  size_t pos = 0;
  while ((pos = src.find('{', pos)) != std::string::npos) {
    size_t end = src.find('}', pos);
    if (end == std::string::npos) break;
    std::string obj = src.substr(pos, end - pos + 1);
    pos = end + 1;

    auto extract = [&](const char* key, bool is_num = false) -> std::string {
      std::string needle = std::string("\"") + key + "\":";
      size_t kpos = obj.find(needle);
      if (kpos == std::string::npos) return "";
      size_t vstart = kpos + needle.size();
      while (vstart < obj.size() && (obj[vstart] == ' ' || obj[vstart] == '\"')) vstart++;
      size_t vend = vstart;
      if (is_num) {
        while (vend < obj.size() && isdigit(obj[vend])) vend++;
      } else {
        vend = obj.find('\"', vstart);
      }
      if (vend == std::string::npos || vend <= vstart) return "";
      return obj.substr(vstart, vend - vstart);
    };

    std::string id_str = extract("id", true);
    if (id_str.empty()) continue;

    int64_t id = std::stoll(id_str);
    std::string type = extract("type");
    std::string title = extract("title");
    std::string lang = extract("lang");
    std::string codec = extract("codec");

    bool selected = (type == "audio" && id == current_aid) || (type == "sub" && id == current_sid);

    Napi::Object track = Napi::Object::New(env);
    track.Set("id", Napi::Number::New(env, (double)id));
    track.Set("type", Napi::String::New(env, type));
    track.Set("title", Napi::String::New(env, title.empty() ? type : title));
    track.Set("lang", Napi::String::New(env, lang));
    track.Set("codec", Napi::String::New(env, codec));
    track.Set("selected", Napi::Boolean::New(env, selected));
    result.Set(arrayIdx++, track);
  }
  return result;
}

void Destroy(const Napi::CallbackInfo&) {
  stop_mpv_thread();
}

Napi::Value GetHeartbeat(const Napi::CallbackInfo& info) {
  return Napi::BigInt::New(info.Env(), g_heartbeat.load());
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
  exports.Set("isAvailable",      Napi::Function::New(env, IsAvailable));
  exports.Set("initialize",       Napi::Function::New(env, Initialize));
  exports.Set("setWindowId",      Napi::Function::New(env, SetWindowId));
  exports.Set("open",             Napi::Function::New(env, Open));
  exports.Set("play",             Napi::Function::New(env, Play));
  exports.Set("pause",            Napi::Function::New(env, Pause));
  exports.Set("seek",             Napi::Function::New(env, Seek));
  exports.Set("getState",         Napi::Function::New(env, GetState));
  exports.Set("setVolume",        Napi::Function::New(env, SetVolume));
  exports.Set("setMuted",         Napi::Function::New(env, SetMuted));
  exports.Set("getAudioState",    Napi::Function::New(env, GetAudioState));
  exports.Set("setAudioTrack",    Napi::Function::New(env, SetAudioTrack));
  exports.Set("setSubtitleTrack", Napi::Function::New(env, SetSubtitleTrack));
  exports.Set("addSubtitleFile",  Napi::Function::New(env, AddSubtitleFile));
  exports.Set("getTrackList",     Napi::Function::New(env, GetTrackList));
  exports.Set("destroy",          Napi::Function::New(env, Destroy));
  exports.Set("getHeartbeat",     Napi::Function::New(env, GetHeartbeat));
  return exports;
}

NODE_API_MODULE(addon, Init)
