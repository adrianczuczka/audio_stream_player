"""Local development proxy: OpenAI PCM speech, or an offline streaming fixture."""

import argparse
import json
import math
import os
import struct
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def fixture_chunks():
    """Two seconds of 24 kHz mono s16le, delivered in 100 ms chunks."""
    for start in range(0, 48000, 2400):
        yield b"".join(
            struct.pack("<h", int(4000 * math.sin(2 * math.pi * 440 * i / 24000)))
            for i in range(start, start + 2400)
        )
        time.sleep(0.1)


class SpeechHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path != "/speech":
            self.send_error(404)
            return
        upstream = None
        try:
            if self.server.fixture:
                chunks = fixture_chunks()
            else:
                request = urllib.request.Request(
                    "https://api.openai.com/v1/audio/speech",
                    data=json.dumps({
                        "model": "gpt-4o-mini-tts",
                        "voice": "coral",
                        "input": "Hello! This speech is playing as the audio arrives.",
                        "response_format": "pcm",
                        "stream_format": "audio",
                    }).encode(),
                    headers={
                        "Authorization": "Bearer " + os.environ["OPENAI_API_KEY"],
                        "Content-Type": "application/json",
                    },
                )
                upstream = urllib.request.urlopen(request, timeout=30)
                chunks = iter(lambda: upstream.read1(4096), b"")
        except urllib.error.HTTPError as error:
            self.send_error(error.code, "Speech provider rejected the request")
            return
        except (OSError, KeyError):
            self.send_error(502, "Cannot connect to the speech provider")
            return

        try:
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            for chunk in chunks:
                self.wfile.write(f"{len(chunk):X}\r\n".encode() + chunk + b"\r\n")
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        except OSError:
            # Close without the final chunk so upstream failure is not EOF success.
            self.close_connection = True
        finally:
            if upstream is not None:
                upstream.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", action="store_true", help="Stream a test tone")
    args = parser.parse_args()
    if not args.fixture and not os.environ.get("OPENAI_API_KEY"):
        parser.error("Set OPENAI_API_KEY, or use --fixture")
    server = ThreadingHTTPServer(("127.0.0.1", 8765), SpeechHandler)
    server.fixture = args.fixture
    print("Streaming at http://127.0.0.1:8765/speech", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
