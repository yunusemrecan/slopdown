#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Every L("…") / LF("…") key in the app must have a translation in each
# Resources/<lang>.lproj/Localizable.strings (except English, the source language).
# Usage: scripts/check_strings.py   (exit 1 when something is missing)

import glob, re, sys, os

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
keys = set()
for path in glob.glob(os.path.join(root, "Sources/Slopdown/*.swift")):
    for m in re.finditer(r'\bLF?\("((?:[^"\\]|\\.)*)"', open(path, encoding="utf-8").read()):
        keys.add(m.group(1))
# Link style names come from SlopdownCore and are localized with L(style.title/shortName).
core = open(os.path.join(root, "Sources/SlopdownCore/HugoSite.swift"), encoding="utf-8").read()
for block in re.findall(r'public var (?:title|shortName): String \{(.*?)\n    \}', core, re.S):
    keys |= set(re.findall(r'return "((?:[^"\\]|\\.)*)"', block))

failed = False
for strings in glob.glob(os.path.join(root, "Resources/*.lproj/Localizable.strings")):
    lang = os.path.basename(os.path.dirname(strings)).split(".")[0]
    if lang == "en":
        continue
    have = set(re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', open(strings, encoding="utf-8").read(), re.M))
    missing = sorted(keys - have)
    if missing:
        failed = True
        print(f"{lang}: {len(missing)} missing translation(s):")
        for k in missing:
            print("   ", k)
    else:
        print(f"{lang}: all {len(keys)} strings translated")
sys.exit(1 if failed else 0)
