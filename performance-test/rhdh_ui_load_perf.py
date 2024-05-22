#!/usr/bin/env python3

from playwright.sync_api import sync_playwright
import time
import os # to capture pid of current process
import psutil # to capture cpu and memory metrics
import csv # to capture ,metrics into a csv file
import socket # to capture hostname
from utils.monitor import MemoryMonitor  # custom utility for monitoring memory
from rich.progress import Progress # to display progress bar for relaods
from rich.console import Console # to print in a nice way
from rich.table import Table
import pandas as pd # for printing csv file in human readable format

monitor = None
console = Console()

def setup_monitoring():
    global monitor
    console.print("\n[bold green]Setting up monitoring...[/bold green]")
    monitor = MemoryMonitor()
    monitor.start()

def teardown_monitoring():
    global monitor
    monitor.stop()
    monitor.join()

def get_memory_info():
    global monitor
    avg_rss = sum(monitor.rss_usage) / len(monitor.rss_usage) / (1024 * 1024)
    avg_vms = sum(monitor.vms_usage) / len(monitor.vms_usage) / (1024 * 1024)
    avg_shared = sum(monitor.shared_usage) / len(monitor.shared_usage) / (1024 * 1024)
    return avg_rss, avg_vms, avg_shared

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
                "current_time", "hostname",
                "first-paint_start_time", "first-contentful-paint_start_time",
                "domContentLoadedEventStart", "domContentLoadedEventEnd", "domComplete",
                "cputimes_user", "cputimes_system", "cputimes_iowait",
                "rss_memory", "vms_memory", "shared_memory"
            ]
        )

        browser = p.chromium.launch()
        context = browser.new_context()
        page = context.new_page()

        setup_monitoring()

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
                page.wait_for_selector('//h1[contains(text(),"Welcome back!")]')
                paint_info = page.evaluate("window.performance.getEntriesByType('paint')")
                navigation_info = page.evaluate("performance.getEntriesByType('navigation')")

                cpu_times = process.cpu_times()
                avg_rss, avg_vms, avg_shared = get_memory_info()

                current_time = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime())

                writer.writerow(
                    [
                        current_time, hostname,
                        paint_info[0]["startTime"], paint_info[1]["startTime"],
                        navigation_info[0]["domContentLoadedEventStart"],
                        navigation_info[0]["domContentLoadedEventEnd"],
                        navigation_info[0]["domComplete"],
                        cpu_times.user, cpu_times.system, cpu_times.iowait,
                        avg_rss, avg_vms, avg_shared
                    ]
                )
                assert page.title() == expected_title
                page.reload()
                progress.update(reload_task, advance=1)

        csv_file_obj.close()
        teardown_monitoring()
        browser.close()

        # Print CSV in a readable table format
        print_csv_as_table(csv_file_path)

if __name__ == "__main__":
    main()
