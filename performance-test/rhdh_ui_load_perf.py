#!/usr/bin/env python3

from playwright.sync_api import sync_playwright
import time
import os
import psutil
import csv
import socket
from utils.monitor import MemoryMonitor  # custom utility for monitoring memory
from rich.progress import Progress
from rich.console import Console
from rich.table import Table
import pandas as pd

console = Console()


def print_csv_as_table(file_path):
    df = pd.read_csv(file_path)
    table = Table(show_header=True, header_style="bold magenta")
    for column in df.columns:
        table.add_column(column)
    for _, row in df.iterrows():
        table.add_row(*map(str, row.values))
    console.print(table)


def main():
    rhdh_endpoint = os.environ.get("endpoint")
    customReload = int(os.environ.get("reload"))
    if not rhdh_endpoint:
        raise ValueError("RHDH_ENDPOINT environment variable is not set.")

    hostname = socket.gethostname()

    with sync_playwright() as p:
        csv_file_path = "test.csv"
        csv_file_obj = open(csv_file_path, "w", newline="")
        writer = csv.writer(csv_file_obj)
        writer.writerow(
            [
                "current_time",
                "hostname",
                "first-paint_start_time",
                "first-contentful-paint_start_time",
                "domContentLoadedEventStart",
                "domContentLoadedEventEnd",
                "domComplete",
                "cputimes_user_diff",
                "cputimes_system_diff",
                "cputimes_iowait_diff",
                "rss_memory",
                "vms_memory",
                "shared_memory",
                "bytes_sent_diff",
                "bytes_recv_diff",
                "pkts_sent_diff",
                "pkts_recv_diff",
            ]
        )

        browser = p.chromium.launch()
        context = browser.new_context()
        page = context.new_page()

        page.goto(rhdh_endpoint)

        guest_enter_button = page.wait_for_selector(
            '//span[@class="MuiButton-label-222" and text()="Enter"]'
        )
        guest_enter_button.click()

        current_pid = os.getpid()
        process = psutil.Process(pid=current_pid)
        expected_title = "Welcome back! | Red Hat Developer Hub"

        with Progress() as progress:
            reload_task = progress.add_task("[cyan]Reloading...", total=customReload)

            for i in range(customReload):
                monitor = MemoryMonitor()
                monitor.start()

                # Record the CPU times before the page reload
                cpu_times_before = process.cpu_times()
                network_before = psutil.net_io_counters()

                page.reload()
                page.wait_for_selector('//h1[contains(text(),"Welcome back!")]')
                paint_info = page.evaluate(
                    "window.performance.getEntriesByType('paint')"
                )
                navigation_info = page.evaluate(
                    "performance.getEntriesByType('navigation')"
                )
                assert page.title() == expected_title
                progress.update(reload_task, advance=1)

                # Stop monitoring before reload
                network_after = psutil.net_io_counters()
                monitor.stop()
                monitor.join()

                # Calculate the average memory usage during the monitoring period
                avg_rss = (
                    sum(monitor.rss_usage) / len(monitor.rss_usage) / (1024 * 1024)
                )
                avg_vms = (
                    sum(monitor.vms_usage) / len(monitor.vms_usage) / (1024 * 1024)
                )
                avg_shared = (
                    sum(monitor.shared_usage)
                    / len(monitor.shared_usage)
                    / (1024 * 1024)
                )

                # Record the CPU times after the page reload
                cpu_times_after = process.cpu_times()

                bytes_sent_diff = network_after.bytes_sent - network_before.bytes_sent
                bytes_recv_diff = network_after.bytes_recv - network_before.bytes_recv
                pkts_sent_diff = (
                    network_after.packets_sent - network_before.packets_sent
                )
                pkts_recv_diff = (
                    network_after.packets_recv - network_before.packets_recv
                )

                # Calculate the differences in CPU times
                cpu_times_user_diff = cpu_times_after.user - cpu_times_before.user
                cpu_times_system_diff = cpu_times_after.system - cpu_times_before.system
                cpu_times_iowait_diff = cpu_times_after.iowait - cpu_times_before.iowait

                current_time = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())

                writer.writerow(
                    [
                        current_time,
                        hostname,
                        paint_info[0]["startTime"],
                        paint_info[1]["startTime"],
                        navigation_info[0]["domContentLoadedEventStart"],
                        navigation_info[0]["domContentLoadedEventEnd"],
                        navigation_info[0]["domComplete"],
                        cpu_times_user_diff,
                        cpu_times_system_diff,
                        cpu_times_iowait_diff,
                        avg_rss,
                        avg_vms,
                        avg_shared,
                        bytes_sent_diff,
                        bytes_recv_diff,
                        pkts_sent_diff,
                        pkts_recv_diff,
                    ]
                )

        csv_file_obj.close()
        browser.close()

        # Print CSV in a readable table format
        print_csv_as_table(csv_file_path)


if __name__ == "__main__":
    main()
