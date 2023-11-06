from locust import HttpUser, task
from urllib3.exceptions import InsecureRequestWarning
import urllib3

urllib3.disable_warnings(InsecureRequestWarning)


class OCLicenseTest(HttpUser):
    def on_start(self):
        self.client.verify = False

    @task
    def get_license(self) -> None:
        self.client.get("/oc-license", verify=False)
