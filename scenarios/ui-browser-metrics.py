from selenium.webdriver.common.by import By
from selenium.common.exceptions import (
    InvalidSessionIdException,
    NoSuchWindowException,
    TimeoutException,
)
from locust import task, events
from ui_shared import RHDHBrowserUser
import json


class UIBrowserMetricsTest(RHDHBrowserUser):

    def _inject_web_vitals_observer(self):
        """Inject persistent observers: LCP (valid until first interaction) + Long Tasks."""
        try:
            self.driver.execute_cdp_cmd("Page.addScriptToEvaluateOnNewDocument", {
                "source": """
                    window.__vitals    = { lcp: 0 };
                    window.__longTasks = { count: 0, total_ms: 0 };
                    try {
                        new PerformanceObserver(list => {
                            for (const e of list.getEntries())
                                window.__vitals.lcp = e.startTime;
                        }).observe({ type: 'largest-contentful-paint', buffered: true });
                    } catch(e) {}
                    try {
                        new PerformanceObserver(list => {
                            for (const e of list.getEntries()) {
                                window.__longTasks.count++;
                                window.__longTasks.total_ms += e.duration;
                            }
                        }).observe({ type: 'longtask', buffered: true });
                    } catch(e) {}
                """
            })
        except Exception:
            pass

    def _record_nav_start(self):
        """Reset per-page long-task counters before navigating to a new SPA page."""
        try:
            self.driver.execute_script(
                "window.__longTasks = { count: 0, total_ms: 0 };"
            )
        except Exception:
            pass

    def _collect_web_vitals(self, page_name):
        """Collect LCP (home only), long tasks, and JS heap per page."""
        try:
            data = self.driver.execute_script("""
                const lt  = window.__longTasks || {};
                const mem = performance.memory  || {};
                return {
                    lcp:          (window.__vitals || {}).lcp || 0,
                    long_tasks:   lt.count    || 0,
                    long_task_ms: lt.total_ms || 0,
                    heap_mb:      Math.round((mem.usedJSHeapSize || 0) / 1048576),
                };
            """)
        except Exception:
            return
        if page_name == "home" and data["lcp"] > 0:
            self._report_success(f"vitals:{page_name}", "lcp_ms", data["lcp"])
        if data["long_tasks"] > 0:
            self._report_success(f"vitals:{page_name}", "long_task_count", data["long_tasks"])
            self._report_success(f"vitals:{page_name}", "long_task_ms",    data["long_task_ms"])
        if data["heap_mb"] > 0:
            self._report_success(f"vitals:{page_name}", "heap_used_mb", data["heap_mb"])

    def _collect_network_metrics(self, page_name):
        """Parse CDP logs and fire per-request timings (net:*) and per-MIME byte totals (size:*)."""
        try:
            logs = self.driver.get_log("performance")
        except Exception:
            return

        request_mime = {}
        request_bytes = {}

        for entry in logs:
            try:
                msg = json.loads(entry["message"])["message"]
                method = msg.get("method")
                params = msg["params"]

                if method == "Network.responseReceived":
                    resp = params.get("response", {})
                    mime = resp.get("mimeType", "unknown").split(";")[0].strip()
                    timing = resp.get("timing")
                    request_mime[params["requestId"]] = mime
                    if timing:
                        rt_ms = max(
                            timing.get("receiveHeadersEnd", 0) - timing.get("sendStart", 0), 0
                        )
                        self._report_success(f"net:{page_name}", mime, rt_ms)

                elif method == "Network.loadingFinished":
                    req_id = params.get("requestId")
                    if req_id in request_mime:
                        request_bytes[req_id] = params.get("encodedDataLength", 0)

            except Exception:
                continue

        mime_bytes = {}
        for rid, mime in request_mime.items():
            mime_bytes[mime] = mime_bytes.get(mime, 0) + request_bytes.get(rid, 0)
        for mime, total in mime_bytes.items():
            if total > 0:
                events.request.fire(
                    request_type=f"size:{page_name}",
                    name=mime,
                    response_time=total,
                    response_length=total,
                    exception=None,
                )

    MAX_RETRIES = 2

    @task
    def user_activity(self) -> None:
        for attempt in range(self.MAX_RETRIES):
            try:
                self._ensure_driver()
                self._inject_web_vitals_observer()

                self.driver.get(self.baseUrl)
                username = self.wait_for_clickable_element(By.ID, "username")
                password = self.wait_for_clickable_element(By.ID, "password")
                login = self.wait_for_clickable_element(By.ID, "kc-login")
                username.send_keys(self.user_name)
                password.send_keys(self.user_password)
                login.click()

                catalog = self.wait_for_clickable_element(
                    By.XPATH, "//span[normalize-space()='Catalog']")
                self._collect_network_metrics("home")
                self._collect_web_vitals("home")
                self._record_nav_start()
                catalog.click()

                self.wait_for_clickable_element(
                    By.XPATH, "//h2[contains(.,'All Components (')]")
                self._collect_network_metrics("catalog")
                self._collect_web_vitals("catalog")

                if self.catalog_tab_n_count > 0:
                    component = self.wait_for_clickable_element(
                        By.XPATH, "//span[normalize-space()='playback-sdk-1']")
                    self._record_nav_start()
                    component.click()
                    catalog_tab_n = self.wait_for_clickable_element(
                        By.XPATH, "//a[normalize-space(text())='Catalog Tab 1']")
                    self._collect_network_metrics("component")
                    self._collect_web_vitals("component")
                    self._record_nav_start()
                    catalog_tab_n.click()
                    self.wait_for_clickable_element(
                        By.XPATH, "//td[normalize-space()='Valgi da Cunha']")
                    self._collect_network_metrics("catalog_tab")
                    self._collect_web_vitals("catalog_tab")

                if self.page_n_count > 0:
                    page_1 = self.wait_for_clickable_element(
                        By.XPATH, "//span[normalize-space()='Page 1']")
                    self._record_nav_start()
                    page_1.click()
                    self.wait_for_clickable_element(
                        By.XPATH, "//td[normalize-space()='Valgi da Cunha']")
                    self._collect_network_metrics("page_n")
                    self._collect_web_vitals("page_n")

                return

            except TimeoutException as e:
                debug = self._page_debug()
                if attempt == 0:
                    continue
                self._report_failure(
                    "ui", "timeout", 0, f"{e.__class__.__name__}: {debug}")
                raise
            except (NoSuchWindowException, InvalidSessionIdException) as e:
                self._dispose_driver()
                if attempt == 0:
                    continue
                self._report_failure("login", "login_page", 0, str(e))
                raise
            finally:
                self._dispose_driver()
