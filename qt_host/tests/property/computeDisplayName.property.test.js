/**
 * Property-Based Test for computeDisplayName
 * Feature: desktop-player-enhancements, Property 10: DisplayName derivation is correct for any email/userId combination
 *
 * Validates: Requirements 5.1, 5.2, 5.3, 5.4
 *
 * Uses fast-check to generate arbitrary (email, userId, authenticated) triples
 * and asserts each of the four branches for ≥ 100 iterations.
 */

// Feature: desktop-player-enhancements, Property 10: DisplayName derivation is correct for any email/userId combination

const fc = require("fast-check");

// ── Inline the pure JS logic from main.qml's computeDisplayName ─────────────

function computeDisplayName(email, userId, authenticated) {
  if (!authenticated) return "Guest";
  if (email && email.indexOf("@") !== -1) {
    var local = email.substring(0, email.indexOf("@"));
    if (local.length === 0) {
      // fall through to userId logic
    } else {
      return local.length > 16 ? local.substring(0, 16) + "\u2026" : local;
    }
  }
  if (userId && userId.length > 0) {
    var s = userId.startsWith("user_") ? userId.substring(5) : userId;
    return s.length > 16 ? s.substring(0, 16) + "\u2026" : s;
  }
  return "User";
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/** Truncate a string to 16 chars, appending … if longer */
function truncate16(s) {
  return s.length > 16 ? s.substring(0, 16) + "\u2026" : s;
}

/** Strip a leading "user_" prefix if present */
function stripUserPrefix(s) {
  return s.startsWith("user_") ? s.substring(5) : s;
}

// ── Arbitraries ──────────────────────────────────────────────────────────────

/**
 * Generates an email string guaranteed to have '@' and a non-empty local-part.
 * local-part: 1–30 printable ASCII chars (no '@')
 * domain:     1–20 printable ASCII chars (no '@')
 */
const validEmailArb = fc
  .tuple(
    fc.string({ minLength: 1, maxLength: 30 }).filter((s) => !s.includes("@")),
    fc.string({ minLength: 1, maxLength: 20 }).filter((s) => !s.includes("@"))
  )
  .map(([local, domain]) => `${local}@${domain}`);

/**
 * Generates a string with no '@' character (or empty), to represent
 * emails that should fall through to the userId branch.
 */
const noAtEmailArb = fc.oneof(
  fc.constant(""),
  fc.constant(null),
  fc.string({ minLength: 1, maxLength: 30 }).filter((s) => !s.includes("@"))
);

/**
 * Generates an email where the local-part is empty: "@domain"
 */
const emptyLocalEmailArb = fc
  .string({ minLength: 1, maxLength: 20 })
  .filter((s) => !s.includes("@"))
  .map((domain) => `@${domain}`);

/**
 * Generates a non-empty userId string (with or without "user_" prefix).
 */
const nonEmptyUserIdArb = fc.string({ minLength: 1, maxLength: 40 });

// ── Property Tests ────────────────────────────────────────────────────────────

describe('computeDisplayName — Property 10: DisplayName derivation is correct for any email/userId combination', () => {
  // ── Branch 1: unauthenticated → always "Guest" (Requirement 5.1) ──────────
  test(
    'Property 10.1 — returns "Guest" for any input when authenticated is false',
    () => {
      fc.assert(
        fc.property(
          fc.option(fc.string(), { nil: null }),  // arbitrary email (or null)
          fc.option(fc.string(), { nil: null }),  // arbitrary userId (or null)
          (email, userId) => {
            const result = computeDisplayName(email, userId, false);
            return result === "Guest";
          }
        ),
        { numRuns: 100 }
      );
    }
  );

  // ── Branch 2: authenticated + valid email with non-empty local-part (Requirement 5.2) ──
  test(
    'Property 10.2 — returns truncated local-part of email when authenticated and email has non-empty local-part',
    () => {
      fc.assert(
        fc.property(
          validEmailArb,
          fc.option(fc.string(), { nil: null }),  // userId is irrelevant for this branch
          (email, userId) => {
            const local = email.substring(0, email.indexOf("@"));
            const expected = truncate16(local);
            const result = computeDisplayName(email, userId, true);
            return result === expected;
          }
        ),
        { numRuns: 100 }
      );
    }
  );

  // ── Branch 3: authenticated + no valid email + non-empty userId (Requirement 5.3) ──
  test(
    'Property 10.3 — returns truncated stripped userId when authenticated, email has no valid local-part, and userId is non-empty',
    () => {
      fc.assert(
        fc.property(
          // Use either: no-@ email, empty-local email, or empty/null email
          fc.oneof(noAtEmailArb, emptyLocalEmailArb),
          nonEmptyUserIdArb,
          (email, userId) => {
            const s = stripUserPrefix(userId);
            const expected = truncate16(s);
            const result = computeDisplayName(email, userId, true);
            return result === expected;
          }
        ),
        { numRuns: 100 }
      );
    }
  );

  // ── Branch 4: authenticated + no valid email + empty/null userId → "User" (Requirement 5.4) ──
  test(
    'Property 10.4 — returns "User" when authenticated but email has no valid local-part and userId is empty or absent',
    () => {
      fc.assert(
        fc.property(
          fc.oneof(noAtEmailArb, emptyLocalEmailArb),
          // userId is empty string, null, or undefined
          fc.oneof(
            fc.constant(""),
            fc.constant(null),
            fc.constant(undefined)
          ),
          (email, userId) => {
            const result = computeDisplayName(email, userId, true);
            return result === "User";
          }
        ),
        { numRuns: 100 }
      );
    }
  );
});
