#!/usr/bin/env python3
"""Strip absolute runner paths from lcov so SonarQube can match files."""
import os

prefix = os.environ.get("GITHUB_WORKSPACE", os.getcwd()) + "/"

with open("coverage.lcov") as f:
    data = f.read()

stripped = data.replace(prefix, "")

with open("coverage.lcov", "w") as f:
    f.write(stripped)

first_sf = next((l for l in stripped.splitlines() if l.startswith("SF:")), "none")
print("Prefix stripped: " + prefix)
print("First SF after strip: " + first_sf)
