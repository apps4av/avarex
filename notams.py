"""Lightweight NOTAM fetcher from official U.S. government sources.

Primary source: Aviation Weather Center (aviationweather.gov)
Fallback source: FAA DINS (notams.faa.gov)

Example:
    from notams import get_notams
    messages = get_notams("KBVY")
    for m in messages:
        print(m)

Notes:
- This module uses only the public endpoints intended for human consumption.
- Responses and formats may change; this code attempts to be resilient with
  multiple fallbacks and simple parsing.
"""

from __future__ import annotations

import html
import re
from typing import List, Optional

import requests


USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)


class NotamFetchError(RuntimeError):
    """Raised when NOTAM retrieval fails from all known sources."""


def get_notams(icao_code: str, timeout_seconds: float = 15.0) -> List[str]:
    """Return NOTAM messages for an ICAO airport as a list of strings.

    Parameters
    ----------
    icao_code: str
        The 4-letter ICAO airport code (e.g., "KBVY"). Case-insensitive.
    timeout_seconds: float
        Per-request timeout in seconds.

    Returns
    -------
    List[str]
        A list of NOTAM messages as plain strings.

    Raises
    ------
    NotamFetchError
        If retrieval fails from all supported government endpoints.
    """
    if not icao_code or len(icao_code.strip()) < 3:
        raise ValueError("Expected an ICAO code like 'KBVY'.")

    icao = icao_code.strip().upper()

    # Try sources in order of preference
    errors: list[str] = []

    # 1) AviationWeather: documented data API (raw)
    awc_variants = [
        f"https://www.aviationweather.gov/api/data/notams?format=raw&loc={icao}",
        f"https://www.aviationweather.gov/api/data/notams?format=raw&ids={icao}",
        # Legacy page variant that sometimes returns raw; kept as a fallback
        f"https://www.aviationweather.gov/notam?format=raw&ids={icao}",
    ]

    for url in awc_variants:
        try:
            text = _http_get_text(url, timeout_seconds)
            messages = _parse_notam_text(text)
            if messages:
                return messages
        except Exception as exc:  # noqa: BLE001 - collect and try fallbacks
            errors.append(f"AWC fetch failed: {url} -> {exc}")

    # 2) FAA DINS web interface (HTML with <pre> content)
    try:
        dins_url = (
            "https://www.notams.faa.gov/dinsQueryWeb/"
            f"queryRetrievalByICAOAction.do?retrieveLocId={icao}&"
            "actionType=notamRetrievalByICAOs&formatType=ICAO"
        )
        text = _http_get_text(dins_url, timeout_seconds)
        messages = _parse_dins_html(text)
        if messages:
            return messages
    except Exception as exc:  # noqa: BLE001
        errors.append(f"FAA DINS fetch failed: {exc}")

    # If we reached here, nothing worked
    details = " | ".join(errors) if errors else "No details available."
    raise NotamFetchError(f"Failed to retrieve NOTAMs for {icao}. {details}")


def _http_get_text(url: str, timeout_seconds: float) -> str:
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "text/plain, text/html, */*",
        "Accept-Language": "en-US,en;q=0.9",
        "Connection": "close",
    }
    response = requests.get(url, headers=headers, timeout=timeout_seconds)
    response.raise_for_status()
    return response.text or ""


def _parse_notam_text(text: str) -> List[str]:
    """Parse raw NOTAM text (as returned by AWC raw endpoints).

    The raw format frequently contains one NOTAM per line, though sometimes
    lines wrap. We attempt a robust split on blank lines first, then fall
    back to line-by-line when needed.
    """
    if not text:
        return []

    # Normalize line endings and strip extraneous whitespace
    normalized = text.replace("\r\n", "\n").replace("\r", "\n").strip()
    if not normalized:
        return []

    # If it looks like HTML, do not parse here
    if "<html" in normalized.lower() or "<pre" in normalized.lower():
        return []

    # Prefer splitting on blank lines to group wrapped messages
    chunks = [c.strip() for c in re.split(r"\n\s*\n", normalized) if c.strip()]
    if len(chunks) > 1:
        return [_squash_whitespace(c) for c in chunks]

    # Fall back to line-based messages, filtering headers and noise
    lines = [ln.strip() for ln in normalized.split("\n")]
    lines = [ln for ln in lines if ln]

    # Heuristic: keep lines that start with NOTAM-like prefixes or ICAO
    kept: list[str] = []
    buffer: list[str] = []

    def flush():
        if buffer:
            kept.append(_squash_whitespace(" ".join(buffer)))
            buffer.clear()

    for ln in lines:
        if _looks_like_notam_start(ln):
            flush()
            buffer.append(ln)
        else:
            buffer.append(ln)
    flush()
    return kept


def _parse_dins_html(html_text: str) -> List[str]:
    """Parse NOTAMs out of the FAA DINS HTML page.

    DINS typically embeds NOTAMs within <pre> ... </pre>. We extract, then
    split on blank lines to group wrapped NOTAMs.
    """
    if not html_text:
        return []

    # Extract <pre> content if present
    pre_match = re.search(r"<pre[^>]*>([\s\S]*?)</pre>", html_text, re.IGNORECASE)
    text = html.unescape(pre_match.group(1)) if pre_match else html_text
    text = text.replace("\r\n", "\n").replace("\r", "\n").strip()
    if not text:
        return []

    # Remove any HTML tags that might remain
    text = re.sub(r"<[^>]+>", "", text)

    # Split on blank lines to group NOTAMs, then squash whitespace
    chunks = [c.strip() for c in re.split(r"\n\s*\n", text) if c.strip()]
    messages = [_squash_whitespace(c) for c in chunks]

    # Filter out common boilerplate or headers
    filtered: list[str] = []
    for msg in messages:
        upper = msg.upper()
        if "NO NOTAMS" in upper or "NO NOTAM" in upper:
            continue
        if upper.startswith("DISCLAIMER"):
            continue
        # Typical info lines that are not individual NOTAMs
        if upper.startswith("QUERY") or upper.startswith("REQUEST"):
            continue
        filtered.append(msg)

    return filtered


def _squash_whitespace(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def _looks_like_notam_start(line: str) -> bool:
    l = line.strip()
    if not l:
        return False

    # Domestic NOTAMs often start with '!' followed by facility identifier
    if l.startswith("!"):
        return True

    # ICAO-style NOTAM identifiers often contain a Q- line or series like:
    # KBVY (airport) followed by NOTAM number or 'Q)' prefix
    if re.match(r"^[A-Z]{4}\b", l):
        return True

    if l.startswith("Q)") or l.startswith("A)"):
        return True

    return False


if __name__ == "__main__":
    import sys

    code = sys.argv[1] if len(sys.argv) > 1 else "KBVY"
    try:
        for m in get_notams(code):
            print(m)
    except Exception as e:  # noqa: BLE001
        print(f"Error: {e}")

