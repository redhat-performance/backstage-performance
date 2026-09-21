from selenium.webdriver.common.by import By
from selenium.common.exceptions import (
    InvalidSessionIdException,
    NoSuchWindowException,
    TimeoutException,
)
from selenium.webdriver.chrome.service import Service
from selenium import webdriver
from locust.exception import LocustError
from locust.runners import MasterRunner, WorkerRunner
from locust import User, task, events
import concurrent.futures
import os
from locust import task
from ui_shared import RHDHBrowserUser
import time


class UIBaselineTest(RHDHBrowserUser):

    timer_start = -1.0
    timer_stop = -1.0
    step = -1


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

    @task
    def user_activity(self) -> None:
        e2e_start = time.time()
        for attempt in range(2):
            try:
                self.reset_steps()
                self._dispose_driver()
                self._ensure_driver()

                self.reset_timer()
                self.driver.get(self.baseUrl)
                username = self.wait_for_clickable_element(By.ID, "username")
                password = self.wait_for_clickable_element(By.ID, "password")
                login = self.wait_for_clickable_element(By.ID, "kc-login")

                username.send_keys(self.user_name)
                password.send_keys(self.user_password)
                self._report_success(
                    self.step_name("login"), "login_page_loaded", self.tick_timer())
                login.click()

                catalog = self.wait_for_clickable_element(
                    By.XPATH, "//span[normalize-space()='Catalog']")
                self._report_success(
                    self.step_name("home"), "home_page_loaded", self.tick_timer())
                catalog.click()

                self.wait_for_clickable_element(
                    By.XPATH, "//h2[contains(.,'All Components (')]")
                self._report_success(
                    self.step_name("catalog"), "catalog_page_loaded", self.tick_timer())

                if self.catalog_tab_n_count > 0:
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
                    page_1 = self.wait_for_clickable_element(
                        By.XPATH, "//span[normalize-space()='Page 1']")
                    self.reset_timer()
                    page_1.click()
                    self.wait_for_clickable_element(
                        By.XPATH, "//td[normalize-space()='Valgi da Cunha']")
                    self._report_success(
                        self.step_name("page_n"), "page_n_loaded", self.tick_timer())

                self._report_success(
                    self.step_name("e2e"), "duration", (time.time() - e2e_start) * 1000)
                return

            except TimeoutException as e:
                debug = self._page_debug()
                if attempt == 0:
                    continue
                rt = self.tick_timer()
                self._report_failure(
                    self.step_name("ui"), "timeout", rt,
                    f"{e.__class__.__name__}: {debug}")
                raise
            except (NoSuchWindowException, InvalidSessionIdException) as e:
                self._dispose_driver()
                if attempt == 0:
                    continue
                rt = self.tick_timer()
                self._report_failure(
                    self.step_name("login"), "login_page", rt, str(e))
                raise
            finally:
                self._dispose_driver()
