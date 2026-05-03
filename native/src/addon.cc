/**
 * addon.cc – animind mpv embedded backend
 *
 * ARCHITECTURE: Dedicated MPV thread with Win32 message pump.
 *
 * Why wid=child-HWND doesn't work inside Electron:
 *   Electron uses Chromium's GPU compositor (DirectComposition on Windows).
 *   All rendering goes through Chromium's D3D device. A native WS_CHILD window
 *   created inside the Electron HWND renders through a DIFFERENT D3D context and
 *   is composited below Chromium's layer — so Chromium literally paints over it,
 *   producing a black rectangle where the video should be.
 *
 * The fix — use a SEPARATE TOP-LEVEL (WS_POPUP) window for mpv, NOT a child:
 *   1. Create a borderless WS_POPUP window (no parent, no taskbar entry).
 *   2. Use SetWindowLong to make it an owned window of the main Electron HWND
 *      so it moves with it and is destroyed with it, but is NOT a WS_CHILD.
 *   3. Set it to always render on top of the Electron window (SetWindowPos HWND_TOPMOST).
 *   4. Pass its HWND as mpv's wid — mpv renders into this top-level window.
 *   5. Position/resize this window to match the player div via SetWindowBounds.
 *
 * This is exactly how external mpv players (MPC-HC, etc.) overlay video on other
 * windows, and how media players like Kodi embed video on Windows.
 *
 * Coordinate system:
 *   TypeScript sends SCREEN-ABSOLUTE DPI-scaled physical pixels.
 *   SetWindowBounds receives those and calls SetWindowPos directly (no
 *   ScreenToClient needed — WS_POPUP uses screen coordinates).
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
#include <cstdlib>

// ─── mpv type definitions ───────────────────────────────────────────────────
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

struct MpvString {
  char* ptr;
  MpvString(char* p) : ptr(p) {}
  ~MpvString() { if (ptr && mpv_free_ptr) mpv_free_ptr(ptr); }
  operator const char*() const { return ptr; }
  bool empty() const { return !ptr || !ptr[0]; }
  std::string str() const { return ptr ? ptr : ""; }
};

// ─── MPV worker thread ───────────────────────────────────────────────────────

struct WorkItem {
  std::function<void()> fn;
  std::mutex mu;
  std::condition_variable cv;
  bool done = false;
  bool ok   = false;
  std::string err;
};

static mpv_handle*       g_mpv          = nullptr;
static bool              g_initialized  = false;
static std::thread*      g_mpv_thread   = nullptr;
static std::atomic<bool> g_thread_running{false};
static std::atomic<int64_t> g_heartbeat{0};

// g_overlay_wnd: WS_POPUP (NOT child) window that mpv renders into.
// It is an OWNED window of g_owner_wnd so it moves with it,
// but it is NOT a child — so Chromium cannot occlude it.
static HWND g_overlay_wnd = nullptr;
static HWND g_owner_wnd   = nullptr;  // Electron main window HWND
static bool g_surface_visible = false;
static bool g_trace_bounds = false;

static std::queue<WorkItem*> g_work_queue;
static std::mutex g_queue_mu;

#define WM_MPV_WORK (WM_USER + 1)
static HWND g_msg_hwnd = nullptr;

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
      item->ok  = false;
      item->err = e.what();
    } catch (...) {
      item->ok  = false;
      item->err = "unknown error in work item";
    }
    {
      std::lock_guard<std::mutex> lk(item->mu);
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
      std::lock_guard<std::mutex> lk(item->mu);
      item->done = true;
      item->ok   = false;
      item->err  = reason ? reason : "mpv thread stopped";
    }
    item->cv.notify_one();
  }
}

// Window class name for the overlay and message window
static const char* OVERLAY_CLASS = "AnimindMpvOverlay";
static const char* MSG_CLASS     = "AnimindMpvMsgWnd";

static void mpv_thread_fn(int64_t owner_wnd_arg) {
  g_trace_bounds = std::getenv("ANIMIND_MPV_TRACE_BOUNDS") != nullptr;
  fprintf(stderr, "[MPV thread] started (overlay/popup approach)\n"); fflush(stderr);
  g_initialized = false;
  g_owner_wnd = (HWND)(intptr_t)owner_wnd_arg;

  if (!g_owner_wnd || !IsWindow(g_owner_wnd)) {
    fprintf(stderr, "[MPV thread] ERROR: invalid owner HWND %p\n", g_owner_wnd);
    fflush(stderr);
    g_thread_running.store(false);
    return;
  }

  // Register window classes
  WNDCLASSEXA wc = {};
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = DefWindowProcA;
  wc.hInstance = GetModuleHandleA(nullptr);
  wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
  wc.lpszClassName = OVERLAY_CLASS;
  RegisterClassExA(&wc);

  wc.lpszClassName = MSG_CLASS;
  wc.hbrBackground = nullptr;
  RegisterClassExA(&wc);

  // Message-only helper HWND for PostMessage wakeups
  g_msg_hwnd = CreateWindowExA(0, MSG_CLASS, nullptr, 0,
                                0, 0, 0, 0, HWND_MESSAGE, nullptr,
                                GetModuleHandleA(nullptr), nullptr);

  // ── KEY CHANGE: Un-owned WS_POPUP ──────────────────────────────
  //
  // We use WS_POPUP so the video is an independent top-level window (which avoids
  // Chromium's WS_CHILD drawing issues). We pass nullptr for parent so it is NOT
  // owned by the Electron window, allowing us to place it BEHIND the Electron
  // window in Z-order. Electron is transparent, so the video shows through.
  //
  g_overlay_wnd = CreateWindowExA(
    WS_EX_NOACTIVATE,
    OVERLAY_CLASS,
    "mpv_overlay",
    WS_CHILD | WS_CLIPSIBLINGS,
    0, 0, 16, 16,
    g_owner_wnd,
    nullptr,
    GetModuleHandleA(nullptr),
    nullptr
  );

  if (!g_msg_hwnd || !g_overlay_wnd) {
    fprintf(stderr, "[MPV thread] ERROR: CreateWindowEx failed: %lu\n", GetLastError());
    fflush(stderr);
    g_thread_running.store(false);
    return;
  }

  fprintf(stderr, "[MPV thread] owner_wnd=%p overlay_wnd=%p msg_hwnd=%p\n",
          g_owner_wnd, g_overlay_wnd, g_msg_hwnd);
  fflush(stderr);

  // VO candidate order — prioritize modern gpu VOs for Windows embedding:
  //  gpu+d3d11 → libmpv gpu VO with explicit D3D11 backend (most reliable for modern Windows)
  //  gpu-next  → Vulkan/D3D12 (modern rendering)
  //  gpu       → Auto-select
  //  d3d11     → Legacy Direct3D 11 VO
  //  direct3d  → Legacy D3D9, very reliable fallback
  struct VoCand { const char* vo; const char* ctx; };
  static const VoCand cands[] = {
    { "gpu",      "d3d11"  },
    { "gpu-next", nullptr  },
    { "gpu",      nullptr  },
    { "d3d11",    nullptr  },
    { "direct3d", nullptr  },
  };
  static const int NUM_CANDS = 5;

  int ret = -1;
  for (int ci = 0; ci < NUM_CANDS; ++ci) {
    if (g_mpv) {
      mpv_terminate_destroy_ptr(g_mpv);
      g_mpv = nullptr;
    }
    g_mpv = mpv_create_ptr();
    if (!g_mpv) {
      fprintf(stderr, "[MPV thread] ERROR: mpv_create() returned null\n");
      fflush(stderr);
      g_thread_running.store(false);
      return;
    }

    // Set wid to the OVERLAY window (WS_POPUP, not WS_CHILD)
    if (mpv_set_option_ptr) {
      int64_t wid_val = (int64_t)(intptr_t)g_overlay_wnd;
      int r = mpv_set_option_ptr(g_mpv, "wid", MPV_FORMAT_INT64, &wid_val);
      fprintf(stderr, "[MPV thread] set wid=%p => %d\n", g_overlay_wnd, r);
      fflush(stderr);
    }

    if (mpv_set_option_string_ptr) {
      mpv_set_option_string_ptr(g_mpv, "vo",           cands[ci].vo);
      if (cands[ci].ctx)
        mpv_set_option_string_ptr(g_mpv, "gpu-context", cands[ci].ctx);
      // Use hwdec=auto for hardware decoding and force-window=yes to ensure rendering surface is active immediately
      mpv_set_option_string_ptr(g_mpv, "hwdec",        "auto");
      mpv_set_option_string_ptr(g_mpv, "keepaspect",   "yes");
      mpv_set_option_string_ptr(g_mpv, "force-window", "yes");
      const char* log_lvl = std::getenv("ANIMIND_MPV_DEBUG") ? "all=debug" : "all=info";
      mpv_set_option_string_ptr(g_mpv, "msg-level",    log_lvl);
    }

    fprintf(stderr, "[MPV thread] trying vo=%s ctx=%s\n",
            cands[ci].vo, cands[ci].ctx ? cands[ci].ctx : "auto");
    fflush(stderr);

    ret = mpv_initialize_ptr(g_mpv);
    if (ret == 0) {
      fprintf(stderr, "[MPV thread] mpv_initialize OK: vo=%s\n", cands[ci].vo);
      fflush(stderr);
      break;
    }
    fprintf(stderr, "[MPV thread] vo=%s failed: %s (%d), trying next\n",
            cands[ci].vo, get_mpv_err(ret), ret);
    fflush(stderr);
  }

  if (ret < 0 || !g_mpv) {
    fprintf(stderr, "[MPV thread] ERROR: all VO candidates failed\n");
    fflush(stderr);
    if (g_mpv) { mpv_terminate_destroy_ptr(g_mpv); g_mpv = nullptr; }
    g_thread_running.store(false);
    return;
  }

  // Brief settle time so the VO fully attaches before the first loadfile
  std::this_thread::sleep_for(std::chrono::milliseconds(100));
  g_initialized = true;

  // Message pump
  MSG msg = {};
  while (g_thread_running.load()) {
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
  if (g_overlay_wnd && IsWindow(g_overlay_wnd)) {
    DestroyWindow(g_overlay_wnd);
    g_overlay_wnd = nullptr;
  }
  if (g_msg_hwnd && IsWindow(g_msg_hwnd)) {
    DestroyWindow(g_msg_hwnd);
    g_msg_hwnd = nullptr;
  }
  g_initialized = false;
  fprintf(stderr, "[MPV thread] exiting\n"); fflush(stderr);
}

static bool post_to_mpv_thread(
  std::function<void()> fn,
  std::string* errOut = nullptr,
  int timeout_ms = 5000
) {
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
  PostMessageA(g_msg_hwnd, WM_MPV_WORK, 0, 0);

  std::unique_lock<std::mutex> lk(item.mu);
  if (timeout_ms < 1) timeout_ms = 1;
  item.cv.wait_for(lk, std::chrono::milliseconds(timeout_ms), [&]{ return item.done; });
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

static bool ReadHwndArg(const Napi::Value& value, int64_t* out) {
  if (value.IsBigInt()) {
    bool lossless = false;
    *out = value.As<Napi::BigInt>().Int64Value(&lossless);
    return lossless;
  }
  if (value.IsNumber()) { *out = value.As<Napi::Number>().Int64Value(); return true; }
  return false;
}

// ─── Exported functions ──────────────────────────────────────────────────────

Napi::Boolean IsAvailable(const Napi::CallbackInfo& info) {
  return Napi::Boolean::New(info.Env(), load_libmpv());
}

class InitializeWorker : public Napi::AsyncWorker {
 public:
  InitializeWorker(Napi::Function& callback, int64_t owner_wnd)
      : Napi::AsyncWorker(callback), owner_wnd_(owner_wnd) {}

  void Execute() override {
    stop_mpv_thread();
    g_initialized = false;
    g_thread_running.store(true);
    g_mpv_thread = new std::thread(mpv_thread_fn, owner_wnd_);

    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while (std::chrono::steady_clock::now() < deadline) {
      if (g_initialized) break;
      if (!g_thread_running.load()) break;
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }

    if (!g_initialized) {
      stop_mpv_thread();
      SetError("mpv_initialize() failed or timed out. Check stderr for VO error details.");
    }
  }

  void OnOK() override {
    Callback().Call({Env().Null(), Napi::Boolean::New(Env(), g_initialized)});
  }

 private:
  int64_t owner_wnd_;
};

void Initialize(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!load_libmpv()) {
    Napi::Error::New(env,
      "Failed to load libmpv-2.dll — ensure vendor/mpv/win-x64/libmpv-2.dll exists")
      .ThrowAsJavaScriptException();
    return;
  }

  int64_t wid = 0;
  if (info.Length() < 1 || !ReadHwndArg(info[0], &wid)) {
    Napi::TypeError::New(env, "initialize(hwnd, callback): HWND required")
      .ThrowAsJavaScriptException();
    return;
  }

  // Re-owner the overlay window without full reinit if already running
  if (g_thread_running.load() && g_initialized) {
    g_owner_wnd = (HWND)(intptr_t)wid;
    // SetWindowLongPtr to re-owner the overlay
    if (g_overlay_wnd && IsWindow(g_overlay_wnd)) {
      SetWindowLongPtr(g_overlay_wnd, GWLP_HWNDPARENT, (LONG_PTR)g_owner_wnd);
    }
    if (info.Length() >= 2 && info[1].IsFunction()) {
      info[1].As<Napi::Function>().Call({env.Null(), Napi::Boolean::New(env, true)});
    }
    return;
  }

  if (info.Length() < 2 || !info[1].IsFunction()) {
    Napi::TypeError::New(env, "initialize(hwnd, callback): callback required")
      .ThrowAsJavaScriptException();
    return;
  }

  Napi::Function cb = info[1].As<Napi::Function>();
  auto* worker = new InitializeWorker(cb, wid);
  worker->Queue();
}

Napi::Boolean IsInitialized(const Napi::CallbackInfo& info) {
  return Napi::Boolean::New(info.Env(), g_initialized && g_thread_running.load());
}

Napi::Boolean SetWindowId(const Napi::CallbackInfo& info) {
  // No-op for the overlay approach — wid is set at init time
  return Napi::Boolean::New(info.Env(), true);
}

/**
 * SetWindowBounds(screenX, screenY, width, height)
 *
 * Positions and resizes the WS_POPUP overlay window on screen.
 *
 * Since the overlay is a WS_POPUP (top-level), SetWindowPos uses SCREEN
 * coordinates directly — no ScreenToClient conversion needed.
 *
 * width=0 or height=0 → hide the overlay (move off-screen).
 */
Napi::Boolean SetWindowBounds(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (info.Length() < 4) {
    Napi::TypeError::New(env, "Expected x, y, w, h").ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }
  int x = info[0].As<Napi::Number>().Int32Value();
  int y = info[1].As<Napi::Number>().Int32Value();
  int w = info[2].As<Napi::Number>().Int32Value();
  int h = info[3].As<Napi::Number>().Int32Value();

  if (!g_overlay_wnd || !IsWindow(g_overlay_wnd)) {
    if (g_trace_bounds) {
      fprintf(stderr, "[MPV addon] setWindowBounds skipped: no overlay window\n");
      fflush(stderr);
    }
    return Napi::Boolean::New(env, false);
  }

  if (w <= 0 || h <= 0) {
    // Hide: move off-screen, keep GL context alive
    SetWindowPos(g_overlay_wnd, nullptr, -32000, -32000, 16, 16,
                 SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOREDRAW);
    ShowWindow(g_overlay_wnd, SW_HIDE);
    if (g_trace_bounds) {
      fprintf(stderr, "[MPV addon] setWindowBounds: hide (w=%d h=%d)\n", w, h);
      fflush(stderr);
    }
    return Napi::Boolean::New(env, true);
  }

  POINT pt = { x, y };
  if (g_owner_wnd) ScreenToClient(g_owner_wnd, &pt);

  if (g_trace_bounds) {
    RECT owner = {0};
    if (g_owner_wnd) GetWindowRect(g_owner_wnd, &owner);
    fprintf(stderr, "[MPV addon] setWindowBounds screenX=%d screenY=%d clientX=%ld clientY=%ld w=%d h=%d\n",
            x, y, pt.x, pt.y, w, h);
    fflush(stderr);
  }

  if (!IsWindowVisible(g_overlay_wnd)) {
    ShowWindow(g_overlay_wnd, SW_SHOWNA);
  }
  // HWND_BOTTOM ensures the video sits behind Chromium's RenderWidgetHostHWND
  SetWindowPos(g_overlay_wnd, HWND_BOTTOM, pt.x, pt.y, w, h,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);

  if (g_trace_bounds) {
    RECT after = {0};
    GetWindowRect(g_overlay_wnd, &after);
    fprintf(stderr, "[MPV addon] setWindowBounds after=(%ld,%ld %ldx%ld) vis=%d\n",
            (long)after.left, (long)after.top,
            (long)(after.right - after.left), (long)(after.bottom - after.top),
            IsWindowVisible(g_overlay_wnd));
    fflush(stderr);
  }

  return Napi::Boolean::New(env, true);
}

Napi::Boolean Open(const Napi::CallbackInfo& info) {
  Napi::Env env = info.Env();
  if (!g_initialized) {
    Napi::Error::New(env, "mpv not initialized — call initialize(hwnd) first")
      .ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }
  if (info.Length() < 1 || !info[0].IsString()) {
    Napi::TypeError::New(env, "Expected url string").ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }
  std::string url = info[0].As<Napi::String>().Utf8Value();

  std::string authHeader;
  if (info.Length() >= 2 && info[1].IsString()) {
    std::string token = info[1].As<Napi::String>().Utf8Value();
    if (!token.empty()) {
      authHeader = "Authorization: Bearer " + token;
    }
  }
  const bool useAuthHeader = std::getenv("ANIMIND_MPV_USE_AUTH_HEADER") != nullptr;

  fprintf(stderr, "[MPV addon] open(%s) auth=%s\n",
          url.c_str(), authHeader.empty() ? "none" : "yes");
  fflush(stderr);

  std::string err;
  bool ok = post_to_mpv_thread([url, authHeader, useAuthHeader]{
    if (useAuthHeader && !authHeader.empty() && mpv_set_property_ptr) {
      const char* header = authHeader.c_str();
      mpv_set_property_ptr(g_mpv, "http-header-fields", MPV_FORMAT_STRING, (void*)header);
    }
    fprintf(stderr, "[MPV addon] running loadfile...\n"); fflush(stderr);
    const char* cmd[] = { "loadfile", url.c_str(), nullptr };
    int r = mpv_command_ptr(g_mpv, cmd);
    fprintf(stderr, "[MPV addon] loadfile => %d\n", r); fflush(stderr);
    if (r < 0) throw std::runtime_error(
      std::string("loadfile failed: ") + get_mpv_err(r) + " (" + std::to_string(r) + ")");
  }, &err, 30000);

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
  if (!info[0].IsNumber()) {
    Napi::TypeError::New(env, "Expected volume").ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }
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
  if (!info[0].IsBoolean()) {
    Napi::TypeError::New(env, "Expected boolean").ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }
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
  if (!info[0].IsNumber()) {
    Napi::TypeError::New(env, "Expected track id").ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }
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
  if (info.Length() < 1) {
    Napi::TypeError::New(env, "Expected id or 'no'").ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }
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
  if (!info[0].IsString()) {
    Napi::TypeError::New(env, "Expected file path").ThrowAsJavaScriptException();
    return Napi::Boolean::New(env, false);
  }
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
      if (is_num) { while (vend < obj.size() && isdigit(obj[vend])) vend++; }
      else { vend = obj.find('\"', vstart); }
      if (vend == std::string::npos || vend <= vstart) return "";
      return obj.substr(vstart, vend - vstart);
    };

    std::string id_str = extract("id", true);
    if (id_str.empty()) continue;

    int64_t id = std::stoll(id_str);
    std::string type  = extract("type");
    std::string title = extract("title");
    std::string lang  = extract("lang");
    std::string codec = extract("codec");
    bool selected = (type == "audio" && id == current_aid) || (type == "sub" && id == current_sid);

    Napi::Object track = Napi::Object::New(env);
    track.Set("id",       Napi::Number::New(env, (double)id));
    track.Set("type",     Napi::String::New(env, type));
    track.Set("title",    Napi::String::New(env, title.empty() ? type : title));
    track.Set("lang",     Napi::String::New(env, lang));
    track.Set("codec",    Napi::String::New(env, codec));
    track.Set("selected", Napi::Boolean::New(env, selected));
    result.Set(arrayIdx++, track);
  }
  return result;
}

void Destroy(const Napi::CallbackInfo&) {
  stop_mpv_thread();
}

Napi::Value GetHeartbeat(const Napi::CallbackInfo& info) {
  return Napi::BigInt::New(info.Env(), (uint64_t)g_heartbeat.load());
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
  exports.Set("isAvailable",      Napi::Function::New(env, IsAvailable));
  exports.Set("isInitialized",    Napi::Function::New(env, IsInitialized));
  exports.Set("initialize",       Napi::Function::New(env, Initialize));
  exports.Set("setWindowId",      Napi::Function::New(env, SetWindowId));
  exports.Set("setWindowBounds",  Napi::Function::New(env, SetWindowBounds));
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
