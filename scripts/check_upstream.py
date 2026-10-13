#!/usr/bin/env python3
"""Read-only upstream release and branch checks for catalog-managed SHIORI."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import quote, urlparse

ROOT = Path(__file__).resolve().parents[1]


def version_key(label):
    match = re.fullmatch(r"(?:Tc|Mc)(\d)(\d{2})-(\d+)", label)
    if match:
        return (tuple(map(int, match.groups())), 1, ())
    match = re.fullmatch(r"v?(\d+(?:\.\d+)+)(?:-([\w.-]+))?(?:\+[\w.-]+)?", label)
    if not match:
        return None
    core = tuple(map(int, match[1].split(".")))
    core += (0,) * max(0, 3 - len(core))
    prerelease = tuple((0, int(part)) if part.isdecimal() else (1, part)
                       for part in (match[2] or "").split(".") if part)
    return (core, int(match[2] is None), prerelease)


def github_repo(url):
    parsed = urlparse(url)
    parts = parsed.path.strip("/").removesuffix(".git").split("/")
    if parsed.scheme != "https" or parsed.netloc != "github.com" or len(parts) != 2:
        raise ValueError(f"GitHubリポジトリURLではありません: {url}")
    if not all(re.fullmatch(r"[\w.-]+", part) for part in parts):
        raise ValueError(f"不正なリポジトリURL: {url}")
    return "/".join(parts)


class GitHub:
    def __init__(self):
        self.cache = {}

    def get(self, endpoint, paginate=False):
        key = (endpoint, paginate)
        if key not in self.cache:
            command = ["gh", "api", endpoint, "--hostname", "github.com"]
            if paginate:
                command += ["--paginate", "--slurp"]
            try:
                result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", timeout=30)
            except FileNotFoundError as error:
                raise RuntimeError("ghが必要です。GitHub CLIを導入し、gh auth loginを実行してください") from error
            except subprocess.TimeoutExpired as error:
                raise RuntimeError("GitHub APIが30秒以内に応答しませんでした") from error
            if result.returncode:
                raise RuntimeError(result.stderr.strip() or "GitHub APIの取得に失敗しました")
            data = json.loads(result.stdout)
            self.cache[key] = [item for page in data for item in page] if paginate else data
        return self.cache[key]


def targets(root):
    # Local Native implementations and instruction-only listings have no pinned
    # external source to compare. No source checkout or catalog validation needed.
    for path in sorted((root / "catalog/modules").glob("*.json")):
        module = json.loads(path.read_text(encoding="utf-8"))
        source = module.get("source", {})
        if ("shiori" in module["kinds"] and module["origin"] == "upstream-port"
                and module["delivery"] == "binary" and source.get("kind") != "local"):
            yield module


def newest_releases(releases, pattern):
    accepted = []
    ignored = []
    for release in releases:
        tag = release["tag_name"]
        if release["draft"] or (pattern and not re.fullmatch(pattern, tag)):
            continue
        key = version_key(tag)
        if key is None:
            ignored.append(tag)
            continue
        accepted.append((key, release))
    def latest(preview):
        candidates = [(key, r) for key, r in accepted if bool(r["prerelease"]) == preview]
        if not candidates:
            return None
        _, release = max(candidates, key=lambda item: item[0])
        return {key: release[key] for key in ("tag_name", "html_url", "published_at", "prerelease")}
    return latest(False), latest(True), ignored


def inspect(module, tracking, api):
    source = module["source"]
    result = {"id": module["id"], "name": module["displayName"], "installed": module["version"],
              "revision": module["revision"], "source_commit": source["commit"], "error": None}
    try:
        if tracking.get("baseline") and tracking.get("baseline_for_source") != source["commit"]:
            raise ValueError(f"{module['id']}の固定ソースが変わっています。upstream-watch.jsonの比較基準を更新してください")
        repo = github_repo(module["upstream"]["url"])
        branch = tracking.get("branch") or api.get(f"repos/{repo}")["default_branch"]
        baseline = tracking.get("baseline") or source["commit"]
        result.update(repo=repo, branch=branch, baseline=baseline)
        stable, preview, ignored = newest_releases(
            api.get(f"repos/{repo}/releases?per_page=100", paginate=True), tracking.get("tags"))
        result.update(stable=stable, preview=preview, unrecognized_tags=ignored)
        installed = version_key(module["version"])
        if installed is None:
            raise ValueError(f"現在版を比較できません: {module['version']}")
        for kind, release in (("stable", stable), ("preview", preview)):
            result[kind + "_update"] = bool(release and version_key(release["tag_name"]) > installed)
        head = api.get(f"repos/{repo}/commits/{quote(branch, safe='')}")["sha"]
        result["head"] = head
        comparison = {"ahead_by": 0, "commits": [], "html_url": f"https://github.com/{repo}/commit/{head}"}
        if baseline != head:
            comparison = api.get(f"repos/{repo}/compare/{quote(baseline, safe='')}...{quote(head, safe='')}")
        result.update(branch_commits=comparison["ahead_by"], compare_url=comparison["html_url"],
                      commits=[{"sha": c["sha"], "title": c["commit"]["message"].splitlines()[0],
                                "url": c["html_url"]} for c in comparison["commits"][-5:]])
        result["update"] = result["stable_update"] or result["preview_update"] or result["branch_commits"] > 0
    except (RuntimeError, ValueError, KeyError, TypeError) as error:
        result["error"] = str(error)
        result["update"] = False
    return result


def show(rows):
    print("SHIORI上流更新チェック（カタログの固定版との比較）")
    for row in rows:
        print(f"\n{row['name']} [{row['id']}]  現在: {row['installed']} r{row['revision']}")
        if row["error"]:
            print(f"  確認失敗: {row['error']}")
            continue
        for kind, label in (("stable", "正式版"), ("preview", "試験版")):
            release = row[kind]
            if release:
                marker = " ← 更新候補" if row[kind + "_update"] else ""
                print(f"  {label}: {release['tag_name']}{marker}  {release['html_url']}")
            else:
                print(f"  {label}: 公開なし")
        count = row["branch_commits"]
        print(f"  ブランチ: {row['repo']} / {row['branch']}  未取り込み +{count}")
        if count:
            print(f"  比較: {row['compare_url']}")
            for commit in row["commits"]:
                print(f"    {commit['sha'][:7]} {commit['title']}")
            if count > len(row["commits"]):
                print("    （コミット表示は比較APIの取得範囲から最大5件）")
        if row["unrecognized_tags"]:
            print("  版比較できないタグ: " + ", ".join(row["unrecognized_tags"][:5]))
    updates = sum(row["update"] for row in rows)
    errors = sum(row["error"] is not None for row in rows)
    print(f"\n対象 {len(rows)}件 / 更新候補 {updates}件 / 確認失敗 {errors}件")
    print("試験版・ブランチ更新は確認候補です。自動更新や互換性の判定は行いません。")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="JSONで結果を出力")
    parser.add_argument("--module", action="append", help="対象IDを限定（複数指定可）")
    parser.add_argument("--fail-on-update", action="store_true", help="更新候補があれば終了コード1")
    args = parser.parse_args(argv)
    configuration = json.loads((ROOT / "catalog/upstream-watch.json").read_text(encoding="utf-8"))
    selected = list(targets(ROOT))
    if args.module:
        unknown = set(args.module) - {module["id"] for module in selected}
        if unknown:
            parser.error("対象外のmodule ID: " + ", ".join(sorted(unknown)))
        selected = [module for module in selected if module["id"] in args.module]
    api = GitHub()
    rows = [inspect(module, configuration["modules"].get(module["id"], {}), api) for module in selected]
    if args.json:
        print(json.dumps({"checked_at": datetime.now(timezone.utc).isoformat(), "modules": rows}, ensure_ascii=False, indent=2))
    else:
        show(rows)
    if any(row["error"] for row in rows):
        return 2
    return int(args.fail_on_update and any(row["update"] for row in rows))


if __name__ == "__main__":
    raise SystemExit(main())
