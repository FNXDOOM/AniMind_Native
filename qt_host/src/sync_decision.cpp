#include "sync_decision.h"

#include <QtGlobal>

namespace sync
{

QString outcomeName(Outcome outcome)
{
    switch (outcome) {
    case Outcome::None:                return QStringLiteral("none");
    case Outcome::RejectStale:         return QStringLiteral("reject-stale");
    case Outcome::RejectSelfEcho:      return QStringLiteral("reject-self-echo");
    case Outcome::RejectWrongEpisode:  return QStringLiteral("reject-wrong-episode");
    case Outcome::DeferLocalIntent:    return QStringLiteral("defer-local-intent");
    case Outcome::DeferClockUnknown:   return QStringLiteral("defer-clock-unknown");
    case Outcome::AwaitSchedule:       return QStringLiteral("await-schedule");
    case Outcome::StartNow:            return QStringLiteral("start");
    case Outcome::Pause:               return QStringLiteral("pause");
    case Outcome::Seek:                return QStringLiteral("seek");
    case Outcome::NudgeSlow:           return QStringLiteral("nudge-slow");
    case Outcome::NudgeFast:           return QStringLiteral("nudge-fast");
    case Outcome::ResumeRate:          return QStringLiteral("resume-rate");
    case Outcome::CorrectToGroup:      return QStringLiteral("correct-to-group");
    case Outcome::HoldInGate:          return QStringLiteral("hold-in-gate");
    }
    return QStringLiteral("unknown");
}

double driftMs(const Observation& observation)
{
    return (observation.localPosition - observation.groupPosition) * 1000.0;
}

void noteLocalIntent(State& state, qint64 nowMonoMs, const Tuning& tuning)
{
    state.localIntentUntilMonoMs = nowMonoMs + tuning.localIntentGuardMs;
}

static Decision make(Outcome outcome, const QString& reason,
                     double target = 0.0, double rate = 1.0, qint64 holdMs = 0)
{
    Decision decision;
    decision.outcome = outcome;
    decision.reason = reason;
    decision.targetPosition = target;
    decision.rate = rate;
    decision.holdMs = holdMs;
    return decision;
}

static QString who(const RoomSignal& signal)
{
    return signal.sourceUserId.isEmpty() ? QStringLiteral("the room") : signal.sourceUserId;
}

// Letting go of a nudge is an action: the caller has to restore the user's own speed.
static Decision release(State& state, const QString& reason)
{
    if (state.correcting == Outcome::None)
        return make(Outcome::None, reason);
    const Outcome previous = state.correcting;
    state.correcting = Outcome::None;
    state.driftSinceMonoMs = 0;
    if (previous == Outcome::HoldInGate)
        return make(Outcome::None, reason);
    return make(Outcome::ResumeRate, reason);
}

static Outcome bandFor(double magnitude, double drift, const Tuning& tuning)
{
    if (magnitude >= tuning.maxCatchUpOffsetMs)
        return Outcome::HoldInGate;
    if (magnitude >= tuning.fastForwardDriftMs)
        return Outcome::CorrectToGroup;
    return drift > 0 ? Outcome::NudgeSlow : Outcome::NudgeFast;
}

static Decision engage(Outcome outcome, const QString& reason, const Observation& observation,
                       const Tuning& tuning, State& state)
{
    state.correcting = outcome;
    state.correctionSinceMonoMs = observation.nowMonoMs;
    const double rate = outcome == Outcome::NudgeSlow ? tuning.slowdownRate
        : outcome == Outcome::NudgeFast ? tuning.speedupRate : 1.0;
    return make(outcome, reason, observation.groupPosition, rate, 0);
}

Decision decide(const Observation& observation, State& state)
{
    const RoomSignal& signal = observation.signal;
    const Tuning& tuning = observation.tuning;

    // ── Ordering ─────────────────────────────────────────────────────────────
    // Applying a stale packet is how a pause overtakes the play it followed; a zero seq means an
    // older hub, so the guard stands down rather than silencing the room.
    if (signal.seq > 0) {
        if (state.lastSeq != 0 && signal.seq <= state.lastSeq) {
            return make(Outcome::RejectStale,
                QStringLiteral("packet %1 is at or behind applied %2").arg(signal.seq).arg(state.lastSeq));
        }
        state.lastSeq = signal.seq;
    }

    // ── Attribution ──────────────────────────────────────────────────────────
    if (!signal.episodeId.isEmpty() && !observation.localEpisodeId.isEmpty()
        && signal.episodeId != observation.localEpisodeId) {
        // A signal for an episode this client is not watching, as a slow joiner produces.
        return make(Outcome::RejectWrongEpisode,
            QStringLiteral("signal is for %1, playing %2").arg(signal.episodeId, observation.localEpisodeId));
    }
    if (!signal.sourceUserId.isEmpty() && signal.sourceUserId == observation.selfUserId
        && signal.kind != RoomSignal::Kind::None && signal.kind != RoomSignal::Kind::StateRefresh) {
        state.scheduledStartMonoMs = 0;
        return make(Outcome::RejectSelfEcho, QStringLiteral("our own action, returned"));
    }

    // ── Discrete signals ─────────────────────────────────────────────────────
    switch (signal.kind) {
    case RoomSignal::Kind::GateOpened:
        // Anything armed belongs to an instant that is no longer coming.
        state.scheduledStartMonoMs = 0;
        state.driftSinceMonoMs = 0;
        return release(state, QStringLiteral("gate opened"));

    case RoomSignal::Kind::EpisodeChanged:
        state.scheduledStartMonoMs = 0;
        state.driftSinceMonoMs = 0;
        return release(state, QStringLiteral("episode changed"));

    case RoomSignal::Kind::Pause: {
        state.scheduledStartMonoMs = 0;
        if (!observation.localPlaying)
            return make(Outcome::None, QStringLiteral("already paused"));
        const qint64 since = observation.nowMonoMs - state.lastRemotePauseMonoMs;
        if (state.lastRemotePauseMonoMs != 0 && since >= 0 && since < tuning.remotePauseDebounceMs) {
            // Two pauses a moment apart are one event; rendering both is the flicker here.
            return make(Outcome::None, QStringLiteral("pause debounced at %1 ms").arg(since));
        }
        state.lastRemotePauseMonoMs = observation.nowMonoMs;
        // The pause supersedes a running nudge; the caller restores the rate as part of pausing.
        state.correcting = Outcome::None;
        return make(Outcome::Pause, QStringLiteral("paused by %1").arg(who(signal)), signal.position);
    }

    case RoomSignal::Kind::Seek:
        state.scheduledStartMonoMs = observation.scheduledStartMonoMs;
        state.scheduledStartPosition = signal.position;
        if (observation.scheduledStartMonoMs > observation.nowMonoMs) {
            return make(Outcome::AwaitSchedule,
                QStringLiteral("seek lands in %1 ms").arg(observation.scheduledStartMonoMs - observation.nowMonoMs),
                signal.position);
        }
        return make(Outcome::Seek, QStringLiteral("seek by %1").arg(who(signal)), signal.position);

    case RoomSignal::Kind::Play:
    case RoomSignal::Kind::GateClosed: {
        if (!signal.groupPlaying) {
            state.scheduledStartMonoMs = 0;
            state.correcting = Outcome::None;
            return make(Outcome::Pause, QStringLiteral("the gate closed without a play intent"), signal.position);
        }
        // The hub announces one start twice — gate release, then the play that follows — and both
        // name the same instant.
        if (observation.scheduledStartMonoMs > observation.nowMonoMs
            && observation.scheduledStartMonoMs == state.scheduledStartMonoMs) {
            return make(Outcome::None, QStringLiteral("that start is already armed"));
        }
        state.scheduledStartPosition = signal.position;
        if (observation.scheduledStartMonoMs > observation.nowMonoMs) {
            // Heard about the play late: move at the instant everyone else will, not on receipt.
            state.scheduledStartMonoMs = observation.scheduledStartMonoMs;
            return make(Outcome::AwaitSchedule,
                QStringLiteral("start armed for +%1 ms").arg(observation.scheduledStartMonoMs - observation.nowMonoMs),
                signal.position);
        }
        state.scheduledStartMonoMs = 0;
        return make(Outcome::StartNow, QStringLiteral("play from %1").arg(signal.position, 0, 'f', 1),
            signal.position);
    }

    case RoomSignal::Kind::ServerRegate:
        // The hub has given up on polite correction.
        state.scheduledStartMonoMs = 0;
        return engage(Outcome::HoldInGate,
            signal.reason.isEmpty() ? QStringLiteral("the room is re-gating") : signal.reason,
            observation, tuning, state);

    case RoomSignal::Kind::ServerCorrect:
    case RoomSignal::Kind::ServerSpeedSeek: {
        // A hub directive is measured without our anchor, so it wins only when we cannot measure.
        const double own = driftMs(observation);
        if (observation.clockTrusted && qAbs(own) < tuning.engageDriftMs) {
            return make(Outcome::None, QStringLiteral("hub correction inside our own deadband"));
        }
        if (signal.kind == RoomSignal::Kind::ServerSpeedSeek) {
            const double rate = signal.rate > 0.0 ? signal.rate : tuning.speedupRate;
            const Outcome outcome = rate < 1.0 ? Outcome::NudgeSlow : Outcome::NudgeFast;
            state.correcting = outcome;
            state.correctionSinceMonoMs = observation.nowMonoMs;
            return make(outcome, QStringLiteral("hub rate nudge"), signal.position, rate, signal.holdMs);
        }
        return engage(Outcome::CorrectToGroup, QStringLiteral("hub seek"), observation, tuning, state);
    }

    case RoomSignal::Kind::StateRefresh:
    case RoomSignal::Kind::None:
        break;  // falls through to the steady-state controller
    }

    // ── Steady-state correction ──────────────────────────────────────────────

    // Never correct the peer that owns the clock: steering the host moves everyone.
    if (observation.isHost)
        return release(state, QStringLiteral("this client is the clock"));

    // Opting out of the wait declined correction as much as waiting.
    if (observation.ignoreWait)
        return release(state, QStringLiteral("this member declined the wait"));

    // The target belongs to the outgoing host; freeze until the incoming one reports.
    if (observation.clockHandoverPending)
        return release(state, QStringLiteral("the room's clock is changing hands"));

    if (observation.gateOpen || !observation.groupPlaying)
        return release(state, QStringLiteral("the room is not playing"));

    if (state.scheduledStartMonoMs > observation.nowMonoMs) {
        return make(Outcome::AwaitSchedule, QStringLiteral("still waiting for the scheduled start"));
    }

    // Never correct the driver: the local user's opinion of position outranks the group's.
    if (observation.scrubbing || observation.midSeek)
        return release(state, QStringLiteral("the local user is seeking"));

    if (observation.nowMonoMs < state.localIntentUntilMonoMs) {
        return make(Outcome::DeferLocalIntent, QStringLiteral("own action in flight, %1 ms left").arg(
            state.localIntentUntilMonoMs - observation.nowMonoMs));
    }

    if (!observation.clockTrusted) {
        // Correcting on an untrusted estimate makes a group agree on a wrong position.
        return release(state, QStringLiteral("clock estimate is not trusted yet"));
    }

    const double drift = driftMs(observation);
    const double magnitude = qAbs(drift);

    if (state.correcting == Outcome::None) {
        if (magnitude < tuning.engageDriftMs) {
            state.driftSinceMonoMs = 0;
            return make(Outcome::None, QStringLiteral("in tolerance at %1 ms").arg(drift, 0, 'f', 0));
        }
        return engage(bandFor(magnitude, drift, tuning),
            QStringLiteral("%1 ms %2 the group").arg(drift, 0, 'f', 0)
                .arg(drift > 0 ? QStringLiteral("ahead of") : QStringLiteral("behind")),
            observation, tuning, state);
    }

    // Hold the band until the error is inside releaseDriftMs; escalate only across a boundary.
    if (magnitude <= tuning.releaseDriftMs)
        return release(state, QStringLiteral("back inside %1 ms").arg(tuning.releaseDriftMs));

    const Outcome wanted = bandFor(magnitude, drift, tuning);
    if (wanted != state.correcting) {
        return engage(wanted, QStringLiteral("drift moved to %1 ms").arg(drift, 0, 'f', 0),
            observation, tuning, state);
    }
    const double rate = wanted == Outcome::NudgeSlow ? tuning.slowdownRate
        : wanted == Outcome::NudgeFast ? tuning.speedupRate : 1.0;
    return make(wanted, QStringLiteral("still %1 ms out").arg(drift, 0, 'f', 0),
        observation.groupPosition, rate, 0);
}

}  // namespace sync
