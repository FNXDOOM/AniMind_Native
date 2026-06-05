/**
 * Unit tests for TopBar avatar initial computation
 * Validates: Requirements 6.1, 6.2, 6.3
 *
 * Both helper functions are inlined from their QML definitions:
 *   - computeDisplayName  (main.qml, design section 6.5)
 *   - computeAvatarInitial (TopBar.qml binding, design section 6.6)
 */

// ── Inline computeDisplayName from main.qml (design section 6.5) ─────────────

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

// ── Inline computeAvatarInitial from TopBar.qml binding (design section 6.6) ─

function computeAvatarInitial(email, userId, authenticated) {
  if (!authenticated) return "?";
  var dn = computeDisplayName(email, userId, authenticated);
  if (dn === "Guest" || dn === "User") return "?";
  return dn.charAt(0).toUpperCase();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("TopBar avatar initial — computeAvatarInitial", () => {
  // Requirement 6.1 — unauthenticated state shows "?"
  describe('returns "?" when not authenticated', () => {
    test("not authenticated with no email or userId", () => {
      expect(computeAvatarInitial("", "", false)).toBe("?");
    });

    test("not authenticated even if email is provided", () => {
      expect(computeAvatarInitial("jane@example.com", "", false)).toBe("?");
    });

    test("not authenticated even if userId is provided", () => {
      expect(computeAvatarInitial("", "user_abc123", false)).toBe("?");
    });

    test("not authenticated with both email and userId provided", () => {
      expect(computeAvatarInitial("alice@mail.com", "user_xyz", false)).toBe("?");
    });
  });

  // Requirement 6.2 — authenticated but no usable name → "?"
  describe('returns "?" when authenticated but display name resolves to "User"', () => {
    test("authenticated with empty email and empty userId", () => {
      expect(computeAvatarInitial("", "", true)).toBe("?");
    });

    test("authenticated with null email and null userId", () => {
      expect(computeAvatarInitial(null, null, true)).toBe("?");
    });

    test("authenticated with email that has no @ and empty userId", () => {
      // email with no "@" falls through; userId is empty → "User"
      expect(computeAvatarInitial("notanemail", "", true)).toBe("?");
    });

    test('authenticated with empty local-part email ("@domain") and empty userId', () => {
      // local-part is empty → falls through; userId is empty → "User"
      expect(computeAvatarInitial("@example.com", "", true)).toBe("?");
    });
  });

  // Requirement 6.3 — email-derived initial
  describe("returns correct uppercased initial when display name is email-derived", () => {
    test("jane@example.com → J", () => {
      expect(computeAvatarInitial("jane@example.com", "", true)).toBe("J");
    });

    test("alice@mail.com → A", () => {
      expect(computeAvatarInitial("alice@mail.com", "user_xyz", true)).toBe("A");
    });

    test("uppercase email char (JOHN@…) → J", () => {
      expect(computeAvatarInitial("JOHN@domain.com", "", true)).toBe("J");
    });

    test("mixed-case email (bOb@…) → B", () => {
      expect(computeAvatarInitial("bOb@example.com", "", true)).toBe("B");
    });

    test("single-char local-part (z@x.com) → Z", () => {
      expect(computeAvatarInitial("z@x.com", "", true)).toBe("Z");
    });

    test("long local-part is truncated to 16 chars; initial is first char → correct letter", () => {
      // local = "abcdefghijklmnopqrstuvwxyz" (26 chars) → truncated to "abcdefghijklmnop…"
      // initial = "A"
      expect(
        computeAvatarInitial("abcdefghijklmnopqrstuvwxyz@example.com", "", true)
      ).toBe("A");
    });
  });

  // Requirement 6.3 — userId-derived initial (email absent / no valid local-part)
  describe("returns correct uppercased initial when display name is userId-derived", () => {
    test("user_abc123 → A (strips user_ prefix, takes first char of remainder)", () => {
      expect(computeAvatarInitial("", "user_abc123", true)).toBe("A");
    });

    test("user_XYZ → X", () => {
      expect(computeAvatarInitial("", "user_XYZ", true)).toBe("X");
    });

    test("userId without user_ prefix: myId → M", () => {
      expect(computeAvatarInitial("", "myId", true)).toBe("M");
    });

    test("email has no @ so userId branch is used: user_beta → B", () => {
      expect(computeAvatarInitial("notanemail", "user_beta", true)).toBe("B");
    });

    test("email has empty local-part so userId branch is used: user_delta → D", () => {
      expect(computeAvatarInitial("@domain.com", "user_delta", true)).toBe("D");
    });
  });

  // Extra: "Guest" display name path (unauthenticated → computeDisplayName returns "Guest")
  describe('returns "?" when display name is "Guest" (unauthenticated)', () => {
    test("unauthenticated user always gets Guest display name → ?", () => {
      // computeDisplayName returns "Guest" when authenticated=false
      expect(computeAvatarInitial("guest@example.com", "user_guest", false)).toBe("?");
    });
  });
});
