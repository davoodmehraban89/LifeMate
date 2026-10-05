# LifeMate — PWA Platform Constraints v1

## iPhone/iPad install model
LifeMate must include a Web App Manifest and standalone display behavior plus explicit icons. On iOS/iPadOS, a Home Screen web app can open as its own app-like surface rather than a normal browser tab. `apple-touch-icon` is provided intentionally for icon quality.

## Push
Web Push is supported for Home Screen web apps on iOS/iPadOS 16.4+. Permission must be requested in response to user interaction. Therefore notification onboarding must feature-detect capability and explain installation/permission rather than assuming push exists in an ordinary Safari tab.

## Service worker / offline
Current Flutter web does not provide a managed caching service worker by default. LifeMate must own its caching strategy. Phase 2 begins with conservative app-shell/static caching; offline data editing is added only per domain after conflict semantics are defined.

## Storage assumptions
Browser storage is a cache, not the authoritative database. Critical user data must sync to the backend when connectivity exists. The UX must tolerate local cache eviction and rehydration.

## Background behavior
Do not design correctness around background sync/execution. Reminders requiring guaranteed server-side timing should be generated from backend scheduling/push infrastructure; client background execution is an optimization only.

## Install UX
Provide a contextual install guide when capability/platform warrants it. Do not repeatedly nag. After installation, standalone safe-area layout, status-bar/theme metadata, deep-link/recovery redirect behavior and keyboard handling must be tested on real iPhone Safari/Home Screen.

## Phase 2 smoke matrix
- Android current supported baseline: install, auth, navigation, notifications when implemented.
- iPhone Safari: login/recovery/responsive layout.
- iPhone Home Screen: standalone launch, icon, safe areas, auth persistence, deep link/recovery, push capability where OS supports it.
- Desktop Chrome/Edge/Safari: responsive core flows.

## Sources validated in Phase 1
Official WebKit documentation for iOS/iPadOS Home Screen Web Push and official Flutter Web FAQ/initialization documentation for PWA suitability and service-worker behavior.