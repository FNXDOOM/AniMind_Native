#include "clock_estimator.h"

#include <QElapsedTimer>

#include <algorithm>

qint64 monotonicMs()
{
    // QueryPerformanceCounter on Windows: unmoved by wall-clock corrections and resumes.
    static const QElapsedTimer clock = [] {
        QElapsedTimer timer;
        timer.start();
        return timer;
    }();
    return clock.elapsed();
}

qint64 ClockEstimator::Sample::offsetMs() const
{
    // Legs cancel on a symmetric path, leaving the clock difference; asymmetry survives averaging.
    return ((serverReceiveMs - clientSendMs) + (serverSendMs - clientReceiveMs)) / 2;
}

qint64 ClockEstimator::Sample::rttMs() const
{
    return (clientReceiveMs - clientSendMs) - (serverSendMs - serverReceiveMs);
}

static qint64 medianOf(QVector<qint64> values)
{
    if (values.isEmpty())
        return 0;
    std::sort(values.begin(), values.end());
    const int middle = values.size() / 2;
    if (values.size() % 2 == 0)
        return (values.at(middle - 1) + values.at(middle)) / 2;
    return values.at(middle);
}

qint64 ClockEstimator::medianOffset(const QVector<Timed>& pool)
{
    QVector<qint64> offsets;
    offsets.reserve(pool.size());
    for (const auto& sample : pool)
        offsets.append(sample.offsetMs());
    return medianOf(offsets);
}

auto ClockEstimator::fresh(qint64 nowMonoMs) const -> QVector<Timed>
{
    QVector<Timed> out;
    out.reserve(samples_.size());
    for (const auto& sample : samples_) {
        if (nowMonoMs - sample.takenMonoMs <= options_.maxAgeMs)
            out.append(sample);
    }
    return out;
}

void ClockEstimator::clear()
{
    samples_.clear();
    committed_ = false;
    committedOffsetMs_ = 0;
}

void ClockEstimator::addSample(const Sample& sample, qint64 nowMonoMs)
{
    if (sample.clientSendMs <= 0 || sample.clientReceiveMs < sample.clientSendMs)
        return;

    Timed entry;
    static_cast<Sample&>(entry) = sample;
    entry.takenMonoMs = nowMonoMs;

    if (entry.rttMs() < 0) {
        // A negative round trip is a clock that moved mid-exchange, so the whole window is stale.
        clear();
        stepDetected_ = true;
        return;
    }

    samples_.append(entry);
    while (samples_.size() > options_.window)
        samples_.removeAt(0);

    const QVector<Timed> candidates = fresh(nowMonoMs);
    if (candidates.isEmpty())
        return;

    // Median of the lowest-RTT half: averaging the congested half drags the estimate around.
    QVector<Timed> best = candidates;
    std::sort(best.begin(), best.end(), [](const Timed& a, const Timed& b) {
        return a.rttMs() < b.rttMs();
    });
    best.resize(std::max<qsizetype>(1, (best.size() + 1) / 2));
    const qint64 estimate = medianOffset(best);

    if (!committed_ || qAbs(estimate - committedOffsetMs_) >= options_.deadbandMs) {
        committedOffsetMs_ = estimate;
        committed_ = true;
    }
}

ClockEstimator::Confidence ClockEstimator::confidence(qint64 nowMonoMs) const
{
    const int count = freshCount(nowMonoMs);
    if (count == 0 || !committed_)
        return Confidence::Unknown;
    if (count < options_.minTrusted)
        return Confidence::Seeded;
    return Confidence::Trusted;
}

int ClockEstimator::freshCount(qint64 nowMonoMs) const
{
    int count = 0;
    for (const auto& sample : samples_) {
        if (nowMonoMs - sample.takenMonoMs <= options_.maxAgeMs)
            ++count;
    }
    return count;
}

qint64 ClockEstimator::ageMs(qint64 nowMonoMs) const
{
    if (samples_.isEmpty())
        return -1;
    return nowMonoMs - samples_.last().takenMonoMs;
}

qint64 ClockEstimator::bestRttMs(qint64 nowMonoMs) const
{
    const QVector<Timed> candidates = fresh(nowMonoMs);
    if (candidates.isEmpty())
        return -1;
    qint64 lowest = candidates.first().rttMs();
    for (const auto& sample : candidates)
        lowest = qMin(lowest, sample.rttMs());
    return lowest;
}

qint64 ClockEstimator::spreadMs(qint64 nowMonoMs) const
{
    const QVector<Timed> candidates = fresh(nowMonoMs);
    if (candidates.size() < 2)
        return -1;
    qint64 lowest = candidates.first().offsetMs();
    qint64 highest = lowest;
    for (const auto& sample : candidates) {
        lowest = qMin(lowest, sample.offsetMs());
        highest = qMax(highest, sample.offsetMs());
    }
    return highest - lowest;
}

qint64 ClockEstimator::medianOffsetMs(qint64 nowMonoMs) const
{
    return medianOffset(fresh(nowMonoMs));
}

qint64 ClockEstimator::localMonoForServerTime(qint64 serverMs, qint64 nowWallMs, qint64 nowMonoMs) const
{
    // With no estimate the hub's instant cannot be placed on this timeline, so the caller acts on
    // receipt. Arming against an unmeasured clock was tried and reverted: far-off peers never
    // reached their own start and the gate reopened around them.
    if (serverMs <= 0 || !committed_)
        return nowMonoMs;
    // Hub instant minus the offset, then carried across as a difference onto the monotonic clock.
    const qint64 target = nowMonoMs + (serverMs - adjustedOffsetMs() - nowWallMs);
    return target > nowMonoMs ? target : nowMonoMs;
}

qint64 ClockEstimator::serverWallMs(qint64 nowWallMs) const
{
    if (!committed_)
        return nowWallMs;
    return nowWallMs + adjustedOffsetMs();
}

qint64 ClockEstimator::nextIntervalMs(qint64 nowMonoMs, bool playing) const
{
    constexpr qint64 greedyMs = 1000;
    constexpr qint64 idlePlayingMs = 15000;
    constexpr qint64 idlePausedMs = 60000;

    if (!committed_ || freshCount(nowMonoMs) < options_.minTrusted)
        return greedyMs;
    // Half the age limit: the estimate is on its way out rather than fresh.
    if (const qint64 age = ageMs(nowMonoMs); age > options_.maxAgeMs / 2)
        return greedyMs;
    return playing ? idlePlayingMs : idlePausedMs;
}

void ClockEstimator::noteClockDomain(qint64 nowWallMs, qint64 nowMonoMs)
{
    if (lastMonoMs_ != 0) {
        const qint64 wallDelta = nowWallMs - lastWallMs_;
        const qint64 monoDelta = nowMonoMs - lastMonoMs_;
        // The clocks advance together to within a scheduling tick; a larger gap means the offset on
        // record was measured against a clock that no longer exists.
        if (qAbs(wallDelta - monoDelta) > 500) {
            clear();
            stepDetected_ = true;
        }
    }
    lastWallMs_ = nowWallMs;
    lastMonoMs_ = nowMonoMs;
}
