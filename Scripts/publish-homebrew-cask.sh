#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-}"
DMG_FILE="${DMG_FILE:-}"
OWNER_REPO="${OWNER_REPO:-mitchins/clipdisk}"
TAP_REPO="${TAP_REPO:-mitchins/homebrew-tap}"
CASK_NAME="${CASK_NAME:-clipdisk}"

if [[ -z "$VERSION" ]]; then
  echo "VERSION is required"
  exit 1
fi

if [[ -z "$DMG_FILE" ]]; then
  echo "DMG_FILE is required"
  exit 1
fi

if [[ ! -f "$DMG_FILE" ]]; then
  echo "DMG file not found: $DMG_FILE"
  echo "Build/package first or point DMG_FILE at the notarized release artifact."
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI (gh) is required"
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required"
  exit 1
fi

if ! command -v shasum >/dev/null 2>&1; then
  echo "shasum is required"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Run 'gh auth login' before publishing Homebrew cask metadata."
  exit 1
fi

gh auth setup-git >/dev/null

SHA256=$(shasum -a 256 "$DMG_FILE" | awk '{print $1}')
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TAP_DIR="$TMP_DIR/tap"
CASK_PATH="$TAP_DIR/Casks/$CASK_NAME.rb"

echo "Cloning tap: $TAP_REPO"
git clone "https://github.com/$TAP_REPO.git" "$TAP_DIR"
mkdir -p "$TAP_DIR/Casks"

cat > "$CASK_PATH" <<EOF
cask "$CASK_NAME" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$OWNER_REPO/releases/download/v#{version}/ClipboardFolder-#{version}.dmg"
  name "Clipdisk"
  desc "Clipboard contents on a RAM disk for quick file uploads"
  homepage "https://github.com/$OWNER_REPO"

  app "ClipboardFolder.app"
end
EOF

cd "$TAP_DIR"
if git diff --quiet -- "$CASK_PATH"; then
  echo "No Homebrew cask changes detected for $CASK_NAME"
  exit 0
fi

git add "$CASK_PATH"
git commit -m "$CASK_NAME $VERSION"
git push

echo "Published Homebrew cask: $TAP_REPO/Casks/$CASK_NAME.rb"
