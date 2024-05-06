from threading import Thread
import psutil
import time
import os

class MemoryMonitor(Thread):
    def __init__(self):
        super().__init__()
        self.rss_usage = []
        self.vms_usage = []
        self.shared_usage = []
        self.running = True

    def run(self):
        while self.running:
            # Get memory usage metrics
            process = psutil.Process(os.getpid())
            self.rss_usage.append(process.memory_info().rss)
            self.vms_usage.append(process.memory_info().vms)
            self.shared_usage.append(process.memory_info().shared)
            time.sleep(1)  # Adjust sleep time for monitoring frequency

    def stop(self):
        self.running = False