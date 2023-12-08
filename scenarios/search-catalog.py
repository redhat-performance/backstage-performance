from locust import HttpUser, task
from urllib3.exceptions import InsecureRequestWarning
import urllib3

urllib3.disable_warnings(InsecureRequestWarning)

__version__ = "1"

params = {}

params["all"] = {
    "types[0]": "software-catalog",
}

params["all_components"] = {
    "types[0]": "software-catalog",
    "filters[kind]": "Component",
}

params["not_found"] = {
    "types[0]": "software-catalog",
    "term": "n/a"
}

params["components_by_lifecycle"] = {
    "types[0]": "software-catalog",
    "filters[kind]": "Component",
    "filters[lifecycle][0]": "experimental",
}

base_path = "/api/search/query"


class SearchCatalogTest(HttpUser):

    def on_start(self):
        self.client.verify = False

    def search(self, query="all") -> None:
        self.client.get(base_path,
                        verify=False,
                        params=params[query])

    @task
    def searchAll(self) -> None:
        self.search("all")

    @task
    def searchAllComponents(self) -> None:
        self.search("all_components")

    @task
    def searchNotFound(self) -> None:
        self.search("not_found")

    @task
    def searchComponentsByLifecycle(self) -> None:
        self.search("components_by_lifecycle")
