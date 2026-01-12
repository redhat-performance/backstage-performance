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


def get_entities_by_query_params(kind=None, limit=0, user_ref=None, group_ref=None, additional_filter={}, additional_params={}):
    params = {}
    params["limit"] = limit
    if limit > 0:
        params["orderField"] = "metadata.name,asc"
    filter = ""
    if kind is not None:
        filter = f"kind={kind}"
    if user_ref is not None:
        filter += f",relations.ownedBy={user_ref}"
    if group_ref is not None:
        filter += f",relations.ownedBy={group_ref}"
    if len(additional_filter) > 0:
        for k, v in additional_filter.items():
            filter += f",{k}={v}"
    if len(filter) > 0:
        params["filter"] = filter

    params.update(additional_params)
    return params


base_path_facets = "/api/catalog/entity-facets"
base_path_entities = "/api/catalog/entities"


def setup_test_users(environment, msg, **kwargs):
    # Fired when the worker receives a message of type 'test_users'
    usernames.extend(map(lambda u: u, msg.data))
    print(f"Usernames: {usernames}")


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


@events.init_command_line_parser.add_listener
def _(parser):
    parser.add_argument("--keycloak-host", type=str, default="")
    parser.add_argument("--keycloak-password", is_secret=True, default="")
    parser.add_argument("--debug", type=bool, default=False)


class MVP1dot2Test(HttpUser):

    def on_start(self):
        self.client.verify = False
        if self.environment.parsed_options.keycloak_host:
            kc_host = self.environment.parsed_options.keycloak_host
            KEYCLOAK_URL = f'https://{kc_host}'
            bs_host = self.environment.host
            REDIRECT_URL = f'{bs_host}/oauth2/callback'
            REFRESH_URL = f'{bs_host}/api/auth/oauth2Proxy/refresh'
            REALM = "backstage"
            CLIENTID = "backstage"

            # Step 1: Get state from refresh URL redirect chain
            r = self.client.get(REFRESH_URL, verify=False,
                                allow_redirects=True)
            parsed = urllib.parse.urlparse(r.url)
            qs = urllib.parse.parse_qs(parsed.query)
            state = qs.get('state', [''])[0]

            # Step 2: Request keycloak auth endpoint to get login form
            auth_url = f'{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/auth'
            auth_params = {
                'client_id': CLIENTID,
                'state': state,
                'redirect_uri': REDIRECT_URL,
                'scope': 'openid email profile',
                'response_type': 'code'
            }
            r = self.client.get(auth_url, verify=False,
                                params=auth_params, allow_redirects=True)

            # Extract action URL from login form
            pattern = r'action="([^"]*)"'
            authenticate_url = re.findall(pattern, r.text)[
                0].replace("&amp;", "&")

            # Extract execution and tab_id from action URL
            parsed_auth = urllib.parse.urlparse(authenticate_url)
            auth_qs = urllib.parse.parse_qs(parsed_auth.query)
            execution = auth_qs.get('execution', [''])[0]
            tab_id = auth_qs.get('tab_id', [''])[0]

            # Step 3: POST credentials to authenticate
            form_data = {
                'username': self.USERNAME,
                'password': self.PASSWORD,
                'credentialId': '',
                'client_id': CLIENTID,
                'tab_id': tab_id,
                'execution': execution
            }
            r = self.client.post(authenticate_url, verify=False, data=form_data,
                                 allow_redirects=False)

            # Get redirect URL with authorization code
            code_url = r.headers.get('Location', '').replace("&amp;", "&")

            # Step 4: Complete OAuth flow - follow the redirect to get token
            r = self.client.get(code_url, verify=False, allow_redirects=True)
            json_dict = json.loads(r.content)
            TOKEN = json_dict['backstageIdentity']['token']

            identity_refs = json_dict['backstageIdentity']['identity']['ownershipEntityRefs']
            for id_ref in identity_refs:
                if str(id_ref).startswith("group"):
                    self.GROUP_REF = id_ref
                    continue
                if str(id_ref).startswith("user"):
                    self.USER_REF = id_ref

            self.HEADER = {'Authorization': 'Bearer ' + TOKEN}
        else:
            r = self.client.get('/api/auth/guest/refresh', verify=False)
            json_dict = json.loads(r.content)
            TOKEN = json_dict['backstageIdentity']['token']

            identity_refs = json_dict['backstageIdentity']['identity']['ownershipEntityRefs']
            for id_ref in identity_refs:
                if str(id_ref).startswith("user"):
                    self.USER_REF = id_ref
                    if "guest" in str(id_ref):
                        self.GROUP_REF = None
                        break
                    continue
                if str(id_ref).startswith("group"):
                    self.GROUP_REF = id_ref

            self.HEADER = {'Authorization': 'Bearer ' + TOKEN}

    def __init__(self, parent):
        super().__init__(parent)
        self.HEADER = ''
        if self.environment.parsed_options.keycloak_host:
            if len(usernames) > 0:
                self.USERNAME = usernames.pop()
            else:
                self.USERNAME = "t_1"
            kc_host = self.environment.parsed_options.keycloak_host
            self.KEYCLOAK_URL = f'https://{kc_host}'
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

    def entities_by_query(self, kind=None, limit=0, user_ref=None, group_ref=None, additional_filter={}, additional_params={}):
        r = self.client.get(f"{base_path_entities}/by-query",
                            verify=False,
                            headers=self.HEADER,
                            params=get_entities_by_query_params(kind, limit, user_ref, group_ref, additional_filter, additional_params))
        if self.environment.parsed_options.debug:
            size = sum(len(chunk) for chunk in r.iter_content(8196))
            debug_output = f"\n[DEBUG][entities_by_query]"
            debug_output += f" kind={kind}"
            debug_output += f", limit={limit}"
            debug_output += f", user_ref={user_ref}"
            debug_output += f", group_ref={group_ref}"
            debug_output += f", additional_filter={additional_filter}"
            debug_output += f", additional_params={additional_params}"
            debug_output += f", response_size={size}"
            debug_output += f", response={r.content}\n"
            print(debug_output)
        return r

    def entities_by_refs(self, refs=[]):
        entity_refs = {"entityRefs": refs}
        r = self.client.post(f"{base_path_entities}/by-refs",
                             verify=False,
                             headers=self.HEADER,
                             json=entity_refs)
        if self.environment.parsed_options.debug:
            size = sum(len(chunk) for chunk in r.iter_content(8196))
            debug_output = f"\n[DEBUG][entities_by_refs]"
            debug_output += f", refs={refs}"
            debug_output += f", response_size={size}"
            debug_output += f", response={r.content}\n"
            print(debug_output)

    @task
    def execute(self) -> None:
        # Load Catalog
        group_ref = self.GROUP_REF
        if "guest" in self.USER_REF:
            group_ref = "group:default/group1"
        self.entitiy_facets("relations.ownedBy")
        self.entitiy_facets("kind")
        self.entitiy_facets("spec.lifecycle")
        self.entitiy_facets("metadata.tags")
        self.entitiy_facets("metadata.namespace")
        self.entities_by_query(kind="component", limit=20)
        self.entities_by_query(kind="component", limit=20)
        self.entitiy_facets("component/spec.type")
        self.entities_by_query(
            kind="component", limit=0,
            user_ref=self.USER_REF, group_ref=group_ref)
        self.entities_by_query(kind="component", limit=0)
        self.entitiy_facets("component/spec.lifecycle")
        self.entitiy_facets("component/metadata.tags")
        self.entitiy_facets("component/metadata.namespace")
        self.entities_by_refs([group_ref])
        self.entities_by_query(
            kind="component", limit=20,
            user_ref=self.USER_REF, group_ref=group_ref)

        # Switch to API
        self.entities_by_query(
            kind="api", limit=20,
            user_ref=self.USER_REF, group_ref=group_ref)
        self.entitiy_facets("api/spec.type")
        self.entities_by_query(
            kind="api", limit=0,
            user_ref=self.USER_REF, group_ref=group_ref)
        self.entities_by_query(kind="api", limit=0)
        self.entitiy_facets("api/spec.lifecycle")
        self.entitiy_facets("api/metadata.tags")
        self.entitiy_facets("api/metadata.namespace")

        # Switch to Component
        self.entities_by_query(
            kind="component", limit=20,
            user_ref=self.USER_REF, group_ref=group_ref)
        self.entitiy_facets("component/spec.lifecycle")
        self.entities_by_query(
            kind="component", limit=0,
            user_ref=self.USER_REF, group_ref=group_ref)
        self.entities_by_query(kind="component", limit=0)
        self.entitiy_facets("component/spec.lifecycle")
        self.entitiy_facets("component/metadata.tags")
        self.entitiy_facets("component/metadata.namespace")
        self.entities_by_refs([group_ref])

        # Select "library"
        self.entities_by_query(
            kind="component", limit=20,
            user_ref=self.USER_REF, group_ref=group_ref,
            additional_filter={"spec_type": "library"})
        self.entities_by_query(
            kind="component", limit=0,
            user_ref=self.USER_REF, group_ref=group_ref,
            additional_filter={"spec_type": "library"})
        self.entities_by_query(
            kind="component", limit=0,
            additional_filter={"spec_type": "library"})
        self.entities_by_query(kind="component", limit=20)
        self.entities_by_refs([group_ref])

        # Select "all"
        self.entities_by_query(
            kind="component", limit=20,
            group_ref=group_ref)
        self.entities_by_query(
            kind="component", limit=0,
            group_ref=group_ref)
        self.entities_by_refs([group_ref])

        # Select/Load next page
        r = self.entities_by_query(
            kind="component", limit=20,
            group_ref=group_ref)
        json_dict = json.loads(r.content)
        page_info = json_dict["pageInfo"]
        if len(page_info) > 0:
            self.entities_by_query(
                limit=20,
                additional_params={"cursor": page_info["nextCursor"]})
