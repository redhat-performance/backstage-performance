import pytest
from playwright.sync_api import Page
import time
import os
import psutil


@pytest.fixture(scope="function")
def access(page: Page):
    page.goto(
        "https://rhdh-redhat-developer-hub-rhdh-performance.apps.rhperfcluster.ptjz.p1.openshiftapps.com/"
    )
    guestEnterButton = page.wait_for_selector(
        '//span[@class="MuiButton-label-222" and text()="Enter"]'
    )
    guestEnterButton.click()


# ==================================================TODO===============================================================
# def test_github_sigin(browser):
# pass


def test_guest_enter(page: Page, access):

    expected_title = "Welcome back! | Red Hat Developer Hub"
    page.wait_for_selector('//h1[contains(text(),"Welcome back!")]')
    print(
        page.evaluate("window.performance.getEntriesByType('paint')")
    )  # info painting page(rendering)
    print(
        page.evaluate("performance.getEntriesByType('navigation')")
    )  # info about dom complete duration etc
    assert page.title() == expected_title


def test_search_bar(page: Page, access):

    searchBar = page.wait_for_selector(
        "#search-bar-text-field"
    )  # here '#' is used to grep id tag elements
    searchBar.type("demo")  # Type demo in big search bar
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


def test_catalog(page: Page, access):

    catalog = page.wait_for_selector('//span[contains(text(), "Catalog")]')
    catalog.click()

    createButton = page.wait_for_selector('//span[contains(text(), "Create")]')
    createButton.click()

    registerExistingComponent = page.wait_for_selector(
        '//span[contains(text(), "Register Existing Component")]'
    )
    registerExistingComponent.click()

    url = page.wait_for_selector("#url")
    url.type("https://github.com/backstage/backstage/blob/master/catalog-info.yaml")

    analyzeButton = page.wait_for_selector('//span[contains(text(), "Analyze")]')
    analyzeButton.click()

    page.wait_for_timeout(2000)  # 2 seconds for processing
    importButton = page.wait_for_selector('//span[contains(text(),"Import")]')
    importButton.click()

    viewComponent = page.wait_for_selector('//span[contains(text(),"View Component")]')
    viewComponent.click()

    page.wait_for_timeout(2000)  # 2 seconds for processing
    assert page.title() == "backstage | Overview | Red Hat Developer Hub"
    page.wait_for_timeout(5000)
