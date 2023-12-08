# rhdh-setup
Run `./deploy.sh -i` to install backstage with keycloak.

The script expects follwoing environmental variables to be set:
* `QUAY_TOKEN`
* `GITHUB_TOKEN`
* `GITHUB_USER`
* `GITHUB_REPO`

Run with `-r` to delete backstage and redeploy again `./deploy.sh -r`. This is used to syc up users and groups from keycloak.

Run with `-d` to delete backstage only.

Run with `-c` to create objects (Users, Groups, Components and APIs).
