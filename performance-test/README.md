
## Playwright Test Automation

This repository contains automated tests using Playwright for testing web applications.

### Requirements

- **Playwright**: Playwright is required to run these tests.

### Installation

1. Install `pytest-playwright` using pip: `pip install pytest-playwright`
2. Install Playwright dependencies: `playwright install`

### Running Tests

To run the tests using pytest: `pytest -sv`

#### Debug Mode

To run the tests in debug mode (with additional debugging output): `PWDEBUG=1 pytest -sv`

#### Visual Output

To enable tracing and view visible output: `pytest -sv --tracing on`

After running the tests with tracing enabled, you can find the trace output in the `test-results/<test-file>/trace.zip` directory.

To view the trace output using Playwright: `playwright show-trace test-results/<test-file>/trace.zip`







