#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK_SRC="${ROOT}/PinkTabHook/PinkTabHook.m"
DYLIB_NAME="libLockedInPinkTabs.dylib"
ENTITLEMENTS="${ROOT}/entitlements/pink-inject.entitlements"

# Default: sibling "Contents" in workspace (this repo lives inside a .app skeleton)
DEFAULT_SRC="$(cd "${ROOT}/.." && pwd)"
SOURCE_APP="${1:-${DEFAULT_SRC}}"

if [[ ! -d "${SOURCE_APP}/Contents" ]]; then
  echo "Usage: $0 [/path/to/LockDown\\ Browser.app-or-folder-with-Contents]"
  echo "Expected: .../Contents/{MacOS,Frameworks,Info.plist,...}"
  exit 1
fi

OUT_DIR="${ROOT}/dist"
APP_NAME="LockedIn-Browser-Cursor-HotPink.app"
DEST="${OUT_DIR}/${APP_NAME}"

rm -rf "${DEST}"
mkdir -p "${DEST}"
rsync -a "${SOURCE_APP}/Contents" "${DEST}/"

# Developer provisioning profile from the vendor does not match ad hoc signing and can confuse validation.
rm -f "${DEST}/Contents/embedded.provisionprofile"

HOOK_BUILD="$(mktemp -d)"
trap 'rm -rf "${HOOK_BUILD}"' EXIT

# LockDown Browser ships x86_64 (Rosetta on Apple Silicon). The inject dylib must
# include an x86_64 slice or dyld aborts. Universal2 covers Intel + Apple Silicon hosts.
clang -dynamiclib -fobjc-arc -O2 \
  -arch x86_64 -arch arm64 \
  -framework Security -framework AppKit -framework Foundation \
  -install_name "@executable_path/../Frameworks/${DYLIB_NAME}" \
  -o "${HOOK_BUILD}/${DYLIB_NAME}" \
  "${HOOK_SRC}"

lipo -info "${HOOK_BUILD}/${DYLIB_NAME}"

mkdir -p "${DEST}/Contents/Frameworks"
cp "${HOOK_BUILD}/${DYLIB_NAME}" "${DEST}/Contents/Frameworks/${DYLIB_NAME}"

# Helpers have their own Info.plist LSEnvironment (often only MallocNanoZone). That
# can replace inherited env so DYLD_INSERT_LIBRARIES never reaches GPU/Renderer/etc.
# Mirror the dylib and merge DYLD_INSERT_LIBRARIES into every nested helper bundle.
shopt -s nullglob
for helper_app in "${DEST}/Contents/Frameworks/"*.app; do
  [[ -d "${helper_app}/Contents" ]] || continue
  mkdir -p "${helper_app}/Contents/Frameworks"
  cp "${HOOK_BUILD}/${DYLIB_NAME}" "${helper_app}/Contents/Frameworks/${DYLIB_NAME}"
  hp="${helper_app}/Contents/Info.plist"
  if [[ -f "${hp}" ]]; then
    /usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "${hp}" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :LSEnvironment:DYLD_INSERT_LIBRARIES string @executable_path/../Frameworks/${DYLIB_NAME}" "${hp}" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Set :LSEnvironment:DYLD_INSERT_LIBRARIES @executable_path/../Frameworks/${DYLIB_NAME}" "${hp}"
  fi
done
shopt -u nullglob

PLIST="${DEST}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName LockedIn Browser (Cursor · Hot Pink)" "${PLIST}" || true
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string LockedIn Browser · Hot Pink" "${PLIST}" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName LockedIn Browser · Hot Pink" "${PLIST}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 2.1.5-cursor-hotpink" "${PLIST}" || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 7603-cursor-hotpink" "${PLIST}" || true

# Merge LSEnvironment for DYLD_INSERT_LIBRARIES
/usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "${PLIST}" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:DYLD_INSERT_LIBRARIES string @executable_path/../Frameworks/${DYLIB_NAME}" "${PLIST}" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :LSEnvironment:DYLD_INSERT_LIBRARIES @executable_path/../Frameworks/${DYLIB_NAME}" "${PLIST}"

echo "Built: ${DEST}"
echo "Re-signing ad hoc (required after modifying the bundle)..."

codesign --force --deep --sign - --entitlements "${ENTITLEMENTS}" "${DEST}" || {
  echo "codesign failed. Try: open System Settings → Privacy & Security, or run from Terminal to see the Gatekeeper prompt."
  exit 1
}

# Strip provenance/quarantine bits that sometimes trigger “damaged” dialogs for locally rebuilt bundles.
xattr -cr "${DEST}" 2>/dev/null || true

echo "Done. Open with:"
echo "  open \"${DEST}\""
