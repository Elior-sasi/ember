"""Find the Switcher water heater on your home network.

Run this on a computer connected to the same WiFi as the heater:
    python discover.py

It listens for the broadcast every Switcher sends every few seconds and prints
the IP address, device id and key to type into the app's settings.
"""
import socket
import sys
import time

MODELS = {"030f": "Switcher Mini", "030b": "Switcher Touch", "01a7": "Switcher V2",
          "01a1": "Switcher V2", "0317": "Switcher V4"}


def main(seconds=20):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("", 20002))
    s.settimeout(1)
    print("Listening for a Switcher for up to %d seconds..." % seconds)
    seen = set()
    end = time.time() + seconds
    while time.time() < end:
        try:
            data, _ = s.recvfrom(1024)
        except socket.timeout:
            continue
        if len(data) != 165 or data[:2] != b"\xfe\xf0":
            continue
        model = MODELS.get(data[74:76].hex())
        if not model:
            continue
        dev_id = data[18:21].hex()
        if dev_id in seen:
            continue
        seen.add(dev_id)
        name = data[42:74].split(b"\0")[0].decode(errors="replace")
        ip = ".".join(str(b) for b in data[76:80])
        print()
        print("Found:      %s (%s)" % (name or "Switcher", model))
        print("IP address: %s" % ip)
        print("Device id:  %s" % dev_id)
        print("Key:        %s" % data[40:41].hex())
        break
    if not seen:
        print("No Switcher heard. Check the computer is on the same WiFi, and allow Python")
        print("through the Windows firewall if it asks.")


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 20)
