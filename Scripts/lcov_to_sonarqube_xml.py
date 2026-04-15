#!/usr/bin/env python3
"""
Convert lcov coverage report to SonarQube generic coverage XML.

Strips the absolute runner path prefix so the output paths are relative
to the repo root, matching what SonarQube expects when scanning on a
different agent (e.g. ubuntu after a macOS build).

Usage:
    python3 Scripts/lcov_to_sonarqube_xml.py [input.lcov] [output.xml]

Defaults to coverage.lcov -> coverage.xml in the current directory.
GITHUB_WORKSPACE is used as the path prefix to strip (falls back to cwd).
"""
import os
import sys
import xml.etree.ElementTree as ET
from xml.dom import minidom


def convert(lcov_path: str, xml_path: str) -> None:
    prefix = os.environ.get("GITHUB_WORKSPACE", os.getcwd()).rstrip("/") + "/"

    root = ET.Element("coverage", version="1")
    current_file: ET.Element | None = None

    with open(lcov_path) as f:
        for raw in f:
            line = raw.strip()
            if line.startswith("SF:"):
                path = line[3:].replace(prefix, "")
                current_file = ET.SubElement(root, "file", path=path)
            elif line.startswith("DA:") and current_file is not None:
                parts = line[3:].split(",")
                if len(parts) >= 2:
                    lineno = parts[0]
                    try:
                        covered = "true" if int(parts[1]) > 0 else "false"
                        ET.SubElement(current_file, "lineToCover",
                                      lineNumber=lineno, covered=covered)
                    except ValueError:
                        pass

    xml_str = minidom.parseString(ET.tostring(root)).toprettyxml(indent="  ")
    with open(xml_path, "w") as f:
        f.write(xml_str)

    files = root.findall("file")
    total = sum(len(list(fi)) for fi in files)
    covered = sum(
        1 for fi in files
        for lc in fi.findall("lineToCover")
        if lc.get("covered") == "true"
    )
    print(f"Prefix stripped : {prefix}")
    print(f"Files           : {len(files)}")
    print(f"Lines           : {total} total, {covered} covered")
    print(f"Output          : {xml_path}")


if __name__ == "__main__":
    lcov = sys.argv[1] if len(sys.argv) > 1 else "coverage.lcov"
    out = sys.argv[2] if len(sys.argv) > 2 else "coverage.xml"
    convert(lcov, out)
