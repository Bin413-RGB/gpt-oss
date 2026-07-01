#!/usr/bin/env bash
set -u
ROOT_WIN='/mnt/d/Codex'
REPORT_DIR="$ROOT_WIN/Reports"
mkdir -p "$ROOT_WIN/Projects" "$ROOT_WIN/ReadyApps" "$ROOT_WIN/Scripts" "$REPORT_DIR"
READY=(); MISSING=(); FIXED=(); REMAINING=()
add_unique(){ local arr="$1" val="$2"; eval "[[ \" \${${arr}[*]} \" == *\" $val \"* ]] || ${arr}+=(\"$val\")"; }
if ! grep -qi microsoft /proc/version 2>/dev/null; then add_unique REMAINING 'ليست جلسة WSL'; fi
if ! command -v lsb_release >/dev/null 2>&1 && ! [[ -f /etc/os-release ]]; then add_unique REMAINING 'تعذر تحديد Ubuntu'; fi
sudo apt-get update
sudo dpkg --audit | tee "$REPORT_DIR/wsl-dpkg-audit.txt"
sudo apt-get check | tee "$REPORT_DIR/wsl-apt-check.txt"
need=(git curl ca-certificates build-essential cmake ninja-build python3 python3-venv python3-pip sqlite3 openjdk-21-jdk jq ripgrep fd-find)
install=()
for p in "${need[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || install+=("$p"); done
if ((${#install[@]})); then sudo apt-get install -y --no-install-recommends "${install[@]}" && FIXED+=("apt:${install[*]}"); fi
if ! command -v node >/dev/null 2>&1; then sudo apt-get install -y --no-install-recommends nodejs npm && FIXED+=('nodejs/npm'); fi
if command -v corepack >/dev/null 2>&1; then corepack enable && corepack prepare pnpm@latest --activate && FIXED+=('corepack/pnpm'); else REMAINING+=('corepack غير متوفر'); fi
ZRC="$HOME/.zshrc"; touch "$ZRC"
block='# >>> CODEX FACTORY START >>>
projects(){ cd /mnt/d/Codex/Projects; }
readyapps(){ cd /mnt/d/Codex/ReadyApps; }
factory-doctor(){ for c in git node npm pnpm python3 java cmake ninja jq rg fdfind; do command -v "$c" >/dev/null 2>&1 && { printf "%s: " "$c"; "$c" --version 2>&1 | head -1; }; done; }
# <<< CODEX FACTORY END <<<'
if ! grep -q 'CODEX FACTORY START' "$ZRC"; then printf '\n%s\n' "$block" >> "$ZRC"; FIXED+=('.zshrc aliases'); fi
printf 'WSL جاهز: %s\nإصلاحات: %s\nمتبقي: %s\n' "$(. /etc/os-release 2>/dev/null; echo ${PRETTY_NAME:-unknown})" "${FIXED[*]:-لا يوجد}" "${REMAINING[*]:-لا يوجد}" > "$REPORT_DIR/wsl-summary.txt"
