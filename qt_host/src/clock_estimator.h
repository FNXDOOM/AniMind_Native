#pragma once

#include <QtGlobal>

#include <QVector>

// Monotonic ms; never schedule with the wall clock, because a step mid-episode teleports the group.
qint64 monotonicMs();

// Four-timestamp NTP estimator. Below four stamps, round trip and clock error collapse into one
// number, so a slow link is indistinguishable from a wrong wall clock.
// Keeps the lowest-RTT half of a short window and takes the median of those.
class ClockEstimator
{
public:
    struct Sample
    {
        qint64 clientSendMs = 0;
        qint64 serverReceiveMs = 0;
        qint64 serverSendMs = 0;
        qint64 clientReceiveMs = 0;

        // Server minus client: positive means the hub is ahead, so a hub instant lands lower here.
        qint64 offsetMs() const;
        // Round trip with the hub's own processing time removed.
        qint64 rttMs() const;
    };

    struct Options
    {
        int window = 8;
        // Older than this measured a path that no longer exists: suspended, slept, or re-joined.
        qint64 maxAgeMs = 150000;
        // Inside this the estimate is not news; committing it would re-arm timers already right.
        qint64 deadbandMs = 120;
        // Fewer fresh samples than this and the estimate is a guess.
        int minTrusted = 3;
    };

    enum class Confidence
    {
        Unknown,  // nothing fresh
        Seeded,   // not schedulable
        Trusted,  // safe to arm a start against
    };

    explicit ClockEstimator(Options options = {}) : options_(options) {}

    // The hub can retune a running client; existing samples stay, same path.
    void setOptions(Options options) { options_ = options; }

    void addSample(const Sample& sample, qint64 nowMonoMs);
    void clear();

    Confidence confidence(qint64 nowMonoMs) const;
    qint64 offsetMs() const { return committedOffsetMs_; }
    // The viewer's own correction for a consistently late display pipeline.
    void setExtraOffsetMs(qint64 ms) { extraOffsetMs_ = ms; }
    qint64 extraOffsetMs() const { return extraOffsetMs_; }
    qint64 adjustedOffsetMs() const { return committedOffsetMs_ + extraOffsetMs_; }
    bool hasEstimate() const { return committed_; }

    // Round trip of the clearest path in the window: the latency worth scheduling to.
    qint64 bestRttMs(qint64 nowMonoMs) const;
    // Best-to-worst offset spread in the window: how much the answer is worth.
    qint64 spreadMs(qint64 nowMonoMs) const;
    int freshCount(qint64 nowMonoMs) const;
    qint64 ageMs(qint64 nowMonoMs) const;
    qint64 medianOffsetMs(qint64 nowMonoMs) const;

    // The local monotonic instant for a hub wall-clock instant. Converted by difference, not
    // absolute, so a suspend or a mismatched wall clock cannot move an armed timer.
    qint64 localMonoForServerTime(qint64 serverMs, qint64 nowWallMs, qint64 nowMonoMs) const;
    // The hub's wall clock now; compare only against stamps already in that domain.
    qint64 serverWallMs(qint64 nowWallMs) const;

    // Next probe delay: greedy while young or decaying, relaxed once settled.
    qint64 nextIntervalMs(qint64 nowMonoMs, bool playing) const;

    // Clears the window when wall and monotonic diverge (sync client, resume, manual change);
    // call every tick so armed timers do not inherit the step.
    void noteClockDomain(qint64 nowWallMs, qint64 nowMonoMs);
    bool detectedStep() const { return stepDetected_; }

    int windowSize() const { return samples_.size(); }

private:
    struct Timed : Sample
    {
        qint64 takenMonoMs = 0;
    };

    auto fresh(qint64 nowMonoMs) const -> QVector<Timed>;
    static qint64 medianOffset(const QVector<Timed>& pool);

    Options options_;
    QVector<Timed> samples_;
    qint64 committedOffsetMs_ = 0;
    qint64 extraOffsetMs_ = 0;
    bool committed_ = false;
    qint64 lastWallMs_ = 0;
    qint64 lastMonoMs_ = 0;
    bool stepDetected_ = false;
};

// A group position stamped when its packet arrives and advanced on the monotonic clock. Never
// derive "where the group is" by subtracting two clocks at the moment of the question.
struct GroupAnchor
{
    double positionSeconds = 0.0;
    qint64 takenMonoMs = 0;
    double rate = 1.0;
    bool playing = false;
    // The hub's own stamp for that position, for reporting estimate disagreement.
    qint64 serverTimeMs = 0;
    qint64 seq = 0;

    double projected(qint64 nowMonoMs) const
    {
        if (!playing || takenMonoMs == 0)
            return positionSeconds;
        const double elapsed = double(nowMonoMs - takenMonoMs) / 1000.0;
        return positionSeconds + elapsed * (rate > 0.0 ? rate : 1.0);
    }

    bool valid() const { return takenMonoMs != 0; }
};
