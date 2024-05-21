
## Playwright Test Automation

This repository contains automated tests using Playwright for testing web applications.

### Requirements

- **Playwright**: Playwright is required to run these tests.

### Running Container

`podman run -e endpoint="https://rhdh-redhat-developer-hub-rhdh-performance.apps.rhperfcluster.ptjz.p1.openshiftapps.com/" -e reload=10 -it quay.io/rhcloudperfscale/rhdh_ui_load_perf:<latest-tag>`

### Local Testing
1. `podman build -t q1 .`
2. `podman run -e endpoint="https://rhdh-redhat-developer-hub-rhdh-performance.apps.rhperfcluster.ptjz.p1.openshiftapps.com/" -e reload=10 -it localhost/q1`







