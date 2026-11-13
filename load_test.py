"""Generate concurrent HTTP load for the Lab1 HorizontalPodAutoscaler."""

from __future__ import annotations

import argparse
import http.client
import json
import socket
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import urlsplit


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:8080/predict")
    parser.add_argument("--seconds", type=int, default=60)
    parser.add_argument("--workers", type=int, default=50)
    parser.add_argument("--batch-size", type=int, default=1)
    args = parser.parse_args()
    if args.seconds < 1 or args.workers < 1 or args.batch_size < 1:
        parser.error("--seconds, --workers, and --batch-size must be positive")
    target = urlsplit(args.url)
    if target.scheme not in ("http", "https") or not target.hostname:
        parser.error("--url must be an http:// or https:// URL")
    connection_type = http.client.HTTPSConnection if target.scheme == "https" else http.client.HTTPConnection
    connection_args = (target.hostname, target.port)
    request_path = target.path or "/"
    if target.query:
        request_path += f"?{target.query}"

    deadline = time.monotonic() + args.seconds
    lock = threading.Lock()
    counts = {
        "success": 0,
        "timeout": 0,
        "http_error": 0,
        "connection_error": 0,
        "other_error": 0,
    }
    error_details: dict[str, int] = {}
    sample = [5.1, 3.5, 1.4, 0.2]
    body = json.dumps({"instances": [sample] * args.batch_size}).encode("utf-8")

    def worker() -> None:
        connection: http.client.HTTPConnection | None = None
        try:
            while time.monotonic() < deadline:
                try:
                    if connection is None:
                        connection = connection_type(*connection_args, timeout=5)
                    connection.request(
                        "POST",
                        request_path,
                        body=body,
                        headers={
                            "Content-Type": "application/json",
                            "Connection": "keep-alive",
                        },
                    )
                    response = connection.getresponse()
                    response.read()
                    result = "success" if 200 <= response.status < 300 else "http_error"
                    detail = f"HTTP {response.status} {response.reason}"
                    if response.will_close:
                        connection.close()
                        connection = None
                except (TimeoutError, socket.timeout) as error:
                    result = "timeout"
                    detail = f"{type(error).__name__}: {error}"
                    if connection is not None:
                        connection.close()
                        connection = None
                except OSError as error:
                    result = "connection_error"
                    detail = f"{type(error).__name__}: {error}"
                    if connection is not None:
                        connection.close()
                        connection = None
                except Exception as error:
                    result = "other_error"
                    detail = f"{type(error).__name__}: {error}"
                    if connection is not None:
                        connection.close()
                        connection = None
                with lock:
                    counts[result] += 1
                    if result != "success":
                        error_details[detail] = error_details.get(detail, 0) + 1
        finally:
            if connection is not None:
                connection.close()

    print(
        f"Sending requests to {args.url} for {args.seconds}s "
        f"with {args.workers} workers and batch size {args.batch_size}..."
    )
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(worker) for _ in range(args.workers)]
        for future in futures:
            future.result()
    print(f"Successful requests: {counts['success']}")
    print(f"Timed out: {counts['timeout']}")
    print(f"HTTP errors: {counts['http_error']}")
    print(f"Connection errors: {counts['connection_error']}")
    print(f"Other errors: {counts['other_error']}")
    failures = sum(value for key, value in counts.items() if key != "success")
    print(f"Total failed requests: {failures}")
    if error_details:
        print("Failure details:")
        for detail, count in sorted(error_details.items(), key=lambda item: item[1], reverse=True):
            print(f"  {detail}: {count}")


if __name__ == "__main__":
    main()
