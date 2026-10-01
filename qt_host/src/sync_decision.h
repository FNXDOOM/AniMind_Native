#pragma once

#include "clock_estimator.h"

#include <QString>
#include <QtGlobal>

// The decision layer: one function from "what the room said and what I am doing" to a named
// outcome. No player calls, no socket writes, no wall-clock reads — the caller passes the
// monotonic instant and actuates the answer.

namespace sync
{

// Tuning the hub publishes in syncConfig, so a threshold can move without shipping a build.
struct Tuning
{
    // Inside this, no viewer can tell, so nothing is done.
    qint64 maxPlaybackOffsetMs = 500;
    // Distance, not duration: how far the playhead must drift before a rate nudge starts.
    qint64 engageDriftMs = 1500;
    // Where the nudge lets go; the gap to engageDriftMs is the hysteresis that stops hunting.
    qint64 releaseDriftMs = 100;
    double slowdownRate = 0.95;
    double speedupRate = 1.05;
    // Beyond this a nudge would take minutes: seek once and let the viewer see why.
    qint64 fastForwardDriftMs = 5000;
    // Beyond this even a seek is wrong: the member must rejoin the buffer gate.
    qint64 maxCatchUpOffsetMs = 20000;
    // How long this client ignores the room after its own action, so its own round trip is not
    // read as someone else's decision.
    qint64 localIntentGuardMs = 800;
    // A second remote pause inside this window is the same event arriving twice.
    qint64 remotePauseDebounceMs = 1000;
};

enum class Outcome
{
    None,
    RejectStale,       // an older or duplicate broadcast
    RejectSelfEcho,
    RejectWrongEpisode,
    DeferLocalIntent,  // inside the guard window after we acted
    DeferClockUnknown,
    AwaitSchedule,     // start armed for a future instant
    StartNow,
    Pause,
    Seek,              // the room's seek, not ours
    NudgeSlow,         // we are ahead
    NudgeFast,         // we are behind
    ResumeRate,        // hand the speed back to the user
    CorrectToGroup,    // our own seek to the projected group position
    HoldInGate,        // too far behind to fix politely
};

QString outcomeName(Outcome outcome);

struct Decision
{
    Outcome outcome = Outcome::None;
    // Set by the outcomes that move the playhead.
    double targetPosition = 0.0;
    // Set by the nudges.
    double rate = 1.0;
    // How long the action stays in effect; zero means until something else changes.
    qint64 holdMs = 0;
    // Always set when the outcome is not None.
    QString reason;

    bool acts() const { return outcome != Outcome::None; }
};

// What the room said, already parsed.
struct RoomSignal
{
    enum class Kind
    {
        None,
        Play,
        Pause,
        Seek,
        GateOpened,
        GateClosed,
        StateRefresh,
        ServerCorrect,
        ServerSpeedSeek,
        ServerRegate,
        EpisodeChanged,
    };
    Kind kind = Kind::None;

    // Room broadcast order; 0 means an older hub that sends none, so the ordering guard stands down.
    qint64 seq = 0;
    qint64 serverTimeMs = 0;

    double position = 0.0;
    bool groupPlaying = false;
    // Hub wall-clock instant to act at, already carrying the room's worst-case latency.
    qint64 scheduledPlayAtMs = 0;
    QString sourceUserId;
    QString episodeId;
    // Set by a hub directive: the rate it asked for, its hold, and its reason.
    double rate = 1.0;
    qint64 holdMs = 0;
    QString reason;
};

struct Observation
{
    qint64 nowMonoMs = 0;

    // Projected from the anchor, never recomputed from two clocks.
    GroupAnchor anchor;
    double groupPosition = 0.0;
    bool groupPlaying = false;
    bool gateOpen = false;

    double localPosition = 0.0;
    double localRate = 1.0;
    bool localPlaying = false;
    bool scrubbing = false;
    bool midSeek = false;
    double bufferedAhead = 0.0;
    bool isHost = false;
    bool ignoreWait = false;
    bool clockTrusted = false;
    // The target position belongs to a peer that stopped being the reference.
    bool clockHandoverPending = false;
    qint64 rttMs = -1;

    QString selfUserId;
    QString localEpisodeId;

    RoomSignal signal;
    // Hub-published, with the values this client ships as the fallback.
    Tuning tuning;
    // Converted onto this process's monotonic clock by the caller's estimator; 0 means act now.
    qint64 scheduledStartMonoMs = 0;
};

// Policy memory between packets: held by the caller, owned by this layer.
struct State
{
    qint64 lastSeq = 0;
    // Armed by AwaitSchedule and executed by the caller when the instant arrives.
    qint64 scheduledStartMonoMs = 0;
    double scheduledStartPosition = 0.0;
    qint64 localIntentUntilMonoMs = 0;
    qint64 lastRemotePauseMonoMs = 0;
    qint64 driftSinceMonoMs = 0;
    Outcome correcting = Outcome::None;
    qint64 correctionSinceMonoMs = 0;
    // The hub's own seek target, so a directive and a local decision can be compared.
    qint64 lastServerDirectiveSeq = 0;

    void reset() { *this = State{}; }
};

// Reads everything from its arguments and writes only the State it owns.
Decision decide(const Observation& observation, State& state);

// Arms the local guard before the round trip starts.
void noteLocalIntent(State& state, qint64 nowMonoMs, const Tuning& tuning);

// ms, positive when this client is ahead of the group.
double driftMs(const Observation& observation);

}  // namespace sync
