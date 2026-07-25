#!/usr/bin/env python3
"""Serve the Flutter build and a constrained same-origin RSS proxy."""

from __future__ import annotations

import http.server
import ipaddress
import json
import os
import socket
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser


MAX_RESPONSE_BYTES = 5 * 1024 * 1024
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/138.0.0.0 Safari/537.36"
)
FEED_TYPES = (
    "application/rss+xml",
    "application/atom+xml",
    "application/rdf+xml",
    "application/xml",
    "text/xml",
)


class FeedLinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[tuple[str, str | None]] = []

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        if tag.lower() != "link":
            return
        values = {key.lower(): value for key, value in attrs}
        relationships = set((values.get("rel") or "").lower().split())
        media_type = (values.get("type") or "").lower()
        href = values.get("href")
        if (
            "alternate" in relationships
            and href
            and (
                "rss" in media_type
                or "atom" in media_type
                or "xml" in media_type
            )
        ):
            self.links.append((href, values.get("title")))


def validate_public_url(url: str) -> urllib.parse.SplitResult:
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("Only complete http:// or https:// URLs are allowed")
    if parsed.username or parsed.password:
        raise ValueError("URLs containing credentials are not allowed")
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    try:
        addresses = socket.getaddrinfo(
            parsed.hostname, port, type=socket.SOCK_STREAM
        )
    except socket.gaierror as error:
        raise ValueError("The feed host could not be resolved") from error
    for address in addresses:
        ip = ipaddress.ip_address(address[4][0])
        if not ip.is_global:
            raise ValueError("Private and local network addresses are blocked")
    return parsed


class SafeRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file_pointer, code, message, headers, url):
        validate_public_url(url)
        return super().redirect_request(
            request, file_pointer, code, message, headers, url
        )


OPENER = urllib.request.build_opener(SafeRedirectHandler())


def fetch(url: str) -> tuple[bytes, str, str]:
    validate_public_url(url)
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": ", ".join(FEED_TYPES) + ", text/html;q=0.8",
            "Accept-Language": "it-IT,it;q=0.9,en;q=0.8",
        },
    )
    with OPENER.open(request, timeout=15) as response:
        final_url = response.geturl()
        validate_public_url(final_url)
        content_type = response.headers.get(
            "Content-Type", response.headers.get_content_type()
        )
        declared_length = response.headers.get("Content-Length")
        if declared_length and int(declared_length) > MAX_RESPONSE_BYTES:
            raise ValueError("The response is larger than 5 MB")
        body = response.read(MAX_RESPONSE_BYTES + 1)
        if len(body) > MAX_RESPONSE_BYTES:
            raise ValueError("The response is larger than 5 MB")
        return body, final_url, content_type


def looks_like_html(body: bytes, content_type: str) -> bool:
    sample = body[:500].lstrip().lower()
    return content_type.lower().split(";", 1)[0].strip() == "text/html" or sample.startswith(
        (b"<!doctype html", b"<html")
    )


def discover_feed(
    body: bytes, page_url: str
) -> tuple[str | None, str | None]:
    parser = FeedLinkParser()
    parser.feed(body.decode("utf-8", errors="replace"))
    if not parser.links:
        return None, None
    href, title = parser.links[0]
    return urllib.parse.urljoin(page_url, href), title


class WeekendPlannerHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, directory: str, **kwargs) -> None:
        super().__init__(*args, directory=directory, **kwargs)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.path == "/rss-proxy":
            self.proxy_rss(parsed)
            return
        # This is a development server: always send the current Nix/web build.
        # A newly built file can have an older store timestamp than a browser's
        # cached local build, which would otherwise produce a misleading 304.
        for header in ("If-Modified-Since", "If-None-Match"):
            if header in self.headers:
                del self.headers[header]
        super().do_GET()

    def proxy_rss(self, request_url: urllib.parse.SplitResult) -> None:
        query = urllib.parse.parse_qs(request_url.query)
        target = (query.get("url") or [""])[0]
        if not target:
            self.send_proxy_error(400, "Missing RSS URL")
            return
        try:
            body, final_url, content_type = fetch(target)
            discovered_url = None
            discovered_title = None
            if looks_like_html(body, content_type):
                discovered_url, discovered_title = discover_feed(body, final_url)
                if not discovered_url:
                    raise ValueError(
                        "No RSS or Atom feed was found in the page metadata"
                    )
                body, final_url, content_type = fetch(discovered_url)

            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("X-RSS-Final-URL", final_url)
            if discovered_url:
                self.send_header("X-RSS-Discovered-URL", discovered_url)
            if discovered_title:
                safe_title = urllib.parse.quote(
                    discovered_title.replace("\r", " ").replace("\n", " "),
                    safe="",
                )
                self.send_header("X-RSS-Discovered-Title", safe_title)
            self.end_headers()
            self.wfile.write(body)
        except urllib.error.HTTPError as error:
            self.send_proxy_error(error.code, f"Feed server returned HTTP {error.code}")
        except (OSError, ValueError, urllib.error.URLError) as error:
            self.send_proxy_error(502, str(error))

    def send_proxy_error(self, status: int, message: str) -> None:
        body = json.dumps({"error": message}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8003
    directory = sys.argv[2] if len(sys.argv) > 2 else "build/web"
    directory = os.path.abspath(directory)
    handler = lambda *args, **kwargs: WeekendPlannerHandler(  # noqa: E731
        *args, directory=directory, **kwargs
    )
    with http.server.ThreadingHTTPServer(("127.0.0.1", port), handler) as server:
        print(
            f"Weekend Planner on http://127.0.0.1:{port} "
            f"(serving {directory}, RSS proxy enabled)",
            flush=True,
        )
        server.serve_forever()


if __name__ == "__main__":
    main()
