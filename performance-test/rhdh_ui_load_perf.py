#!/usr/bin/env python3

from playwright.sync_api import sync_playwright
import time
import os
import psutil
import csv
from utils.monitor import (
    MemoryMonitor,
)  # this is a custom utility for monitoring memory
from rich.progress import Progress
from rich.console import Console

monitor = None
console = Console()


def setup_monitoring():
    global monitor
    console.print("\n[bold green]Setting up monitoring...[/bold green]")
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

    console.print(
        f"[bold yellow]Average Memory Usage (RSS, VMS, Shared):[/bold yellow] {avg_rss:.2f} MB, {avg_vms:.2f} MB, {avg_shared:.2f} MB"
    )


def main():
    rhdh_endpoint = os.environ.get("endpoint")
    customReload = int(os.environ.get("reload"))
    if not rhdh_endpoint:
        raise ValueError("RHDH_ENDPOINT environment variable is not set.")

    with sync_playwright() as p:

        # csv report init
        csv_file_obj = open("test.csv", "w", newline="")
        writer = csv.writer(csv_file_obj)
        writer.writerow(
            [
                "first-paint_start_time",
                "first-contentful-paint_start_time",
                "domContentLoadedEventStart",
                "domContentLoadedEventEnd",
                "domComplete",
            ]
        )

        browser = p.chromium.launch()
        context = browser.new_context()
        page = context.new_page()

        setup_monitoring()

        page.goto(rhdh_endpoint)

        # Click the 'Enter' button after the page has loaded
        guest_enter_button = page.wait_for_selector(
            '//span[@class="MuiButton-label-222" and text()="Enter"]'
        )
        guest_enter_button.click()

        # Get the current process ID
        current_pid = os.getpid()

        # Create a psutil.Process object for the current process
        process = psutil.Process(pid=current_pid)

        # Get CPU times and IO counters before opening the browser
        cpu_times_before = process.cpu_times()

        expected_title = "Welcome back! | Red Hat Developer Hub"

        with Progress() as progress:
            reload_task = progress.add_task("[cyan]Reloading...", total=customReload)

            # Wait for the page to load and assert the title
            for i in range(customReload):
                page.wait_for_selector('//h1[contains(text(),"Welcome back!")]')

                # info about painting the page (rendering)
                paint_info = page.evaluate(
                    "\nwindow.performance.getEntriesByType('paint')"
                )
                # console.print(paint_info)

                # info about DOM complete duration etc
                navigation_info = page.evaluate(
                    "performance.getEntriesByType('navigation')"
                )
                # console.print(navigation_info)

                writer.writerow(
                    [
                        paint_info[0]["startTime"],
                        paint_info[1]["startTime"],
                        navigation_info[0]["domContentLoadedEventStart"],
                        navigation_info[0]["domContentLoadedEventEnd"],
                        navigation_info[0]["domComplete"],
                    ]
                )
                assert page.title() == expected_title
                page.reload()

                progress.update(reload_task, advance=1)

        # Get CPU times and IO counters after the page has loaded
        cpu_times_after = process.cpu_times()

        console.print("[bold blue]CPU times before:[/bold blue]", cpu_times_before)
        console.print("[bold blue]CPU times after:[/bold blue]", cpu_times_after)

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
        console.print(
            "[bold green]User CPU time during page load:[/bold green]", user_time_diff
        )
        console.print(
            "[bold green]System CPU time during page load:[/bold green]",
            system_time_diff,
        )
        console.print(
            "[bold green]Children User CPU time during page load:[/bold green]",
            children_user_time_diff,
        )
        console.print(
            "[bold green]Children System CPU time during page load:[/bold green]",
            children_system_time_diff,
        )

        # close csv report file object
        csv_file_obj.close()

        teardown_monitoring()
        browser.close()


if __name__ == "__main__":
    main()
