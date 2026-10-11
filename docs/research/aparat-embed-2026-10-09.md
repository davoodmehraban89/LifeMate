# Aparat official embedded player: research and boundary

Checked on 2026-10-09. This is public-source research and a paused player-frame
probe, followed by client component tests. No video was played, downloaded,
rehosted or transcribed. No provider account, user data or credentials were used.

## Official frame and sources

The official JavaScript endpoint
[`https://www.aparat.com/embed/rod03i6`](https://www.aparat.com/embed/rod03i6)
returned HTTP200 over verified HTTPS. It creates an iframe with fullscreen
attributes and this address:

```text
https://www.aparat.com/video/video/embed/videohash/{videoHash}/vt/frame
```

The public example `rod03i6` is a 54-second embed-code tutorial, **not an approved
school lesson or a catalog seed**. Its public metadata endpoint
[`/etc/api/video/videohash/rod03i6`](https://www.aparat.com/etc/api/video/videohash/rod03i6)
returned HTTP200; the frame also returned HTTP200. The official embed script
does not add autoplay parameters by default. The frame is a provider-controlled
JavaScript application, not a direct video-file URL.

Relevant official public sources:

- [Aparat editorial explanation of embedding](https://aparat.blog/what-is-embed/)
  describes the supported embed flow, attribution/view counts, adaptive quality
  and optional autoplay settings. It explains embedding videos without hosting
  another copy; it does not grant blanket rights to arbitrary third-party lessons.
- [Official upload guidance](https://support.aparat.com/kb/articles/article-94)
  describes copyright enforcement and inappropriate-for-children settings.
  Those uploader controls do not certify every public video as suitable for minors.
- [Official revenue-sharing page](https://www.aparat.com/income/) establishes
  that advertising is part of the provider's service. Exact ad behavior in an
  embedded school lesson was not verified.
- [Main-service rules](https://www.aparat.com/etc/main/rules) returned HTTP403;
  a search-provider fetch also timed out. The full current terms and privacy
  policy remain **UNVERIFIED**. Rules from Aparat Kids/Music were not substituted.

Keep provider branding and controls. Do not fetch file variants, strip ads,
scrape playback into another player, infer permission from public availability,
or claim ad-free, cookie-free or age-filtered playback. Catalog publishing still
requires separate content suitability and rights review.

## Client contract

`AparatPlayer(videoHash: ..., title: ...)` accepts a case-preserving ASCII
alphanumeric hash of 5–64 characters. It rejects URLs, slashes, escapes, query
strings, whitespace and other scripts. The component constructs the official
HTTPS frame URI itself. No caller-supplied HTML, media URL, app token, account ID,
callback URL or autoplay parameter is forwarded.

The Persian explanation and an explicit **بارگذاری ویدئو از آپارات** button appear
before creating the remote platform view. Selecting another video requires a new
click. Close, route disposal and paused/hidden app lifecycle remove the view.
Load errors and a 30-second frame-document timeout offer an explicit retry;
frame readiness is not reported as successful playback or recorded study.

Web/PWA uses `HtmlElementView.fromTagName('iframe')`, with restrictions set before
attachment and `src` assignment:

```text
referrerpolicy="no-referrer"
sandbox="allow-scripts allow-same-origin"
allow="fullscreen; autoplay 'none'; camera 'none'; microphone 'none';
       geolocation 'none'; payment 'none'"
allowfullscreen
```

The cross-origin frame needs scripts and its own origin for provider resources.
Top navigation, popups, downloads and forms are not granted by the sandbox.
The app's CSP needs `frame-src https://www.aparat.com`; app script/connect/font
sources should remain local. The child document has its own network and policy
context. Browsers may fire iframe `load` for a provider error page, so this event
cannot prove media availability or viewing.

Android uses official `webview_flutter`4.14.1 and Android implementation4.14.1.
JavaScript is enabled for the provider; no JavaScript bridge or app headers are
installed. Media requires a user gesture, third-party cookies and geolocation are
disabled, mixed content is forbidden and permission requests are denied. TLS
errors cancel. Initial controller loading is validated separately because it does
not pass through the navigation delegate.

Main-document navigation permits only HTTPS, port443, `www.aparat.com` or
`aparat.com`, and the exact selected embed path, with no userinfo/query/fragment.
Other redirects and app protocols are prevented. The native delegate is **not a
CDN/subframe resource firewall**. First-party provider cookies can still exist;
provider-related recommendations, controls and ads remain provider-controlled.
This component must not imply that only the curated lesson can ever be displayed.
The component installs official Android custom-widget callbacks with a presenter
that records its exact fullscreen route. User Back/close/disposal returns the
native custom view once; a repeated provider hide removes only that owned route,
not a different app page. This replaces the plugin's broad default `Navigator.pop`
behavior. Physical fullscreen/back-button behavior remains a device acceptance gate.

Current direct additions are `web`1.1.1, `webview_flutter`4.14.1 and
`webview_flutter_android`4.14.1; lockfile resolves platform interface2.15.1 and
WKWebView3.27.0. The core package requires Dart3.10+/Flutter3.38+, compatible with
the existing Flutter3.47.6/Dart3.13.5 toolchain. The resolved native implementations
raise lockfile minimums to Flutter3.47/Dart3.13; these are satisfied here.
iPhone/iPad delivery uses the PWA
iframe; a future native iOS build is not accepted by this research. Native desktop
shows an in-page unsupported message instead of launching another application.

## Actual probe and test limits

[Sanitized real frame receipt](../audits/evidence/aparat-frame-probe-2026-10-09.json)
records a Playwright1.62.1/system Chromium probe. Only the reserved test wrapper
was intercepted. Aparat's document, scripts, stylesheet, metadata API, font and
poster/profile images used actual HTTPS through the normal proxy, with
`ignoreHTTPSErrors:false` and no TLS bypass. The inspected frame displayed a
paused Play control and `00:54`; it was not clicked.

Observed: one synthetic wrapper request plus seven real provider/CDN requests;
initial iframe request sent no wrapper Referer; provider child resources used
their own provider Referer. No media request, page/request error or initial cookie
was observed in this fresh browser profile. Playback was deliberately disabled and
media request types/extensions were guarded before fetching. Empty initial cookies
do not establish provider behavior after Play or for an existing browser profile.

The fixture widget tests verify hash/navigation validation, no remote frame before
consent, failure/retry, selection change, stale callback rejection, close/background
removal, fullscreen route isolation and desktop
fallback. They use a replaceable platform port and **do not prove playback**.
The first widget run found a short-viewport overflow; a scrollable body and visible
close control fixed it. Focused final suite:12/12 passed, zero skips. Platform source
analysis is separate from native Android compilation.

Actual media streaming, ads/cookies after Play, fullscreen, Android WebView/device
behavior, iPhone/iPad Safari/PWA, VPN-free reachability inside Iran, and the full
latest service terms remain **UNVERIFIED**. No live service or release was changed.
