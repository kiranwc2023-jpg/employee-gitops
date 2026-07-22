#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════
# update-image-tag.sh — GitOps Image Tag Updater
#
# PURPOSE:
#   Called by the CI pipeline (GitHub Actions) to update the Docker image
#   tag in the GitOps repository after a successful build.
#
# USAGE:
#   ./scripts/update-image-tag.sh <new-version>
#   ./scripts/update-image-tag.sh 1.2.3
#
# WHAT IT DOES:
#   1. Validates the input version
#   2. Updates image tag in helm/values.yaml
#   3. Updates image in k8s/deployment.yaml
#   4. Commits and pushes the changes
#
# This script is idempotent — running it with the same version twice
# produces the same result (no duplicate commits).
# ═══════════════════════════════════════════════════════════════════════

# set -e: Exit immediately if ANY command fails (returns non-zero exit code).
# Without this: if `sed` fails, the script continues and commits broken changes.
set -e

# set -u: Exit if an undefined variable is used.
# Without this: "${UNDEFINED_VAR}" silently becomes empty → cryptic bugs.
set -u

# set -o pipefail: If any command in a pipeline fails, the whole pipeline fails.
# Without this: `false | echo "ok"` returns 0 (pipelines return last command's exit code).
# With pipefail: the failed `false` causes the pipeline to return 1.
set -o pipefail

# ───────────────────────────────────────────────────────────────────────
# ARGUMENTS AND VALIDATION
# ───────────────────────────────────────────────────────────────────────

# $1 is the first command-line argument.
# ${1:-} uses empty string as default if $1 is not set.
# We then check if it's empty and exit with error.
NEW_VERSION="${1:-}"

# Validate: version must be provided
if [ -z "$NEW_VERSION" ]; then
  # >&2 redirects to stderr (standard error stream).
  # Error messages should go to stderr, not stdout.
  # Allows callers to capture stdout separately: result=$(./script.sh 2>/dev/null)
  echo "ERROR: Version argument is required." >&2
  echo "Usage: $0 <version>" >&2
  echo "Example: $0 1.2.3" >&2
  # exit 1: non-zero exit code signals failure to the caller (GitHub Actions).
  # GitHub Actions aborts the workflow step if a script exits non-zero.
  exit 1
fi

# Validate: version must match Semantic Versioning format (e.g., 1.2.3)
# [[ =~ ]] is a bash regular expression test.
# ^ = start of string
# [0-9]+\.[0-9]+\.[0-9]+ = one or more digits, dot, repeat (e.g., 10.2.345)
# $ = end of string
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: Version must follow Semantic Versioning format: MAJOR.MINOR.PATCH" >&2
  echo "Received: '$NEW_VERSION'" >&2
  exit 1
fi

echo "Updating image tag to: $NEW_VERSION"

# ───────────────────────────────────────────────────────────────────────
# IMAGE REFERENCE
# ───────────────────────────────────────────────────────────────────────

# IMAGE_REPO: the Docker image repository (without tag).
# ${IMAGE_REPO:-ghcr.io/mycompany/employee-service}: use env var or default.
# In GitHub Actions, this is set from ${{ env.IMAGE_NAME }}.
IMAGE_REPO="${IMAGE_REPO:-ghcr.io/mycompany/employee-service}"

# The full image reference with the new tag
FULL_IMAGE="${IMAGE_REPO}:${NEW_VERSION}"
echo "Full image reference: $FULL_IMAGE"

# ───────────────────────────────────────────────────────────────────────
# DETECT AVAILABLE TOOLS
# ───────────────────────────────────────────────────────────────────────

# Prefer yq over sed for YAML manipulation.
# yq is a structured YAML parser — safe for nested keys.
# sed uses regex — fragile for YAML (whitespace/indentation sensitive).
if command -v yq &>/dev/null; then
  echo "Using yq for YAML updates"

  # yq -i: in-place edit (modify the file directly).
  # '.image.tag = "1.2.3"' sets the nested key image.tag to the new version.
  # This is type-safe YAML: yq understands the structure.
  # With sed: `s/tag: .*/tag: "1.2.3"/` might accidentally match wrong lines.
  yq -i ".image.tag = \"${NEW_VERSION}\"" helm/values.yaml

  # Update the appVersion in Chart.yaml to match
  yq -i ".appVersion = \"${NEW_VERSION}\"" helm/Chart.yaml

else
  echo "yq not found, falling back to sed"

  # sed -i: in-place edit.
  # 's/pattern/replacement/' syntax.
  # Pattern: tag: "any-semver-string"
  # Replacement: tag: "new-version"
  # The -E flag enables extended regular expressions (ERE).
  # [0-9]+\.[0-9]+\.[0-9]+ matches any semantic version.
  sed -i -E "s/tag: \"[0-9]+\.[0-9]+\.[0-9]+\"/tag: \"${NEW_VERSION}\"/" helm/values.yaml
fi

# Update the plain k8s deployment manifest.
# Pattern matches the image line (regardless of current version).
# The pipe in the image URL uses | as sed delimiter (safer than / which appears in URLs).
sed -i "s|image: ${IMAGE_REPO}:.*|image: ${FULL_IMAGE}|g" k8s/deployment.yaml

echo "File changes:"
echo "--- helm/values.yaml ---"
grep -n "tag:" helm/values.yaml || true
echo "--- k8s/deployment.yaml ---"
grep -n "image:" k8s/deployment.yaml | grep employee-service || true

# ───────────────────────────────────────────────────────────────────────
# GIT OPERATIONS
# ───────────────────────────────────────────────────────────────────────

# Configure git identity for automated commits.
# github-actions[bot] is the conventional name for GitHub Actions automation.
# Using a bot identity makes automated commits identifiable in git log.
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# git diff --quiet: returns exit 0 if no changes, exit 1 if changes exist.
# We only commit when there are actual changes — avoids empty commits.
if git diff --quiet; then
  echo "No changes detected — image tag was already up to date."
  exit 0
fi

# Stage specific files — avoid `git add .` which might stage unexpected files.
git add helm/values.yaml helm/Chart.yaml k8s/deployment.yaml

# Show what is staged
echo "Staged changes:"
git status --short

# git commit with a descriptive message.
# The message includes:
#   - What: "deploy: update image tag"
#   - Version: 1.2.3
#   - Triggered by: source repo + commit SHA (from CI environment variables)
COMMIT_MESSAGE="deploy: update employee-service image to ${NEW_VERSION}

Image: ${FULL_IMAGE}
Triggered by: ${GITHUB_REPOSITORY:-manual}@${GITHUB_SHA:-unknown}
Pipeline: ${GITHUB_WORKFLOW:-manual}
Branch: ${GITHUB_REF_NAME:-unknown}
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

git commit -m "$COMMIT_MESSAGE"

# git push: push the commit to the remote repository (employee-gitops).
# This push is what Argo CD detects (either via polling or webhook).
# After this push:
#   1. GitHub updates the remote branch
#   2. Argo CD polls/receives webhook → detects new commit SHA
#   3. Argo CD re-renders Helm templates with new image tag
#   4. Argo CD applies: kubectl set image deployment/employee-service employee-service=ghcr.io/..:1.2.3
#   5. Kubernetes rolling update starts
#   6. New pods start with new image
#   7. Health probes pass → traffic shifted to new pods
#   8. Old pods terminated
git push

echo "SUCCESS: GitOps repository updated to version ${NEW_VERSION}"
echo "Argo CD will detect the change and deploy the new version to Kubernetes."
echo "Monitor deployment at: https://argocd.company.com/applications/employee-service-prod"
