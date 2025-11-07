from locust import HttpUser, events, task
from locust.runners import MasterRunner, WorkerRunner
from requests import Response
from urllib3.exceptions import InsecureRequestWarning
import urllib.parse
import json
import re
import urllib3
import uuid

urllib3.disable_warnings(InsecureRequestWarning)

__version__ = "1"

usernames = []

base_path_orchestrator = "/api/orchestrator/v2"
base_path_permission = "/api/permission"


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
    parser.add_argument("--debug", type=bool, default=False)


class OrchestratorTest(HttpUser):

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

    def workflows_overview(self) -> Response:
        r = self.client.post(f"{base_path_orchestrator}/workflows/overview",
                             verify=False,
                             headers=self.HEADER,
                             json={})
        if self.environment.parsed_options.debug:
            size = sum(len(chunk) for chunk in r.iter_content(8196))
            debug_output = f"\n[DEBUG][workflows_overview]"
            debug_output += f", response_size={size}"
            debug_output += f", response={r.content}\n"
            print(debug_output)
        return r

    def authorize_permission(self, name: str, action: str) -> Response:
        r = self.client.post(f"{base_path_permission}/authorize",
                             verify=False,
                             headers=self.HEADER,
                             json={"items": [
                                 {
                                     "id": str(uuid.uuid4()),
                                     "permission": {
                                         "type": "basic",
                                         "name": name,
                                         "attributes": {
                                             "action": action
                                         }
                                     }
                                 }
                             ]
        })
        if self.environment.parsed_options.debug:
            size = sum(len(chunk) for chunk in r.iter_content(8196))
            debug_output = f"\n[DEBUG][authorize_permissions]"
            debug_output += f", name={name}"
            debug_output += f", action={action}"
            debug_output += f", response_size={size}"
            debug_output += f", response={r.content}\n"
            print(debug_output)
        return r

    def execute_workflow(self, workflow_name: str, input_data: dict) -> Response:
        r = self.client.post(f"{base_path_orchestrator}/workflows/{workflow_name}/execute",
                             verify=False,
                             headers=self.HEADER,
                             json={"inputData": input_data, "authTokens": []})
        if self.environment.parsed_options.debug:
            size = sum(len(chunk) for chunk in r.iter_content(8196))
            debug_output = f"\n[DEBUG][execute_workflow]"
            debug_output += f", workflow_name={workflow_name}"
            debug_output += f", input_data={input_data}"
            debug_output += f", response_size={size}"
            debug_output += f", response={r.content}\n"
            print(debug_output)
        return r

    def get_workflow_instance_by_id(self, id: str) -> Response:
        r = self.client.get(f"{base_path_orchestrator}/workflows/instances/{id}",
                            verify=False,
                            headers=self.HEADER)
        if self.environment.parsed_options.debug:
            size = sum(len(chunk) for chunk in r.iter_content(8196))
            debug_output = f"\n[DEBUG][get_workflow_instance_by_id]"
            debug_output += f", id={id}"
            debug_output += f", response_size={size}"
            debug_output += f", response={r.content}\n"
            print(debug_output)
        return r

    def get_workflow_instances(self, workflow_name: str) -> Response:
        r = self.client.post(f"{base_path_orchestrator}/workflows/instances",
                             verify=False,
                             headers=self.HEADER,
                             json={"paginationInfo": {"pageSize": 21, "offset": 0, "orderBy": "start", "orderDirection": "DESC"}, "filters": {"operator": "EQ", "value": workflow_name, "field": "processId"}})
        if self.environment.parsed_options.debug:
            size = sum(len(chunk) for chunk in r.iter_content(8196))
            debug_output = f"\n[DEBUG][get_workflow_instances]"
            debug_output += f", workflow_name={workflow_name}"
            debug_output += f", response_size={size}"
            debug_output += f", response={r.content}\n"
            print(debug_output)
        return r

    @task
    def execute(self) -> None:
        self.workflows_overview()
        self.authorize_permission("orchestrator.workflow.use", "update")
        r = self.execute_workflow("basic", {"projectName": "test"})
        wf_json = json.loads(r.content)
        self.get_workflow_instance_by_id(wf_json["id"])
        self.get_workflow_instances("basic")
