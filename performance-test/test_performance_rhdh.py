import pytest
from playwright.sync_api import Page
import time
import os
import psutil
from utils.monitor import MemoryMonitor

monitor = None


def setup_module(module):
    global monitor
    print("\nSetting up monitoring...")
    # Start monitoring thread
    monitor = MemoryMonitor()
    monitor.start()


def teardown_module(module):
    global monitor
    monitor.stop()
    monitor.join()

    # Calculate average memory usage
    avg_rss = sum(monitor.rss_usage) / len(monitor.rss_usage) / (1024 * 1024)
    avg_vms = sum(monitor.vms_usage) / len(monitor.vms_usage) / (1024 * 1024)
    avg_shared = sum(monitor.shared_usage) / len(monitor.shared_usage) / (1024 * 1024)

    print(
        f"Average Memory Usage (RSS, VMS, Shared): {avg_rss:.2f} MB, {avg_vms:.2f} MB, {avg_shared:.2f} MB"
    )


@pytest.fixture(scope="function")
def access(page: Page):
    page.goto(
        "https://rhdh-redhat-developer-hub-rhdh-performance.apps.rhperfcluster.ptjz.p1.openshiftapps.com/"
    )
    guestEnterButton = page.wait_for_selector(
        '//span[@class="MuiButton-label-222" and text()="Enter"]'
    )
    guestEnterButton.click()


def test_guest_enter(page: Page, access):
    # Get the current process ID
    current_pid = os.getpid()

    # Create a psutil.Process object for the current process
    p = psutil.Process(pid=current_pid)

    # Get CPU times and IO counters before opening the browser
    cpu_times_before = p.cpu_times()
    io_counters_before = p.io_counters()

    expected_title = "Welcome back! | Red Hat Developer Hub"

    # Wait for the page to load and assert the title
    for i in range(100):
        page.wait_for_selector('//h1[contains(text(),"Welcome back!")]')
        assert page.title() == expected_title
        page.reload()

    # Get CPU times and IO counters after the page has loaded
    cpu_times_after = p.cpu_times()
    io_counters_after = p.io_counters()

    print("CPU times before:", cpu_times_before)
    print("CPU times after:", cpu_times_after)
    print("io counter before:", io_counters_before)
    print("io counter after:", io_counters_after)

    # Calculate CPU time differences
    user_time_diff = cpu_times_after.user - cpu_times_before.user
    system_time_diff = cpu_times_after.system - cpu_times_before.system
    children_user_time_diff = (
        cpu_times_after.children_user - cpu_times_before.children_user
    )
    children_system_time_diff = (
        cpu_times_after.children_system - cpu_times_before.children_system
    )

    # Print CPU time differences
    print("User CPU time during page load:", user_time_diff)
    print("System CPU time during page load:", system_time_diff)
    print("Children User CPU time during page load:", children_user_time_diff)
    print("Children System CPU time during page load:", children_system_time_diff)

    # Calculate IO counters differences
    read_count_diff = io_counters_after.read_count - io_counters_before.read_count
    write_count_diff = io_counters_after.write_count - io_counters_before.write_count
    read_bytes_diff = io_counters_after.read_bytes - io_counters_before.read_bytes
    write_bytes_diff = io_counters_after.write_bytes - io_counters_before.write_bytes

    # Print IO counters differences
    print("Read count during page load:", read_count_diff)
    print("Write count during page load:", write_count_diff)
    print("Bytes read during page load:", read_bytes_diff)
    print("Bytes written during page load:", write_bytes_diff)


# ==================================================TODO===============================================================
# def test_github_sigin(browser):
# pass


# def test_search_bar(page: Page, access):

#     searchBar = page.wait_for_selector(
#         "#search-bar-text-field"
#     )  # here '#' is used to grep id tag elements
#     searchBar.type("demo")  # Type demo in big search bar
#     searchBar.press("Enter")  # Press enter after typing demo

#     markElement = page.wait_for_selector(
#         '//mark[contains(text(), "demo")]'
#     )  # We are catching the element with tag and text since class is dynamic and changes with every reload
#     markElement.click()

#     page.wait_for_timeout(5000)  # 5 seconds delay (5000 milliseconds)
#     assert page.title() == "demo | Overview | Red Hat Developer Hub"


# def test_learning_path(page: Page, access):

#     learningPathButton = page.wait_for_selector(
#         '//span[contains(text(), "Learning Paths")]'
#     )
#     learningPathButton.click()

#     availableOptions = [
#         "Building Operators on OpenShift",
#         "Configure a Jupyter notebook to use GPUs for AI/ML modeling",
#         "Deploy a Spring application on OpenShift",
#         "Deploy and manage your first API",
#     ]  # Many available picked few of them

#     for index, option in enumerate(availableOptions, start=1):
#         print(f"{index}. {option}")

#     desiredChoice = ""  # This is what user wants to press on Learning Paths
#     while True:
#         choice = input("Enter the number corresponding to your choice:")
#         try:
#             choice_index = int(choice)
#             if 1 <= choice_index <= len(availableOptions):
#                 desiredChoice = availableOptions[choice_index - 1]  # Store in variable
#                 break
#             else:
#                 print("Invalid choice. Please enter a valid number.")
#         except ValueError:
#             print("Invalid input. Please enter a number.")

#     learningSelect = page.wait_for_selector(
#         f'//span[contains(text(), "{desiredChoice}")]'
#     )
#     learningSelect.click()
#     page.wait_for_timeout(5000)  # 5 seconds delay (5000 milliseconds)


# def test_catalog(page: Page, access):

#     catalog = page.wait_for_selector('//span[contains(text(), "Catalog")]')
#     catalog.click()

#     createButton = page.wait_for_selector('//span[contains(text(), "Create")]')
#     createButton.click()

#     registerExistingComponent = page.wait_for_selector(
#         '//span[contains(text(), "Register Existing Component")]'
#     )
#     registerExistingComponent.click()

#     url = page.wait_for_selector("#url")
#     url.type("https://github.com/backstage/backstage/blob/master/catalog-info.yaml")

#     analyzeButton = page.wait_for_selector('//span[contains(text(), "Analyze")]')
#     analyzeButton.click()

#     page.wait_for_timeout(2000)  # 2 seconds for processing
#     importButton = page.wait_for_selector('//span[contains(text(),"Import")]')
#     importButton.click()

#     viewComponent = page.wait_for_selector('//span[contains(text(),"View Component")]')
#     viewComponent.click()

#     page.wait_for_timeout(2000)  # 2 seconds for processing
#     assert page.title() == "backstage | Overview | Red Hat Developer Hub"
#     page.wait_for_timeout(5000)
