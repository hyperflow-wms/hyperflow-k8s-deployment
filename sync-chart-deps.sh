#!/usr/bin/env bash
#
# Rebuild the vendored subchart archives (charts/<umbrella>/charts/*.tgz) for
# every umbrella chart that depends on a local `file://` subchart.
#
# WHY THIS EXISTS
# ---------------
# Helm's `--dependency-update` flag on `helm install`/`helm upgrade` updates
# dependencies **only if they are missing**. An existing-but-stale
# `charts/<sub>-<ver>.tgz` is therefore silently reused: you edit
# `charts/hyperflow-engine/...`, deploy, and get the OLD template, with no
# warning and no error.
#
# Either `helm dependency build` or `helm dependency update` repackages a
# `file://` subchart from source, so running one of them before every install
# is the whole fix -- this script just does it for every umbrella chart at
# once and adds a `--check` guard for when someone forgets (forgetting is the
# actual failure mode).
#
# We prefer `build` over `update`: `build` resolves from Chart.lock, whereas
# `update` re-resolves the *remote* dependency version ranges (this repo pins
# them with wildcards -- kube-prometheus-stack 68.*.*, keda 2.16.*,
# rabbitmq 15.2.*, ...), so `update` can silently bump a third-party chart
# under you. `build` falls back to `update` when there is no lock file yet.
#
# The archives are gitignored build artifacts (.gitignore:
# `charts/**/charts/*`), so a fresh clone is always correct; it is long-lived
# working copies that rot. Run this after editing ANY local subchart, before
# install/upgrade.
#
# USAGE
#   ./sync-chart-deps.sh           # rebuild vendored deps (safe to re-run)
#   ./sync-chart-deps.sh --check   # exit 1 if any vendored archive is stale
#                                  # (read-only; for CI / pre-deploy guards)
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHARTS_DIR="$REPO_ROOT/charts"
MODE="${1:-sync}"

case "$MODE" in
  sync|--check) ;;
  *) echo "usage: $(basename "$0") [--check]" >&2; exit 2 ;;
esac

if ! command -v helm >/dev/null 2>&1; then
  echo "error: helm not found on PATH" >&2
  exit 2
fi

# Umbrella charts are those whose Chart.yaml declares at least one file:// dep.
mapfile -t UMBRELLAS < <(
  grep -l -e 'repository:[[:space:]]*file://' "$CHARTS_DIR"/*/Chart.yaml 2>/dev/null \
    | xargs -r -n1 dirname | sort
)

if [ "${#UMBRELLAS[@]}" -eq 0 ]; then
  echo "no umbrella charts with file:// dependencies found under $CHARTS_DIR" >&2
  exit 0
fi

# Newest mtime (epoch seconds) of any file under $1; 0 if absent/empty.
# The umbrella's own vendored archives are excluded so a subchart that is
# itself an umbrella never looks "newer than itself" after a rebuild.
newest_mtime() {
  local dir="$1" t
  [ -d "$dir" ] || { echo 0; return 0; }
  t="$(find "$dir" -type f -not -path "$dir/charts/*" -printf '%T@\n' 2>/dev/null \
        | cut -d. -f1 | sort -rn | head -1)"
  echo "${t:-0}"
}

# Local subchart names for an umbrella: basename of each file:// repository.
local_dep_names() {
  sed -n 's#^[[:space:]]*repository:[[:space:]]*file://\.\./##p' "$1/Chart.yaml"
}

stale=0
failed=0

for umbrella in "${UMBRELLAS[@]}"; do
  name="$(basename "$umbrella")"

  if [ "$MODE" = "--check" ]; then
    while read -r dep; do
      [ -n "$dep" ] || continue
      src="$CHARTS_DIR/$dep"
      # Packaged archive for this dep, whatever version it carries (may be absent).
      tgz="$(find "$umbrella/charts" -maxdepth 1 -name "$dep-*.tgz" 2>/dev/null | head -1)"
      if [ -z "$tgz" ]; then
        echo "STALE  $name: '$dep' is not vendored (charts/$name/charts/$dep-*.tgz missing)"
        stale=1
        continue
      fi
      src_t="$(newest_mtime "$src")"
      tgz_t="$(stat -c %Y "$tgz" 2>/dev/null || echo 0)"
      if [ "$src_t" -gt "$tgz_t" ]; then
        echo "STALE  $name: '$dep' source is newer than $(basename "$tgz")"
        stale=1
      fi
    done < <(local_dep_names "$umbrella")
  else
    # `build` honors Chart.lock (no remote re-resolution). If the lock is
    # missing or unusable, fall back to `update`, which writes one.
    if [ -f "$umbrella/Chart.lock" ] \
       && ( cd "$umbrella" && helm dependency build . >/dev/null 2>&1 ); then
      echo "==> helm dependency build  $name"
    else
      echo "==> helm dependency update $name (no usable Chart.lock)"
      if ! ( cd "$umbrella" && helm dependency update . >/dev/null ); then
        echo "error: dependency update failed for $name" >&2
        failed=1
      fi
    fi
  fi
done

if [ "$MODE" = "--check" ]; then
  if [ "$stale" -ne 0 ]; then
    echo
    echo "Vendored subcharts are out of date. Run: ./sync-chart-deps.sh" >&2
    echo "(helm's --dependency-update will NOT fix this: it only fetches MISSING deps.)" >&2
    exit 1
  fi
  echo "all vendored subcharts are up to date"
  exit 0
fi

[ "$failed" -eq 0 ] || exit 1
echo
echo "done. Vendored subcharts rebuilt from source."
