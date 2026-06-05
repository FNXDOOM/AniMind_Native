/**
 * Unit test for AniListApi XHR return value
 * Validates: Requirements 1.2
 *
 * Verifies that the query() function (which backs searchAnime) returns a
 * non-null object that has an `abort` method, so callers like SearchOverlay
 * can cancel in-flight requests.
 */

// ── Inline the pure JS logic extracted from AniListApi.qml's query() ────────

/**
 * Pure-JS equivalent of the query() function in AniListApi.qml.
 * Returns the XHR object so callers can abort the request.
 */
function query(endpoint, gql, variables, callback) {
  var xhr = new XMLHttpRequest();
  var finished = false;

  function done(data, err) {
    if (finished) return;
    finished = true;
    callback(data, err);
  }

  xhr.open("POST", endpoint, true);
  xhr.setRequestHeader("Content-Type", "application/json");
  xhr.setRequestHeader("Accept", "application/json");
  xhr.timeout = 15000;

  xhr.onreadystatechange = function () {
    if (xhr.readyState !== 4 /* DONE */) return;
    if (xhr.status === 200) {
      try {
        var json = JSON.parse(xhr.responseText);
        if (json.errors && json.errors.length > 0) {
          done(null, json.errors[0].message);
        } else {
          done(json.data, null);
        }
      } catch (e) {
        done(null, "JSON parse error: " + e);
      }
    } else {
      done(null, "HTTP " + xhr.status + ": " + xhr.statusText);
    }
  };

  xhr.onerror = function () {
    done(null, "Network error while contacting AniList");
  };

  xhr.ontimeout = function () {
    done(null, "AniList request timed out");
  };

  xhr.send(JSON.stringify({ query: gql, variables: variables || {} }));
  return xhr;
}

/**
 * Simplified searchAnime() that mirrors AniListApi.qml's implementation.
 * Returns whatever query() returns (the XHR object).
 */
function searchAnime(opts, callback) {
  var gql = "query Search($search: String) { Page { media(search: $search) { id } } }";

  var vars = {
    page: opts.page || 1,
    perPage: opts.perPage || 20,
  };
  if (opts.search && opts.search !== "") vars.search = opts.search;

  return query("https://graphql.anilist.co", gql, vars, function (data, err) {
    if (err) {
      callback([], null, err);
      return;
    }
    callback(data.Page.media, data.Page.pageInfo, null);
  });
}

// ── Tests ────────────────────────────────────────────────────────────────────

describe("AniListApi.searchAnime — XHR return value (Requirement 1.2)", () => {
  let originalXHR;

  beforeEach(() => {
    // Save any real XMLHttpRequest (undefined in Node, but be safe)
    originalXHR = global.XMLHttpRequest;

    // Mock XMLHttpRequest with a minimal but real abort method
    global.XMLHttpRequest = jest.fn().mockImplementation(() => ({
      open: jest.fn(),
      setRequestHeader: jest.fn(),
      send: jest.fn(),
      abort: jest.fn(),
      readyState: 1,
      status: 0,
      responseText: "",
      statusText: "",
      timeout: 0,
      onreadystatechange: null,
      onerror: null,
      ontimeout: null,
    }));
  });

  afterEach(() => {
    global.XMLHttpRequest = originalXHR;
    jest.clearAllMocks();
  });

  test("returns a non-null value", () => {
    const cb = jest.fn();
    const result = searchAnime({ search: "Naruto" }, cb);
    expect(result).not.toBeNull();
    expect(result).not.toBeUndefined();
  });

  test("returned value has an abort method", () => {
    const cb = jest.fn();
    const result = searchAnime({ search: "Naruto" }, cb);
    expect(typeof result.abort).toBe("function");
  });

  test("abort method is callable without throwing", () => {
    const cb = jest.fn();
    const result = searchAnime({ search: "Naruto" }, cb);
    expect(() => result.abort()).not.toThrow();
  });

  test("returns a non-null value even when opts has no search term", () => {
    const cb = jest.fn();
    const result = searchAnime({}, cb);
    expect(result).not.toBeNull();
    expect(typeof result.abort).toBe("function");
  });

  test("each call returns an independent XHR object", () => {
    const cb = jest.fn();
    const result1 = searchAnime({ search: "Naruto" }, cb);
    const result2 = searchAnime({ search: "Bleach" }, cb);
    // Both must be non-null with abort
    expect(result1).not.toBeNull();
    expect(result2).not.toBeNull();
    expect(typeof result1.abort).toBe("function");
    expect(typeof result2.abort).toBe("function");
    // They should be different XHR instances
    expect(result1).not.toBe(result2);
  });
});
