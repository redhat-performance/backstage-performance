from selenium.webdriver.support.ui import WebDriverWait, Select
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.common.by import By
from selenium.webdriver.common.action_chains import ActionChains
from selenium.common.exceptions import (
    InvalidSessionIdException,
    NoSuchWindowException,
)
from selenium.webdriver.chrome.service import Service
from selenium import webdriver
from locust.exception import LocustError
from locust.runners import MasterRunner, WorkerRunner
from locust import User, task, events
import concurrent.futures
import os
import time
import uuid

os.environ.setdefault(
    "SE_CACHE_PATH",
    os.path.join(os.environ.get("TMPDIR", "/tmp"), "selenium-cache"),
)

_CHROME_BIN_CANDIDATES = (
    "/usr/local/bin/chromium",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
)
_CHROMEDRIVER_CANDIDATES = (
    "/usr/local/bin/chromedriver",
    "/usr/bin/chromedriver",
)


def _is_executable(path: str) -> bool:
    return bool(path and os.path.isfile(path) and os.access(path, os.X_OK))


def _first_executable(candidates: tuple[str, ...]) -> str | None:
    for p in candidates:
        if _is_executable(p):
            return p
    return None


def _resolved_chrome_bin() -> str | None:
    env = os.environ.get("CHROME_BIN", "").strip()
    if env:
        return env
    return _first_executable(_CHROME_BIN_CANDIDATES)


def _resolved_chromedriver_path() -> str | None:
    env = os.environ.get("CHROMEDRIVER_PATH", "").strip()
    if env:
        return env
    return _first_executable(_CHROMEDRIVER_CANDIDATES)


def _env_truthy(name: str) -> bool:
    return str(os.environ.get(name, "")).lower() in ("1", "true", "yes", "on")


__version__ = "1"

usernames = []


@events.init_command_line_parser.add_listener
def _(parser):
    parser.add_argument("--page-n-count", type=int, default=0)
    parser.add_argument("--catalog-tab-n-count", type=int, default=0)
    parser.add_argument("--keycloak-host", type=str, default="")
    parser.add_argument("--keycloak-password", is_secret=True, default="")
    parser.add_argument("--debug", type=bool, default=False)


def setup_test_users(environment, msg, **kwargs):
    # Fired when the worker receives a message of type 'test_users'
    usernames.extend(map(lambda u: u, msg.data))
    print(f"Usernames: {usernames}")


@events.init.add_listener
def on_locust_init(environment, **_kwargs):
    if isinstance(environment.runner, WorkerRunner):
        environment.runner.register_message("test_users", setup_test_users) 

@events.test_start.add_listener
def on_test_start(environment, **_kwargs):
    # When the test is started, evenly divides list between
    # worker nodes to ensure unique data across threads
    if isinstance(environment.runner, MasterRunner):
        users = []
        for i in range(1, int(environment.runner.target_user_count)+1):
            users.append(f"t_{i}")

        worker_count = environment.runner.worker_count
        chunk_size = int(len(users) / worker_count)
        chunk_leftover = int(len(users) % worker_count)

        for i, worker in enumerate(environment.runner.clients):
            start_index = i * chunk_size
            end_index = start_index + chunk_size
            data = users[start_index:end_index]
            if chunk_leftover > 0 and chunk_leftover > i:
                data.append(users[worker_count * chunk_size + i])
            print(f"Setting up test users {data}...")
            environment.runner.send_message("test_users", data, worker)


class UIBaselineTest(User):

    timeout = 60

    baseUrl = ""
    driver = None

    timer_start = -1.0
    timer_stop = -1.0

    page_n_count = 0
    catalog_tab_n_count = 0

    user_password = ""
    user_name = ""

    step = -1

    _dead_session_errors = (NoSuchWindowException, InvalidSessionIdException)

    def __init__(self, environment):
        super().__init__(environment)
        self.baseUrl = environment.host
        opts = environment.parsed_options
        self.page_n_count = opts.page_n_count
        self.catalog_tab_n_count = opts.catalog_tab_n_count
        self.user_password = opts.keycloak_password
        if len(usernames) > 0:
            self.user_name = usernames.pop()
        else:
            self.user_name = "t_1"

    def on_start(self):
        self._ensure_driver()

    def _chrome_options(self):
        opts = webdriver.ChromeOptions()
        opts.add_argument("--headless=new")
        opts.add_argument("--window-size=1920,1080")
        opts.add_argument("--window-position=0,0")
        opts.add_argument("--ignore-ssl-errors=yes")
        opts.add_argument("--ignore-certificate-errors")
        profile_id = uuid.uuid4().hex[:16]
        opts.add_argument(
            f"--user-data-dir=/tmp/chrome-user-data-{profile_id}")
        opts.add_argument(f"--disk-cache-dir=/tmp/chrome-cache-{profile_id}")
        crash_dir = f"/tmp/chrome-crash-{profile_id}"
        try:
            os.makedirs(crash_dir, mode=0o755, exist_ok=True)
        except OSError:
            pass
        opts.add_argument(f"--crash-dumps-dir={crash_dir}")
        opts.add_argument("--no-sandbox")
        opts.add_argument("--disable-dev-shm-usage")
        opts.add_argument("--disable-gpu")
        opts.add_argument("--remote-allow-origins=*")
        opts.add_argument("--ozone-platform=headless")
        opts.add_argument("--disable-breakpad")
        opts.add_argument("--disable-crash-reporter")
        opts.add_argument(
            "--disable-features=CrashReporting,OptimizationHints")
        opts.add_argument("--disable-setuid-sandbox")
        opts.add_argument("--disable-hang-monitor")
        opts.add_argument("--disable-background-networking")
        opts.add_argument("--disable-sync")
        opts.add_argument("--password-store=basic")
        opts.add_argument("--use-mock-keychain")
        if _env_truthy("CHROME_SINGLE_PROCESS"):
            opts.add_argument("--single-process")
        chrome_bin = _resolved_chrome_bin()
        if chrome_bin:
            opts.binary_location = chrome_bin
        return opts

    def _dispose_driver(self):
        if self.driver is not None:
            try:
                self.driver.quit()
            except Exception:
                pass
            self.driver = None

    def _new_chrome_webdriver(self):
        opts = self._chrome_options()
        driver_path = _resolved_chromedriver_path()
        service_kwargs = {}
        if driver_path:
            service_kwargs["executable_path"] = driver_path
        service = Service(**service_kwargs)
        return webdriver.Chrome(service=service, options=opts)

    def _ensure_driver(self):
        if self.driver is not None:
            return
        timeout_s = int(os.environ.get("CHROME_STARTUP_TIMEOUT", "120"))
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(self._new_chrome_webdriver)
            try:
                self.driver = future.result(timeout=timeout_s)
            except concurrent.futures.TimeoutError:
                raise LocustError(
                    f"Chrome/WebDriver did not start within {timeout_s}s "
                    "(check CHROME_BIN + CHROMEDRIVER_PATH or "
                    "/usr/local/bin vs /usr/bin paths for your image; "
                    "CHROME_STARTUP_TIMEOUT; worker logs)"
                ) from None

    def on_stop(self):
        self._dispose_driver()

    @task
    def user_activity(self) -> None:
        e2e_start = time.time()
        for attempt in range(2):
            try:
                self.reset_steps()
                self._ensure_driver()
                self.driver.delete_all_cookies()
                self.driver.execute_cdp_cmd("Network.clearBrowserCookies", {})
                self.driver.execute_cdp_cmd("Network.clearBrowserCache", {})

                # load login page
                self.reset_timer()
                self.driver.get(self.baseUrl)
                username = self.wait_for_clickable_element(By.ID, "username")
                password = self.wait_for_clickable_element(By.ID, "password")
                login = self.wait_for_clickable_element(By.ID, "kc-login")

                # login
                username.send_keys(self.user_name)
                password.send_keys(self.user_password)
                self._report_success(
                    self.step_name("login"), "login_page_loaded", self.tick_timer())
                login.click()

                # load home page
                catalog = self.wait_for_clickable_element(
                    By.XPATH, "//span[normalize-space()='Catalog']")
                self._report_success(
                    self.step_name("home"), "home_page_loaded", self.tick_timer())
                catalog.click()

                # load catalog page
                self.wait_for_clickable_element(
                    By.XPATH, "//h2[contains(.,'All Components (')]")
                self._report_success(
                    self.step_name("catalog"), "catalog_page_loaded", self.tick_timer())

                if self.catalog_tab_n_count > 0:
                    # load catalog tab 1 plugin
                    component = self.wait_for_clickable_element(
                        By.XPATH, "//span[normalize-space()='playback-sdk-1']")
                    self.reset_timer()
                    component.click()
                    catalog_tab_n = self.wait_for_clickable_element(
                        By.XPATH, "//a[normalize-space(text())='Catalog Tab 1']")
                    self._report_success(
                        self.step_name("catalog"), "component_page_loaded", self.tick_timer())
                    catalog_tab_n.click()
                    self.wait_for_clickable_element(
                        By.XPATH, "//td[normalize-space()='Valgi da Cunha']")
                    self._report_success(
                        self.step_name("catalog"), "catalog_tab_n_loaded", self.tick_timer())

                if self.page_n_count > 0:
                    # load page 1 plugin
                    page_1 = self.wait_for_clickable_element(
                        By.XPATH, "//span[normalize-space()='Page 1']")
                    self.reset_timer()
                    page_1.click()
                    self.wait_for_clickable_element(
                        By.XPATH, "//td[normalize-space()='Valgi da Cunha']")
                    self._report_success(
                        self.step_name("page_n"), "page_n_loaded", self.tick_timer())
                self._report_success(
                    self.step_name("e2e"), "duration", (time.time() - e2e_start)*1000)
                return
            except self._dead_session_errors as e:
                self._dispose_driver()
                if attempt == 0:
                    continue
                rt = self.tick_timer()
                self._report_failure(self.step_name(
                    "login"), "login_page", rt, str(e))
                raise

    # utility methods
    def reset_timer(self):
        self.timer_start = time.time()

    def tick_timer(self):
        self.timer_stop = time.time()
        ret_val = (self.timer_stop - self.timer_start) * 1000
        self.timer_start = self.timer_stop
        return ret_val

    def reset_steps(self):
        self.step = 0

    def tick_step(self):
        self.step += 1
        return self.step

    def step_name(self, name):
        return f"{str(self.tick_step()).zfill(2)}_{name}"

    def wait_for_clickable_element(self, by, value, timeout=-1):
        if timeout < 0:
            timeout = self.timeout
        element = WebDriverWait(self.driver, timeout).until(
            EC.element_to_be_clickable((by, value))
        )
        return element

    def wait_for_url(self, url_contains):
        return WebDriverWait(self.driver, self.timeout).until(
            EC.url_contains(url_contains)
        )

    # reporting methods
    def _report_success(self, category, name, response_time):
        events.request.fire(
            request_type=category,
            name=name,
            response_time=response_time,
            response_length=0,
            exception=None
        )

    def _report_failure(self, category, name, response_time, msg):
        events.request.fire(
            request_type=category,
            name=name,
            response_time=response_time,
            response_length=0,
            exception=LocustError(msg)
        )
