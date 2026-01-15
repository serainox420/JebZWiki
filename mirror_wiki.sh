#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./mirror_wiki.sh "https://www.wikiful.com/@Kurwaras/jebzwiki" wikiHash.txt
#   cat wikiHash.txt | ./mirror_wiki.sh "https://www.wikiful.com"

RAW_BASE="${1:-}"
INPUT_FILE="${2:-}"

if [[ -z "${RAW_BASE}" ]]; then
  echo "Użycie: $0 <BASE_URL> [plik_wejsciowy]"
  exit 1
fi

read_input() {
  if [[ -n "${INPUT_FILE}" ]]; then
    cat -- "${INPUT_FILE}"
  else
    cat
  fi
}

# Wyciągnij origin (scheme://host) nawet jeśli podasz URL z path
BASE_ORIGIN="$(printf '%s\n' "$RAW_BASE" | awk -F/ '{print $1"//"$3}')"
if [[ -z "$BASE_ORIGIN" || "$BASE_ORIGIN" == "://" ]]; then
  echo "[-] Nie umiem wyciągnąć origin z: $RAW_BASE"
  exit 1
fi

TMP_JSON="$(mktemp -t wikiHash.XXXXXX.json)"
trap 'rm -f "$TMP_JSON"' EXIT

extract_json() {
  # Zbiera linie od "window.wikiHash =" do linii zawierającej "};"
  # Potem:
  # - w pierwszej linii usuwa wszystko do pierwszego '{'
  # - w ostatniej linii usuwa tylko końcowy ';' (zostawia '}')
  read_input \
    | awk '
        BEGIN{inblk=0}
        /window\.wikiHash[[:space:]]*=[[:space:]]*{/ {inblk=1}
        inblk {print}
        inblk && /};[[:space:]]*$/ {exit}
      ' \
    | sed -e '1s/^[^{]*//' \
          -e '$s/;[[:space:]]*$//'
}

extract_json > "$TMP_JSON"

# Szybka walidacja JSON (żeby nie lecieć w maliny)
if ! jq -e . >/dev/null 2>&1 < "$TMP_JSON"; then
  echo "[-] Wyciągnięty JSON jest popsuty. Zapisuję go do: ./wikiHash.extracted.json"
  cp -f "$TMP_JSON" ./wikiHash.extracted.json
  echo "    Otwórz i zobacz gdzie się urwało."
  exit 2
fi

mapfile -t PATHS < <(jq -r '.. | objects | .pathname? // empty' "$TMP_JSON" | sort -u)

if [[ "${#PATHS[@]}" -eq 0 ]]; then
  echo "[-] Nie znalazłem żadnych .pathname w JSON."
  exit 3
fi

echo "[+] Origin: $BASE_ORIGIN"
echo "[+] Znalezione ścieżki: ${#PATHS[@]}"
echo

MANIFEST="manifest.txt"
: > "$MANIFEST"

SLEEP_SEC="${SLEEP_SEC:-0.2}"

fetch_one() {
  local path="$1"
  local rel="${path#/}"
  local out_dir="./${rel}"
  local out_file="${out_dir%/}/index.html"
  local url="${BASE_ORIGIN}${path}"

  mkdir -p "$out_dir"

  echo "[GET] $url"
  curl -fsSL -L --retry 3 --retry-delay 1 \
    -H 'User-Agent: mirror_wiki.sh (+curl)' \
    -o "$out_file" \
    "$url"

  printf '%s\t%s\n' "$url" "$out_file" >> "$MANIFEST"
}

for p in "${PATHS[@]}"; do
  fetch_one "$p"
  sleep "$SLEEP_SEC"
done

echo
echo "[+] Gotowe."
echo "    - Manifest: $MANIFEST"
