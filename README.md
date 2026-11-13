# Rodin Bundle (eventb-rossi)

A Rodin distribution built from the Rodin 3.10 platform plus two plug-ins that
came out of work at ISP RAS (parallel and faster automatic proving, and a
recovery tool for broken proof obligations), plus a bridge that lets the Rossi
language server talk to a running Rodin.

Windows, Linux and macOS (Intel and Apple Silicon) archives are published on the
[releases page](../../releases). The macOS archives are signed with a Developer
ID certificate, notarized by Apple and stapled: unzip, move `rodin.app` to
Applications, and the first launch shows only macOS's usual confirmation for
an app downloaded from the Internet -- no malware warning, no `xattr`. Every
asset carries a build provenance attestation you can check with
`gh attestation verify --repo eventb-rossi/Rodin-Bundle <file>`.

## What this adds to stock Rodin

**A `First Successful` tactic combinator.** Runs several tactics at once and
finishes as soon as one of them proves the goal, or when they have all failed.
With six provers at a one-second timeout, the worst case is one second instead
of six, and the usual case is a fraction of that.

**A `Default Interactive Tactic with SMT` profile.** Built on the combinator and
aimed at interactive proving: pressing the auto-prover button is bounded at
about a second. Since a single interactive proof involves many such presses,
this is the change the original author found most valuable in practice.
The bundle selects this profile for interactive proving by default, and
`Default Auto Tactic with SMT` for background proving. Existing workspace and
project choices are preserved. Use *Restore Defaults* in Event-B → Sequent
Prover → Auto/Post Tactic to adopt the bundle defaults in an existing workspace.

**Eight more tactics in the profile editor** (Event-B → Sequent Prover →
Auto/Post Tactic → Profiles), all wrappers around reasoners Rodin already has:

| Tactic | |
| --- | --- |
| Disjunctions in Hypotheses (Split) | Implications in Hypotheses (Split) |
| Relation Overriding in Hypotheses (Split) | Relation Overriding in Goal (Split) |
| Disjunction to Implication in Hypotheses (Simplify) | Disjunction to Implication in Goal (Simplify) |
| Set Equality Rewrites in Hypotheses (Simplify) | Set Equality Rewrites in Goal (Simplify) |

**SMT solvers before Lasso as well as after.** Some goals are provable by an SMT
solver before `Lasso` runs but not after. The default auto profile now attempts
both.

**An empty-set axiom in the SMT translation**, which lets the solvers discharge
some goals about empty sets that they previously could not.

**ProB.** The animator and model checker from the HHU Düsseldorf STUPS group,
bundled rather than left to its update site: *Start Animation* on a machine to
explore its states, and the ProB disprover to hunt counterexamples for proof
obligations no prover discharges. Its binaries are universal, so this is the one
prover integration here that works natively on Apple Silicon.

**Proof Obligation Cleaner.** Adds a *Clean Proof Obligation(s)* context menu to
the Event-B Explorer that drops the stored proof of the selected obligations.
This is the way out when a proof is broken badly enough that Rodin throws when
opening it.

**Rossi Bridge.** Opens a loopback socket inside Rodin and publishes it as
`<workspace>/.rossi-bridge/port`, so [Rossi](https://github.com/eventb-rossi/rossi)'s
Event-B language server can reach the *running* instance instead of only
writing files at it. It registers and reveals a project while Rodin holds the
workspace, which otherwise needs `File > Import`, and refreshes a project
after an external build. Nothing else changes: with the plug-in absent Rossi
keeps to its file-mediated path.

## Caveats

- **No SMT provers on Apple Silicon.** The bundled solver binaries are x86_64
  only. This is inherited from upstream: the official Rodin 3.10 release notes
  carry the same caveat. Apple Silicon users who need SMT should install the
  Intel build and an Intel JVM under Rosetta. The native Apple Silicon bundle
  includes the SMT integration and profiles, but no bundled solver entries;
  the profiles still run their available non-SMT tactics. Its startup prover
  check reports unavailable SMT tactics. ProB is unaffected: it animates and
  disproves natively there.
- **The archives are large.** ProB ships a single plug-in carrying its `probcli`
  binaries for Linux, macOS and Windows at once, so every archive holds all
  three, roughly 75 MB, whichever platform it targets.
- **The macOS archives ship as `.zip`, not `.tar.gz`.** Apple's notary service
  accepts only zip, dmg and pkg, and a tarball cannot carry the notarization
  ticket, so the format is dictated by the signing step. Linux and Windows are
  unchanged.

## Installing into an existing Rodin

The Proof Obligation Cleaner and the Rossi Bridge are ordinary Rodin plug-ins
and install into a stock Rodin 3.10 from

```
https://eventb-rossi.github.io/Rodin-Bundle/
```

through *Help > Install New Software*, or from a shell with the p2 director:

```sh
java -jar <rodin>/plugins/org.eclipse.equinox.launcher_*.jar -nosplash \
  -application org.eclipse.equinox.p2.director \
  -repository https://eventb-rossi.github.io/Rodin-Bundle/ \
  -installIU org.eventb.rossi.bridge.feature.feature.group \
  -destination <rodin> -profile DefaultProfile
```

A Rodin installed from this bundle already carries that site in its repository
list, so it can update the add-ons in place.

The site does not offer the SMT plug-in, and cannot: it calls
`BasicTactics.firstSuccessful`, which exists only in this bundle's Rodin, while
stock Rodin ships `org.eventb.core.seqprover` under the same version without
it. p2 would install the plug-in and it would fail the first time the tactic
ran. The SMT work comes with the bundle.

The site follows releases rather than `main`, so it offers the last released
version of each add-on.

## Layout

The four component repositories are submodules, each keeping its own `upstream`
remote so it can be rebased independently:

| Submodule | Upstream | Branch |
| --- | --- | --- |
| `rodincore/` | [systerel/RodinCore](https://github.com/systerel/RodinCore) | `rossi` |
| `rodin-b-sharp-smt/` | `git.code.sf.net/p/rodin-b-sharp/smt` | `rossi` |
| `POCleaner/` | ISP RAS, no upstream | `rossi` |
| `rossi-bridge/` | [eventb-rossi/rossi-bridge](https://github.com/eventb-rossi/rossi-bridge), no upstream | `rossi` |

`branding/` and `branding-feature/` register the bundle product and its defaults,
reusing artwork and base preferences from Rodin core at build time.
`bundle/` holds the product definition and `updates/` the add-on update
site; everything builds in one Tycho reactor.

## Building

Requires JDK 21 and Maven 3.9+, and a `~/.m2/toolchains.xml` declaring a
`jdk`/`21` toolchain (see `rodincore/org.rodinp.releng/toolchains.xml`; note the
checked-in template still says 17).

```bash
git clone --recurse-submodules https://github.com/eventb-rossi/Rodin-Bundle
cd Rodin-Bundle
mvn -pl '!rodincore/org.rodinp.platform.repository' clean verify \
  -DforceContextQualifier=local
```

Archives land in `bundle/target/products/`, the p2 update site in
`bundle/target/repository/`. The excluded module builds the *stock* Rodin
product; skipping it avoids materializing eight product archives instead of
four.

## Releasing

Releases are cut by pushing a tag; CI builds, smoke-tests every platform archive,
then publishes the release and attaches the assets.

```bash
# submodule pins must already point at the rossi tips -- the workflow refuses
# to publish a release that would ship stale component commits
git tag v3.10.0-2609
git push origin v3.10.0-2609
```

The tag is `vX.Y.Z-YYMM[.N]`, where `X.Y.Z` is the Rodin version in the bundle
and `YYMM` the build month, following the scheme `eventB-Soton/Rodin-Bundles`
uses. A second release in the same month adds the serial `.N`, which that
scheme has no room for. The workflow rejects a tag whose version does not match
`bundle/pom.xml`.

Each release carries the four product archives, the p2 update site as a zip, and
`SHA256SUMS`. To re-attach assets to an existing tag, run the *Release* workflow
manually with that tag as its input; every upload uses `--clobber`, so re-runs
replace rather than duplicate.

### Signing the macOS archives

`sign-macos.yml` runs between the build and the smoke test: it signs every
Mach-O in the bundle that its vendor has not already signed, notarizes the app
with Apple, staples the ticket and re-emits the archive as a zip. Without the
secrets below it still repairs the bundle and re-emits it as a zip, signed ad
hoc and not notarized, and warns; a fork can still cut a release, and its
users are back to `xattr -rc rodin.app`. An ad-hoc signature goes without the
hardened runtime: there is no Team ID for its library validation to match, so
it would reject every bundled library a binary loads, and CVC4 could not load
its own dylibs.

A Developer ID certificate is a *team* identity, not an app identity: one
certificate signs Rodin, the solvers and any future
eventb-rossi tool. What distinguishes them is the bundle identifier
(`org.eventb.rossi.rodin` here), which for Developer ID distribution needs no
registration with Apple. Apple allows five Developer ID Application
certificates per team, so the only split worth making is by trust boundary --
one key on a laptop, one in CI -- never one per project.

To issue one, as the **Account Holder** (no other role can):

1. Keychain Access → Certificate Assistant → *Request a Certificate From a
   Certificate Authority*. Your Apple ID email, **Saved to disk**, **Let me
   specify key pair information**, **2048 bits**, **RSA**. Apple rejects ECC
   here.
2. developer.apple.com → Certificates → **+** → **Developer ID Application**,
   profile type **G2 Sub-CA**. Not *Developer ID Installer* (that signs `.pkg`,
   which we do not ship) and not the *Mac App Distribution* pair (App Store
   only -- Gatekeeper rejects those for direct downloads).
3. Install the issued certificate, then export it **with its private key** as a
   `.p12`. Keep an offline copy: the private key cannot be downloaded again.
4. App Store Connect → Users and Access → Integrations → **Team Keys** →
   generate a key with **Developer** access. `AuthKey_<KeyID>.p8` downloads
   once. This is preferred over an Apple ID and app-specific password because
   it can be revoked on its own.

| Setting | Kind | Value |
| --- | --- | --- |
| `MACOS_CERT_P12_BASE64` | secret | `base64 -i cert.p12` |
| `MACOS_CERT_PASSWORD` | secret | the `.p12` export password |
| `AC_API_KEY_P8_BASE64` | secret | `base64 -i AuthKey_<KeyID>.p8` |
| `AC_API_KEY_ID` | secret | the key's ID |
| `AC_API_ISSUER_ID` | secret | the team's issuer UUID |
| `MACOS_SIGN_IDENTITY` | variable | `Developer ID Application: <name> (<team id>)` |

Signatures carry a secure timestamp, so they keep verifying after the
certificate expires; revoking one is what invalidates them, which is the
argument for giving CI a key of its own.

Notarization usually takes minutes to an hour, but Apple holds some
submissions far longer and says nothing about why. On 13 November 2026 an
x86_64 build was accepted in 48 minutes while the arm64 build sent the same
second was still "In Progress" four hours later, and four resubmissions of it,
sent half an hour apart, fared no better. Resubmitting does not help, so the
script submits once and waits up to five hours, most of what a GitHub job may
run. If Apple is slower still, the job fails naming the submission, and it
needs re-running later, not fixing.

`bundle/macos/sign-and-notarize.sh` is the whole flow and runs by hand too,
which is how to debug a rejection without pushing a tag:

```bash
export MACOS_SIGN_IDENTITY="Developer ID Application: ... (...)"
# sign and verify only, no notary round-trip
SKIP_NOTARIZE=1 bundle/macos/sign-and-notarize.sh \
  bundle/target/products/rodin-*-macosx.cocoa.aarch64.tar.gz /tmp/out
```

Neither `.entitlements` file carries comments, and they should stay that way:
`codesign` hands them to AMFI, whose XML parser is not a general one. It
rejects a plist `plutil -lint` calls valid -- a `--` inside an XML comment is
enough -- and the only symptom is `Failed to parse entitlements` at signing
time. So the reasoning lives here instead.

`rodin.entitlements` covers the launcher, which runs a JVM in process. Each key
buys back something the hardened runtime denies by default, and dropping any of
them breaks the app at launch or at the first proof:

| Entitlement | Why |
| --- | --- |
| `allow-jit` | HotSpot executes pages it just compiled into |
| `allow-unsigned-executable-memory` | the JIT writes them through a mapping that is not `MAP_JIT` |
| `disable-library-validation` | the product bundles no JRE, so the launcher loads `libjli`/`libjvm` from the user's JDK, signed by another team; SWT and JNA unpack `.jnilib` files at runtime |
| `allow-dyld-environment-variables` | the launcher and the JVM both find their libraries through `DYLD_*` |

A bundled native that arrives with its vendor's Developer ID signature, with
the hardened runtime and a secure timestamp and still valid, is left alone
(`vendor_signed` in the script). That is every native but CVC4's: ProB's
`probcli` and its libraries are signed by HHU, JNA and the Equinox launcher
library by the Eclipse Foundation. Notarization accepts nested code from
another team, and re-signing would replace the vendor's entitlements with
ours. `probcli` shows why that matters: its SICStus runtime generates code at
run time, and re-signed without `allow-jit` the x86_64 build stops at
`Prolog engine initialization failed`.

The rest -- the SMT solvers -- take `solver.entitlements`, an empty dict:
ahead-of-time native code that needs the hardened runtime notarization
requires and none of the JVM's exemptions. That keeps library validation on
even for CVC4, which loads four sibling dylibs by `@executable_path`.
Validation only asks that a library come from the loading binary's own team,
and the siblings are signed in the same pass with the same identity. Checked
on macOS 27 with a Developer ID: CVC4 runs, and with one sibling re-signed ad
hoc it dies with `Library not loaded: @executable_path/libgmp.10.dylib`. That
is also why the ad-hoc path leaves the hardened runtime off.

CVC3's macOS binary was built in 2013 against the 10.7 SDK, and notarization
rejects anything recording an SDK older than 10.9 (`The binary uses an SDK
older than the 10.9 SDK`, even from inside its jar). Rebuilding is not an
option: the 2.4.1 source only builds correctly with a pre-GCC 6 toolchain, see
`rodin-b-sharp-smt`'s Linux `build.sh`. So `lift_old_sdk` rewrites the one
field of `LC_VERSION_MIN_MACOSX` with `vtool` before signing, leaving the
minimum macOS at 10.7. The patched, signed binary still runs under Rosetta on
macOS 27 and answers SMT-LIB 2 correctly. Anything built against the 10.9 SDK
or later is left alone.

Things the script does that the build should arguably do itself:

- It restores the executable bits p2 drops: on every Mach-O and every `#!`
  script. The ProB and SMT plug-ins put them back at startup, but only in a
  writable install. Unzipped and opened in place, a quarantined app runs from
  a read-only translocated copy, and ProB then fails with `probcli.sh isn't
  executable` -- seen on macOS 27 with the notarized build before this step
  existed. The smoke test checks `probcli` is executable as shipped.
- It sets `CFBundleIdentifier` to `org.eventb.rossi.rodin`, the identifier
  the signature carries; Tycho brands the bundle with the p2 product id,
  `org.eventb.rossi.product`. It also still guards against a product build
  that fails to brand at all, removing a leftover `Contents/Eclipse.app`
  skeleton and writing `Contents/Info.plist` and the icon (see
  `bundle/macos/Info.plist.in`; `bundle/macos/rodin.icns` is a copy of
  `rodincore/org.rodinp.platform/rodin.icns`). Current builds arrive branded
  and skip those.
- It signs the solver binaries inside their fragment jars, and lifts CVC3's
  recorded SDK. Those are vendored blobs in `rodin-b-sharp-smt` that never
  change between releases, so doing both once at source and committing the
  resulting bytes would retire the jar walk. It would also give the p2 update
  site signed solvers for free: the site is deliberately not touched here,
  because rewriting a jar inside a finished p2 repository invalidates the size
  and SHA checksums recorded for it in `artifacts.jar`, and p2 then refuses to
  install the feature.
- Only CVC4's fragment is marked `unpack="true"` in its feature; giving Z3,
  CVC3 and veriT the same would put their binaries on disk where the loose
  scan already finds them.

Rodin breaks its own seal in normal use, and that is fine. Run from a writable
place -- dragged to Applications -- it writes its OSGi configuration into
`Contents/Eclipse/configuration`, and updating add-ons in place rewrites
`plugins/`. Gatekeeper assesses an app once, at its first launch, and does not
look again at one the user approved: on macOS 27, launched a second time with
its seal broken, Rodin started with nothing logged by `syspolicyd` and ProB
ran. A write does break inspecting the bundle from outside. Before that first
launch a modified bundle is "damaged" and nothing in it runs; once Gatekeeper
has checked it, macOS refuses writes into it from other teams' code, so a
`java -jar` p2 director pointed at the app fails with `Operation not
permitted`. The smoke test therefore runs the director on a copy.

### Releasing a plug-in

Tagging a plug-in repository `vX.Y.Z` is how a version bump there becomes
visible here. Its *Release* workflow sends a `repository_dispatch` to this
repository, which builds the bundle against the new tip and opens a pull
request bumping that submodule's pin. Merging it and tagging the bundle stay
manual: the release workflow refuses to publish while a pin trails its branch,
so an automatic release racing an unmerged pin bump would fail by design.

The dispatch needs a repository secret `BUNDLE_DISPATCH_TOKEN` in each plug-in
repository, a fine-grained token with `Contents: write` on this one.
`GITHUB_TOKEN` cannot reach another repository.

### Watching upstream

`upstream.yml` runs monthly and reports how far `rodincore` and
`rodin-b-sharp-smt` trail the branches they are rebased onto, opening or
updating one issue per fork. Given the optional secret `SUBMODULE_ISSUE_TOKEN`,
a fine-grained token with `Issues: write` on the forks, the issue lands in the
fork; without it, here.

## Credits

The proving work is by **Ilya Shchepetkov** and **Pavel Ivanov** at
[ISP RAS](http://www.ispras.ru), published by Ilya Shchepetkov on GitHub in 2021
and unmaintained since. Those repositories have been transferred into this
organisation, so the original history is preserved here rather than in a
separate upstream: the work sits on the `ispras` branch of
[rodincore](https://github.com/eventb-rossi/rodincore/tree/ispras),
[rodin-b-sharp-smt](https://github.com/eventb-rossi/rodin-b-sharp-smt/tree/ispras)
and on `master` of
[POCleaner](https://github.com/eventb-rossi/POCleaner), with the author's own
release notes on the
[2021-07-09](https://github.com/eventb-rossi/rodincore/releases/tag/2021-07-09)
and
[2021-07-30](https://github.com/eventb-rossi/rodincore/releases/tag/2021-07-30)
tags. The `rossi` branches rebase that work onto current upstream.

Rodin itself is developed by [Systerel](https://github.com/systerel/RodinCore)
and the Event-B community; the SMT plug-in comes from the
[rodin-b-sharp](https://sourceforge.net/p/rodin-b-sharp/smt/) project on
SourceForge. Everything here is EPL.

ProB is by **Michael Leuschel** and the [STUPS group](https://prob.hhu.de/w/) at
HHU Düsseldorf, (C) 2000-2026, and is bundled unmodified under the EPL 1.0 from
their release update site. Its sources are at
[hhu-stups](https://github.com/hhu-stups), and the Prolog core's at
<https://stups.hhu-hosting.de/downloads/prob/source/>. One restriction of theirs
travels with it: ProB's nauty library for symmetry reduction may not be used for
applications with nontrivial military significance.
