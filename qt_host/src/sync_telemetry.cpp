#include "sync_telemetry.h"

#include <algorithm>
#include <cmath>

void SyncTelemetry::record(const Sample& sample)
{
    samples_.append(sample);
    while (samples_.size() > kCapacity)
        samples_.removeFirst();

    switch (sample.outcome) {
    case sync::Outcome::NudgeSlow:
    case sync::Outcome::NudgeFast:
        ++nudges_;
        break;
    case sync::Outcome::CorrectToGroup:
    case sync::Outcome::Seek:
        ++seeks_;
        break;
    case sync::Outcome::HoldInGate:
        ++holdsInGate_;
        break;
    case sync::Outcome::RejectStale:
        ++staleDropped_;
        break;
    case sync::Outcome::DeferLocalIntent:
        ++deferredByLocalIntent_;
        break;
    default:
        break;
    }
    if (sample.clockTrusted)
        ++trustedClockSamples_;
}

void SyncTelemetry::recordStart(qint64 scheduledMonoMs, qint64 actedMonoMs)
{
    if (scheduledMonoMs <= 0)
        return;
    // Signed: an absolute value would hide which side of the instant a peer habitually lands on.
    startSkewsMs_.append(actedMonoMs - scheduledMonoMs);
    while (startSkewsMs_.size() > 64)
        startSkewsMs_.removeFirst();
}

SyncTelemetry::Summary SyncTelemetry::summarize() const
{
    Summary summary;
    summary.samples = samples_.size();

    if (!startSkewsMs_.isEmpty()) {
        // Worst, not average: one member two seconds late is as visible as all of them late.
        qint64 worst = 0;
        for (const qint64 skew : startSkewsMs_)
            worst = qMax(worst, qAbs(skew));
        summary.startSkewMs = worst;
    }
    if (samples_.isEmpty())
        return summary;

    summary.spanMs = samples_.last().atMonoMs - samples_.first().atMonoMs;

    QVector<double> magnitudes;
    magnitudes.reserve(samples_.size());
    for (const auto& sample : samples_)
        magnitudes.append(qAbs(sample.driftMs));
    std::sort(magnitudes.begin(), magnitudes.end());

    // Nearest-rank percentile: averaging neighbours would report a drift nobody had.
    const int count = magnitudes.size();
    const int last = count - 1;
    summary.medianAbsDriftMs = magnitudes.at(last / 2);
    summary.p95AbsDriftMs = magnitudes.at(qBound(0, int(std::ceil(0.95 * count)) - 1, last));
    summary.maxAbsDriftMs = magnitudes.at(last);
    summary.trustedClockShare = double(trustedClockSamples_) / double(samples_.size());

    const double minutes = qMax(1.0, double(summary.spanMs) / 60000.0);
    summary.nudgesPerMinute = double(nudges_) / minutes;
    summary.seeks = seeks_;
    summary.holdsInGate = holdsInGate_;
    summary.staleDropped = staleDropped_;
    summary.deferredByLocalIntent = deferredByLocalIntent_;
    return summary;
}

QString SyncTelemetry::dump() const
{
    const Summary s = summarize();
    return QStringLiteral(
               "SYNCTELEMETRY samples=%1 spanMs=%2 driftMed=%3 driftP95=%4 driftMax=%5 "
               "nudgesPerMin=%6 seeks=%7 holds=%8 stale=%9 deferred=%10 startSkew=%11 clockTrusted=%12")
        .arg(s.samples)
        .arg(s.spanMs)
        .arg(s.medianAbsDriftMs, 0, 'f', 0)
        .arg(s.p95AbsDriftMs, 0, 'f', 0)
        .arg(s.maxAbsDriftMs, 0, 'f', 0)
        .arg(s.nudgesPerMinute, 0, 'f', 2)
        .arg(s.seeks)
        .arg(s.holdsInGate)
        .arg(s.staleDropped)
        .arg(s.deferredByLocalIntent)
        .arg(s.startSkewMs)
        .arg(s.trustedClockShare, 0, 'f', 2);
}

void SyncTelemetry::reset()
{
    samples_.clear();
    startSkewsMs_.clear();
    seeks_ = nudges_ = holdsInGate_ = staleDropped_ = deferredByLocalIntent_ = 0;
    trustedClockSamples_ = 0;
}
