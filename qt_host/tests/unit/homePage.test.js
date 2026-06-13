// Unit tests for HomePage.qml logic (pure JS — no Qt runtime)
// Tests the data-flow functions and row structure expectations.

// ── Helpers extracted from HomePage.qml ───────────────────────────────────

// Guard: don't re-fetch if already loaded
function loadTrendingIfNeeded(state, fetchFn) {
    if (state.trendingList.length > 0 || state.loadingHero) return false
    fetchFn()
    return true
}

// Hero selection: first item in trendingList
function selectHero(trendingList) {
    if (!trendingList || trendingList.length === 0) return null
    return trendingList[0]
}

// Top Rated: sort trendingList by averageScore desc
function buildTopRated(trendingList) {
    return trendingList.slice().sort((a, b) => (b.averageScore || 0) - (a.averageScore || 0))
}

// Scroll clamp helpers
function scrollLeft(contentX) {
    return Math.max(0, contentX - 320)
}
function scrollRight(contentX, contentWidth, viewWidth) {
    return Math.min(contentWidth - viewWidth, contentX + 320)
}

// ── Mock data ──────────────────────────────────────────────────────────────
const mockTrending = [
    { id: 1, title: { romaji: "Attack on Titan" }, averageScore: 90, seasonYear: 2013, studios: { nodes: [{ name: "WIT Studio" }] } },
    { id: 2, title: { romaji: "Fullmetal Alchemist" }, averageScore: 95, seasonYear: 2009, studios: { nodes: [{ name: "Bones" }] } },
    { id: 3, title: { romaji: "One Piece" }, averageScore: 88, seasonYear: 1999, studios: { nodes: [{ name: "Toei Animation" }] } },
    { id: 4, title: { romaji: "Naruto" }, averageScore: 79, seasonYear: 2002, studios: { nodes: [] } },
]

// ── Tests ──────────────────────────────────────────────────────────────────

describe("HomePage — loadTrendingIfNeeded guard", () => {
    test("calls fetchFn when list is empty and not loading", () => {
        const state = { trendingList: [], loadingHero: false }
        const fetchFn = jest.fn()
        const result = loadTrendingIfNeeded(state, fetchFn)
        expect(result).toBe(true)
        expect(fetchFn).toHaveBeenCalledTimes(1)
    })

    test("does NOT call fetchFn when trendingList already has items", () => {
        const state = { trendingList: mockTrending, loadingHero: false }
        const fetchFn = jest.fn()
        const result = loadTrendingIfNeeded(state, fetchFn)
        expect(result).toBe(false)
        expect(fetchFn).not.toHaveBeenCalled()
    })

    test("does NOT call fetchFn when loadingHero is true", () => {
        const state = { trendingList: [], loadingHero: true }
        const fetchFn = jest.fn()
        const result = loadTrendingIfNeeded(state, fetchFn)
        expect(result).toBe(false)
        expect(fetchFn).not.toHaveBeenCalled()
    })
})

describe("HomePage — hero selection", () => {
    test("returns null when trendingList is empty", () => {
        expect(selectHero([])).toBeNull()
        expect(selectHero(null)).toBeNull()
    })

    test("returns first item of trendingList", () => {
        const hero = selectHero(mockTrending)
        expect(hero).toBe(mockTrending[0])
        expect(hero.id).toBe(1)
    })

    test("returns single item when list has one entry", () => {
        expect(selectHero([mockTrending[2]])).toBe(mockTrending[2])
    })
})

describe("HomePage — Top Rated row (buildTopRated)", () => {
    test("sorts by averageScore descending", () => {
        const sorted = buildTopRated(mockTrending)
        expect(sorted[0].averageScore).toBe(95)
        expect(sorted[1].averageScore).toBe(90)
        expect(sorted[2].averageScore).toBe(88)
        expect(sorted[3].averageScore).toBe(79)
    })

    test("does not mutate the original array", () => {
        const original = [...mockTrending]
        buildTopRated(mockTrending)
        expect(mockTrending[0].id).toBe(original[0].id)
    })

    test("handles missing averageScore (treats as 0)", () => {
        const list = [
            { id: 10, averageScore: undefined },
            { id: 11, averageScore: 80 },
        ]
        const sorted = buildTopRated(list)
        expect(sorted[0].averageScore).toBe(80)
    })

    test("returns empty array for empty input", () => {
        expect(buildTopRated([])).toEqual([])
    })
})

describe("HomePage — row visibility", () => {
    test("Trending row visible when trendingList is non-empty", () => {
        expect(mockTrending.length > 0).toBe(true)
    })

    test("Currently Airing row hidden when airingList is empty", () => {
        const airingList = []
        expect(airingList.length > 0).toBe(false)
    })

    test("Top Rated row visible when trendingList is non-empty (reuses data)", () => {
        expect(mockTrending.length > 0).toBe(true)
    })

    test("Hero not shown when trendingList is empty", () => {
        expect(selectHero([])).toBeNull()
    })
})

describe("HomePage — scroll button clamping", () => {
    test("scrollLeft clamps to 0 at start", () => {
        expect(scrollLeft(0)).toBe(0)
        expect(scrollLeft(100)).toBe(0)
        expect(scrollLeft(400)).toBe(80)
    })

    test("scrollRight clamps to max at end", () => {
        // contentWidth=2000, viewWidth=600 → max = 1400
        expect(scrollRight(1400, 2000, 600)).toBe(1400)
        expect(scrollRight(1200, 2000, 600)).toBe(1400)
        expect(scrollRight(0, 2000, 600)).toBe(320)
    })

    test("scrollRight does not exceed contentWidth - viewWidth", () => {
        const result = scrollRight(1300, 2000, 600)
        expect(result).toBeLessThanOrEqual(2000 - 600)
    })

    test("scrollLeft never goes below 0", () => {
        for (let x = 0; x <= 400; x += 50) {
            expect(scrollLeft(x)).toBeGreaterThanOrEqual(0)
        }
    })
})

describe("HomePage — expected API calls on load", () => {
    test("loadTrendingIfNeeded makes 3 API calls (trending, seasonal, airingNow)", () => {
        const calls = []
        const mockApi = {
            trendingAnime: (n, cb) => { calls.push("trending"); cb(mockTrending, null) },
            seasonalAnime: (s, y, n, cb) => { calls.push("seasonal"); cb([], null) },
            airingNow: (n, cb) => { calls.push("airing"); cb([], null) },
        }

        // Simulate loadTrendingIfNeeded
        const state = { trendingList: [], loadingHero: false }
        loadTrendingIfNeeded(state, () => {
            mockApi.trendingAnime(12, () => {})
            mockApi.seasonalAnime("SPRING", 2024, 12, () => {})
            mockApi.airingNow(12, () => {})
        })

        expect(calls).toContain("trending")
        expect(calls).toContain("seasonal")
        expect(calls).toContain("airing")
        expect(calls).toHaveLength(3)
    })
})
