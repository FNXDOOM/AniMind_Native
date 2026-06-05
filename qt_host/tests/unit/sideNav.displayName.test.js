/**
 * Unit tests for SideNav DisplayName states
 * Validates: Requirements 5.1, 5.2, 5.3, 5.4
 *
 * Covers the `computeDisplayName(email, userId, authenticated)` pure function
 * extracted inline from main.qml's root context, which drives the userNameText
 * binding in SideNav.qml.
 */

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

// ── Tests ────────────────────────────────────────────────────────────────────

describe("computeDisplayName — SideNav DisplayName states", () => {
  // ── Requirement 5.1: unauthenticated → "Guest" ────────────────────────────

  describe('when not authenticated', () => {
    test('returns "Guest" regardless of email and userId', () => {
      expect(computeDisplayName("user@example.com", "user_abc123", false)).toBe("Guest");
    });

    test('returns "Guest" when email and userId are empty', () => {
      expect(computeDisplayName("", "", false)).toBe("Guest");
    });

    test('returns "Guest" when email and userId are null', () => {
      expect(computeDisplayName(null, null, false)).toBe("Guest");
    });

    test('returns "Guest" even with a valid-looking email', () => {
      expect(computeDisplayName("alice@example.com", "", false)).toBe("Guest");
    });
  });

  // ── Requirement 5.2: email local-part derivation ─────────────────────────

  describe('when authenticated with a valid email', () => {
    test('returns the local-part before "@"', () => {
      expect(computeDisplayName("alice@example.com", "", true)).toBe("alice");
    });

    test('returns local-part for a simple username', () => {
      expect(computeDisplayName("bob@mail.org", "user_xyz", true)).toBe("bob");
    });

    test('prefers email local-part over userId when email is valid', () => {
      expect(computeDisplayName("carol@domain.com", "user_carol123", true)).toBe("carol");
    });

    test('returns local-part that is exactly 16 chars without truncation', () => {
      // "abcdefghijklmnop" is exactly 16 chars
      expect(computeDisplayName("abcdefghijklmnop@x.com", "", true)).toBe("abcdefghijklmnop");
    });

    // ── Requirement 5.2 truncation ────────────────────────────────────────

    test('truncates local-part to 16 chars and appends "…" when longer', () => {
      // 17-char local-part → first 16 + ellipsis
      expect(computeDisplayName("abcdefghijklmnopq@example.com", "", true))
        .toBe("abcdefghijklmnop\u2026");
    });

    test('truncates a very long local-part correctly', () => {
      const longLocal = "averylongemailaddress";
      expect(computeDisplayName(longLocal + "@x.com", "", true))
        .toBe(longLocal.substring(0, 16) + "\u2026");
    });

    test('truncated result has length 17 (16 chars + ellipsis char)', () => {
      const result = computeDisplayName("toolonglocalpart1@example.com", "", true);
      // \u2026 is a single character
      expect(result.length).toBe(17);
      expect(result[16]).toBe("\u2026");
    });
  });

  // ── Requirement 5.3: userId fallback with user_ prefix stripping ──────────

  describe('when authenticated and email has no "@"', () => {
    test('falls back to userId when email has no "@"', () => {
      expect(computeDisplayName("notanemail", "johndoe", true)).toBe("johndoe");
    });

    test('strips "user_" prefix from userId', () => {
      expect(computeDisplayName("", "user_alice", true)).toBe("alice");
    });

    test('strips "user_" prefix from userId when email is null', () => {
      expect(computeDisplayName(null, "user_bob", true)).toBe("bob");
    });

    test('does not strip prefix when userId does not start with "user_"', () => {
      expect(computeDisplayName("", "alice123", true)).toBe("alice123");
    });

    test('does not strip a "user" prefix that lacks underscore', () => {
      expect(computeDisplayName("", "useralice", true)).toBe("useralice");
    });

    test('strips only the leading "user_" prefix, not any later occurrence', () => {
      expect(computeDisplayName("", "user_user_nested", true)).toBe("user_nested");
    });

    // ── Requirement 5.3 truncation ────────────────────────────────────────

    test('truncates userId to 16 chars and appends "…" when stripped value exceeds 16', () => {
      // "user_" + 17-char suffix → strip prefix → 17 chars → truncate
      expect(computeDisplayName("", "user_abcdefghijklmnopq", true))
        .toBe("abcdefghijklmnop\u2026");
    });

    test('truncates raw userId (no prefix) to 16 chars with "…"', () => {
      expect(computeDisplayName("", "verylongusernamethatexceeds", true))
        .toBe("verylongusername\u2026");
    });

    test('userId of exactly 16 chars (after prefix strip) is not truncated', () => {
      expect(computeDisplayName("", "user_abcdefghijklmnop", true))
        .toBe("abcdefghijklmnop");
    });

    test('falls back to userId when email has an empty local-part ("@domain")', () => {
      expect(computeDisplayName("@example.com", "user_charlie", true)).toBe("charlie");
    });
  });

  // ── Requirement 5.4: "User" fallback when all inputs are empty ─────────────

  describe('when authenticated but email and userId are both empty/absent', () => {
    test('returns "User" when email and userId are both empty strings', () => {
      expect(computeDisplayName("", "", true)).toBe("User");
    });

    test('returns "User" when email and userId are both null', () => {
      expect(computeDisplayName(null, null, true)).toBe("User");
    });

    test('returns "User" when email and userId are both undefined', () => {
      expect(computeDisplayName(undefined, undefined, true)).toBe("User");
    });

    test('returns "User" when email has empty local-part and userId is empty', () => {
      expect(computeDisplayName("@example.com", "", true)).toBe("User");
    });

    test('returns "User" when email has no "@" and userId is empty', () => {
      expect(computeDisplayName("notanemail", "", true)).toBe("User");
    });
  });
});
