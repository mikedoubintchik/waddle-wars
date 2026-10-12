# Waddle Wars iOS disk-capacity capability patch

Status: source patch only; no engine build, export, binary inspection, runtime
acceptance, privacy-mask change or store approval.

Pinned upstream: `a13da4feb8d8aefc283c3763d33a2f170a18d541` (Godot 4.7.1).
Patch: `godot-4.7.1-ios-disable-disk-capacity.patch`.

## Purpose and scope

Waddle's shipped scripts/native bridges do not call `get_space_left()` or enable
movie recording. iOS uses `OS_IOS -> OS_AppleEmbedded -> OS_Unix`;
`OS_AppleEmbedded::initialize_core()` delegates to Unix, whose default
resource/user/filesystem directory factories instantiate `DirAccessUnix`.
The sole located nonbinding capacity caller is `MovieWriter::begin()`.

This explicit opt-in template profile disables the unused capacity capability,
not ordinary directory access or a privacy declaration:

- New iOS SCons option `waddle_disable_disk_capacity=yes` defines
  `WADDLE_IOS_DISK_CAPACITY_DISABLED` and appends
  `.waddle_no_disk_capacity` to generated library/object/template ZIP names.
- Only when both `IOS_ENABLED` and that flag are defined, the Unix capacity
  getter reports an unsupported-operation error and returns `0`, already the
  upstream unavailable/error sentinel. It does not call `statvfs`.
- The method declaration, virtual slot, ClassDB binding, class layout and all
  directory/open/write/flush/rename/remove/mkdir behavior stay unchanged.
- MovieWriter omits its optional capacity preflight in this profile, rather
  than displaying the unsupported return as measured low disk space. Movie
  writes still use their ordinary error handling; no recording feature is
  enabled by this patch.
- Default `no` keeps upstream behavior. Other platforms remain unaffected.
  Rendering, timers, resource loaders, native bridges and export code are not
  modified. No API declarations or source files are deleted.

The getter's `0` is not measured available capacity. Future app/extension code
requiring capacity must reject this profile or implement a separately reviewed
feature/profile; do not treat `0` as enough space or restore a query silently.

## Apply requirements

Use a new isolated upstream checkout; do not mutate retained stock engine,
generated headers, installed templates, old candidates or receipts.

Before applying, require the exact commit above and these upstream SHA-256s:

| Upstream file | SHA-256 |
| --- | --- |
| `platform/ios/detect.py` | `e7fe9867344d77e92ff4b318fc820ad05c0d5c0799032542cb5c59bfb568e478` |
| `drivers/unix/dir_access_unix.cpp` | `07aeda127111457212a2b9cd859c246a901c2c6c60f89dcfc435125aea298598` |
| `servers/movie_writer/movie_writer.cpp` | `ab9b69b78f137adea4e3e24f5dec3d1c64d8beae2efa1d6c434474675259b005` |

From that isolated checkout, after checking its identity and unrelated changes:

```sh
git apply --check /absolute/waddle-wars/tools/release/engine_patches/godot-4.7.1-ios-disable-disk-capacity.patch
git apply /absolute/waddle-wars/tools/release/engine_patches/godot-4.7.1-ios-disable-disk-capacity.patch
```

The preparation task performed only the first, non-mutating applicability check
against the retained exact-commit source. It did not apply the patch there.

## Build and export integration requirements

Before building, record fresh free disk space and the isolated checkout's
allocation. Monitor headroom during the build; stop SCons gracefully if space
approaches 2 GiB free. Build only the launch-required ARM64 device Release slice
first, with no other slice concurrently. Keep the existing Xcode/SDK and
renderer/font/physics/thread/module options, record them, and use pinned SCons
4.11.1. Do not reduce real app features to fit. Signing and game export remain
separate actions, not part of the template build.

The additional option must be used on every included slice and target. Build
command shape (append the reviewed baseline build/toolchain options unchanged):

```sh
scons platform=ios target=template_release arch=arm64 simulator=no waddle_disable_disk_capacity=yes -j2
scons platform=ios target=template_debug arch=arm64 simulator=no waddle_disable_disk_capacity=yes -j2
scons platform=ios target=template_release arch=arm64 simulator=yes waddle_disable_disk_capacity=yes -j2
scons platform=ios target=template_debug arch=arm64 simulator=yes waddle_disable_disk_capacity=yes -j2
```

If the template advertises x86_64 simulator support, also build both targets with
`arch=x86_64 simulator=yes` and the same option. Do not mix stock and patched
slices or advertise architectures not actually present. After all required
libraries exist, the pinned bundle helper can be invoked with:

```sh
scons platform=ios target=template_release arch=arm64 simulator=no waddle_disable_disk_capacity=yes generate_bundle=yes -j2
```

With no other extra suffix, expected ZIP:
`bin/godot_ios_waddle_no_disk_capacity.zip`. The helper overwrites its own
`bin/ios_xcode` scratch directory, so run only in the isolated checkout. It can
omit a missing library without failing; independently require all advertised
device/simulator Debug/Release slices before accepting this ZIP.

Use the resulting immutable ZIP only through the prepared candidate's
`custom_template/release` (and `custom_template/debug` for debug exports).
The pinned Apple exporter supports these ZIP options. Existing Waddle
`native_release.prepare`/export defaults do not select this profile: candidate
settings and receipt/template hashing must explicitly bind it before export.
Do not replace the global stock `ios.zip` or modify canonical export presets.

Bind upstream commit, original/patched file hashes, patch hash, all build
options/defines, toolchain, template ZIP and every included library in retained
evidence. Existing stock-template receipts do not attest this custom profile.

## Acceptance still required

- Compile both branches/required slices and confirm actual iOS compile commands
  include the flag. A patch applicability check is not a compiler result.
- Verify each patched archive object/final app and all linked SDK/framework
  binaries for covered capacity entrypoints/selectors; do not infer whole-app
  absence from this source patch or one symbol search.
- Validate local save/settings atomic replacement, ghost reads/writes, audio
  discovery, menus/gameplay and the explicit unsupported getter behavior using
  isolated data. No real user save mutation is authorized here.
- Reconcile required-reason declarations only after the resulting template and
  final app verification. This patch deliberately leaves `E174.1`/`85F4.1`
  masks/manifests unchanged. File/timer reasons remain separate.
- Preserve Godot MIT notices and document this downstream capability difference.
  Apple review, other SDK use, privacy disclosures and device/store acceptance
  remain independent. This is not a claim that privacy is cleared.
