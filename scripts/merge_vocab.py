#!/usr/bin/env python3
"""把 iPhone 匯出的學習資料（MSKEcho-learning-*.json）合併進內建詞庫 msk_vocab.json。

用法（在 MSKEcho 專案資料夾內）：
    python3 scripts/merge_vocab.py ~/Downloads/MSKEcho-learning-20261120-1830.json

選項：
    --dry-run            只顯示會變更什麼，不寫檔
    --include-sentences  一併併入定稿句子（確認無病人識別資料才用）
    --include-inactive   連「未採用」的修正候選也併入（預設只併已採用的）
    --overwrite          既有誤辨對照與新規則衝突時，以新規則為準（預設保留舊的）
    --no-git             不自動 git commit / push

合併後按 Xcode 的 ⌘R 重新安裝，新詞庫就會進到手機。
"""
import argparse
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_VOCAB = ROOT / "MSKEcho" / "Resources" / "msk_vocab.json"
USER_CATEGORY = "user"


def load_json(path: Path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def main() -> int:
    ap = argparse.ArgumentParser(description="合併 MSKEcho 學習資料到內建詞庫")
    ap.add_argument("export", type=Path, help="iPhone 匯出的 JSON 檔")
    ap.add_argument("--vocab", type=Path, default=DEFAULT_VOCAB)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--include-sentences", action="store_true")
    ap.add_argument("--include-inactive", action="store_true")
    ap.add_argument("--overwrite", action="store_true")
    ap.add_argument("--no-git", action="store_true")
    args = ap.parse_args()

    export = load_json(args.export.expanduser())
    if export.get("format") != "mskecho-learning":
        print("✗ 這不是 MSKEcho 的學習資料檔")
        return 1
    vocab = load_json(args.vocab)

    # 既有詞彙（不分大小寫）
    known_terms = {t.lower() for cat in vocab["terms"].values() for t in cat}
    for a in vocab.get("abbreviations", []):
        known_terms.update({a["abbr"].lower(), a["expansion"].lower()})
    mis = vocab.setdefault("misrecognitions", {})
    mis_lower = {k.lower(): k for k in mis}

    added_terms, added_rules, conflicts, same = [], [], [], 0

    def add_rule(src: str, dst: str):
        nonlocal same
        src, dst = src.strip(), dst.strip()
        if not src or not dst or src == dst:
            return
        existing_key = mis_lower.get(src.lower())
        if existing_key is None:
            mis[src] = dst
            mis_lower[src.lower()] = src
            added_rules.append((src, dst))
        elif mis[existing_key] == dst:
            same += 1
        elif args.overwrite:
            conflicts.append((src, mis[existing_key], dst, "已覆寫"))
            mis[existing_key] = dst
        else:
            conflicts.append((src, mis[existing_key], dst, "保留舊的"))

    # 1. 個人詞彙 → terms["user"]；別名 → 誤辨對照
    user_cat = vocab["terms"].setdefault(USER_CATEGORY, [])
    for t in export.get("userTerms", []):
        text = t["text"].strip()
        if text and text.lower() not in known_terms:
            user_cat.append(text)
            known_terms.add(text.lower())
            added_terms.append(text)
        for alias in t.get("aliases", []):
            add_rule(alias, text)

    # 2. 修正規則 → 誤辨對照
    skipped_inactive = 0
    for r in export.get("rules", []):
        if r.get("isActive") or args.include_inactive:
            add_rule(r["from"], r["to"])
        else:
            skipped_inactive += 1

    # 3. 定稿句子（選擇性）
    added_sentences = 0
    sentences = export.get("sentences") or []
    if sentences and args.include_sentences:
        pool = vocab.setdefault("trainingSentences", [])
        seen = set(pool)
        for s in sentences:
            if s not in seen:
                pool.append(s)
                seen.add(s)
                added_sentences += 1

    # ---- 報告 ----
    print(f"來源：{args.export.name}（匯出於 {export.get('exportedAt', '?')}）")
    print(f"＋ 新詞彙 {len(added_terms)}：{'、'.join(added_terms) if added_terms else '—'}")
    print(f"＋ 新誤辨對照 {len(added_rules)}")
    for src, dst in added_rules:
        print(f"    {src} → {dst}")
    if same:
        print(f"＝ 已存在相同規則 {same} 條（略過）")
    if skipped_inactive:
        print(f"・ 未採用的候選 {skipped_inactive} 條未併入（要併入請加 --include-inactive）")
    for src, old, new, action in conflicts:
        print(f"! 衝突：{src}  舊→{old}  新→{new}（{action}）")
    if sentences and not args.include_sentences:
        print(f"・ 檔案含 {len(sentences)} 句定稿句子，未併入（要併入請加 --include-sentences）")
    if added_sentences:
        print(f"＋ 定稿句子 {added_sentences} 句 ⚠️ 請確認不含病人識別資料")

    changed = bool(added_terms or added_rules or added_sentences or (conflicts and args.overwrite))
    if not changed:
        print("沒有需要更新的內容。")
        return 0
    if args.dry_run:
        print("（--dry-run：未寫入）")
        return 0

    vocab["version"] = int(vocab.get("version", 0)) + 1
    vocab["updatedAt"] = datetime.now().isoformat(timespec="seconds")
    with open(args.vocab, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"✓ 已寫入 {args.vocab.relative_to(ROOT) if args.vocab.is_relative_to(ROOT) else args.vocab}（詞庫版本 v{vocab['version']}）")

    if not args.no_git:
        git_commit(args.vocab, len(added_terms), len(added_rules), added_sentences, vocab["version"])

    print("下一步：在 Xcode 按 ⌘R 重新安裝到 iPhone。")
    return 0


def git_commit(vocab_path: Path, n_terms: int, n_rules: int, n_sent: int, version: int):
    def git(*a, check=True):
        return subprocess.run(["git", *a], cwd=ROOT, capture_output=True, text=True, check=check)

    try:
        git("rev-parse", "--is-inside-work-tree")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("・ 這個資料夾還不是 git repo，略過 commit（先執行 scripts/setup_github.sh）")
        return

    parts = [f"+{n_terms} terms", f"+{n_rules} corrections"]
    if n_sent:
        parts.append(f"+{n_sent} sentences")
    msg = f"vocab v{version}: " + ", ".join(parts)
    git("add", str(vocab_path))
    result = git("commit", "-m", msg, check=False)
    if result.returncode != 0:
        print("・ git commit 未完成：", result.stdout.strip() or result.stderr.strip())
        return
    print(f"✓ git commit：{msg}")

    if git("remote", check=False).stdout.strip():
        push = git("push", check=False)
        print("✓ 已推送到 GitHub" if push.returncode == 0 else f"・ push 失敗：{push.stderr.strip()}")


if __name__ == "__main__":
    sys.exit(main())
