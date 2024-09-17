from locust import HttpUser, events, task
from locust.runners import MasterRunner, WorkerRunner
from urllib3.exceptions import InsecureRequestWarning
import urllib.parse
import json
import re
import urllib3

urllib3.disable_warnings(InsecureRequestWarning)

__version__ = "1"

usernames = []

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


def setup_test_users(environment, msg, **kwargs):
    # Fired when the worker receives a message of type 'test_users'
    usernames.extend(map(lambda u: u, msg.data))


@events.init.add_listener
def on_locust_init(environment, **_kwargs):
    if not isinstance(environment.runner, MasterRunner):
        environment.runner.register_message("test_users", setup_test_users)


@events.test_start.add_listener
def on_test_start(environment, **_kwargs):
    # When the test is started, evenly divides list between
    # worker nodes to ensure unique data across threads
    if not isinstance(environment.runner, WorkerRunner):
        users = []
        for i in range(1, int(environment.runner.target_user_count)+1):
            users.append(f"test{i}")

        worker_count = environment.runner.worker_count
        chunk_size = int(len(users) / worker_count)

        for i, worker in enumerate(environment.runner.clients):
            start_index = i * chunk_size

            if i + 1 < worker_count:
                end_index = start_index + chunk_size
            else:
                end_index = len(users)

            data = users[start_index:end_index]
            environment.runner.send_message("test_users", data, worker)


@events.init_command_line_parser.add_listener
def _(parser):
    parser.add_argument("--keycloak-host", type=str, default="")
    parser.add_argument("--keycloak-password", is_secret=True, default="")


class MVP1dot1Test(HttpUser):

    def on_start(self):
        self.client.verify = False
        if self.environment.parsed_options.keycloak_host:
            r = self.client.get('/api/auth/oauth2Proxy/refresh', verify=False)
            qs_str = urllib.parse.parse_qs(r.url)
            STATE = qs_str['state']
            login_cookies = r.cookies
            pattern = r'action="([^"]*)"'
            LOGIN_URL_tmp = re.findall(pattern, str(r.content))[0]
            LOGIN_URL = LOGIN_URL_tmp.replace("&amp;", "&")
            qs_str = urllib.parse.parse_qs(LOGIN_URL)
            TAB_ID = qs_str['tab_id']
            EXECUTION = qs_str['execution']

            param = {'client_id': self.CLIENTID,
                     'tab_id': TAB_ID, 'execution': EXECUTION}
            form = {'username': self.USERNAME,
                    'password': self.PASSWORD, 'credentialId': ''}
            r = self.client.post(LOGIN_URL, verify=False,
                                 data=form, params=param)

            r = self.client.get(self.REFRESH_URL, verify=False)
            json_dict = json.loads(r.content)
            TOKEN = json_dict['backstageIdentity']['token']

            self.HEADER = {'Authorization': 'Bearer ' + TOKEN}
        else:
            r = self.client.get('/api/auth/guest/refresh', verify=False)
            json_dict = json.loads(r.content)
            TOKEN = json_dict['backstageIdentity']['token']

            self.HEADER = {'Authorization': 'Bearer ' + TOKEN}

    def __init__(self, parent):
        super().__init__(parent)
        self.HEADER = ''
        if self.environment.parsed_options.keycloak_host:
            self.USERNAME = usernames.pop()
            kc_host = self.environment.parsed_options.keycloak_host
            self.KEYCLOAK_URL = f'https://{kc_host}/auth'
            bs_host = self.environment.host
            self.REDIRECT_URL = f'{bs_host}/oauth2/callback'
            self.REFRESH_URL = f'{bs_host}/api/auth/oauth2Proxy/refresh'

            self.PASSWORD = self.environment.parsed_options.keycloak_password
            self.REALM = "backstage"
            self.CLIENTID = "backstage"

    def entitiy_facets(self, query) -> None:
        self.client.get(base_path_facets,
                        verify=False,
                        headers=self.HEADER,
                        params=entity_facets_params[query])

    def entities(self, query) -> None:
        self.client.get(base_path_entities,
                        verify=False,
                        headers=self.HEADER,
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
