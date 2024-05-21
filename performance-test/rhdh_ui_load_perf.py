#!/usr/bin/env python3

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
    rhdh_endpoint = os.environ.get('RHDH_ENDPOINT')
    if not rhdh_endpoint:
        raise ValueError("RHDH_ENDPOINT environment variable is not set.")

    with sync_playwright() as p:
        
        # csv report init
        csv_file_obj = open('test.csv', 'w', newline='')
        writer = csv.writer(csv_file_obj)
        writer.writerow([
            "first-paint_start_time",
            "first-contentful-paint_start_time",
            "domContentLoadedEventStart",
            "domContentLoadedEventEnd"
        ])

        browser = p.chromium.launch()
        context = browser.new_context()
        page = context.new_page()

        setup_monitoring()

        page.goto(rhdh_endpoint)

        # Click the 'Enter' button after the page has loaded
        guest_enter_button = page.wait_for_selector('//span[@class="MuiButton-label-222" and text()="Enter"]')
        guest_enter_button.click()

        # Get the current process ID
        current_pid = os.getpid()

        # Create a psutil.Process object for the current process
        process = psutil.Process(pid=current_pid)

        # Get CPU times and IO counters before opening the browser
        cpu_times_before = process.cpu_times()
        io_counters_before = psutil.net_io_counters()

        expected_title = "Welcome back! | Red Hat Developer Hub"

        # Wait for the page to load and assert the title
        for i in range(10):
            page.wait_for_selector('//h1[contains(text(),"Welcome back!")]')
            
            # info about painting the page (rendering)
            paint_info = page.evaluate("\nwindow.performance.getEntriesByType('paint')")
            print(paint_info)

            # info about DOM complete duration etc
            navigation_info = page.evaluate("performance.getEntriesByType('navigation')")
            print(navigation_info)
            
            writer.writerow([
                paint_info[0]['startTime'],
                paint_info[1]['startTime'],
                navigation_info[0]['domContentLoadedEventStart'],
                navigation_info[0]['domContentLoadedEventEnd']
            ])
            assert page.title() == expected_title
            page.reload()

        # Get CPU times and IO counters after the page has loaded
        cpu_times_after = process.cpu_times()
        io_counters_after = psutil.net_io_counters()

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

        bytes_sent_diff = io_counters_after.bytes_sent - io_counters_before.bytes_sent
        bytes_recv_diff = io_counters_after.bytes_recv - io_counters_before.bytes_recv
        packets_sent_diff = io_counters_after.packets_sent - io_counters_before.packets_sent
        packets_recv_diff = io_counters_after.packets_recv - io_counters_before.packets_recv

        # Print IO counters differences
        print("Bytes sent diff:", bytes_sent_diff)
        print("Bytes received diff:", bytes_recv_diff)
        print("Packets sent diff:", packets_sent_diff)
        print("Packets received diff:", packets_recv_diff)

        # close csv report file object
        csv_file_obj.close()

        teardown_monitoring()
        browser.close()

if __name__ == "__main__":
    main()
