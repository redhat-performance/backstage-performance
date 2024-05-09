from playwright.sync_api import sync_playwright
import time
import os
import psutil
from utils.monitor import MemoryMonitor  # this is a custom utility for monitoring memory

monitor = None

def setup_monitoring():
    global monitor
    print("\nSetting up monitoring...")
    # Start monitoring thread
    monitor = MemoryMonitor()
    monitor.start()

def teardown_monitoring():
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

def main():
    with sync_playwright() as p:
        browser = p.chromium.launch()
        context = browser.new_context()
        page = context.new_page()

        setup_monitoring()

        page.goto("https://rhdh-redhat-developer-hub-rhdh-performance.apps.rhperfcluster.ptjz.p1.openshiftapps.com/")

        # Click the 'Enter' button after the page has loaded
        guest_enter_button = page.wait_for_selector('//span[@class="MuiButton-label-222" and text()="Enter"]')
        guest_enter_button.click()

        # Get the current process ID
        current_pid = os.getpid()

        # Create a psutil.Process object for the current process
        process = psutil.Process(pid=current_pid)

        # Get CPU times and IO counters before opening the browser
        cpu_times_before = process.cpu_times()
        io_counters_before = process.io_counters()

        expected_title = "Welcome back! | Red Hat Developer Hub"

        # Wait for the page to load and assert the title
        for i in range(10):
            page.wait_for_selector('//h1[contains(text(),"Welcome back!")]')
            print(
                page.evaluate("\nwindow.performance.getEntriesByType('paint')")
            )  # info about painting the page (rendering)
            print(
                page.evaluate("performance.getEntriesByType('navigation')")
            )  # info about DOM complete duration etc
            assert page.title() == expected_title
            page.reload()

        # Get CPU times and IO counters after the page has loaded
        cpu_times_after = process.cpu_times()
        io_counters_after = process.io_counters()

        print("CPU times before:", cpu_times_before)
        print("CPU times after:", cpu_times_after)
        print("io counter before:", io_counters_before)
        print("io counter after:", io_counters_after)

        # Calculate CPU time differences
        user_time_diff = cpu_times_after.user - cpu_times_before.user
        system_time_diff = cpu_times_after.system - cpu_times_before.system
        children_user_time_diff = cpu_times_after.children_user - cpu_times_before.children_user
        children_system_time_diff = cpu_times_after.children_system - cpu_times_before.children_system

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

        teardown_monitoring()
        browser.close()

if __name__ == "__main__":
    main()
