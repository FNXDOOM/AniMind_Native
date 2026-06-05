/**
 * Property-Based Test for TopBar avatar initial
 * Feature: desktop-player-enhancements, Property 11: TopBar avatar initial always matches SideNav DisplayName
 *
 * Validates: Requirements 6.1, 6.2, 6.3, 6.4
 *
 * Uses fast-check to generate arbitrary (email, userId, authenticated) triples
 * and asserts the avatar initial invariant for ≥ 100 iterations.
 */

// Feature: desktop-player-enhancements, Property 11: TopBar avatar initial always matches SideNav DisplayName

"use strict";

const fc = require("fast-check");

// ── Inline the pure JS logic from main.qml's computeDisplayName ──────────────

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

// ── Inline the pure JS logic from TopBar.qml (design section 6.6) ────────────

function computeAvatarInitial(email, userId, authenticated) {
  if (!authenticated) return "?";
  var dn = computeDisplayName(email, userId, authenticated);
  if (dn === "Guest" || dn === "User") return "?";
  return dn.charAt(0).toUpperCase();
}

// ── Arbitraries ───────────────────────────────────────────────────────────────

/** Email with a non-empty local-part and an @ separator */
const validEmailArb = fc
  .tuple(
    fc.string({ minLength: 1, maxLength: 30 }).filter((s) => !s.includes("@")),
    fc.string({ minLength: 1, maxLength: 20 }).filter((s) => !s.includes("@"))
  )
  .map(([local, domain]) => `${local}@${domain}`);

/** Email with an empty local-part: "@domain" */
const emptyLocalEmailArb = fc
  .string({ minLength: 1, maxLength: 20 })
  .filter((s) => !s.includes("@"))
  .map((domain) => `@${domain}`);

/** String with no @ (or empty / null) — falls through to userId branch */
const noAtEmailArb = fc.oneof(
  fc.constant(""),
  fc.constant(null),
  fc.string({ minLength: 1, maxLength: 30 }).filter((s) => !s.includes("@"))
);

/** Arbitrary non-empty userId */
const nonEmptyUserIdArb = fc.string({ minLength: 1, maxLength: 40 });

/** Any email (valid, empty-local, or no-@) */
const anyEmailArb = fc.oneof(validEmailArb, emptyLocalEmailArb, noAtEmailArb);

/** Any userId (non-empty string or empty/null) */
const anyUserIdArb = fc.oneof(
  nonEmptyUserIdArb,
  fc.constant(""),
  fc.constant(null)
);

// ── Property Tests ────────────────────────────────────────────────────────────

describe(
  "computeAvatarInitial — Property 11: TopBar avatar initial always matches SideNav DisplayName",
  () => {
    // ── Core invariant: initial always matches displayName or is "?" ──────────
    test(
      'Property 11 — avatar initial equals displayName.charAt(0).toUpperCase() or "?" for any (email, userId, authenticated)',
      () => {
        fc.assert(
          fc.property(anyEmailArb, anyUserIdArb, fc.boolean(), (email, userId, authenticated) => {
            const initial = computeAvatarInitial(email, userId, authenticated);
            const dn = computeDisplayName(email, userId, authenticated);

            if (!authenticated || dn === "Guest" || dn === "User") {
              // Must be "?"
              return initial === "?";
            }
            // Must be the uppercased first character of the display name
            return initial === dn.charAt(0).toUpperCase();
          }),
          { numRuns: 100 }
        );
      }
    );

    // ── Unauthenticated always yields "?" (Requirement 6.1) ──────────────────
    test(
      'Property 11.1 — returns "?" for any input when authenticated is false',
      () => {
        fc.assert(
          fc.property(
            fc.option(fc.string(), { nil: null }),
            fc.option(fc.string(), { nil: null }),
            (email, userId) => {
              return computeAvatarInitial(email, userId, false) === "?";
            }
          ),
          { numRuns: 100 }
        );
      }
    );

    // ── Valid email → initial matches email local-part first char (Requirement 6.2) ─
    test(
      "Property 11.2 — returns uppercased first char of email local-part when authenticated with valid email",
      () => {
        fc.assert(
          fc.property(
            validEmailArb,
            fc.option(fc.string(), { nil: null }),
            (email, userId) => {
              const local = email.substring(0, email.indexOf("@"));
              const truncated = local.length > 16 ? local.substring(0, 16) + "\u2026" : local;
              const expected = truncated.charAt(0).toUpperCase();
              return computeAvatarInitial(email, userId, true) === expected;
            }
          ),
          { numRuns: 100 }
        );
      }
    );

    // ── No valid email + non-empty userId → initial from userId (Requirement 6.3) ──
    test(
      "Property 11.3 — returns uppercased first char of stripped userId when authenticated, no valid email, non-empty userId",
      () => {
        fc.assert(
          fc.property(
            fc.oneof(noAtEmailArb, emptyLocalEmailArb),
            nonEmptyUserIdArb,
            (email, userId) => {
              const stripped = userId.startsWith("user_") ? userId.substring(5) : userId;
              if (stripped.length === 0) {
                // Edge: stripping "user_" yielded an empty string → display name is "User" → "?"
                return computeAvatarInitial(email, userId, true) === "?";
              }
              const truncated = stripped.length > 16 ? stripped.substring(0, 16) + "\u2026" : stripped;
              const expected = truncated.charAt(0).toUpperCase();
              return computeAvatarInitial(email, userId, true) === expected;
            }
          ),
          { numRuns: 100 }
        );
      }
    );

    // ── Authenticated but both email and userId empty/absent → "?" (Requirement 6.4) ─
    test(
      'Property 11.4 — returns "?" when authenticated but no email and no userId (display name is "User")',
      () => {
        fc.assert(
          fc.property(
            fc.oneof(noAtEmailArb, emptyLocalEmailArb),
            fc.oneof(fc.constant(""), fc.constant(null), fc.constant(undefined)),
            (email, userId) => {
              return computeAvatarInitial(email, userId, true) === "?";
            }
          ),
          { numRuns: 100 }
        );
      }
    );
  }
);
