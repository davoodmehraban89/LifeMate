"""Developer-only real HTTPS PWA load test; requires Playwright + Chromium.

The public CA must already be trusted normally by the browser. This program
never ignores TLS errors, intercepts network responses, or logs credentials.
Real Safari/Android and Iran reachability are separate acceptance gates.
"""
import argparse
import json
import re
import time
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument("origin")
parser.add_argument("--chromium", default="/usr/bin/chromium")
parser.add_argument("--profile", required=True)
parser.add_argument("--screenshot", required=True)
parser.add_argument("--viewport-width", type=int, default=390)
parser.add_argument("--synthetic-login-email", choices=["stage0-mother@lifeguide.test", "stage0-father@lifeguide.test"])
parser.add_argument("--synthetic-password-file")
parser.add_argument("--expected-task-title")
parser.add_argument("--expected-recorded-seconds", type=int)
parser.add_argument("--expected-planned-seconds", type=int)
parser.add_argument("--expected-status")
parser.add_argument("--resume-parent-session", action="store_true")
args = parser.parse_args()
origin = args.origin.rstrip("/")
parsed = urlparse(origin)
if parsed.scheme != "https" or parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment:
    raise SystemExit("Use one HTTPS origin without credentials/path/query/fragment")
requests, failures, errors, http_errors, auth_responses = [], [], [], [], []
login_verified, report_verified, report_body_verified, reported_task = False, False, False, None
if bool(args.synthetic_login_email) != bool(args.synthetic_password_file):
    raise SystemExit("Synthetic login requires both the known fixture email and private local password file")
if args.resume_parent_session and not args.synthetic_login_email:
    raise SystemExit("Resume requires a previously authenticated synthetic parent profile")
with sync_playwright() as playwright:
    context = playwright.chromium.launch_persistent_context(
        user_data_dir=args.profile, executable_path=args.chromium, headless=True,
        viewport={"width": args.viewport_width, "height": 960}, ignore_https_errors=False,
        service_workers="allow", timezone_id="Asia/Tehran",
    )
    try:
        page = context.pages[0] if context.pages else context.new_page()
        def requested(request):
            url = urlparse(request.url)
            requests.append({"origin": f"{url.scheme}://{url.netloc}", "path": url.path})
        page.on("request", requested)
        page.on("requestfailed", lambda request: failures.append({"path": urlparse(request.url).path, "failure": request.failure}))
        page.on("pageerror", lambda error: errors.append(str(error)))
        def responded(response):
            path = urlparse(response.url).path
            if response.status >= 400:
                http_errors.append({"path": path, "status": response.status})
            if path in ("/api/v1/auth/login", "/api/v1/auth/refresh"):
                auth_responses.append({"path": path, "status": response.status})
        page.on("response", responded)
        initial_url = page.url
        if initial_url.rstrip("/") == origin:
            # Persistent Chromium may already be restoring the prior page.
            # Never start a second navigation while it rotates refresh tokens.
            response = None
            page.wait_for_load_state("networkidle", timeout=90000)
        else:
            response = page.goto(origin, wait_until="networkidle", timeout=90000)
            assert response and response.status == 200, "PWA navigation failed"
        page.wait_for_selector("flt-glass-pane", state="attached", timeout=90000)
        page.wait_for_function("() => !document.getElementById('startup-status')", timeout=90000)
        placeholder = page.locator("flt-semantics-placeholder")
        if placeholder.count():
            placeholder.evaluate("element => element.click()")
        page.wait_for_load_state("networkidle")
        if args.synthetic_login_email:
            if args.resume_parent_session:
                pass
            else:
                password = Path(args.synthetic_password_file).read_text().strip()
                assert len(password) >= 10, "Synthetic password too short"
                page.get_by_label("ایمیل یا شماره تلفن", exact=True).fill(args.synthetic_login_email)
                page.get_by_label("رمز عبور", exact=True).fill(password)
                password = None
                with page.expect_response(lambda response: urlparse(response.url).path == "/api/v1/auth/login" and response.request.method == "POST") as logged_in:
                    page.get_by_role("button", name="ورود", exact=True).click()
                assert logged_in.value.status == 200, f"Synthetic parent login HTTP {logged_in.value.status}"
            page.get_by_role("tab", name="خانواده", exact=True).wait_for(timeout=30000)
            page.wait_for_load_state("networkidle")
            if args.resume_parent_session:
                assert {"path": "/api/v1/auth/refresh", "status": 200} in auth_responses, "Saved parent session did not refresh after browser restart"
            # Flutter's RTL semantic tab has a transformed DOM rectangle. Use
            # the actual visible centre tab of the five-destination navbar.
            page.mouse.click(args.viewport_width / 2, 920)
            child = page.get_by_role("button", name=re.compile("فرزند آزمایشی"))
            child.wait_for(timeout=30000)
            with page.expect_response(lambda response: urlparse(response.url).path.endswith("/learning-report")) as loaded_report:
                child.evaluate("element => element.click()")
            assert loaded_report.value.status == 200, "Permitted child report API failed"
            # Chromium's restored tab can expose a response without retaining
            # its CDP response body. Fresh-login runs independently validate
            # server JSON; restart runs validate refresh, new report HTTP 200
            # and the actual rendered values, without inventing a JSON check.
            server_report = None if args.resume_parent_session else loaded_report.value.json()
            report_body_verified = server_report is not None
            if server_report is not None and args.expected_planned_seconds is not None:
                assert server_report["metrics"]["plannedInRangeDurationSeconds"] == args.expected_planned_seconds, "Planned time for the selected report range differs"
            page.get_by_role("heading", name=re.compile("گزارش یادگیری")).wait_for(timeout=30000)
            if server_report is not None and args.expected_task_title:
                reported_task = next((item for item in server_report["items"] if item["title"] == args.expected_task_title), None)
                assert reported_task, "Expected synthetic homework missing from server report"
                if args.expected_recorded_seconds is not None:
                    assert reported_task["recordedDurationSeconds"] == args.expected_recorded_seconds, "Reported task duration differs"
                if args.expected_status:
                    assert reported_task["status"] == args.expected_status, "Reported task status differs"
                assert "SYNTHETIC-OWNER-PRIVATE-NOTE" not in json.dumps(server_report), "Private owner note leaked to parent"
            deadline = time.monotonic() + 30
            while True:
                rendered = page.locator("body").aria_snapshot()
                if "زمان ثبت‌شده" in rendered and (not args.expected_task_title or args.expected_task_title in rendered):
                    break
                assert time.monotonic() < deadline, "Expected allowed report was not rendered in PWA"
                page.wait_for_timeout(100)
            if args.expected_recorded_seconds is not None:
                assert f"ثبت {round(args.expected_recorded_seconds / 60)} دقیقه" in rendered, "Recorded task duration not shown in PWA"
            if args.expected_status == "completed":
                assert "انجام‌شده به گزارش فرزند" in rendered, "Recorded completion status not shown in PWA"
            if args.expected_planned_seconds is not None:
                assert f"زمان برنامه‌ریزی‌شده: {round(args.expected_planned_seconds / 60)} دقیقه" in rendered, "Planned duration for report range not shown in PWA"
            assert "SYNTHETIC-OWNER-PRIVATE-NOTE" not in rendered, "Private owner note rendered for parent"
            login_verified, report_verified = True, True
        external = [request for request in requests if request["origin"] != origin]
        assert not external, f"Unexpected external request: {external}"
        assert not failures, f"Network failure: {failures}"
        assert not errors, f"Browser error: {errors}"
        assert not http_errors, f"HTTP failure: {http_errors}"
        assert any("/canvaskit/" in request["path"] and request["path"].endswith(".wasm") for request in requests), "Local CanvasKit WASM missing"
        assert "LifeGuide" in page.title() and "لایف‌گاید" in page.title(), "Product title differs"
        page.screenshot(path=args.screenshot, full_page=False)
        print(json.dumps({"mode": "actual local HTTPS gateway, normal browser trust, real API", "browser": context.browser.version if context.browser else "Chromium", "http": response.status if response else "Chromium restored navigation; initial HTTP status UNVERIFIED",
                          "requestCount": len(requests), "externalRequests": external,
                          "failedRequests": failures, "browserErrors": errors,
                          "httpErrors": http_errors,
                          "syntheticParentLogin": login_verified and not args.resume_parent_session,
                          "syntheticParentAuthenticated": login_verified,
                          "permittedChildReportRendered": report_verified,
                          "serverReportBodyVerified": report_body_verified,
                          "reportBodyLimit": "Restored-tab JSON body UNVERIFIED; fresh-login runs independently validate JSON" if args.resume_parent_session else None,
                          "resumedPersistedParentSession": args.resume_parent_session,
                          "authResponses": auth_responses,
                          "reportedTask": None if reported_task is None else {key: reported_task.get(key) for key in ["title", "status", "recordedDurationSeconds", "plannedDurationSeconds", "activityState"]},
                          "fonts": [request["path"] for request in requests if request["path"].endswith((".ttf", ".otf", ".woff2"))],
                          "inputLabels": page.locator("input").evaluate_all("els => els.map(e => ({type:e.type,label:e.getAttribute('aria-label')}))"),
                          "serviceWorkers": len(context.service_workers),
                          "limitations": "Safari install, Android, three physical devices and Iran reachability UNVERIFIED"}, ensure_ascii=False, indent=2))
    finally:
        # Park the saved profile on a blank page before closing. Chromium may
        # otherwise auto-restore the prior URL before a subsequent explicit
        # navigation, accidentally racing two refresh rotations in this test.
        for open_page in context.pages:
            open_page.goto("about:blank")
        context.close()
