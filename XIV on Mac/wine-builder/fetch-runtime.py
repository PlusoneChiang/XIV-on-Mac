#!/usr/bin/env python3
"""取得與 winecx 子模組 commit/tag 相符的預編譯 runtime。"""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile

REPOSITORY = "https://github.com/PlusoneChiang/winecx"
RECEIPT = ".winecx-runtime.json"


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def download(url, destination):
    subprocess.run(
        ["curl", "--fail", "--location", "--silent", "--show-error",
         "--retry", "2", "--connect-timeout", "30", "--max-time", "600",
         "--output", str(destination), url],
        check=True,
    )


def valid_runtime(runtime):
    files = ("bin/wine", "bin/wineserver", "bin/wine64",
             "lib/wine/x86_64-windows/ntdll.dll", "share/wine/wine.inf")
    return (all((runtime / name).is_file() for name in files)
            and all(os.access(runtime / "bin" / name, os.X_OK)
                    for name in ("wine", "wine64", "wineserver"))
            and (runtime / "lib/wine/x86_64-unix").is_dir())


def extract_archive(archive, staging):
    # 只接受 wine/ 內的一般檔案、目錄及指向解壓目錄內的連結。
    with tarfile.open(archive, "r:xz") as tar:
        for member in tar:
            # macOS tar 可附帶根目錄的 AppleDouble metadata，runtime 不需要它。
            if member.name == "._wine" and member.isfile():
                continue
            path = Path(member.name)
            if (path.is_absolute() or ".." in path.parts or not path.parts
                    or path.parts[0] != "wine"
                    or not (member.isfile() or member.isdir()
                            or member.issym() or member.islnk())):
                raise ValueError("壓縮包含有不允許的路徑或檔案類型")
            root = (staging / "wine").resolve()
            destination = staging / path
            if not destination.resolve().is_relative_to(root):
                raise ValueError("壓縮包路徑超出 wine 目錄")
            if member.issym() or member.islnk():
                link = Path(member.linkname)
                target = (destination.parent if member.issym() else staging) / link
                if link.is_absolute() or not target.resolve().is_relative_to(root):
                    raise ValueError("壓縮包連結超出 wine 目錄")
            tar.extract(member, staging)


def prepare_runtime(builder):
    source = builder / "source"
    # 防止未初始化的子模組讓 git 意外讀取父專案的版本。
    if not (source / ".git").exists():
        raise ValueError("請先初始化 wine-builder/source 子模組")
    commit = run("git", "-C", str(source), "rev-parse", "HEAD")
    tag = run("git", "-C", str(source), "describe", "--tags", "--exact-match", "HEAD")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", tag):
        raise ValueError("winecx tag 格式不適用於 release asset")
    if run("git", "-C", str(source), "status", "--porcelain"):
        raise ValueError("winecx 子模組有未提交變更，不能以預編譯 release 代表此原始碼")
    asset = "wine-macos-x86_64-{}.tar.xz".format(tag)
    identity = {"repository": REPOSITORY, "commit": commit, "tag": tag, "asset": asset}
    runtime = builder.parent / "wine"
    try:
        receipt = json.loads((runtime / RECEIPT).read_text())
    except (OSError, ValueError):
        receipt = {}
    if (isinstance(receipt, dict)
            and all(receipt.get(key) == value for key, value in identity.items())
            and re.fullmatch(r"[0-9a-f]{64}", str(receipt.get("sha256", "")))
            and valid_runtime(runtime)):
        print("note: 沿用 winecx {} ({})".format(tag, commit[:12]))
        return

    refs = dict(line.split()[::-1] for line in run(
        "git", "ls-remote", "--tags", REPOSITORY + ".git",
        "refs/tags/" + tag, "refs/tags/" + tag + "^{}",
    ).splitlines())
    remote_commit = refs.get("refs/tags/" + tag + "^{}", refs.get("refs/tags/" + tag))
    if remote_commit != commit:
        raise ValueError("GitHub tag 與本機 winecx commit 不符；不會使用其他版本或本機編譯")

    with tempfile.TemporaryDirectory(prefix=".winecx-", dir=builder.parent) as temporary:
        staging = Path(temporary)
        archive = staging / asset
        checksum = staging / (asset + ".sha256")
        url = REPOSITORY + "/releases/download/" + tag + "/" + asset
        print("note: 下載 winecx {} ({})".format(tag, commit[:12]), flush=True)
        download(url, archive)
        download(url + ".sha256", checksum)
        expected = checksum.read_text().split()[0].lower()
        digest = hashlib.sha256()
        with archive.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        if not re.fullmatch(r"[0-9a-f]{64}", expected) or digest.hexdigest() != expected:
            raise ValueError("Wine runtime SHA-256 校驗失敗")
        extract_archive(archive, staging)
        prepared = staging / "wine"
        alias = prepared / "bin/wine64"
        if not alias.exists() and not alias.is_symlink():
            alias.symlink_to("wine")
        if not valid_runtime(prepared):
            raise ValueError("Wine runtime 缺少必要檔案或執行權限")
        (prepared / RECEIPT).write_text(
            json.dumps(dict(identity, sha256=expected), indent=2) + "\n")
        previous = staging / "previous"
        if runtime.exists() or runtime.is_symlink():
            runtime.rename(previous)
        try:
            prepared.rename(runtime)
        except OSError:
            if previous.exists() or previous.is_symlink():
                previous.rename(runtime)
            raise
    print("note: 已備妥 winecx {}，由 Xcode 複製並重簽".format(tag))


if __name__ == "__main__":
    try:
        prepare_runtime(Path(__file__).resolve().parent)
    except (OSError, ValueError, IndexError, tarfile.TarError,
            subprocess.CalledProcessError) as error:
        sys.exit("error: Wine runtime 準備失敗：{}".format(error))
