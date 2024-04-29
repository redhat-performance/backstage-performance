
import pytest
from playwright.sync_api import Page

@pytest.fixture(scope="function")
def access(page:Page):
    page.goto(
        "https://rhdh-redhat-developer-hub-rhdh-performance.apps.rhperfcluster.ptjz.p1.openshiftapps.com/"
    )
    page.wait_for_load_state("networkidle")
    guestEnterButton = page.wait_for_selector(
        '//span[@class="MuiButton-label-222" and text()="Enter"]'
    )
    guestEnterButton.click()


def test_guest_enter(page:Page, access):

    # Assertion: Check if the page title matches the expected title
    page.wait_for_timeout(5000)
    assert page.title() == "Welcome back! | Red Hat Developer Hub"


# ==================================================TODO===============================================================
# def test_github_sigin(browser):


def test_search_bar(page: Page, access):

    searchBar = page.wait_for_selector(
        "#search-bar-text-field"
    )  # here '#' is used to grep id tag elements
    searchBar.type("demo")  # Type demo in bug search bar
    searchBar.press("Enter")  # Press enter after typing demo

    markElement = page.wait_for_selector(
        '//mark[contains(text(), "demo")]'
    )  # We are catching the element with tag and text since class is dynamic and changes with every reload
    markElement.click()

    page.wait_for_timeout(5000)  # 5 seconds delay (5000 milliseconds)
    assert page.title() == "demo | Overview | Red Hat Developer Hub"


def test_learning_path(page: Page, access):

    learningPathButton = page.wait_for_selector(
        '//span[contains(text(), "Learning Paths")]'
    )
    learningPathButton.click()

    availableOptions = [
        "Building Operators on OpenShift",
        "Configure a Jupyter notebook to use GPUs for AI/ML modeling",
        "Deploy a Spring application on OpenShift",
        "Deploy and manage your first API",
    ]  # Many available picked few of them

    for index, option in enumerate(availableOptions, start=1):
        print(f"{index}. {option}")

    desiredChoice = ""  # This is what user wants to press on Learning Paths
    while True:
        choice = input("Enter the number corresponding to your choice:")
        try:
            choice_index = int(choice)
            if 1 <= choice_index <= len(availableOptions):
                desiredChoice = availableOptions[choice_index - 1]  # Store in variable
                break
            else:
                print("Invalid choice. Please enter a valid number.")
        except ValueError:
            print("Invalid input. Please enter a number.")

    learningSelect = page.wait_for_selector(
        f'//span[contains(text(), "{desiredChoice}")]'
    )
    learningSelect.click()
    page.wait_for_timeout(5000)  # 5 seconds delay (5000 milliseconds)
