#!/usr/bin/env python3
"""安全、可重跑地把一個 Sparkle 發佈項目加到 appcast。"""
import argparse
import base64
import binascii
import email.utils
import html
import os
import re
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
VERSION_RE = re.compile(r"^\d+(?:\.\d+)+$")


def get(item, name):
    return (item.findtext(name) or "").strip()


def sparkle(item, name):
    return (item.findtext(f"{{{SPARKLE}}}{name}") or "").strip()


def fail(message):
    raise ValueError(message)


def update(args):
    appcast, notes_file = Path(args.appcast), Path(args.notes)
    if not notes_file.is_file():
        fail("更新說明檔不存在")
    if not VERSION_RE.fullmatch(args.version) or not args.build.isdecimal():
        fail("版本或 build 格式無效")
    if not args.length.isdecimal() or not args.minimum_system_version:
        fail("length 或最低系統版本格式無效")
    if not args.filename.endswith(".dmg") or args.version not in Path(args.filename).name:
        fail("DMG 檔名未包含指定版本，拒絕建立不一致的發佈項目")
    try:
        if len(base64.b64decode(args.signature, validate=True)) != 64:
            fail("EdDSA 簽名必須是解碼後 64 bytes 的 Base64")
    except (binascii.Error, ValueError):
        fail("EdDSA 簽名不是有效的 Base64")
    try:
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
        tree = ET.parse(appcast, parser=parser)
    except (OSError, ET.ParseError) as error:
        fail(f"無法讀取有效的 appcast XML: {error}")
    channel = tree.getroot().find("channel")
    if channel is None:
        fail("appcast 缺少 channel")

    description = f"<pre>{html.escape(notes_file.read_text(encoding='utf-8'), quote=True)}</pre>"
    repo = os.environ.get("GITHUB_REPOSITORY", "PlusoneChiang/XIV-on-Mac-in-TC")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        fail("GITHUB_REPOSITORY 格式無效")
    filename = Path(args.filename).name
    url = f"https://github.com/{repo}/releases/download/v{args.version}/{filename}"
    expected = {"title": f"XIV on Mac v{args.version}", "version": args.build,
                "shortVersionString": args.version, "minimumSystemVersion": args.minimum_system_version,
                "description": description, "url": url, "type": "application/octet-stream",
                "edSignature": args.signature, "length": args.length}
    items, builds, identical = list(channel.findall("item")), [], False
    for item in items:
        build, version = sparkle(item, "version"), sparkle(item, "shortVersionString")
        if build.isdecimal():
            builds.append(int(build))
        if build == args.build and version != args.version:
            fail(f"build {args.build} 已屬於版本 {version}，拒絕重複使用")
        if version != args.version:
            continue
        enc = item.find("enclosure")
        actual = {"title": get(item, "title"), "version": build, "shortVersionString": version,
                  "minimumSystemVersion": sparkle(item, "minimumSystemVersion"),
                  "description": item.findtext("description") or "",
                  "url": "" if enc is None else enc.get("url", ""),
                  "type": "" if enc is None else enc.get("type", ""),
                  "edSignature": "" if enc is None else enc.get(f"{{{SPARKLE}}}edSignature", ""),
                  "length": "" if enc is None else enc.get("length", "")}
        if actual != expected:
            fail(f"appcast 已有版本 {args.version}，內容、資產或簽名不同，拒絕覆寫")
        identical = True
    if identical:
        return False
    if builds and int(args.build) <= max(builds):
        fail(f"build {args.build} 不比現有最新 build {max(builds)} 新，拒絕加入正式 feed")

    item = ET.Element("item")
    ET.SubElement(item, "title").text = expected["title"]
    ET.SubElement(item, "pubDate").text = email.utils.formatdate(usegmt=True)
    for key in ("version", "shortVersionString", "minimumSystemVersion"):
        ET.SubElement(item, f"{{{SPARKLE}}}{key}").text = expected[key]
    ET.SubElement(item, "description").text = description
    ET.SubElement(item, "enclosure", {"url": url, "type": "application/octet-stream",
                  "length": args.length, f"{{{SPARKLE}}}edSignature": args.signature})
    channel.insert(list(channel).index(items[0]) if items else len(channel), item)
    ET.indent(tree, space="    ")
    with tempfile.NamedTemporaryFile("wb", dir=appcast.parent, delete=False) as output:
        temporary = output.name
        tree.write(output, encoding="utf-8", xml_declaration=True)
    os.replace(temporary, appcast)
    return True


def main():
    parser = argparse.ArgumentParser()
    for name in ("appcast", "notes", "filename", "length", "version", "build",
                 "minimum-system-version", "signature"):
        parser.add_argument(f"--{name}", required=True)
    try:
        changed = update(parser.parse_args())
    except ValueError as error:
        print(f"錯誤: {error}", file=sys.stderr)
        return 1
    print("appcast 已更新" if changed else "appcast 已是相同發佈項目")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
