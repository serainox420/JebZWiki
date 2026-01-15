#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"

SNIPPET='<!-- LOCAL_MIRROR_HARD_REFRESH -->
<script>
(function(){
  const ORIGIN = location.origin;
  const COOLDOWN_MS = 400;
  let lastTs = 0;
  let lastHref = location.href;

  function normalizeInternal(url) {
    // Dla "ładnych" ścieżek bez rozszerzenia doklej trailing slash.
    // php -S lubi wtedy znaleźć folder/index.html.
    const p = url.pathname;
    const lastSeg = p.split("/").filter(Boolean).pop() || "";
    const hasExt = lastSeg.includes("."); // prymitywnie, ale działa
    if (!hasExt && !p.endsWith("/")) url.pathname = p + "/";
    return url;
  }

  function hardNav(toHref) {
    const now = Date.now();
    if (now - lastTs < COOLDOWN_MS && toHref === lastHref) return;
    lastTs = now;
    lastHref = toHref;

    try {
      const u = new URL(toHref, location.href);
      if (u.origin !== ORIGIN) { location.assign(u.href); return; }
      normalizeInternal(u);
      u.searchParams.set("_hard", String(now)); // cache buster, query nie zmienia path
      location.assign(u.toString());
    } catch (e) {
      location.reload();
    }
  }

  function hardReloadIfChanged(beforeHref) {
    setTimeout(() => {
      if (location.href !== beforeHref) hardNav(location.href);
    }, 0);
  }

  // 1) Przechwyć klik na linkach wewnętrznych i rób twardą nawigację
  document.addEventListener("click", function(e){
    if (e.defaultPrevented) return;
    if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;

    const a = e.target && e.target.closest ? e.target.closest("a[href]") : null;
    if (!a) return;

    const href = a.getAttribute("href");
    if (!href || href.startsWith("#") || href.startsWith("javascript:")) return;
    if (a.target && a.target.toLowerCase() === "_blank") return;

    let url;
    try { url = new URL(href, location.href); } catch(_) { return; }
    if (url.origin !== ORIGIN) return;

    e.preventDefault();
    e.stopImmediatePropagation();
    hardNav(url.href);
  }, true);

  // 2) Ubij nawigację SPA przez History API
  const _push = history.pushState;
  const _replace = history.replaceState;

  history.pushState = function(state, title, url){
    const before = location.href;
    const ret = _push.apply(this, arguments);

    if (typeof url === "string" && url.length) {
      try {
        const target = new URL(url, before).href;
        if (target !== before) hardNav(target);
      } catch(_) { hardReloadIfChanged(before); }
    } else {
      hardReloadIfChanged(before);
    }
    return ret;
  };

  history.replaceState = function(state, title, url){
    const before = location.href;
    const ret = _replace.apply(this, arguments);

    if (typeof url === "string" && url.length) {
      try {
        const target = new URL(url, before).href;
        if (target !== before) hardNav(target);
      } catch(_) {}
    }
    return ret;
  };

  window.addEventListener("popstate", function(){
    hardNav(location.href);
  }, true);
})();
</script>
'

export SNIPPET

while IFS= read -r -d '' f; do
  if grep -q 'LOCAL_MIRROR_HARD_REFRESH' "$f"; then
    continue
  fi

  cp -f "$f" "$f.bak"

  perl -0777 -pe '
    my $snip = $ENV{SNIPPET};
    if ($_ !~ /LOCAL_MIRROR_HARD_REFRESH/) {
      if ($_ =~ s#</head>#$snip\n</head>#i) {
        # ok
      } else {
        $_ = $snip . "\n" . $_; # jak nie ma </head>, wwal na początek
      }
    }
  ' "$f.bak" > "$f"

  echo "[patch] $f"
done < <(find "$ROOT" -type f -name 'index.html' -print0)

echo "[+] Done. Backupy: *.bak"
