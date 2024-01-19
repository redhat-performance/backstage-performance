from locust import HttpUser, task
from urllib3.exceptions import InsecureRequestWarning
import urllib3

urllib3.disable_warnings(InsecureRequestWarning)

__version__ = "1"

entity_facets_params = {}

entity_facets_params["kind"] = {
    "facet": "kind",
}

entity_facets_params["relations.ownedBy"] = {
    "facet": "relations.ownedBy",
}

entity_facets_params["metadata.namespace"] = {
    "facet": "metadata.namespace",
}

entity_facets_params["spec.lifecycle"] = {
    "facet": "spec.lifecycle",
}

entity_facets_params["metadata.tags"] = {
    "facet": "metadata.tags",
}

entity_facets_params["component/spec.lifecycle"] = {
    "facet": "spec.lifecycle",
    "filter": "kind=component"
}

entity_facets_params["component/spec.type"] = {
    "facet": "spec.type",
    "filter": "kind=component"
}

entity_facets_params["component/metadata.namespace"] = {
    "facet": "metadata.namespace",
    "filter": "kind=component"
}

entity_facets_params["component/metadata.tags"] = {
    "facet": "metadata.tags",
    "filter": "kind=component"
}

entity_facets_params["api/spec.lifecycle"] = {
    "facet": "spec.lifecycle",
    "filter": "kind=api"
}

entity_facets_params["api/spec.type"] = {
    "facet": "spec.type",
    "filter": "kind=api"
}

entity_facets_params["api/metadata.namespace"] = {
    "facet": "metadata.namespace",
    "filter": "kind=api"
}

entity_facets_params["api/metadata.tags"] = {
    "facet": "metadata.tags",
    "filter": "kind=api"
}

entities_params = {}

entities_params["component"] = {
    "filter": "kind=component",
}

entities_params["component/library"] = {
    "filter": "kind=component,spec.type=library",
}

entities_params["api"] = {
    "filter": "kind=api",
}


base_path_facets = "/api/catalog/entity-facets"
base_path_entities = "/api/catalog/entities"


class MVPTest(HttpUser):

    def on_start(self):
        self.client.verify = False

    def entitiy_facets(self, query) -> None:
        self.client.get(base_path_facets,
                        verify=False,
                        params=entity_facets_params[query])

    def entities(self, query) -> None:
        self.client.get(base_path_entities,
                        verify=False,
                        params=entities_params[query])

    @task
    def get_kind(self) -> None:
        self.entitiy_facets("kind")
        self.entitiy_facets("relations.ownedBy")
        self.entitiy_facets("metadata.namespace")
        self.entitiy_facets("spec.lifecycle")
        self.entitiy_facets("metadata.tags")
        self.entities("component")
        self.entitiy_facets("component/spec.lifecycle")
        self.entitiy_facets("component/spec.type")
        self.entitiy_facets("component/metadata.namespace")
        self.entitiy_facets("component/metadata.tags")
        self.entities("api")
        self.entitiy_facets("api/spec.lifecycle")
        self.entitiy_facets("api/spec.type")
        self.entitiy_facets("api/metadata.namespace")
        self.entitiy_facets("api/metadata.tags")
        self.entities("component")
        self.entitiy_facets("component/spec.lifecycle")
        self.entitiy_facets("component/spec.type")
        self.entitiy_facets("component/metadata.namespace")
        self.entitiy_facets("component/metadata.tags")
        self.entities("component/library")
        self.entities("component")
