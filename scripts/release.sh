#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh v0.1.0 [options]

Creates or verifies a release tag, pushes it, and optionally opens the
GitHub Actions run that builds and publishes the GitHub Release.
The packaged app version is derived from the release tag.

Options:
  --dry-run           Print the commands without changing git or GitHub.
  --skip-tests        Do not run swift test before tagging.
  --skip-build        Do not build/package release artifacts before tagging.
  --skip-clean-check  Allow releasing from a dirty working tree.
  --no-open           Do not open the GitHub Actions run in the browser.
  -h, --help          Show this help.

Examples:
  scripts/release.sh v0.1.0
  scripts/release.sh v0.1.0 --dry-run
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

run() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

run_shell() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "+ $*"
  else
    eval "$@"
  fi
}

TAG=""
DRY_RUN=0
SKIP_TESTS=0
SKIP_BUILD=0
SKIP_CLEAN_CHECK=0
OPEN_RUN=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --skip-tests)
      SKIP_TESTS=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --skip-clean-check)
      SKIP_CLEAN_CHECK=1
      shift
      ;;
    --no-open)
      OPEN_RUN=0
      shift
      ;;
    -*)
      die "unknown option: $1"
      ;;
    *)
      if [[ -n "${TAG}" ]]; then
        die "unexpected argument: $1"
      fi
      TAG="$1"
      shift
      ;;
  esac
done

[[ -n "${TAG}" ]] || die "missing release tag, for example v0.1.0"
[[ "${TAG}" =~ ^v[0-9]+(\.[0-9]+){1,2}([-+][0-9A-Za-z.-]+)?$ ]] || die "tag must look like v0.1.0"

command -v git >/dev/null || die "git is required"
command -v swift >/dev/null || die "swift is required"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "${REPO_ROOT}"

APP_VERSION="${TAG#v}"

if [[ "${DRY_RUN}" != "1" ]]; then
  git remote get-url origin >/dev/null 2>&1 || die "git remote 'origin' is required"
fi

if [[ "${SKIP_CLEAN_CHECK}" != "1" && -n "$(git status --porcelain)" ]]; then
  git status --short >&2
  die "working tree is not clean; commit or stash changes first"
fi

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  TAG_SHA="$(git rev-list -n 1 "${TAG}")"
  HEAD_SHA="$(git rev-parse HEAD)"
  [[ "${TAG_SHA}" == "${HEAD_SHA}" ]] || die "tag ${TAG} already exists but does not point at HEAD"
  echo "Tag ${TAG} already exists locally at HEAD."
else
  if [[ "${SKIP_TESTS}" != "1" ]]; then
    run swift test
  fi

  if [[ "${SKIP_BUILD}" != "1" ]]; then
    run env TRAFFICBAR_VERSION="${APP_VERSION}" scripts/package-release.sh
  fi

  run git tag -a "${TAG}" -m "Release ${TAG}"
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  run git push origin "${TAG}"
elif git ls-remote --exit-code --tags origin "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "Tag ${TAG} already exists on origin."
else
  run git push origin "${TAG}"
fi

if command -v gh >/dev/null; then
  if [[ "${DRY_RUN}" == "1" ]]; then
    run gh workflow run release.yml --ref "${TAG}" -f "tag=${TAG}"
  else
    echo "Waiting for GitHub to create the tag-triggered release workflow run..."
    sleep 5
    run_id="$(gh run list --workflow release.yml --branch "${TAG}" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
    if [[ -z "${run_id}" || "${run_id}" == "null" ]]; then
      echo "No tag-triggered run found yet; dispatching release workflow manually for ${TAG}."
      gh workflow run release.yml --ref "${TAG}" -f "tag=${TAG}"
      sleep 3
      run_id="$(gh run list --workflow release.yml --branch "${TAG}" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
    fi

    if [[ -n "${run_id}" && "${run_id}" != "null" ]]; then
      echo "Release workflow run: ${run_id}"
      if [[ "${OPEN_RUN}" == "1" ]]; then
        gh run view "${run_id}" --web
      else
        echo "View it with: gh run view ${run_id} --web"
      fi
    else
      echo "Release workflow was triggered, but no run id was found yet."
    fi
  fi
else
  echo "gh is not installed; the tag push will still trigger GitHub Actions."
fi

echo "Release ${TAG} requested."
