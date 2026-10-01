#pragma once

#include "sync_decision.h"

#include <QString>
#include <QtGlobal>

#include <QVector>

// Measures drift, correction counts and start skew so the inherited thresholds can be replaced
// with this room's numbers. Passive: nothing decides anything from these, so instrumentation
// cannot change behaviour.
class SyncTelemetry
{
public:
    struct Sample
    {
        qint64 atMonoMs = 0;
        // Positive when this client is ahead of the group.
        double driftMs = 0.0;
        qint64 rttMs = -1;
        sync::Outcome outcome = sync::Outcome::None;
        double rate = 1.0;
        bool buffering = false;
        bool gateOpen = false;
        bool clockTrusted = false;
    };

    struct Summary
    {
        int samples = 0;
        qint64 spanMs = 0;
        double medianAbsDriftMs = 0.0;
        double p95AbsDriftMs = 0.0;
        double maxAbsDriftMs = 0.0;
        // A rate, not a count: a nudge a minute and a nudge a second are different rooms.
        double nudgesPerMinute = 0.0;
        int seeks = 0;
        int holdsInGate = 0;
        int staleDropped = 0;
        int deferredByLocalIntent = 0;
        // How far members actually moved from the instant the hub named; -1 when none has fired.
        qint64 startSkewMs = -1;
        double trustedClockShare = 0.0;
    };

    void record(const Sample& sample);
    // The armed instant and the instant the player actually moved.
    void recordStart(qint64 scheduledMonoMs, qint64 actedMonoMs);

    Summary summarize() const;
    // One grep-able line; used by --sync-selftest and the debug overlay.
    QString dump() const;

    void reset();

    // Bounded: percentile estimates do not need the whole history.
    static constexpr int kCapacity = 1200;

private:
    QVector<Sample> samples_;
    QVector<qint64> startSkewsMs_;
    int seeks_ = 0;
    int nudges_ = 0;
    int holdsInGate_ = 0;
    int staleDropped_ = 0;
    int deferredByLocalIntent_ = 0;
    int trustedClockSamples_ = 0;
};
