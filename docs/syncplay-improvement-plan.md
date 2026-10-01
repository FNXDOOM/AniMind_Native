# SyncPlay — production-grade synchronisation: research and implementation plan

Version 2. Status: proposal only, no implementation code.
Scope: the Animind desktop player's watch party (`qt_host/`) against the existing Go backend.
The backend stays authoritative; every phase says whether it needs a backend change at all.

What changed from v1: v1 was built on two open-source clients. v2 is built on the **server-side
schedulers** used in production — Jellyfin's group state machine, Syncplay's room protocol,
Socket.IO's own connection semantics — plus three adjacent engineering fields that solved this
problem decades ago (NTP, multi-room audio, and real-time game netcode). Every number below is
quoted from a source in §12, not invented.

---

## 1. The problem, stated precisely

A watch party is not "everyone at the same position". It is three separate problems, and
systems that feel bad have solved only the first:

| # | Problem | Naive answer | What production does |
|---|---|---|---|
| P1 | **Where is the group?** One authoritative position | Server position | Server position, versioned, with an identity per broadcast so late/duplicate messages cannot win |
| P2 | **Where am I relative to the group?** Compare wall clocks | `serverTime − clientNow` | Either a robust clock estimate **or** no clock comparison at all — project from a local monotonic anchor |
| P3 | **How do we all start at the same instant?** Broadcast "play now" | Everyone starts on receipt | **Schedule the start in the future**, at `now + worst-case delivery latency`, so the slowest peer still receives the order before the start instant |

P3 is the one nobody talks about and the one that most determines perceived quality. A
"play" command that reaches one peer 400 ms after another does not make them 400 ms out of
sync — it makes them 400 ms out of sync *forever*, until something corrects it. Jellyfin's
playing state computes the start delay explicitly (see §4.1); game netcode has done the same
thing for 25 years by rendering the past.

**The bar.** The Jellyfin SyncPlay 2.0 discussion sets the target numerically: keep the delay
"low sub-hundred milliseconds" because people hold a voice call alongside the party, and above
that the conversation falls apart. That is the right target for Animind too — anime is watched
with commentary.

---

## 2. Systems studied, and what each contributes

| System | Kind | What to take from it |
|---|---|---|
| **Jellyfin SyncPlay** (server + web client) | Production, server-authoritative, same domain as ours | Group **state machine**, **scheduled future start**, per-member ping folded into scheduling, wait deadline, `IgnoreWait` escape hatch, `AllReady` broadcast, queue/repeat/shuffle as first-class |
| **Syncplay** (python, mpv/VLC/MPC) | Production, longest-lived OSS implementation | Tuned correction **thresholds with hysteresis**, asymmetric behind/ahead handling, **who is allowed to be corrected**, capability negotiation, OSD feedback, one shared reset path for reconnects, explicit near-EOF playlist rules |
| **Bili-SyncPlay** (TS extension + room server) | Modern, heavily engineered | Robust **offset estimator** (competitive-RTT window, median, deadband, age-out), **monotonic anchor extrapolation**, pure **apply-decision table**, local-intent guard, **remote-pause debounce**, backoff with a rate budget, a `bench/` harness |
| **Socket.IO** | The protocol we speak | `pingInterval`/`pingTimeout` trade-off, **connection state recovery**, **broadcast-with-ack-and-timeout**, rooms keyed by user id |
| **Mux / HLS** | Live streaming | Media timeline carrying **server wall-clock** (PDT) so alignment needs no client loop |
| **Game netcode** (Gambetta) | Real-time authoritative servers | Interpolation with a **render delay**, snapshot ordering, why you never trust a raw remote timestamp |
| **Multi-room audio** (AirPlay 2 / Sonos / PTP / PTS) | Sub-millisecond audio alignment | Continuous rate steering, presentation timestamps, and the fact that *audio* must be tighter than video can be |
| **NTP literature** | Clock synchronisation | Why one-way delay asymmetry, not jitter, is the real enemy; min-delay vs median filtering |

---

## 3. What Animind does today (verified from source)

Policy layer `qt_host/qml/components/WatchParty.qml`, transport `qt_host/src/syncplay_client.cpp`,
hub `internal/syncplay/`.

| Behaviour | Current value |
|---|---|
| Heartbeat while playing | 3000 ms |
| Buffering report debounce | 600 ms |
| Buffer progress inside a gate | 1000 ms |
| Seek emit cooldown | 200 ms |
| Suppress local stall reports after a remote apply | 1500 ms |
| Apply a remote position only if \|Δ\| > | 1500 ms |
| Ignore a `softCorrect` below | 100 ms |
| Escalate `softCorrect` to a seek above | 2500 ms |
| Buffer goal | 120 s, fixed |
| Timesync | 4 samples at 500 ms, median of last 3 |
| Scheduled start | **none** — `syncPlay` means "start now" |
| Per-member latency | measured only as a raw socket RTT, never used |
| Broadcast ordering | **none** — no sequence number, last message wins |

Known defects, all confirmed this session:
1. Offset is `serverTime − clientNow`: **no round-trip compensation at all**, so the estimate
   carries roughly half the one-way delay as bias.
2. The sample window never ages out — after a suspend/resume the client trusts a stepped clock.
3. The hub never emits `allReady` or `peerBuffering`, which the deployed web client listens for.
4. Every join re-gates the whole room, with no attribution ("waiting on…") and no user escape.
5. `keep-open=yes` means mpv emits no `END_FILE` at eof and `eof-reason` reads empty; the
   advance had to be driven from position/pause instead.

---

## 4. Deep dive: how production actually does it

### 4.1 Jellyfin — the server-side scheduler

Jellyfin models the group as an explicit state machine: `IdleGroupState`, `PausedGroupState`,
`PlayingGroupState`, **`WaitingGroupState`**. Requests are typed (`Play`, `Pause`, `Seek`,
`Buffer`, `Ready`, `Ping`, `IgnoreWait`, `SetPlaylistItem`, `MovePlaylistItem`, `Queue`,
`NextItem`, `PreviousItem`, `SetRepeatMode`, `SetShuffleMode`) and each state answers them
differently. That is the single structural thing Animind lacks: our hub handles the same
messages, but the *room* has no named state, so "what may happen now" is implicit in branches.

Constants from `Emby.Server.Implementations/SyncPlay/Group.cs`:

| Constant | Value | Meaning |
|---|---|---|
| `DefaultGroupWaitTimeout` | 30 000 ms | the gate has a hard deadline; it cannot hang forever |
| `DefaultPing` | 500 ms | assumed latency for a member that has not reported one |
| `MaxPing` | 10 000 ms | reported pings are clamped (`Math.Clamp(ping, 0, MaxPing)`) |
| `TimeSyncOffset` | 2000 ms | how far a member's clock may disagree before it is not trusted |
| `MaxPlaybackOffset` | 500 ms | **out-of-sync is 500 ms, not our 1500 ms** |
| `MaxCatchUpOffset` | (used in `WaitingGroupState`) | beyond this a member is *held in buffering* rather than nudged |

The scheduling idea, from `PlayingGroupState.cs`:

> `delayMillis = Math.Max(context.GetHighestPing() * 2, context.DefaultPing)`

The group does **not** start on receipt. It starts at `now + max(2 × worst ping, 500 ms)`, so
the order is delivered before the start instant even for the slowest member. Pings are
"reported by clients and scaled into the delays used to schedule playback" (their own doc
comment). Note `× 2`: one round trip, because the ping is measured as a round trip and only
half of it delays delivery — doubled for safety margin.

Gate mechanics from `WaitingGroupState.cs`:
- Every state transition that needs agreement calls `SetAllBuffering(true)` — the room re-gates
  as a *transition*, not as a special case.
- A member becomes non-buffering only on its `Ready` request, and the group starts only when
  `!IsBuffering()`.
- `IgnoreGroupWait` is a **per-member** flag excluded from `IsBuffering()` — the escape hatch
  for the one person on a train.
- On timeout, `HandleGroupWaitTimeout` force-starts and clears all buffering, so a stuck
  member cannot hold the room indefinitely.
- `SyncPlayBroadcastType.AllReady` exists as a distinct broadcast — the event our hub never
  sends and our web client waits for.

And a cautionary list from the SyncPlay 2.0 discussion: endpoints that fail to return the
group id, no websocket notification when a group is created, missing session tokens,
immutable room names, control routing split across endpoints. Those are the failure modes that
make a sync system feel flaky even when the maths is right.

### 4.2 Jellyfin web — the client-side clock

`src/plugins/syncPlay/core/timeSync/`:

| Setting | Value |
|---|---|
| `NumberOfTrackedMeasurements` | 8 |
| `PollingIntervalGreedy` | 1000 ms |
| `PollingIntervalLowProfile` | 60 000 ms |
| `GreedyPingCount` | 3 |
| Selection rule | **"Pick measurement with minimum delay"** |

Two things worth copying verbatim:
- **Two-speed polling.** Sample fast (1 s) for the first few pings after joining, then drop to
  once a minute. Battery and data matter on a laptop; a steady clock does not need 1 Hz.
- **A user-visible escape hatch: `extraTimeOffset`** (a manual, persisted nudge) and
  `timeSyncDevice` (which device is the reference). Power users trust a system they can bias.

### 4.3 Syncplay — the correction controller

`syncplay/constants.py`:

| Purpose | Value |
|---|---|
| Slow-down rate | `0.95×` |
| Slow-down engages behind by | `1.5 s` (server minimum `1.3 s`) |
| Slow-down releases within | `0.1 s` |
| Fast-forward engages ahead by | `5 s` (minimum `4 s`) |
| Fast-forward extra time | `0.25 s` |
| Fast-forward reset / behind thresholds | `3.0 s` / `1.75 s` |
| Protocol timeout | `12.5 s` |
| Show slowdown/speedup on the OSD | yes |
| Auto-advance: near-EOF window / min file length / time-from-end | `270 s` / `10 s` / `5 s` |

From `syncplay/client.py`, the behaviour rules that make corrections feel fair:
- A `_speedChanged` latch: engage at 1.5 s, release at 0.1 s. **Hysteresis, not a threshold.**
- The correction is **attributed**: the OSD names the user whose action caused it
  (`slowdown-notification`.format(`setBy`)).
- Fast-forward only applies when the local user is **not** the controller, or the user has set
  `dontSlowDownWithMe`. The person driving is never fought by their own client.
- `checkIfConnected` and a single **shared state-reset method used by both automatic and manual
  retries** — one reconnect path, not two.
- `featureList` negotiation: the client learns the server's thresholds at connect, so a room
  can be re-tuned without shipping a build.

### 4.4 Bili-SyncPlay — the estimator and the apply pipeline

`extension/src/background/clock-sync.ts`:

| Constant | Value | Rationale (their words, condensed) |
|---|---|---|
| `CLOCK_SYNC_INTERVAL_MS` | 15 000 | steady re-estimation, not a connect burst |
| `CLOCK_SAMPLE_WINDOW_SIZE` | 8 (~2 min) | enough samples for a majority |
| `CLOCK_SAMPLE_MAX_AGE_MS` | 150 000 | **suspend/resume recovery**: old samples age out and the estimate reseeds |
| `CLOCK_SAMPLE_RTT_TOLERANCE_MS` | 20 | only samples within 20 ms of the *fastest* RTT compete — a slow round trip is asymmetric far more often and skews the offset by up to half the excess |
| `CLOCK_SAMPLE_MIN_TRUSTED_SIZE` | 3 | below this the deadband is not trusted, or a wild first sample gets *held* by the filter meant to protect it |
| `CLOCK_OFFSET_DEADBAND_MS` | 120 | the published offset moves only when the estimate moves more than this |

The architectural decision:

> "The offset is a diagnostic here, not an input to playback: positions are extrapolated from a
> local monotonic anchor instead, precisely because no filter can make a two-clock comparison
> trustworthy."

Plus: snapshot identity `actorId | seq | serverTime | playState | url | currentTime | rate`,
with `serverTime` compared **only for equality**, never subtracted from a local timestamp;
monotonic time from a source that cannot be stepped by the OS clock.

`content/playback-apply.ts` reduces every incoming room state to one named outcome —
`empty-room`, `no-current-video`, `ignore-non-shared`, `ignore-local-guard`,
`ignore-stale-playback`, `ignore-self-playback-version`, `apply` — with ordering enforced by
`(serverTime, seq)` and guards `localIntentGuardMs`, `pauseHoldMs`, `userGestureGraceMs` and
`remotePauseDebounceMs` (delaying a remote `paused` to absorb a peer's buffer-stall flicker).

Their retry discipline is worth quoting as a standard: exponential backoff capped at 10 s,
sized against an explicit rate budget — "a stuck tab wakes 6 times/min; the limiter allows
36/min … the pre-fix spin sent ~171/min from a single tab."

### 4.5 Socket.IO — what the transport already gives you (and what we threw away)

- `pingTimeout` is a documented trade-off: shorter detects dead links faster but causes more
  reconnections; the disconnect reason is surfaced as `"ping timeout"`. We should log and
  display it rather than treat all disconnects alike.
- **Connection state recovery**: a client that reconnects can have buffered packets replayed,
  and reports `socket.recovered`. Our hub already has a `pendingPeers`/`takePendingPeer`
  resume path, so this is a short step, not a redesign.
- **Broadcast with acknowledgements and a timeout** (`to(room).timeout(ms).emit(...)`): the
  clean way to poll "are you ready?" and know who did not answer — better than inferring it
  from silence.
- Rooms keyed by **user id** with `fetchSockets()` to detect the last connection for a user —
  matches the hub's `uniqueParticipants` dedupe and should drive "left" vs "dropped".

### 4.6 Two clock-estimator philosophies, and which to pick

Jellyfin-web uses NTP's classic **minimum-delay filter** (pick the sample with the smallest
RTT). Bili uses **median of competitive-RTT samples**. They disagree, and the disagreement is
the whole point:

- Min-delay assumes noise is one-sided (extra delay only ever gets added). On asymmetric
  links — cable upstream, congested 4G, any bufferbloat — the *fastest* sample can also be the
  most skewed, and min-delay happily locks onto it.
- Median-of-competitive assumes the window contains several good samples and that a majority
  agrees. It is robust to spikes but needs a minimum sample count before it can be trusted,
  and it must be allowed to age out or a clock step poisons it.

Recommendation for Animind: **Bili's rule with Jellyfin's cadence** — competitive-RTT median
over an 8-sample window with 150 s age-out and a 120 ms deadband, sampled greedily for the
first ~3 s after joining and then every 60 s while idle and 15 s while playing. Then keep
Jellyfin-web's `extraTimeOffset` as a user setting, because every estimator eventually meets a
link it cannot model.

### 4.7 What the neighbouring fields insist on

- **Game netcode**: never apply a remote snapshot immediately — render at `now − interpolation
  delay` so late packets still arrive in time to be useful. The watch-party equivalent is the
  scheduled start of §4.1, and it is why "play now" is structurally wrong.
- **Multi-room audio**: alignment is achieved by continuous, sub-perceptual rate steering
  against a shared presentation timeline, not by re-positioning. Audible artefacts appear well
  above 5 % rate error; 2–5 % is invisible for video, and this is exactly Syncplay's `0.95×`.
- **NTP**: the enemy is asymmetric one-way delay, not jitter per se; interleaved/filtered
  sampling and clock-step detection are mandatory, which is why age-out exists.
- **HLS/DASH**: put server wall-clock *into the media timeline* (PDT) so clients align by
  timestamp rather than by negotiating a position over a control channel.

---

## 5. Gap analysis

| Capability | Jellyfin | Syncplay | Bili | Animind |
|---|---|---|---|---|
| Named group state machine | yes | partial | yes | **no** |
| Scheduled future start (`now + f(ping)`) | yes | no | effectively (anchor) | **no** |
| Per-member ping used by the scheduler | yes | no | yes | **no** |
| RTT-compensated offset | yes (min-delay) | partial | yes (competitive median) | **no** |
| Sample age-out / clock-step recovery | yes | no | yes | **no** |
| Deadband on the estimate | implicit | yes (release threshold) | yes | **no** |
| Out-of-sync threshold | 500 ms | 1500 ms behind / 5000 ms ahead | per-decision | 1500 ms both ways |
| Rate-based catch-up with hysteresis | partial | yes | yes | server-initiated only |
| "Don't correct the driver" rule | permission model | yes | yes | **no** |
| Broadcast ordering (`serverTime`, `seq`) | partial | no | yes | **no** |
| Local-intent guard | no | implicit | yes | only after *remote* apply |
| Remote-pause debounce | no | no | yes | **no** |
| Gate deadline | 30 s | yes | yes | yes (ready timers) |
| Per-member wait opt-out | `IgnoreWait` | `dontSlowDownWithMe` | no | **no** |
| `AllReady` broadcast | yes | yes | yes | **never emitted** |
| Capability negotiation | no | `featureList` | no | **no** |
| Correction shown to the user | partial | OSD | toast | **no** |
| Manual user offset | `extraTimeOffset` | no | no | **no** |
| Reconnect state recovery | n/a | shared reset | backoff + budget | partial (`pendingPeers`) |
| Automated two-client proof | e2e in web | manual | `bench/` | manual probe runs |

---

## 6. Target architecture (design, not code)

Four layers, each independently testable:

1. **Transport** (unchanged): Engine.IO/Socket.IO over TLS, plus the hub's existing resume
   buffer. Adds: a monotonic per-room `seq` on every broadcast, and `pingTimeout` reason
   surfaced upward.
2. **Time layer**: the estimator of §4.6, exposing (a) `offsetMs` with a confidence and an
   RTT, (b) `projectedGroupPosition(snapshot)` computed from a **monotonic arrival anchor**,
   never from subtracting two wall clocks.
3. **Decision layer**: one pure function, `roomState → outcome`, with named outcomes exactly as
   in §4.4, plus the guards (local intent, self-echo, stale version, wrong episode, defer
   pause). No player calls, no socket calls — which is what makes it unit-testable.
4. **Actuation layer**: the only place that touches mpv. Implements the correction controller:
   scheduled start, rate nudge with hysteresis, seek escalation, and the "do not correct the
   driver" rule. Every action emits an OSD/toast line naming the peer that caused it.

Control flow for a group start (the P3 fix):

```
host presses play
  → client sends Play{position, myPing}
  → hub computes startAt = serverNow + max(2 × highest member ping, 500 ms)
  → hub broadcasts Play{position, startAt, seq} to all members
  → each member: if behind startAt, arm a monotonic timer; else correct immediately
  → at startAt every member unpauses within the same frame budget
  → members that were buffering during the wait are held by the gate, not dragged
```

---

## 7. Implementation plan

Phases are independently shippable; 0–3 are what make sync *feel* right.

### Phase 0 — Instrument first (client only)
Record on every heartbeat and every apply: `position − canonicalTime`, RTT, buffering flag,
decision outcome, action taken. Dump via the existing `--sync-selftest` / panel probe and show
a drift readout in a debug overlay.
**Exit:** a drift histogram and a corrections-per-minute number exist, so every later phase has
a before/after measurement rather than an opinion.

### Phase 1 — Scheduled future start (client + 1 backend field) — *highest impact*
Implement §6's control flow. The hub adds `startAt` to play/unpause/seek broadcasts, computed
from the highest reported member ping (clamped, with a floor like Jellyfin's 500 ms). Clients
arm a monotonic timer instead of acting on receipt.
**Exit:** with one peer artificially delayed 400 ms, both peers start within 100 ms of each
other without any corrective seek. This is the test that proves the architecture, not the
tuning.

### Phase 2 — Trustworthy time (client + 1 backend field)
Estimator per §4.6: four timestamps, competitive-RTT window of 8, median, 120 ms deadband,
150 s age-out, clear on reconnect and system resume; greedy-then-idle cadence (1 s ×3, then
15 s playing / 60 s paused). Add `extraTimeOffset` as a user setting in the party panel.
**Exit:** on a simulated 300 ms asymmetric link the estimate stays inside ±50 ms; after a
simulated clock step the estimate reseeds within one window.

### Phase 3 — Ordering and a decidable apply layer (client, plus `seq` in §8.2)
Pure decision function with the named outcomes of §4.4; drop stale/duplicate broadcasts by
`(serverTime, seq)`; add `localIntentGuard` (~800 ms after my own action, on top of the
existing 1500 ms remote-apply suppression), self-echo suppression, and a ~1 s remote-pause
debounce.
**Exit:** property tests over the decision function; a duplicate and an out-of-order broadcast
are provably dropped; a peer's stall no longer flickers "paused" at the room.

### Phase 4 — Correction that a human cannot see (client)
Adopt Syncplay's shape, re-tuned against Phase 0:
behind → nudge to `0.95×` from 1.5 s, release within 0.1 s; ahead → nudge `1.05×` from 1.5 s,
seek only from 5 s; anything beyond `MaxCatchUpOffset` (Jellyfin uses the buffering route) →
hold in the gate rather than nudge. Never correct while scrubbing, mid-seek, inside the
local-intent guard, or when the local user is the controller.
Tighten the out-of-sync definition toward Jellyfin's 500 ms once Phases 1–3 hold.
**Exit:** injected 2 s and 6 s errors resolve with zero visible seeks for the small case and
exactly one for the large; corrections/min under budget; the OSD names the cause.

### Phase 5 — The gate as a first-class state (client + backend policy)
Make the room's states explicit server-side (idle / playing / paused / waiting) rather than
inferred; emit `allReady` and `peerBuffering` (already expected by the web client — see §8.3);
per-member `IgnoreWait`; a visible "waiting on Ada (buffering, 42 %)" line; a hard deadline
(Jellyfin: 30 s) that force-starts and clears; and a buffer goal expressed as a fraction of
remaining duration rather than a fixed 120 s.
**Exit:** a member on a throttled link can opt out and the rest start immediately; the panel
names who is holding the room.

### Phase 6 — Resilience
One shared reset path for automatic and manual reconnects (Syncplay's design); use the hub's
resume buffer so a 2 s blip replays missed broadcasts instead of re-joining blind; treat
`ping timeout` distinctly from a clean close and say so in the UI; on `hostChanged`, freeze
correction until the new host's first heartbeat; adopt a protocol timeout (Syncplay: 12.5 s);
make `episodeChanged` carry the *server time* to resume at, and keep the rule that a non-host
never auto-advances.
**Exit:** kill the socket mid-episode; the peer rejoins, replays, and is in sync in under 5 s
with no user action.

### Phase 7 — Product surface that makes it feel finished
Activity feed (joined / sought / paused / became host / waiting-on-X); invite link with the
code pre-filled (clipboard copy already exists); per-peer latency and drift shown dimly in the
roster; follow-host subtitle and audio track choice — the backend already exposes per-episode
`thumbnail` and track metadata, and anime viewers care about sub group more than any other
platform's users do; reactions that never touch the timeline; a host queue with explicit
near-EOF rules instead of "position stopped moving".

### Phase 8 — Keep it
Promote the probe into a two-peer CI harness asserting jelly-party-style invariants (both
connected → N listed → play from one → positions agree within a bound → seek → lands within a
bound → stall one → the room reports it). Add a network-impairment profile knob (RTT, jitter,
asymmetric up/down, loss). Property-test the estimator and the decision function in the
existing `tests/property` suite. Fail CI if p95 drift exceeds the agreed number.

---

## 8. Backend deltas (additive; no rewrite)

1. **`timesync_pong` gains `serverReceiveTime`.** Today it carries only `clientSendTime` and
   `serverTime`, so offset and RTT cannot be separated and Phase 2 is capped at "median of a
   biased number". One field; the highest-leverage change in this document.
2. **Monotonic per-room `seq` on every broadcast**, alongside the existing `sentAt`.
3. **Emit `allReady` and `peerBuffering`.** The web client already listens for them; the hub
   never sends them (`allReady` is literally a Jellyfin broadcast type, which is where the
   site's expectation came from).
4. **`startAt` on play/unpause/seek** (Phase 1), computed server-side from the highest clamped
   member ping, so every client sees the same instant without agreeing on clocks.
5. **A `featureList`-style config in the join ack**: slowdown rate and thresholds,
   fast-forward threshold, `MaxPlaybackOffset`, `MaxCatchUpOffset`, wait deadline, buffer-goal
   policy, protocol timeout. Tuning then needs no client release.
6. **`IgnoreWait` per member** and a group-wait deadline the server enforces.
7. **A hub test that runs through the real middleware.** The existing hub test skips it, which
   is how the missing `Hijack` — a 500 on every websocket upgrade — reached a live client.

---

## 9. Metrics and instrumentation

| Metric | Definition | Target |
|---|---|---|
| p95 drift, LAN, 2 peers | \|position − projected group position\| | < 250 ms |
| p95 drift, 150 ms / 30 ms jitter | same | < 500 ms |
| **Start skew** | spread of actual unpause instants after a group play | < 100 ms (the voice-call bar) |
| Corrections per minute, steady state | rate nudges + seeks | ≤ 1 nudge, 0 seeks |
| Visible seeks per hour | corrective seeks only | < 2 |
| Join → in-sync | accepted to playing | < 3 s healthy, < 30 s worst (deadline) |
| Reconnect → in-sync, no user action | socket drop to corrected | < 5 s |
| False stall reports | `peerStalling` for a peer that was fine | 0 |
| Correction attribution | share of corrections naming a cause | 100 % |

Phase 0 exists so this table stops being aspirational the day Phase 1 lands.

---

## 10. Non-goals

- No P2P/WebRTC mesh and no move away from server-authoritative state: every implementation
  with credible sync quality at this scale is server-authoritative.
- No transcoding or per-client adaptive streaming to fix sync at the media layer.
- No per-user subtitle offset inside the party logic — that belongs to the player's existing
  subtitle-delay control.
- No threshold tuning before Phase 0 produces numbers, and no tuning *below* the values quoted
  in §4 without a measurement to justify it.
- No claim of sub-100 ms audio-grade alignment for video; that is multi-room audio's problem
  and it needs continuous rate steering plus a shared presentation clock.

---

## 11. Suggested order of work

If only three things get done: **Phase 1 (scheduled start)**, **Phase 2 (real clock
estimate)**, **Phase 3 (ordering + decidable apply)**. They are the difference between "peers
converge eventually" and "peers start together and stay together", and none of them requires
replacing anything that exists today.

---

## 12. Sources

Primary source code read this pass
- Jellyfin server: `Emby.Server.Implementations/SyncPlay/Group.cs`,
  `MediaBrowser.Controller/SyncPlay/GroupStates/{Abstract,Idle,Paused,Playing,Waiting}GroupState.cs`,
  `MediaBrowser.Model/SyncPlay/SyncPlayBroadcastType.cs`, `SyncPlay/Queue/PlayQueueManager.cs`
- Jellyfin web client: `src/plugins/syncPlay/core/timeSync/{TimeSync,TimeSyncCore,TimeSyncServer}.js`,
  `core/{PlaybackCore,Controller,Settings}.js`
- Syncplay: `syncplay/constants.py`, `syncplay/client.py`, `syncplay/players/mpv.py`,
  `syncplay/server.py`, `syncplay/protocols.py`
- Bili-SyncPlay: `extension/src/background/{clock-sync,clock-controller,room-manager,room-state}.ts`,
  `extension/src/content/{playback-apply,room-state-apply-controller,sync-controller}.ts`, `bench/`
- Jelly-Party: `e2e/mixed-party-sync.spec.ts`

Web
- [Syncplay — what it does](https://syncplay.pl/about/syncplay/) ·
  [Syncplay development](https://syncplay.pl/about/development/) ·
  [Using the client](https://syncplay.pl/guide/client/)
- [Socket.IO — server options (`pingTimeout`)](https://socket.io/docs/v4/server-options) ·
  [Connection state recovery](https://socket.io/docs/v4/connection-state-recovery) ·
  [Broadcasting events (ack + timeout)](https://socket.io/docs/v4/broadcasting-events)
- [Jellyfin SyncPlay 2.0 discussion (jellyfin-meta #75)](https://github.com/jellyfin/jellyfin-meta/discussions/75)
- [Mux — synchronize video playback](https://www.mux.com/docs/examples/synchronize-video-playback)
- [Gambetta — client-server game architecture](https://www.gabrielgambetta.com/client-server-game-architecture.html) ·
  [entity interpolation](https://www.gabrielgambetta.com/entity-interpolation.html) ·
  [client-side prediction and reconciliation](https://www.gabrielgambetta.com/client-side-prediction-server-reconciliation.html) ·
  [lag compensation](https://www.gabrielgambetta.com/lag-compensation.html)
- [PTS synchronisation across devices](https://www.ampvortex.com/enable-accurate-audio-playback-across-devices/) ·
  [Sonos: how synchronous is the audio](https://en.community.sonos.com/controllers-and-music-services-228995/how-synchronous-is-the-audio-6864315) ·
  [AirPlay 2 grouping drift reports](https://community.roonlabs.com/t/airplay-grouped-devices-out-of-sync/128801)
- [An enhanced time synchronization method for a network protocol](https://pmc.ncbi.nlm.nih.gov/articles/PMC11390965/) ·
  [Synchronisation of streamed audio between multiple devices](https://lup.lub.lu.se/luur/download?func=downloadFile&recordOId=8052964&fileOId=8053165) ·
  [Adaptive delay and synchronisation control for Wi-Fi AV conferencing](https://www.researchgate.net/publication/220292813_An_adaptive_delay_and_synchronization_control_scheme_for_Wi-Fi_based_audiovideo_conferencing) ·
  [Synchronised VOD playback with MOQ](https://dl.acm.org/doi/10.1145/3789239.3793272) ·
  [How does clock synchronisation work?](https://community.dataminer.services/how-does-clock-synchronization-work/) ·
  [Google Firefly clock synchronisation](https://cloud.google.com/blog/products/networking/understanding-the-firefly-clock-synchronization-protocol)
- Real-world failure reports: [jellyfin#5557](https://github.com/jellyfin/jellyfin/issues/5557),
  [jellyfin-tizen#71](https://github.com/jellyfin/jellyfin-tizen/issues/71),
  [r/jellyfin sync-play stability](https://www.reddit.com/r/jellyfin/comments/1ttzoay/sync_play_stability_issue/),
  [Jellyfin SyncPlay explained](https://www.androidauthority.com/jellyfin-syncplay-explained-3530437/)

Other repos surveyed for comparison: [steeelydan/sync-party](https://github.com/steeelydan/sync-party),
[ahmedsadman/redparty](https://github.com/ahmedsadman/redparty),
[Web-SyncPlay/Web-SyncPlay](https://github.com/Web-SyncPlay/Web-SyncPlay),
[Lakunake/Sync-Player](https://github.com/Lakunake/Sync-Player),
[yuroyami/syncplay-mobile](https://github.com/yuroyami/syncplay-mobile),
[mo3rfan/syncplayer](https://github.com/mo3rfan/syncplayer),
[ably-labs/jamstack-sync-stream-video](https://github.com/ably-labs/jamstack-sync-stream-video),
[halitsever/watchbear](https://github.com/halitsever/watchbear),
[sky1wu/Bili-SyncPlay](https://github.com/sky1wu/Bili-SyncPlay).

Confidence note: every number in §4 was read from the cited file this session. The Jellyfin
docs page and the `jellyfin-plugin-syncplay` repository both 404'd — SyncPlay lives in the
main server tree now — so §4.1 is sourced from the server and web-client source directly, not
from documentation. Disney+ GroupWatch and Spotify Jam turned up no engineering material, only
support pages, so nothing from them is claimed here.

---

## 13. Implementation status (2026-10-01)

This section records what was built against the plan above, what deviated, and what is measured
rather than believed.

### Deviation from §8.4: the field is `scheduledPlayAt`, not `startAt`

The deployed web client already parses `scheduledPlayAt` on `allReady`, `waitForReady` and
`syncPlay` (`services/syncplay.client.ts`, `msUntilServerTime()`), and it already listens for
`allReady`, `peerBuffering` and `timesync_pong.serverReceiveTime`. Emitting those names means the
shipped site gains scheduled starts and the four-timestamp clock without a release; a new name
would have meant a coordinated deploy for the same effect. §8.3's "the web client already listens
for them" turned out to be the strongest argument for matching its spelling.

### Landed — backend (`Animind_Backend_Go`)

| § | What | Where |
| --- | --- | --- |
| 8.1 | `serverReceiveTime` read on the first line of the ping handler | `internal/syncplay/room.go` `handleTimeSync` |
| 8.2 | `seq` + `serverTime` stamped at emit time on every broadcast | `scheduling.go` `stamped`/`stampable`, `Hub.stamp` |
| 8.3 | `allReady` at gate close, `peerBuffering` once per fall below goal | `tryResumeAfterReady`, `handleBufferingProgress`, `handlePeerStall` |
| 8.4 | `scheduledPlayAt` on play / unpause / seek, from the highest clamped member ping | `scheduledStartLocked`, `leadMillis` |
| 8.5 | `syncConfig` + `features` in the create/join acks and in `sync` | `syncConfigPayload`, `Hub.syncConfig` |
| 8.6 | `ignoreWait` per member, and a 30 s wait deadline that force-closes | `handleIgnoreWait`, `waitDeadlineExpired`, `WaitDeadline` |
| 8.7 | Hub tests through the real middleware chain | `internal/httpx/socket_middleware_test.go` |
| §5 | Explicit group state (`idle` / `paused` / `playing` / `waiting`) on the wire | `groupState`, `stateLocked` |
| 5 | Buffer goal scaled to the episode remaining, with a 10 s floor | `scaledGoalSeconds`, `goalSecondsLocked` |
| 4 | Corrections name their source and the measured drift | `softCorrectPayload`, `speedSeekPayload` |
| 6 | `correctionsResumeAt` on host handover; `gateEpoch` so a stale timer cannot cross gates | `hostChangedPayload`, `forceReady` |

Two defects were found by the tests written for this work, not before it:

- The websocket writer discarded whatever was still queued when a peer closed, so a refused
  handshake never delivered its `CONNECT_ERROR` — the client saw an unexplained drop. Fixed by
  draining before close and having the reader wait for the writer (`drainBeforeClose`,
  `attachWebSocket`'s `finished` channel). `TestSocketRefusesABadTokenWithoutKillingTheConnection`
  failed before the fix and passes after.
- `handleSeek` in a group read `len(room.participants)` without the room lock, and `Room.close`
  and `handleHeartbeat` read room state after unlocking. Both now take the lock.

### Landed — desktop client

- **New pure layers**: `qt_host/src/clock_estimator.{h,cpp}` (four timestamps, competitive-RTT
  window of 8, median of the best half, 120 ms deadband, 150 s age-out, greedy-then-idle cadence,
  wall-clock-step detection, `extraTimeOffset`, and `GroupAnchor` for monotonic projection);
  `sync_decision.{h,cpp}` (`decide(Observation, State) → named Outcome`, with the seq guard,
  self-echo, wrong-episode, local-intent, pause-debounce, handover-freeze, never-correct-the-driver
  and never-correct-the-clock rules, and the engage/release hysteresis); `sync_telemetry.{h,cpp}`
  (Phase 0: nearest-rank drift percentiles, corrections per minute, worst start skew).
- **`SyncPlayClient`** now owns the estimator, the ordering guard (`acceptSequence`), the tuning
  block from `syncConfig`, `waitingOn` attribution, the activity feed, and `evaluate()`.
- **`WatchParty.qml`** is actuation only: every broadcast goes through `pump()` → `evaluate()`, and
  the named outcome is carried out on mpv. `ANIMIND_SYNC_LATE_DELIVERY_MS` holds inbound broadcasts
  back from the room logic while the transport keeps answering pongs.
- **`syncCoreTests`**: a Qt Test target (`qt_host/tests/cpp/sync_core_test.cpp`, registered with
  CTest) — 40 cases over the estimator, the decision function and telemetry. The existing jest
  suites were not extended: they *inline* the logic under test, which cannot catch a change to the
  QML it claims to cover.

### Measured, not assumed

Two peers against a live backend, one with its broadcasts held back 400 ms
(`ANIMIND_SELFTEST_IMPAIR_MS=400`), the room started by the other:

```
STARTFIRE label=fast skewMs=1 atServerMs=1790821775912
STARTFIRE label=slow skewMs=0 atServerMs=1790821775912   (clock=trusted, ping=400)
SYNCTELEMETRY … nudgesPerMin=0.00 seeks=0 startSkew=0     (both peers)
```

**Start skew across the two peers: 0 ms** in the hub's own clock domain, against a §9 target of
< 100 ms, with zero corrective seeks. The impaired peer armed for `+100 ms` — the room's 500 ms
lead minus the 400 ms it lost — which is the mechanism working rather than being tuned around.
Its estimator also read the impairment as `ping=400`, which is the four-timestamp measurement
doing its job.

§9's other rows are **not yet measured**: p95 drift over a real episode (the scripted harness
reports a fabricated position, so its drift numbers are meaningless), corrections per minute in
steady state, and reconnect-to-in-sync. The instrumentation for all three exists.

### Tried and reverted

Arming a scheduled start when the clock estimate is still cold (assuming offset 0, clamped to a
2 s blind lead) was implemented and measured against the live room, and made things worse: a peer
whose clock was further off than the room's lead never reached its own start, and the gate
reopened around it. Reverted; the client acts on receipt until the estimate is trusted, and
`anUnmeasuredClockCannotScheduleAStart` pins that behaviour with the reason recorded.

### Not implemented

- §7 Phase 6's socket resume buffer for missed broadcasts: the hub buffers only for a
  polling→websocket upgrade, so a dropped websocket still re-joins blind (it re-reads the room from
  the join ack plus `sync`, which is why reconnect works at all). The 12.5 s protocol timeout was
  applied where it fits this transport — as a deadline on the two acked requests (`createRoom`,
  `joinRoom`), which previously had none and could spin forever — rather than as a link-silence
  window, because the hub's own ping arrives every 25 s and 12.5 s of silence is normal here.
- §7 Phase 7's follow-host subtitle and audio track choice, reactions, and the host queue. The
  activity feed, per-peer latency and drift in the roster, the "waiting on X (buffering, 42 %)"
  line, the ignore-wait control, the displayed buffer goal's fractional policy, the attributed
  correction chip and the `extraTimeOffset` control (§7 Phase 2's last item) are done.
- §7 Phase 8's network-impairment *profiles* (the single delay knob exists; jitter, asymmetric
  up/down and loss do not) and CI gates on p95 drift.
- `changeEpisode` now opens a gate, and the decision layer drops signals for an episode this client
  is not on. A non-host is still never told which file to load, so it stays on the old episode
  until it picks the new one — unchanged behaviour, and the remaining half of the cross-episode
  limitation in §5.
