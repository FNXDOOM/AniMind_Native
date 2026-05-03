# Clerk in Electron (Production Checklist)

This app uses a custom Clerk OAuth flow for desktop:

1. Main process creates the OAuth attempt with Clerk FAPI (`/v1/client/sign_ins`).
2. Main process opens the returned URL in the system browser.
3. Clerk redirects back to `animind://auth/callback`.
4. Main process exchanges callback data for a Clerk session and stores it locally.

## Required Clerk Dashboard setup

1. Enable Google social connection in your Clerk instance.
2. Add `animind://auth/callback` to allowed native redirect URLs.
3. Use the correct instance publishable key (`pk_test_...` or `pk_live_...`) in app settings.

## Environment

Set these values:

```env
ANIMIND_BACKEND_URL=https://your-backend.example.com
ANIMIND_CLERK_PUBLISHABLE_KEY=pk_live_...
ANIMIND_MPV_PATH=mpv
```

## Security notes in this app

1. OAuth URLs are validated in Electron main before `shell.openExternal()`.
2. Session data is persisted in the app data directory and encrypted using Electron `safeStorage` when available.
3. Clerk key format is validated before setup is considered ready.

## Official Clerk docs referenced

1. Custom OAuth flow guidance:
   [https://clerk.com/docs/guides/development/custom-flows/authentication/oauth-connections](https://clerk.com/docs/guides/development/custom-flows/authentication/oauth-connections)
2. Redirect callback handling (`authenticateWithRedirect` / callback):
   [https://clerk.com/docs/js-frontend/reference/components/control/authenticate-with-redirect-callback](https://clerk.com/docs/js-frontend/reference/components/control/authenticate-with-redirect-callback)
3. Native redirect allowlisting and production guidance:
   [https://clerk.com/docs/reference/native-mobile/production](https://clerk.com/docs/reference/native-mobile/production)
4. Redirect URL object and custom scheme support:
   [https://clerk.com/docs/reference/backend/types/backend-redirect-url](https://clerk.com/docs/reference/backend/types/backend-redirect-url)
