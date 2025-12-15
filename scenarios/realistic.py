from locust import HttpUser, events, task, between
from locust.runners import MasterRunner, WorkerRunner
from urllib3.exceptions import InsecureRequestWarning
import urllib.parse
import json
import re
import uuid
import time
import urllib3
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Any
from enum import Enum
from collections import defaultdict

urllib3.disable_warnings(InsecureRequestWarning)

__version__ = "1.0"

usernames = []

class PermitResult(Enum):
    ALLOW = "ALLOW"
    DENY = "DENY"
    ERROR = "ERROR"

@dataclass
class APIAction:
    method: str
    endpoint: str
    body: Optional[Dict] = None
    description: str = ""


@dataclass
class Permission:
    name: str
    action: str
    plugin: str
    workflow: List[APIAction] = field(default_factory=list)
    enabled: bool = True

PERMISSIONS: Dict[str, Permission] = {}

PERMISSIONS["catalog-entity"] = Permission(
    name="catalog-entity",
    action="read",
    plugin="catalog",
    workflow=[
        APIAction("GET", "/api/catalog/entities/by-query?limit=20", description="Query entities with pagination"),
        APIAction("GET", "/api/catalog/entities?filter=kind=Component", description="Filter components"),
        APIAction("GET", "/api/catalog/entities?filter=kind=API", description="Filter APIs"),
        APIAction("GET", "/api/catalog/entities?filter=kind=User", description="Filter users"),
        APIAction("GET", "/api/catalog/entities?filter=kind=Group", description="Filter groups"),
        APIAction("GET", "/api/catalog/entities?filter=kind=System", description="Filter systems"),
        APIAction("GET", "/api/catalog/entities?filter=kind=Domain", description="Filter domains"),
        APIAction("GET", "/api/catalog/entities?filter=kind=Resource", description="Filter resources"),
        APIAction("GET", "/api/search/query?term=component", description="Search for components"),
        APIAction("GET", "/api/search/query?term=api", description="Search for APIs"),
        APIAction("GET", "/api/search/query?term=service", description="Search for services"),
    ]
)

PERMISSIONS["catalog.location.read"] = Permission(
    name="catalog.location.read",
    action="read",
    plugin="catalog",
    workflow=[
        APIAction("GET", "/api/catalog/locations", description="List all locations"),
    ]
)

PERMISSIONS["policy-entity"] = Permission(
    name="policy-entity",
    action="read",
    plugin="rbac",
    workflow=[
        APIAction("GET", "/api/permission/policies", description="List all policies"),
        APIAction("GET", "/api/permission/roles", description="List all roles"),
        APIAction("GET", "/api/permission/plugins/policies", description="List plugin policies"),
        APIAction("GET", "/api/permission/plugins/condition-rules", description="List condition rules"),
    ]
)

PERMISSIONS["scaffolder-template"] = Permission(
    name="scaffolder-template",
    action="read",
    plugin="scaffolder",
    workflow=[
        APIAction("GET", "/api/catalog/entities?filter=kind=Template", description="List templates via catalog"),
    ]
)

PERMISSIONS["scaffolder.task.read"] = Permission(
    name="scaffolder.task.read",
    action="read",
    plugin="scaffolder",
    workflow=[
        APIAction("GET", "/api/scaffolder/v2/tasks", description="List all tasks"),
    ]
)

PERMISSIONS["scaffolder.action.read"] = Permission(
    name="scaffolder.action.read",
    action="read",
    plugin="scaffolder",
    workflow=[
        APIAction("GET", "/api/scaffolder/v2/actions", description="List available actions"),
    ]
)

PERMISSIONS["scaffolder.template.management"] = Permission(
    name="scaffolder.template.management",
    action="read",
    plugin="scaffolder",
    workflow=[
        APIAction("GET", "/api/scaffolder/v2/actions", description="View template management actions"),
    ]
)

PERMISSIONS["orchestrator.workflow.use"] = Permission(
    name="orchestrator.workflow.use",
    action="update",
    plugin="orchestrator",
    enabled=False,  # Disabled by default, enabled if plugin detected
    workflow=[
        APIAction("POST", "/api/orchestrator/v2/workflows/overview", {}, "Get workflows overview"),
        APIAction("POST", "/api/orchestrator/v2/workflows/instances", {}, "List workflow instances"),
    ]
)

PERMISSIONS["orchestrator.workflow.read"] = Permission(
    name="orchestrator.workflow.read",
    action="read",
    plugin="orchestrator",
    enabled=False,
    workflow=[
        APIAction("POST", "/api/orchestrator/v2/workflows/overview", {}, "Read workflows overview"),
    ]
)

base_policy_auth = "/api/permission/authorize"


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
            users.append(f"t{i}")

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
    parser.add_argument("--debug", type=bool, default=True)
    parser.add_argument("--enable-orchestrator", type=bool, default=False)


class RealisticTest(HttpUser):
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
            idetity_refs = json_dict['backstageIdentity']['identity']['ownershipEntityRefs']
            for id_ref in idetity_refs:
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

            idetity_refs = json_dict['backstageIdentity']['identity']['ownershipEntityRefs']
            for id_ref in idetity_refs:
                if str(id_ref).startswith("user"):
                    self.USER_REF = id_ref
                    if "guest" in str(id_ref):
                        self.GROUP_REF = None
                        break
                    continue
                if str(id_ref).startswith("group"):
                    self.GROUP_REF = id_ref

            self.HEADER = {'Authorization': 'Bearer ' + TOKEN}

        if self.environment.parsed_options.enable_orchestrator:
            self.enable_plugin("orchestrator")

    def __init__(self, parent):
        super().__init__(parent)
        self.HEADER = ''
        if self.environment.parsed_options.keycloak_host:
            if len(usernames) > 0:
                self.USERNAME = usernames.pop()
            else:
                self.USERNAME = "t1"
            kc_host = self.environment.parsed_options.keycloak_host
            self.KEYCLOAK_URL = f'https://{kc_host}/auth'
            bs_host = self.environment.host
            self.REDIRECT_URL = f'{bs_host}/oauth2/callback'
            self.REFRESH_URL = f'{bs_host}/api/auth/oauth2Proxy/refresh'

            self.PASSWORD = self.environment.parsed_options.keycloak_password
            self.REALM = "backstage"
            self.CLIENTID = "backstage"

    def enable_plugin(self, plugin):
        for perm_name, perm_config in PERMISSIONS.items():
            if perm_config.plugin == plugin:
                perm_config.enabled = True

    def authorize_policy(self, policy, config) -> str:
        r = self.client.post(base_policy_auth,
                            verify=False,
                            headers=self.HEADER,
                            name=f"[AUTH] {policy}",
                            json={"items": [
                                    {
                                        "id": str(uuid.uuid4()),
                                        "permission": {
                                            "type": "basic",
                                            "name": policy,
                                            "attributes": {
                                                "action": config.action
                                            }
                                        }
                                    }
                                ]
                        })
        try:
            result = r.json()["items"][0]["result"]
        except (KeyError, IndexError, json.JSONDecodeError):
            result = "ERROR"

        if self.environment.parsed_options.debug:
            size = sum(len(chunk) for chunk in r.iter_content(8196))
            debug_output = f"\n[DEBUG][authorize_permissions]"
            debug_output += f", name={policy}"
            debug_output += f", action={config.action}"
            debug_output += f", response_size={size}"
            debug_output += f", response={r.content}\n"
            print(debug_output)

        return result

    def execute_action(self, action, permit, policy):
        endpoint = action.endpoint
        method = action.method

        if method == "GET":
            r = self.client.get(
                endpoint,
                headers=self.HEADER,
                verify=False,
                name=f"{endpoint}|{permit}"
            )
        elif method == "POST":
            body = action.body
            r = self.client.post(
                endpoint,
                verify=False,
                headers=self.HEADER,
                json=body,
                name=f"{endpoint}|{permit}"
            )
        else:
            r = {}

        if self.environment.parsed_options.debug:
            size = sum(len(chunk) for chunk in r.iter_content(8196))
            debug_output = f"\n[DEBUG][api call]"
            debug_output += f", endpoint={endpoint}"
            debug_output += f", response_size={size}"
            debug_output += f", response={r.content}\n"
            print(debug_output)
        return r

    @task
    def test_all_permissions_sequential(self):
        """Test all enabled permissions sequentially"""
        for perm_name, perm in PERMISSIONS.items():
            if not perm.enabled:
                continue

            result = self.authorize_policy(perm_name, perm)
            if result != PermitResult.ERROR:
                for action in perm.workflow:
                    self.execute_action(action, result, perm)

