// Unit tests for the clock estimator and the decision function: no socket, no player, and every
// instant passed in.

#include "clock_estimator.h"
#include "sync_decision.h"
#include "sync_telemetry.h"

#include <QtTest>

using sync::Decision;
using sync::Observation;
using sync::Outcome;
using sync::RoomSignal;
using sync::State;
using sync::Tuning;

namespace
{

ClockEstimator::Sample probe(qint64 clientSend, qint64 forwardMs, qint64 processingMs,
                             qint64 returnMs, qint64 serverMinusClient)
{
    // Built from a stated truth, so the expectation tests the world rather than the formula.
    ClockEstimator::Sample sample;
    const qint64 serverAtSend = clientSend + serverMinusClient;
    sample.clientSendMs = clientSend;
    sample.serverReceiveMs = serverAtSend + forwardMs;
    sample.serverSendMs = sample.serverReceiveMs + processingMs;
    sample.clientReceiveMs = clientSend + forwardMs + processingMs + returnMs;
    return sample;
}

}  // namespace

class SyncCoreTest : public QObject
{
    Q_OBJECT

private slots:
    // ── Estimator ────────────────────────────────────────────────────────────

    void symmetricPathMeasuresOffsetExactly()
    {
        ClockEstimator clock;
        // Hub 500 ms ahead on a symmetric path, 110 ms round trip.
        const auto sample = probe(10000, 50, 10, 50, 500);
        QCOMPARE(sample.rttMs(), qint64(100));
        QCOMPARE(sample.offsetMs(), qint64(500));
    }

    void serverProcessingTimeCountsAsNeitherLatencyNorSkew()
    {
        ClockEstimator clock;
        // Without the receive stamp, hub processing time is indistinguishable from clock error.
        const auto quick = probe(10000, 50, 5, 50, 500);
        const auto slow = probe(20000, 50, 4000, 50, 500);
        QCOMPARE(quick.offsetMs(), slow.offsetMs());
        QCOMPARE(quick.rttMs(), slow.rttMs());
    }

    void estimateIsCommittedOnlyOutsideTheDeadband()
    {
        ClockEstimator::Options options;
        options.deadbandMs = 120;
        ClockEstimator clock(options);

        for (int i = 0; i < 3; ++i) {
            const qint64 now = 1000 + i * 1000;
            clock.addSample(probe(now, 50, 5, 50, 500), now);
        }
        QCOMPARE(clock.offsetMs(), qint64(500));

        // A 40 ms wobble on a clearer path: the competitive rule keeps it, the deadband rejects it.
        clock.addSample(probe(5000, 45, 5, 45, 540), 5000);
        QCOMPARE(clock.offsetMs(), qint64(500));

        // A real 400 ms move on the clearest path: not following it arms every timer on a stale instant.
        for (int i = 0; i < 3; ++i) {
            const qint64 now = 6000 + i * 1000;
            clock.addSample(probe(now, 30, 5, 30, 900), now);
        }
        QVERIFY2(qAbs(clock.offsetMs() - 500) >= 120,
                 qPrintable(QStringLiteral("estimate stayed at %1").arg(clock.offsetMs())));
    }

    void congestedSampleDoesNotDragTheEstimate()
    {
        ClockEstimator::Options options;
        options.window = 8;
        options.deadbandMs = 10;
        ClockEstimator clock(options);
        for (int i = 0; i < 4; ++i) {
            const qint64 now = 1000 + i * 1000;
            clock.addSample(probe(now, 40, 5, 40, 500), now);
        }
        QCOMPARE(clock.offsetMs(), qint64(500));

        // One probe behind 900 ms of bufferbloat: averaging it in would drag the estimate.
        const qint64 congestedAt = 6000;
        clock.addSample(probe(congestedAt, 900, 5, 40, 500), congestedAt);
        QVERIFY2(qAbs(clock.offsetMs() - 500) < 120,
                 qPrintable(QStringLiteral("estimate moved to %1").arg(clock.offsetMs())));
        QCOMPARE(clock.bestRttMs(congestedAt), qint64(80));
    }

    void confidenceNeedsAWindow()
    {
        ClockEstimator::Options options;
        options.minTrusted = 3;
        ClockEstimator clock(options);
        QCOMPARE(clock.confidence(1000), ClockEstimator::Confidence::Unknown);
        clock.addSample(probe(1000, 40, 5, 40, 500), 1000);
        QCOMPARE(clock.confidence(1000), ClockEstimator::Confidence::Seeded);
        clock.addSample(probe(2000, 40, 5, 40, 500), 2000);
        clock.addSample(probe(3000, 40, 5, 40, 500), 3000);
        QCOMPARE(clock.confidence(3000), ClockEstimator::Confidence::Trusted);
    }

    void staleSamplesDropOut()
    {
        ClockEstimator::Options options;
        options.maxAgeMs = 10000;
        options.minTrusted = 3;
        ClockEstimator clock(options);
        for (int i = 0; i < 3; ++i)
            clock.addSample(probe(1000 + i * 1000, 40, 5, 40, 500), 1000 + i * 1000);
        QCOMPARE(clock.confidence(4000), ClockEstimator::Confidence::Trusted);
        // A lid closed for a minute: the samples are still in the array and still wrong.
        QCOMPARE(clock.freshCount(70000), 0);
        QCOMPARE(clock.confidence(70000), ClockEstimator::Confidence::Unknown);
    }

    void cadenceChasesThenRelaxes()
    {
        ClockEstimator::Options options;
        options.minTrusted = 3;
        ClockEstimator clock(options);
        QCOMPARE(clock.nextIntervalMs(1000, true), qint64(1000));
        for (int i = 0; i < 3; ++i)
            clock.addSample(probe(1000 + i * 1000, 40, 5, 40, 500), 1000 + i * 1000);
        QCOMPARE(clock.nextIntervalMs(4000, true), qint64(15000));
        QCOMPARE(clock.nextIntervalMs(4000, false), qint64(60000));
        // Past half its age the estimate probes faster, before it expires rather than after.
        QCOMPARE(clock.nextIntervalMs(120000, true), qint64(1000));
    }

    void serverInstantConvertsToMonotonicFuture()
    {
        ClockEstimator clock;
        for (int i = 0; i < 3; ++i)
            clock.addSample(probe(1000 + i * 1000, 40, 5, 40, 500), 1000 + i * 1000);
        QCOMPARE(clock.offsetMs(), qint64(500));

        // Hub wall 5000 minus a 500 offset is local wall 4500, i.e. 3500 past monotonic 1000.
        const qint64 target = clock.localMonoForServerTime(5000, 0, 1000);
        QCOMPARE(target, qint64(1000) + 4500);
        // A target already in the past must not arm a timer in the past.
        QCOMPARE(clock.localMonoForServerTime(1000, 50000, 1000), qint64(1000));
    }

    void anUnmeasuredClockCannotScheduleAStart()
    {
        // Arming on an unmeasured clock was reverted: far-off peers never reached their start.
        ClockEstimator clock;
        QCOMPARE(clock.localMonoForServerTime(5000, 4400, 1000), qint64(1000));
        QCOMPARE(clock.localMonoForServerTime(0, 4400, 1000), qint64(1000));
    }

    void wallClockStepClearsTheWindow()
    {
        ClockEstimator clock;
        for (int i = 0; i < 3; ++i) {
            clock.addSample(probe(1000 + i * 1000, 40, 5, 40, 500), 1000 + i * 1000);
            clock.noteClockDomain(1000 + i * 1000, 1000 + i * 1000);
        }
        QCOMPARE(clock.confidence(3000), ClockEstimator::Confidence::Trusted);
        QVERIFY(!clock.detectedStep());

        // Wall jumps a minute while monotonic keeps walking: the old samples are of another clock.
        clock.noteClockDomain(61000 + 1000, 4000);
        QVERIFY(clock.detectedStep());
        QCOMPARE(clock.confidence(4000), ClockEstimator::Confidence::Unknown);
        QCOMPARE(clock.windowSize(), 0);
    }

    void anchorProjectsOnMonotonicTimeOnly()
    {
        GroupAnchor anchor;
        anchor.positionSeconds = 100.0;
        anchor.takenMonoMs = 1000;
        anchor.rate = 1.0;
        anchor.playing = true;
        QCOMPARE(anchor.projected(6000), 105.0);
        anchor.playing = false;
        QCOMPARE(anchor.projected(6000), 100.0);
        anchor.playing = true;
        anchor.rate = 2.0;
        QCOMPARE(anchor.projected(6000), 110.0);
    }

    // ── Decision: ordering and attribution ───────────────────────────────────

    Observation baseObservation()
    {
        Observation observation;
        observation.nowMonoMs = 10000;
        observation.groupPosition = 100.0;
        observation.localPosition = 100.0;
        observation.groupPlaying = true;
        observation.localPlaying = true;
        observation.localRate = 1.0;
        observation.clockTrusted = true;
        observation.selfUserId = QStringLiteral("me");
        observation.localEpisodeId = QStringLiteral("ep-1");
        return observation;
    }

    void staleBroadcastIsDropped()
    {
        State state;
        Observation newer = baseObservation();
        newer.signal.kind = RoomSignal::Kind::Play;
        newer.signal.seq = 12;
        newer.signal.groupPlaying = true;
        newer.scheduledStartMonoMs = 10000;
        const Decision first = sync::decide(newer, state);
        QCOMPARE(first.outcome, Outcome::StartNow);

        // Sent before the play, arrived after it.
        Observation stale = baseObservation();
        stale.signal.kind = RoomSignal::Kind::Pause;
        stale.signal.seq = 11;
        stale.signal.sourceUserId = QStringLiteral("ada");
        const Decision second = sync::decide(stale, state);
        QCOMPARE(second.outcome, Outcome::RejectStale);
        // A silent drop looks like a client that ignored the room.
        QVERIFY(!second.reason.isEmpty());
    }

    void duplicateBroadcastIsDropped()
    {
        State state;
        state.lastSeq = 40;
        Observation observation = baseObservation();
        observation.signal.kind = RoomSignal::Kind::Pause;
        observation.signal.seq = 40;
        observation.signal.sourceUserId = QStringLiteral("ada");
        QCOMPARE(sync::decide(observation, state).outcome, Outcome::RejectStale);
    }

    void packetsWithoutASeqAreStillApplied()
    {
        // An older hub sends no seq: the guard degrades to "no guard", not "no room".
        State state;
        Observation observation = baseObservation();
        observation.signal.kind = RoomSignal::Kind::Pause;
        observation.signal.sourceUserId = QStringLiteral("ada");
        QCOMPARE(sync::decide(observation, state).outcome, Outcome::Pause);
        QCOMPARE(sync::decide(observation, state).outcome, Outcome::None);  // debounced
    }

    void selfEchoIsIgnored()
    {
        State state;
        Observation observation = baseObservation();
        observation.signal.kind = RoomSignal::Kind::Seek;
        observation.signal.seq = 3;
        observation.signal.sourceUserId = QStringLiteral("me");
        observation.signal.position = 55.0;
        const Decision decision = sync::decide(observation, state);
        QCOMPARE(decision.outcome, Outcome::RejectSelfEcho);
    }

    void wrongEpisodeIsIgnored()
    {
        State state;
        Observation observation = baseObservation();
        observation.signal.kind = RoomSignal::Kind::Play;
        observation.signal.seq = 3;
        observation.signal.episodeId = QStringLiteral("ep-2");
        observation.signal.groupPlaying = true;
        QCOMPARE(sync::decide(observation, state).outcome, Outcome::RejectWrongEpisode);
    }

    // ── Decision: the scheduled start ────────────────────────────────────────

    void playAheadOfTimeArmsInsteadOfActing()
    {
        State state;
        Observation observation = baseObservation();
        observation.signal.kind = RoomSignal::Kind::GateClosed;
        observation.signal.seq = 5;
        observation.signal.groupPlaying = true;
        observation.signal.position = 120.0;
        observation.scheduledStartMonoMs = 10400;  // 400 ms out

        const Decision armed = sync::decide(observation, state);
        QCOMPARE(armed.outcome, Outcome::AwaitSchedule);
        QCOMPARE(state.scheduledStartMonoMs, qint64(10400));

        // While a start is pending a nudge would land wrong whatever it measured.
        Observation ticking = baseObservation();
        ticking.localPosition = 105.0;  // five seconds out, by itself
        const Decision held = sync::decide(ticking, state);
        QCOMPARE(held.outcome, Outcome::AwaitSchedule);
    }

    void anArmedStartIsCarriedUntilTheInstantArrives()
    {
        State state;
        Observation observation = baseObservation();
        observation.signal.kind = RoomSignal::Kind::Play;
        observation.signal.seq = 5;
        observation.signal.groupPlaying = true;
        observation.signal.position = 120.0;
        observation.scheduledStartMonoMs = 10400;

        // Re-driving decide() on fire would read as a duplicate, so the armed state must survive.
        const Decision armed = sync::decide(observation, state);
        QCOMPARE(armed.outcome, Outcome::AwaitSchedule);
        QCOMPARE(state.scheduledStartMonoMs, qint64(10400));
        QCOMPARE(state.scheduledStartPosition, 120.0);

        // A start already in the history must not arm: join where the group is, not where it was.
        Observation late = baseObservation();
        late.signal.kind = RoomSignal::Kind::Play;
        late.signal.seq = 6;
        late.signal.groupPlaying = true;
        late.signal.position = 123.0;
        late.scheduledStartMonoMs = 9000;
        const Decision due = sync::decide(late, state);
        QCOMPARE(due.outcome, Outcome::StartNow);
        QCOMPARE(due.targetPosition, 123.0);
        QCOMPARE(state.scheduledStartMonoMs, qint64(0));
    }

    void oneStartIsNotAppliedTwice()
    {
        // The hub closes a gate with allReady, then broadcasts the play: one instant, two packets.
        State state;
        Observation first = baseObservation();
        first.signal.kind = RoomSignal::Kind::GateClosed;
        first.signal.seq = 5;
        first.signal.groupPlaying = true;
        first.signal.position = 120.0;
        first.signal.scheduledPlayAtMs = 99000;
        first.scheduledStartMonoMs = 10400;
        QCOMPARE(sync::decide(first, state).outcome, Outcome::AwaitSchedule);

        Observation second = baseObservation();
        second.signal.kind = RoomSignal::Kind::Play;
        second.signal.seq = 6;
        second.signal.groupPlaying = true;
        second.signal.position = 120.0;
        second.signal.scheduledPlayAtMs = 99000;
        second.scheduledStartMonoMs = 10400;
        const Decision duplicate = sync::decide(second, state);
        QCOMPARE(duplicate.outcome, Outcome::None);

        // A later start must still arm: the guard compares instants, not packets.
        Observation third = baseObservation();
        third.signal.kind = RoomSignal::Kind::Play;
        third.signal.seq = 7;
        third.signal.groupPlaying = true;
        third.signal.position = 130.0;
        third.signal.scheduledPlayAtMs = 99999;
        third.scheduledStartMonoMs = 11400;
        QCOMPARE(sync::decide(third, state).outcome, Outcome::AwaitSchedule);
    }

    void unscheduledPlayStartsImmediately()
    {
        State state;
        Observation observation = baseObservation();
        observation.signal.kind = RoomSignal::Kind::Play;
        observation.signal.seq = 2;
        observation.signal.groupPlaying = true;
        observation.scheduledStartMonoMs = 0;
        const Decision decision = sync::decide(observation, state);
        QCOMPARE(decision.outcome, Outcome::StartNow);
        QCOMPARE(state.scheduledStartMonoMs, qint64(0));
    }

    void pauseKillsAnArmedStart()
    {
        State state;
        Observation play = baseObservation();
        play.signal.kind = RoomSignal::Kind::Play;
        play.signal.seq = 5;
        play.signal.groupPlaying = true;
        play.scheduledStartMonoMs = 12000;
        sync::decide(play, state);
        QVERIFY(state.scheduledStartMonoMs > 0);

        Observation pause = baseObservation();
        pause.signal.kind = RoomSignal::Kind::Pause;
        pause.signal.seq = 6;
        pause.signal.sourceUserId = QStringLiteral("ada");
        QCOMPARE(sync::decide(pause, state).outcome, Outcome::Pause);
        QCOMPARE(state.scheduledStartMonoMs, qint64(0));
    }

    void repeatedRemotePausesDebouce()
    {
        State state;
        Observation first = baseObservation();
        first.signal.kind = RoomSignal::Kind::Pause;
        first.signal.seq = 1;
        first.signal.sourceUserId = QStringLiteral("ada");
        QCOMPARE(sync::decide(first, state).outcome, Outcome::Pause);

        // Two peers both said pause a third of a second apart; the viewer should see one stop.
        Observation second = first;
        second.signal.seq = 2;
        second.signal.sourceUserId = QStringLiteral("ben");
        second.nowMonoMs = first.nowMonoMs + 350;
        QCOMPARE(sync::decide(second, state).outcome, Outcome::None);

        Observation third = second;
        third.signal.seq = 3;
        third.nowMonoMs = first.nowMonoMs + 3000;
        QCOMPARE(sync::decide(third, state).outcome, Outcome::Pause);
    }

    // ── Decision: correction policy ─────────────────────────────────────────

    void nobodyIsCorrectedInsideTolerance()
    {
        State state;
        Observation observation = baseObservation();
        observation.localPosition = 100.4;  // 400 ms ahead
        QCOMPARE(sync::decide(observation, state).outcome, Outcome::None);
    }

    void smallDriftNudgesInsteadOfSeeking()
    {
        State state;
        Observation observation = baseObservation();
        observation.localPosition = 98.0;  // two seconds behind
        const Decision decision = sync::decide(observation, state);
        QCOMPARE(decision.outcome, Outcome::NudgeFast);
        QVERIFY(decision.rate > 1.0);
        QVERIFY(decision.rate < 1.2);  // a nudge, not a chase
    }

    void aheadDriftSlowsDown()
    {
        State state;
        Observation observation = baseObservation();
        observation.localPosition = 102.0;
        const Decision decision = sync::decide(observation, state);
        QCOMPARE(decision.outcome, Outcome::NudgeSlow);
        QVERIFY(decision.rate < 1.0);
    }

    void nudgeHoldsUntilTheErrorReallyGoesAway()
    {
        State state;
        Observation behind = baseObservation();
        behind.localPosition = 98.0;
        QCOMPARE(sync::decide(behind, state).outcome, Outcome::NudgeFast);

        // 600 ms: below engage, above release. Stopping here is what makes a room oscillate.
        Observation closer = baseObservation();
        closer.nowMonoMs += 2000;
        closer.localPosition = 99.4;
        QCOMPARE(sync::decide(closer, state).outcome, Outcome::NudgeFast);

        Observation arrived = baseObservation();
        arrived.nowMonoMs += 4000;
        arrived.localPosition = 100.05;
        QCOMPARE(sync::decide(arrived, state).outcome, Outcome::ResumeRate);
        QCOMPARE(state.correcting, Outcome::None);
    }

    void bigDriftSeeksOnce()
    {
        State state;
        Observation observation = baseObservation();
        observation.localPosition = 92.0;  // eight seconds behind
        const Decision decision = sync::decide(observation, state);
        QCOMPARE(decision.outcome, Outcome::CorrectToGroup);
        QCOMPARE(decision.targetPosition, 100.0);
    }

    void hugeDriftGoesBackToTheGate()
    {
        State state;
        Observation observation = baseObservation();
        observation.localPosition = 60.0;  // forty seconds behind
        QCOMPARE(sync::decide(observation, state).outcome, Outcome::HoldInGate);
    }

    void theClockOfTheRoomIsNeverSteered()
    {
        State state;
        Observation observation = baseObservation();
        observation.isHost = true;
        observation.localPosition = 80.0;  // twenty seconds off, by its own account
        QCOMPARE(sync::decide(observation, state).outcome, Outcome::None);
    }

    void aMemberThatDeclinedTheWaitIsNotSteered()
    {
        State state;
        Observation observation = baseObservation();
        observation.ignoreWait = true;
        observation.localPosition = 80.0;
        QCOMPARE(sync::decide(observation, state).outcome, Outcome::None);
    }

    void theDriverIsNeverCorrected()
    {
        for (bool scrubbing : {true, false}) {
            State state;
            Observation driving = baseObservation();
            driving.localPosition = 98.0;
            QCOMPARE(sync::decide(driving, state).outcome, Outcome::NudgeFast);

            // Mid-drag: leaving 1.05 would drift their seek, re-applying would fight them for it.
            Observation whileDriving = baseObservation();
            whileDriving.nowMonoMs += 1000;
            whileDriving.localPosition = 98.0;
            whileDriving.scrubbing = scrubbing;
            whileDriving.midSeek = !scrubbing;
            const Decision decision = sync::decide(whileDriving, state);
            QCOMPARE(decision.outcome, Outcome::ResumeRate);
            QCOMPARE(state.correcting, Outcome::None);

            Observation stillDriving = whileDriving;
            stillDriving.nowMonoMs += 1000;
            stillDriving.signal.kind = RoomSignal::Kind::StateRefresh;
            stillDriving.signal.seq = 20;
            QCOMPARE(sync::decide(stillDriving, state).outcome, Outcome::None);
        }
    }

    void ownActionIsNotOverruledInFlight()
    {
        State state;
        Tuning tuning;
        sync::noteLocalIntent(state, 10000, tuning);
        Observation observation = baseObservation();
        observation.nowMonoMs = 10000 + tuning.localIntentGuardMs / 2;
        observation.localPosition = 90.0;
        QCOMPARE(sync::decide(observation, state).outcome, Outcome::DeferLocalIntent);

        Observation after = observation;
        after.nowMonoMs = 10000 + tuning.localIntentGuardMs + 100;
        QCOMPARE(sync::decide(after, state).outcome, Outcome::CorrectToGroup);
    }

    void anUntrustedClockSuspendsCorrection()
    {
        State state;
        Observation observation = baseObservation();
        observation.clockTrusted = false;
        observation.localPosition = 98.0;
        QCOMPARE(sync::decide(observation, state).outcome, Outcome::None);
    }

    void hubDirectiveWinsOnlyWhenWeCannotMeasure()
    {
        State state;
        Observation trusted = baseObservation();
        trusted.signal.kind = RoomSignal::Kind::ServerCorrect;
        trusted.signal.seq = 4;
        trusted.signal.position = 100.0;
        trusted.signal.sourceUserId = QStringLiteral("host");
        trusted.localPosition = 100.1;  // our own reading says we are fine
        QCOMPARE(sync::decide(trusted, state).outcome, Outcome::None);

        State untrustedState;
        Observation untrusted = trusted;
        untrusted.clockTrusted = false;
        untrusted.signal.kind = RoomSignal::Kind::ServerSpeedSeek;
        untrusted.signal.rate = 1.5;
        untrusted.signal.holdMs = 1200;
        untrusted.signal.position = 100.0;
        untrusted.signal.seq = 5;
        const Decision decision = sync::decide(untrusted, untrustedState);
        QCOMPARE(decision.outcome, Outcome::NudgeFast);
        QCOMPARE(decision.rate, 1.5);
        QCOMPARE(decision.holdMs, qint64(1200));
    }

    void gateOpenReleasesACorrection()
    {
        State state;
        Observation behind = baseObservation();
        behind.localPosition = 98.0;
        QCOMPARE(sync::decide(behind, state).outcome, Outcome::NudgeFast);

        Observation gate = baseObservation();
        gate.nowMonoMs += 1000;
        gate.signal.kind = RoomSignal::Kind::GateOpened;
        gate.signal.seq = 9;
        gate.gateOpen = true;
        QCOMPARE(sync::decide(gate, state).outcome, Outcome::ResumeRate);
    }

    // ── Telemetry ────────────────────────────────────────────────────────────

    void telemetryReportsDriftPercentilesAndRates()
    {
        SyncTelemetry telemetry;
        for (int i = 0; i < 100; ++i) {
            SyncTelemetry::Sample sample;
            sample.atMonoMs = i * 100;
            sample.driftMs = i < 95 ? 100.0 : 3000.0;  // five outliers out of a hundred
            sample.clockTrusted = true;
            telemetry.record(sample);
        }
        const auto summary = telemetry.summarize();
        QCOMPARE(summary.samples, 100);
        QCOMPARE(summary.medianAbsDriftMs, 100.0);
        QCOMPARE(summary.p95AbsDriftMs, 100.0);
        QCOMPARE(summary.maxAbsDriftMs, 3000.0);
        QCOMPARE(summary.spanMs, qint64(9900));

        SyncTelemetry::Sample nudge;
        nudge.atMonoMs = 10000;
        nudge.driftMs = -2000.0;
        nudge.outcome = Outcome::NudgeFast;
        telemetry.record(nudge);
        QCOMPARE(telemetry.summarize().nudgesPerMinute > 0.0, true);
    }

    void telemetryCountsTheWorstStart()
    {
        SyncTelemetry telemetry;
        telemetry.recordStart(5000, 5020);
        telemetry.recordStart(9000, 8990);
        telemetry.recordStart(12000, 11700);  // three seconds early
        QCOMPARE(telemetry.summarize().startSkewMs, qint64(300));
    }

    void telemetryNamesEveryOutcome()
    {
        // An outcome with no name is a log line nobody can read.
        const Outcome outcomes[] = {Outcome::None, Outcome::RejectStale, Outcome::RejectSelfEcho,
            Outcome::RejectWrongEpisode, Outcome::DeferLocalIntent, Outcome::DeferClockUnknown,
            Outcome::AwaitSchedule, Outcome::StartNow, Outcome::Pause, Outcome::Seek,
            Outcome::NudgeSlow, Outcome::NudgeFast, Outcome::ResumeRate, Outcome::CorrectToGroup,
            Outcome::HoldInGate};
        for (const Outcome outcome : outcomes)
            QVERIFY2(!sync::outcomeName(outcome).isEmpty(), "an outcome with no name");
    }
};

QTEST_APPLESS_MAIN(SyncCoreTest)
#include "sync_core_test.moc"
