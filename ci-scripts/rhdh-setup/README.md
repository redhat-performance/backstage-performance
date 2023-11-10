# rhdh-setup
Run `./deploy.sh` to setup backstage with keycloak.
The script expects `QUAY_TOKEN` and `GITHUB_TOKEN` to be set.

Run with `-r` to delete backstage and redeploy again `./deploy.sh -r`. This is used to syc up users and groups from keycloak.

Run with `-d` to delete backstage only.
