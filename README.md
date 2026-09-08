# Rodin Bundle (eventb-rossi)

A Rodin distribution built from the Rodin 3.10 platform plus two plug-ins that
came out of work at ISP RAS (parallel and faster automatic proving, and a
recovery tool for broken proof obligations), plus a bridge that lets the Rossi
language server talk to a running Rodin.

Windows, Linux and macOS (Intel and Apple Silicon) archives are published on the
[releases page](../../releases).

## What this adds to stock Rodin

**A `First Successful` tactic combinator.** Runs several tactics at once and
finishes as soon as one of them proves the goal, or when they have all failed.
With six provers at a one-second timeout, the worst case is one second instead
of six, and the usual case is a fraction of that.

**A `Default Interactive Tactic with SMT` profile.** Built on the combinator and
aimed at interactive proving: pressing the auto-prover button is bounded at
about a second. Since a single interactive proof involves many such presses,
this is the change the original author found most valuable in practice.

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
  Intel build and an Intel JVM.
- **The macOS build is not notarized.** After downloading, run
  `xattr -rc Rodin.app`.

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

`bundle/` holds the product definition and `updates/` the add-on update
site; everything builds in one Tycho reactor.

## Building

Requires JDK 21 and Maven 3.9+, and a `~/.m2/toolchains.xml` declaring a
`jdk`/`21` toolchain (see `rodincore/org.rodinp.releng/toolchains.xml`; note the
checked-in template still says 17).

```bash
git clone --recurse-submodules https://github.com/eventb-rossi/Rodin-Bundle
cd Rodin-Bundle
mvn -pl '!rodincore/org.rodinp.platform.repository' clean verify
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

The tag is `vX.Y.Z-YYMM`, where `X.Y.Z` is the Rodin version in the bundle and
`YYMM` the build month, following the scheme `eventB-Soton/Rodin-Bundles` uses.
The workflow rejects a tag whose version does not match `bundle/pom.xml`.

Each release carries the four product archives, the p2 update site as a zip, and
`SHA256SUMS`. To re-attach assets to an existing tag, run the *Release* workflow
manually with that tag as its input; every upload uses `--clobber`, so re-runs
replace rather than duplicate.

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
