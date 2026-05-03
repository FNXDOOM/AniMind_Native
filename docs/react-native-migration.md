# AniMind React Native Migration Guide

**Target Audience:** AI Coding Assistant
**Objective:** Rewrite the AniMind Vite/React/Electron Desktop Application into a native Android application using React Native.

## Core Directives

1. **No Managed Expo Go:** Do NOT use the standard managed Expo Go workflow. You must initialize a project that allows for custom native Android compilation (Bare React Native or Expo with Custom Dev Clients / prebuild). We have to aggressively modify the native Android media player dependencies.
2. **The Audio Codec Requirement (CRITICAL):** The resulting Android application MUST natively play video files containing proprietary audio codecs (AC3, EAC3, DTS). Standard Android WebViews and default ExoPlayer builds DO NOT support this due to licensing.
3. **The Solution:** Use `react-native-video` backed by Android's **ExoPlayer**. Crucially, you must modify the Android build configuration to compile ExoPlayer with the **FFmpeg Audio Extension** enabled. This forces the device to use FFmpeg's software decoders for unsupported audio formats directly inside the video player.

---

## Step-by-Step Implementation Instructions for the AI

### Phase 1: Project Setup & Logic Migration
* Scaffolding: Initialize the new React Native project.
* State & API: Port the existing logic. Dependencies like `zustand` (or Redux), Supabase clients (`src/renderer/src/api.ts` / `auth.service.ts`), and AniList GraphQL fetchers can be copied over directly with almost zero modifications. 

### Phase 2: UI & Routing Translation
* Navigation: Replace `react-router-dom` with `@react-navigation/native` (Stack and Tab navigators).
* Views: Translate HTML DOM elements (`<div>`, `<span>`, `<button>`) and standard CSS into React Native primitives (`<View>`, `<Text>`, `<TouchableOpacity>`, `StyleSheet`).

### Phase 3: The Video Player Ecosystem (The Most Complex Phase)
1. Install `react-native-video`.
2. **Android Gradle Configuration:** You must configure the Android project to include the FFmpeg audio extension. 
   * Check the documentation for the specific version of `react-native-video` being used. 
   * Typically, in `android/build.gradle`, you will need to add a flag in the `ext {}` block, for example: `reactNativeVideoExoPlayerFfmpegExtension = true` or `useExoplayerFfmpegExtension = true`.
   * If the wrapper does not automatically link the renderer, you may need to write Java/Kotlin code in `MainApplication.kt` to inject a custom `RenderersFactory` that includes the `FfmpegAudioRenderer` so ExoPlayer knows to use it during playback.
3. **Player UI:** Rebuild the AniMind custom player overlay (play/pause, seekbars, volume, quality selection) using React Native UI components positioned absolutely over the `<Video>` element.

### Phase 4: Replacing Electron-Specific APIs
* **Authentication:** The desktop app uses a Node.js loopback server (`http://localhost`) to capture Supabase OAuth tokens. This will NOT work on Android. You must replace the auth flow with **Deep Linking (App Links)** using libraries like `expo-auth-session` or React Native's `<Linking>` API to catch the browser redirect.
* **File System / Caching:** Replace any Node.js `fs` or `path` modules with React Native alternatives like `react-native-fs` or `expo-file-system`.

---

## AI Initialization Check
When reading this document to begin the migration task, explicitly tell the user:
1. You understand the requirement for the FFmpeg ExoPlayer extension and why we cannot use standard WebViews.
2. Ask the user to confirm whether they want to proceed using **React Native CLI (Bare)** or **Expo (with EAS Native Builds)** before creating the new repository.
