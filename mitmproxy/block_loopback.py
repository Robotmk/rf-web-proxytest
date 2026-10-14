"""mitmproxy-Addon: Ziele auf 127.0.0.1/localhost mit 502 abweisen.

Ein echter Firmen-Proxy läuft auf einem anderen Host. Für ihn ist "127.0.0.1" er selbst,
d. h. eine über den Proxy geschickte Verbindung zu localhost kommt nie beim Client an.
Läuft mitmdump lokal (ohne Docker), würde er localhost dagegen erreichen. Dieses Addon
stellt das Verhalten des entfernten Proxys nach.
"""

import ipaddress
import logging

from mitmproxy import http

LOOPBACK_NAMES = {"localhost", "localhost.localdomain"}


def _is_loopback(host: str) -> bool:
    if host.lower() in LOOPBACK_NAMES:
        return True
    try:
        return ipaddress.ip_address(host.strip("[]")).is_loopback
    except ValueError:
        return False


def _block(flow: http.HTTPFlow) -> None:
    if _is_loopback(flow.request.host):
        # Gleiche Form wie die Flow-Zeilen von mitmdump, damit die Skripte das Ziel im Log finden
        logging.warning(
            "%s:%s: %s %s:%s << 502 (loopback blocked)",
            *flow.client_conn.peername[:2], flow.request.method, flow.request.host, flow.request.port,
        )
        flow.response = http.Response.make(
            502, b"Proxy cannot reach the client's localhost\n", {"Content-Type": "text/plain"}
        )


def http_connect(flow: http.HTTPFlow) -> None:
    _block(flow)


def request(flow: http.HTTPFlow) -> None:
    _block(flow)
