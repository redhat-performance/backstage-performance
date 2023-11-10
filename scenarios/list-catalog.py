from locust import HttpUser, task
from urllib3.exceptions import InsecureRequestWarning
import urllib3

urllib3.disable_warnings(InsecureRequestWarning)

params = {
    "filter": "kind=component",
    "facet": "spec.type",
}


class ListCatalogTest(HttpUser):

    def on_start(self):
        self.client.verify = False

    @task
    def get_token(self) -> None:

        response = self.client.get("/api/catalog/entity-facets",
                                   verify=False,
                                   params=params)
