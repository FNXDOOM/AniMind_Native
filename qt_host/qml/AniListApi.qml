pragma Singleton
import QtQuick

// AniListApi — thin GraphQL client for https://graphql.anilist.co
// All methods are async; they accept a callback: function(data, error)
//   data  : parsed JS object on success
//   error : string on failure, null on success
//
// Usage:
//   AniListApi.trendingAnime(10, function(list, err) { ... })
//   AniListApi.searchAnime({ genre: "Action", sort: "SCORE_DESC", page: 1, perPage: 20 }, cb)
//   AniListApi.animeDetail(21, cb)
//   AniListApi.seasonalAnime("FALL", 2024, 20, cb)

QtObject {
    id: api

    readonly property string endpoint: "https://graphql.anilist.co"

    // ── Low-level GraphQL POST ─────────────────────────────────────────────
    function query(gql, variables, callback) {
        console.log("[AniListApi] Starting query to " + api.endpoint)
        var xhr = new XMLHttpRequest()
        var finished = false
        function done(data, err) {
            if (finished) return
            finished = true
            if (err) {
                console.log("[AniListApi] Error: " + err)
            } else {
                console.log("[AniListApi] Success, got data")
            }
            callback(data, err)
        }
        xhr.open("POST", api.endpoint, true)
        console.log("[AniListApi] xhr.open complete")
        xhr.setRequestHeader("Content-Type",  "application/json")
        xhr.setRequestHeader("Accept",        "application/json")
        xhr.timeout = 15000

        xhr.onreadystatechange = function() {
            console.log("[AniListApi] readyState: " + xhr.readyState + ", status: " + xhr.status)
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    var json = JSON.parse(xhr.responseText)
                    if (json.errors && json.errors.length > 0) {
                        done(null, json.errors[0].message)
                    } else {
                        done(json.data, null)
                    }
                } catch(e) {
                    done(null, "JSON parse error: " + e)
                }
            } else {
                var msg = "HTTP " + xhr.status + ": " + xhr.statusText
                try {
                    if (xhr.responseText && xhr.responseText.length > 0) {
                        var body = JSON.parse(xhr.responseText)
                        if (body.errors && body.errors.length > 0 && body.errors[0].message)
                            msg += " - " + body.errors[0].message
                    }
                } catch (_) {}
                done(null, msg)
            }
        }
        xhr.onerror = function() {
            console.log("[AniListApi] xhr.onerror fired")
            done(null, "Network error while contacting AniList")
        }
        xhr.ontimeout = function() {
            console.log("[AniListApi] xhr.ontimeout fired")
            done(null, "AniList request timed out")
        }

        console.log("[AniListApi] About to send POST with " + gql.length + " chars of query")
        xhr.send(JSON.stringify({ query: gql, variables: variables || {} }))
        return xhr
    }

    // ── Shared fragment — all fields a page card needs ─────────────────────
    readonly property string mediaFragment: "
        fragment MediaCard on Media {
            id
            title { romaji english native }
            coverImage { large extraLarge color }
            bannerImage
            averageScore
            meanScore
            genres
            episodes
            status
            season
            seasonYear
            format
            studios(isMain: true) { nodes { name } }
            description(asHtml: false)
            trailer { id site }
            nextAiringEpisode { episode timeUntilAiring }
            popularity
            trending
        }
    "

    // ── Trending anime (for Home hero + trending row) ──────────────────────
    // Returns array of media objects
    function trendingAnime(perPage, callback) {
        var gql = mediaFragment + "
            query Trending($perPage: Int) {
                Page(page: 1, perPage: $perPage) {
                    media(sort: TRENDING_DESC, type: ANIME, isAdult: false) {
                        ...MediaCard
                    }
                }
            }
        "
        query(gql, { perPage: perPage || 10 }, function(data, err) {
            if (err) { callback([], err); return }
            callback(data.Page.media, null)
        })
    }

    // ── Recently updated / airing (for Continue Watching row) ─────────────
    // Returns array of media objects currently airing
    function airingNow(perPage, callback) {
        var gql = mediaFragment + "
            query Airing($perPage: Int) {
                Page(page: 1, perPage: $perPage) {
                    media(status: RELEASING, sort: POPULARITY_DESC, type: ANIME, isAdult: false) {
                        ...MediaCard
                    }
                }
            }
        "
        query(gql, { perPage: perPage || 10 }, function(data, err) {
            if (err) { callback([], err); return }
            callback(data.Page.media, null)
        })
    }

    // ── Browse / search with filters ──────────────────────────────────────
    // opts: { genre, sort, page, perPage, search, season, seasonYear, minScore }
    // sort values: TRENDING_DESC | POPULARITY_DESC | SCORE_DESC | START_DATE_DESC | TITLE_ROMAJI
    function searchAnime(opts, callback) {
        var gql = mediaFragment + "
            query Search(
                $page: Int, $perPage: Int,
                $search: String,
                $genre: String,
                $sort: [MediaSort],
                $season: MediaSeason,
                $seasonYear: Int,
                $averageScore_greater: Int
            ) {
                Page(page: $page, perPage: $perPage) {
                    pageInfo { total currentPage lastPage hasNextPage }
                    media(
                        type: ANIME,
                        isAdult: false,
                        search: $search,
                        genre: $genre,
                        sort: $sort,
                        season: $season,
                        seasonYear: $seasonYear,
                        averageScore_greater: $averageScore_greater
                    ) {
                        ...MediaCard
                    }
                }
            }
        "

        // Map sort index → AniList sort enum
        var sortMap = ["TRENDING_DESC", "POPULARITY_DESC", "START_DATE_DESC", "SCORE_DESC", "TITLE_ROMAJI"]
        var sortEnum = sortMap[opts.sort || 0] || "TRENDING_DESC"

        // Map rating filter → score threshold
        var scoreMap = { "9.0+": 89, "8.0+": 79, "7.0+": 69 }
        var minScore = opts.minScore ? scoreMap[opts.minScore] : undefined

        var vars = {
            page:    opts.page    || 1,
            perPage: opts.perPage || 20,
            sort:    [sortEnum]
        }
        if (opts.search  && opts.search  !== "")  vars.search       = opts.search
        if (opts.genre   && opts.genre   !== "" && opts.genre !== "All Genres") vars.genre = opts.genre
        if (opts.season  && opts.season  !== "")  vars.season       = opts.season
        if (opts.seasonYear)                       vars.seasonYear   = opts.seasonYear
        if (minScore !== undefined)                vars.averageScore_greater = minScore

        query(gql, vars, function(data, err) {
            if (err) { callback([], null, err); return }
            callback(data.Page.media, data.Page.pageInfo, null)
        })
    }

    // ── Single anime detail (for Series Detail page) ──────────────────────
    function animeDetail(anilistId, callback) {
        var gql = "
            query Detail($id: Int) {
                Media(id: $id, type: ANIME) {
                    id
                    title { romaji english native }
                    coverImage { large extraLarge color }
                    bannerImage
                    averageScore
                    meanScore
                    genres
                    episodes
                    duration
                    status
                    season
                    seasonYear
                    format
                    source
                    studios(isMain: true) { nodes { name } }
                    description(asHtml: false)
                    trailer { id site }
                    nextAiringEpisode { episode timeUntilAiring }
                    popularity
                    trending
                    streamingEpisodes {
                        title
                        thumbnail
                        url
                        site
                    }
                    characters(sort: ROLE, role: MAIN, page: 1, perPage: 6) {
                        nodes {
                            name { full }
                            image { medium }
                        }
                    }
                    relations {
                        edges {
                            relationType
                            node {
                                id
                                title { romaji }
                                coverImage { medium }
                                type
                            }
                        }
                    }
                    recommendations(page: 1, perPage: 12, sort: RATING_DESC) {
                        nodes {
                            rating
                            mediaRecommendation {
                                id
                                title { romaji english native }
                                type
                            }
                        }
                    }
                }
            }
        "
        query(gql, { id: anilistId }, function(data, err) {
            if (err) { callback(null, err); return }
            callback(data.Media, null)
        })
    }

    // ── Seasonal anime (kept for future use, NOT used on Simulcasts tab) ──
    function seasonalAnime(season, year, perPage, callback) {
        var gql = mediaFragment + "
            query Seasonal($season: MediaSeason, $year: Int, $perPage: Int) {
                Page(page: 1, perPage: $perPage) {
                    media(
                        type: ANIME, isAdult: false,
                        season: $season, seasonYear: $year,
                        sort: POPULARITY_DESC
                    ) {
                        ...MediaCard
                    }
                }
            }
        "
        query(gql, { season: season, year: year, perPage: perPage || 20 }, function(data, err) {
            if (err) { callback([], err); return }
            callback(data.Page.media, null)
        })
    }

    // ── Helpers ────────────────────────────────────────────────────────────

    // Best display title: prefer English, fall back to romaji
    function title(media) {
        if (!media || !media.title) return "Unknown"
        return media.title.english || media.title.romaji || media.title.native || "Unknown"
    }

    // Score: AniList returns 0–100, show as X.X / 10
    function score(media) {
        var s = media.averageScore || media.meanScore || 0
        if (s === 0) return ""
        return (s / 10).toFixed(1)
    }

    // Cover image URL: extraLarge preferred, fall back to large
    function cover(media) {
        if (!media || !media.coverImage) return ""
        return media.coverImage.extraLarge || media.coverImage.large || ""
    }

    // Audio label: AniList doesn't expose dub data directly — default to Sub
    function audioLabel(media) {
        return "Sub"   // extend later with a dub-tracking API
    }

    // Format label (TV, MOVIE, OVA …)
    function formatLabel(media) {
        if (!media) return ""
        var f = media.format || ""
        var map = { "TV": "TV", "TV_SHORT": "TV Short", "MOVIE": "Movie",
                    "OVA": "OVA", "ONA": "ONA", "SPECIAL": "Special", "MUSIC": "Music" }
        return map[f] || f
    }

    // Status label
    function statusLabel(media) {
        if (!media) return ""
        var map = { "FINISHED": "Finished", "RELEASING": "Airing",
                    "NOT_YET_RELEASED": "Upcoming", "CANCELLED": "Cancelled", "HIATUS": "On Hiatus" }
        return map[media.status] || media.status || ""
    }

    // Has new episode airing soon (within 7 days)
    function isNewEpisode(media) {
        if (!media || !media.nextAiringEpisode) return false
        return media.nextAiringEpisode.timeUntilAiring < 7 * 24 * 3600
    }

    // Primary studio name
    function studio(media) {
        if (!media || !media.studios || !media.studios.nodes || media.studios.nodes.length === 0) return ""
        return media.studios.nodes[0].name
    }

    // Clean description — strip newline escapes
    function cleanDesc(media) {
        if (!media || !media.description) return ""
        return media.description.replace(/\n/g, " ").replace(/<[^>]+>/g, "").trim()
    }

    // Genre list as comma string
    function genreString(media) {
        if (!media || !media.genres) return ""
        return media.genres.slice(0, 3).join(" · ")
    }
}
