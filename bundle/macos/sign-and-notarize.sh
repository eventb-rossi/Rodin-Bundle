#!/bin/bash
#
# Turn one Tycho macOS product tarball into a signed, notarized, stapled zip.
#
#   sign-and-notarize.sh <archive.tar.gz> <output-directory>
#
# macOS only; needs the Xcode command line tools for codesign, notarytool and
# stapler.  Safe to run by hand on a developer machine, which is how the flow
# should be proven before it is trusted in CI.
#
# Required:
#   MACOS_SIGN_IDENTITY  e.g. "Developer ID Application: Jane Doe (ABCDE12345)",
#                        or "-" for an ad-hoc signature
#
# Required unless SKIP_NOTARIZE=1:
#   AC_API_KEY_PATH      path to the App Store Connect AuthKey_<KeyID>.p8
#   AC_API_KEY_ID        its Key ID
#   AC_API_ISSUER_ID     the team's issuer UUID
#
# Optional:
#   MACOS_BUNDLE_ID      default org.eventb.rossi.rodin
#   SKIP_NOTARIZE=1      sign and verify only.  The zip it writes is still
#                        rejected by Gatekeeper; this is for iterating on the
#                        signing half without burning notary round-trips.
#
# No arrays and no mapfile anywhere below: /bin/bash on macOS is 3.2, which
# has neither mapfile nor a safe empty-array expansion under `set -u`.  Lists
# are newline-separated strings read with `while read`.
set -euo pipefail

usage="usage: sign-and-notarize.sh <archive.tar.gz> <output-directory>"
archive=${1:?$usage}
outdir=${2:?$usage}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

: "${MACOS_SIGN_IDENTITY:?set MACOS_SIGN_IDENTITY to the Developer ID Application identity}"
bundle_id=${MACOS_BUNDLE_ID:-org.eventb.rossi.rodin}
skip_notarize=${SKIP_NOTARIZE:-0}

if [ "$skip_notarize" != 1 ]; then
  : "${AC_API_KEY_PATH:?set AC_API_KEY_PATH, or SKIP_NOTARIZE=1 to sign only}"
  : "${AC_API_KEY_ID:?set AC_API_KEY_ID, or SKIP_NOTARIZE=1 to sign only}"
  : "${AC_API_ISSUER_ID:?set AC_API_ISSUER_ID, or SKIP_NOTARIZE=1 to sign only}"
fi

archive=$(cd "$(dirname "$archive")" && pwd)/$(basename "$archive")
mkdir -p "$outdir"
outdir=$(cd "$outdir" && pwd)

# The name is bundle/pom.xml's archiveFileName:
#   rodin-<version>.<qualifier>-<bundle-suffix>-<platform>.tar.gz
base=$(basename "$archive" .tar.gz)          # rodin-3.10.0.step2b-rossi-macosx.cocoa.aarch64
version=${base#rodin-}; version=${version%%-rossi-*}   # 3.10.0.step2b
# CFBundleShortVersionString is the user-facing "3.10.0"; the build qualifier
# goes in CFBundleVersion, which macOS treats as an opaque build number.
short_version=$(cut -d. -f1-3 <<< "$version")

# ------------------------------------------------------------------ helpers --

# The hardened runtime only for a real identity.  Notarization is what demands
# it, and an ad-hoc signature is never notarized.  It switches on library
# validation, which with no Team ID to match rejects every non-system library
# a binary loads: ad-hoc signed, CVC4 cannot load its own dylibs.
if [ "$MACOS_SIGN_IDENTITY" = - ]; then hardened=; else hardened=runtime; fi

sign_one() { # sign_one <file-or-bundle> <identifier> <entitlements>
  codesign --force --timestamp ${hardened:+--options "$hardened"} \
           --sign "$MACOS_SIGN_IDENTITY" \
           --identifier "$2" --entitlements "$3" "$1"
}

# True for a binary its vendor already signed for distribution: a Developer ID
# identity, the hardened runtime and a secure timestamp, still intact.  That is
# everything notarization asks of nested code, and code from another team is
# fine inside our bundle, so such a binary is left as it is.  Re-signing it
# would swap the vendor's entitlements for ours, and the vendor knows what its
# code needs: probcli's SICStus runtime generates code at run time and fails
# to start without allow-jit.  Today this keeps ProB's natives (HHU), JNA and
# the Equinox launcher library (Eclipse Foundation).
vendor_signed() {
  local info
  info=$(codesign -dvv "$1" 2>&1) || return 1
  grep -q '^Authority=Developer ID Application: ' <<< "$info" \
    && grep -q '^Timestamp=' <<< "$info" \
    && grep -qE '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime' <<< "$info" \
    && codesign --verify --strict "$1" 2>/dev/null
}

# Absolute path of every Mach-O file under a directory, one per line.  One
# `file` pass over the tree; this is the only Mach-O test in the script.
macho_files_under() {
  find "$1" -type f ! -name '*.jar' -print0 2>/dev/null \
    | xargs -0 file 2>/dev/null | grep '^[^:]*: *Mach-O' | cut -d: -f1 || true
}

# Every file under a directory that should carry the executable bit: each
# Mach-O, and each file that starts with #!.  A function rather than inline in
# the <( ) that reads it, because bash 3.2 mis-parses a comment there.
should_be_executable() {
  macho_files_under "$1"
  # shellcheck disable=SC2016 # the dollar signs are Perl variables
  find "$1" -type f ! -perm -u+x ! -name '*.jar' -size -1024k -print0 \
    | xargs -0 perl -e 'for (@ARGV) { open(my $f, "<", $_) or next;
                                      read($f, my $b, 2); print "$_\n" if $b eq "#!" }'
}

# Notarization rejects a Mach-O whose load commands record an SDK older than
# macOS 10.9.  Today that is CVC3 alone, built in 2013 against the 10.7 SDK, and
# its 2.4.1 source no longer builds correctly with a current toolchain.  vtool
# rewrites the one field: the minimum macOS stays what it was, and the binary
# was checked to run and answer SMT-LIB 2 afterwards.  A binary built against
# the 10.9 SDK or later is left alone, as is one recording its SDK in
# LC_BUILD_VERSION, which no SDK before 10.14 writes.
lift_old_sdk() { # lift_old_sdk <mach-o>
  local cmds minos sdk
  cmds=$(otool -l "$1" 2>/dev/null || true)
  read -r minos sdk < <(awk '
    $1 == "cmd"                { in_min = ($2 == "LC_VERSION_MIN_MACOSX") }
    in_min && $1 == "version"  { minos = $2 }
    in_min && $1 == "sdk"      { print minos, $2; exit }' <<< "$cmds") || return 0
  case $sdk in
    10.[0-8]|10.[0-8].*|n/a) ;;
    *) return 0 ;;
  esac
  xcrun vtool -set-version-min macos "$minos" 10.9 -replace -output "$1.sdk" "$1"
  cat "$1.sdk" > "$1"   # through cat, so the file keeps its mode
  rm -f "$1.sdk"
  echo "    $(basename "$1"): recorded SDK $sdk raised to 10.9, minimum macOS stays $minos"
}

# Sign a bundled native of our own.  Every one gets the empty
# solver.entitlements, library validation included: the only one that loads
# libraries of its own, CVC4, loads siblings signed in this same pass under the
# same Team ID, which is all validation asks.  The reasoning, and why the
# .entitlements files carry no comments, is in README.md under "Signing the
# macOS archives".
sign_native() { # sign_native <file> <identifier>
  lift_old_sdk "$1"
  sign_one "$1" "$2" "$here/solver.entitlements"
}

# Name a nested binary after the file it came from, so `codesign -dv` on a
# crash report says which solver it was rather than repeating the app's id.
native_id() { # native_id <bundle-id-prefix> <path>
  local slug
  slug=$(tr -cs 'A-Za-z0-9.' '-' <<< "$(basename "$2")" | sed 's/^-//;s/-$//')
  echo "$1.native.$slug"
}

# sign_jars_in <directory> <bundle-id-prefix>
#
# Signs every Mach-O held inside a jar under <directory>, in place.  A Mach-O
# signature lives inside the file itself, so a binary signed before it is
# jarred is still signed after Eclipse extracts it to the configuration area
# and execs it -- which is the only thing that makes the jarred solvers
# trusted.  Signing the surrounding .app does nothing for them.
sign_jars_in() {
  local root=$1 prefix=$2
  local jar stage entry entries candidates changed jars_signed=0 skipped=""

  while IFS= read -r jar; do
    entries=$(unzip -Z1 "$jar" 2>/dev/null || true)

    # Only extract entries that could plausibly be Mach-O; probing every entry
    # of every platform jar would dominate the runtime for no gain.  .class is
    # excluded because a Java class file starts with the same 0xCAFEBABE magic
    # as a Mach-O universal binary, and plug-ins like org.eclipse.help.base
    # have whole packages under a macosx/ path.  `file` tells them apart, but
    # not extracting them at all is cheaper and keeps the skipped-jar report
    # down to genuinely native bundles.
    candidates=$(grep -viE '(/|\.class)$' <<< "$entries" \
      | grep -iE '(\.(dylib|jnilib|so)$|(^|/)(os/mac|macos|darwin)[^/]*/)' || true)
    [ -n "$candidates" ] || continue

    # Eclipse signs its own jars, and rewriting an entry silently invalidates
    # that signature.  Skipping them costs nothing: every Mach-O inside one
    # already carries its own code signature from the Eclipse Foundation --
    # checked across SWT, org.eclipse.core.filesystem.macosx and
    # org.eclipse.equinox.security.macosx.  They are still listed so that a
    # future plug-in shipping *unsigned* native code inside a signed jar shows
    # up here rather than as an unexplained notarization rejection.
    if grep -qiE '^META-INF/.*\.(SF|RSA|DSA)$' <<< "$entries"; then
      skipped="$skipped      $(basename "$jar")"$'\n'
      continue
    fi

    stage=$(mktemp -d)
    tr '\n' '\0' <<< "$candidates" | xargs -0 unzip -qo "$jar" -d "$stage" || true
    # unzip's own exit code is useless here -- xargs may have run it several
    # times and maps a warning to 123 -- so check the outcome instead.  An
    # entry that does not come out is a binary that ships unsigned, which
    # surfaces much later as an unexplained notarization rejection.
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      [ -e "$stage/$entry" ] || {
        echo "cannot extract $entry from $jar" >&2
        exit 1
      }
    done <<< "$candidates"
    changed=
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      vendor_signed "$stage/$entry" && continue
      sign_native "$stage/$entry" "$(native_id "$prefix" "$entry")"
      changed="${changed:+$changed$'\n'}$entry"
    done < <(macho_files_under "$stage" | sed "s|^$stage/||")

    if [ -n "$changed" ]; then
      # zip updates the named entries in place and leaves every other byte of
      # the jar alone, so the OSGi metadata and entry order survive.
      ( cd "$stage" && zip -q "$jar" -@ <<< "$changed" )
      echo "    $(basename "$jar"): $(grep -c . <<< "$changed") binaries"
      jars_signed=$((jars_signed + 1))
    fi
    rm -rf "$stage"
  done < <(find "$root" -name '*.jar')

  echo "    signed native code in $jars_signed jars"
  if [ -n "$skipped" ]; then
    echo "    left $(grep -c . <<< "$skipped") jar-signed bundles untouched:"
    printf '%s' "$skipped"
  fi
}

# ---------------------------------------------------------------------- run --

work=$(mktemp -d)
# Success is reaching the last line, not whatever $? says on the way out.
# bash 3.2 dies on some errors -- a parse error inside <( ) is one -- with $?
# already 0 by the time an EXIT trap runs, so a plain cleanup trap turns a
# crash into exit 0 and CI carries on without the zip.
finished=
trap 'status=$?; rm -rf "$work"
      [ -n "$finished" ] || [ "$status" -ne 0 ] || status=1; exit "$status"' EXIT

echo "==> Unpacking $base"
tar xzf "$archive" -C "$work"
app=$(find "$work" -maxdepth 1 -name '*.app' | head -1)
test -n "$app" || { echo "no .app at the root of $archive" >&2; exit 1; }

# Safeguards for a product build that fails to brand the bundle, which has
# happened: Tycho left the Equinox executable's untouched Eclipse.app skeleton
# behind and no Info.plist in Contents/.  A bundle with no Info.plist cannot be
# signed at all, and an unsigned nested bundle claiming org.eclipse.Eclipse
# fails --deep --strict.  Current builds arrive branded and skip all three.
if [ -d "$app/Contents/Eclipse.app" ]; then
  echo "==> Removing the leftover Eclipse.app skeleton"
  rm -rf "$app/Contents/Eclipse.app"
fi

plist="$app/Contents/Info.plist"
if [ ! -f "$plist" ]; then
  echo "==> Synthesizing Contents/Info.plist (Tycho did not brand the bundle)"
  mkdir -p "$app/Contents"
  sed -e "s|@BUNDLE_ID@|$bundle_id|" \
      -e "s|@SHORT_VERSION@|$short_version|" \
      -e "s|@BUNDLE_VERSION@|$version|" \
      "$here/Info.plist.in" > "$plist"
else
  existing_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)
  # Tycho brands the bundle with the p2 product id, org.eventb.rossi.product,
  # or with upstream Eclipse's when a product sets none.  The signature names
  # $bundle_id as its identifier, and the two should agree: macOS keys per-app
  # state and permissions off both.  And two apps must never share one, or
  # Rodin would inherit an Eclipse installation's Launch Services entry.
  if [ "$existing_id" != "$bundle_id" ]; then
    echo "==> Rewriting CFBundleIdentifier '$existing_id' -> $bundle_id"
    plutil -replace CFBundleIdentifier -string "$bundle_id" "$plist"
  fi
fi

if [ ! -f "$app/Contents/Resources/rodin.icns" ]; then
  echo "==> Adding Contents/Resources/rodin.icns"
  mkdir -p "$app/Contents/Resources"
  cp "$here/rodin.icns" "$app/Contents/Resources/rodin.icns"
fi

# Finder metadata and a stray quarantine bit both make codesign refuse.
xattr -cr "$app"

# p2 drops the executable bit on every file it unpacks, and the plug-ins put
# it back when they start: ProB on probcli.sh, probcli and its helpers, the
# SMT plug-in on CVC4.  That needs a writable install.  macOS runs a
# quarantined app the user has not moved from a read-only translocated copy,
# where the chmod fails and ProB never starts ("probcli.sh isn't executable").
# So the zip carries the bits, which ditto restores: every Mach-O, and every
# file that starts with #!.
echo "==> Restoring executable bits"
made_exec=0
while IFS= read -r f; do
  [ -n "$f" ] && [ ! -x "$f" ] || continue
  chmod +x "$f"
  made_exec=$((made_exec + 1))
done < <(should_be_executable "$app/Contents")
echo "    $made_exec files"

echo "==> Signing native code inside jars"
sign_jars_in "$app" "$bundle_id"

# Everything unpacked on disk: the CVC4 fragment and its dylibs, ProB's
# probcli, JNA's libjnidispatch, the Equinox launcher fragment.  Found by
# probing the whole bundle rather than from a path list, so a newly bundled
# plug-in cannot slip a binary past this step.  Only CVC4 arrives unsigned;
# the rest keep their vendors' signatures (see vendor_signed).  The launcher
# is Eclipse's too, and is re-signed regardless below: it is the bundle's main
# executable, so it carries the bundle's identity.
echo "==> Signing loose native code"
signed=0 kept=0
while IFS= read -r bin; do
  [ -n "$bin" ] || continue
  if vendor_signed "$bin"; then
    kept=$((kept + 1))
    continue
  fi
  sign_native "$bin" "$(native_id "$bundle_id" "$bin")"
  signed=$((signed + 1))
done < <(macho_files_under "$app/Contents")
echo "    signed $signed binaries, kept $kept vendor signatures"

# The launcher, then the bundle containing it.  A bundle signature seals the
# files beneath it, so anything re-signed afterwards would break that seal --
# which is why the app is signed last and why --deep is used only to verify.
echo "==> Signing the launcher and the app"
launcher=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$plist")
sign_one "$app/Contents/MacOS/$launcher" "$bundle_id.launcher" "$here/rodin.entitlements"
sign_one "$app" "$bundle_id" "$here/rodin.entitlements"

echo "==> Verifying the signature"
codesign --verify --deep --strict --verbose=2 "$app"
codesign -dv --entitlements - "$app" 2>&1 | sed 's/^/    /'

if [ "$skip_notarize" = 1 ]; then
  echo "==> SKIP_NOTARIZE=1: not submitting to Apple"
else
  echo "==> Notarizing"
  # notarytool takes zip, dmg or pkg -- never a tarball, which is why the macOS
  # release format changes here rather than in bundle/pom.xml.  ditto is the
  # only zipper Apple documents as preserving bundle structure.
  ditto -c -k --sequesterRsrc --keepParent "$app" "$work/submit.zip"
  # Apple usually answers within the hour, but not always: on 13 November
  # 2026 an x86_64 submission was accepted after 48 minutes while the arm64
  # one sent the same second was still "In Progress" four hours later, as were
  # four resubmissions of it sent since.  Resubmitting does not help, waiting
  # might, so wait as long as the job allows, polling by hand so that a failed
  # status query is simply retried.  Results go through files because plutil
  # reads a path reliably on every macOS that ships notarytool, stdin only on
  # some.
  notary() {
    xcrun notarytool "$@" --key "$AC_API_KEY_PATH" --key-id "$AC_API_KEY_ID" \
      --issuer "$AC_API_ISSUER_ID"
  }
  field() { plutil -extract "$1" raw -o - "$2" 2>/dev/null || true; }
  notary submit "$work/submit.zip" --output-format json > "$work/submit.json" || true
  id=$(field id "$work/submit.json")
  # No id means the upload or the credentials failed; waiting will not help.
  [ -n "$id" ] || { cat "$work/submit.json"; echo "notarytool submit failed" >&2; exit 1; }
  echo "    submitted $id"
  status='' started=$SECONDS
  while [ $((SECONDS - started)) -lt 18000 ]; do
    sleep 60
    notary info "$id" --output-format json > "$work/info.json" 2>/dev/null || continue
    status=$(field status "$work/info.json")
    case $status in Accepted|Invalid|Rejected) break ;; *) status='' ;; esac
  done
  if [ "$status" != Accepted ]; then
    if [ -z "$status" ]; then
      echo "Apple has not finished submission $id in five hours; run the" \
           "job again later ('xcrun notarytool info $id' shows where it stands)" >&2
      exit 1
    fi
    # The submission log is the only place Apple names the binary it objected
    # to, so always print it before failing.
    notary log "$id" || true
    echo "notarization failed: submission $id is $status" >&2
    exit 1
  fi
  echo "    $id: Accepted"

  echo "==> Stapling"
  # Staple the .app, not the zip: a zip cannot carry a ticket, but a ticket
  # inside the bundle survives unzipping and then works with no network.
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl -a -t exec -vvv "$app"
fi

echo "==> Packing $base.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$outdir/$base.zip"
ls -l "$outdir/$base.zip"
finished=1
