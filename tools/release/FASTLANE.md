# Local Fastlane release entry points

Waddle adopts Chancey's separation of build, upload and promotion. This first
stage exposes the existing Godot release helpers through local lanes. It has
no upload, store metadata, promotion, Match, key generation, provisioning,
SDK installation or CI dispatch lane. Ruby is needed only for these entry
points; the game and normal Godot builds remain self-contained.

Fastlane is pinned to 2.236.1 in `Gemfile` and its resolved dependency lock.
Run from the repository root. Set these public process flags before Fastlane
starts so even lane discovery skips update checks, analytics and generated
documentation:

```sh
FASTLANE_OPT_OUT_USAGE=1 FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_SKIP_DOCS=1 \
  bundle exec fastlane lanes

FASTLANE_OPT_OUT_USAGE=1 FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_SKIP_DOCS=1 \
  bundle exec fastlane inspect
```

On a new authoring machine, use `bundle install` to install the locked tooling
before invoking lanes. No Apple or Google account credentials are needed for
lane discovery, inspection or preparation. Android export uses the existing
app-specific upload-signing receipt and Keychain helper documented in
[README.md](README.md), not Godot release-keystore environment credentials.
Never put secrets in a lane argument, Appfile, Gemfile or repository `.env` file.

## iOS: prepare, then build the same candidate

Choose an unused store build number and a new absolute destination outside the
checkout. Preparation snapshots runtime files, stamps version/build identity,
records source/prepared hashes, and refuses an existing destination. iOS requires
the real ten-character `team_id:`; no team or build number is inferred.

With the same three process flags as above:

```sh
bundle exec fastlane ios prepare \
  destination:/absolute/new/ios-candidate \
  version:1.0.0 build_number:UNUSED_NUMBER team_id:REALTEAMID

bundle exec fastlane ios build candidate:/absolute/new/ios-candidate
```

Build checks that the candidate's platform matches the selected lane, then
delegates to `build_native.py`. That helper validates the complete immutable
file set, exact Godot version, billing plugin receipt and signing prerequisites;
preserves sanitized import/export diagnostics; rejects Godot error output even
when the process exits zero; and refuses a repeat build. Optional `godot:` and
`android_sdk:` must be absolute paths. Failed candidates remain available for
inspection; prepare a fresh candidate rather than overwrite or retry in place.

iOS's output is an Xcode project. The separate
`build_ios_distribution.py archive` and `ipa` commands now bind the frozen
export, embedded profile, entitlements, exact existing public signer and artifact
hashes through independent offline gates. See [README.md](README.md) for their
explicit public inputs. They are not silently called by this build lane and
never upload or enable automatic provisioning. Signed local artifacts still
require device, purchase and store acceptance.

## Android: fresh safe upload-signing build

The default `android build` lane invokes only
`android_upload_signing.py build`. Supply a **new, absent destination** outside
the checkout; its parent must already exist. It is not a build of an earlier
`android prepare` snapshot. Existing candidates, sibling signing-launch receipts,
symlink paths, traversal and in-checkout destinations are refused before helper
dispatch. Failed attempts remain preserved; there is no retry, unsafe legacy
fallback or automatic key bootstrap.

All tool paths and version/build identity are required, public options:

```sh
bundle exec fastlane android build \
  candidate:/absolute/new/android-candidate \
  python:/absolute/installed/python \
  jdk:/absolute/installed/jdk \
  bundletool:/absolute/installed/bundletool.jar \
  godot:/absolute/installed/Godot \
  android_sdk:/absolute/installed/Android/sdk \
  version:1.0.0 build_number:UNUSED_NUMBER
```

Use the same opt-out/update/docs flags shown above. The specified Python launches
the signer in isolated mode (`-I`); arguments remain separate argv entries, not a
concatenated shell command. The three legacy
`GODOT_ANDROID_KEYSTORE_RELEASE_*` variables are overridden with empty values for
this child without reading their parent values. The signing launcher then
creates clean export/verification environments. The password remains in the
existing exact Waddle Keychain item and its jarsigner-only child environment;
Godot/Gradle receive no signing password. Locked/protected Keychain access fails
without prompting. No signing key, service account or certificate is selected
from lane arguments.

Allowed build options are exactly `candidate`, `python`, `jdk`, `bundletool`,
`godot`, `android_sdk`, `version`, and `build_number`. Secret, legacy or unknown
options fail without echoing their names/values. In particular, do not pass
`upload_certificate_sha256`, `templates`, passwords, key paths or bootstrap
flags to this lane. The exact public certificate pin comes from the existing
app-specific signing receipt; missing or changed signing state stops the helper.
This lane never calls the helper's `setup` mode or the older Godot-signed
`build_native.py` Android route.

Do not put secrets on the Fastlane command line even to test refusal: shell
history, process argv and verbose tooling can record input before lane validation.

The authoritative launcher prepares/imports/exports unsigned, retains the
unsigned AAB, signs via its pinned app-specific helper, and runs mandatory
offline signature/identity/payload/16-KB verification. Success still means
`android_upload_artifact_verified_offline` with `store_ready:false`, not Play
registration, device/billing acceptance, independent key recovery or release.

`android prepare` remains available for **snapshot inspection only**:

```sh
bundle exec fastlane android prepare \
  destination:/absolute/new/android-snapshot-only \
  version:1.0.0 build_number:UNUSED_NUMBER \
  templates:/absolute/Godot/export_templates/4.7.1.stable
```

Do not pass that existing snapshot destination to `android build`. The safe
build creates its own snapshot from current runtime source into a fresh
destination, then owns the full unsigned-export/sign/verify receipt chain.

## Verify existing artifacts and profiles

Verification reads the supplied artifact/profile. It does not install profiles,
import certificates, change trust, use private keys, rebuild or upload anything.

```sh
bundle exec fastlane android verify_artifact \
  artifact:/absolute/android-candidate/project/build/waddle-wars.aab \
  bundletool:/absolute/tools/bundletool.jar

bundle exec fastlane android verify_release \
  artifact:/absolute/android-candidate/project/build/waddle-wars.aab \
  artifact_sha256:EXACT_RECORDED_AAB_SHA256 \
  upload_certificate_sha256:EXACT_PUBLIC_UPLOAD_CERTIFICATE_SHA256 \
  version:1.0.0 build_number:EXACT_BUILD_NUMBER \
  bundletool:/absolute/tools/bundletool.jar jdk:/absolute/installed/jdk

bundle exec fastlane ios verify_profile \
  profile:/absolute/Waddle_Wars_App_Store.mobileprovision \
  cms_helper:/absolute/compiled/verify_ios_profile_cms \
  cms_helper_sha256:EXACT_HELPER_SHA256 \
  team_id:REALTEAMID certificate_sha1:EXACT_DISTRIBUTION_CERTIFICATE_SHA1 \
  "profile_name:Waddle Wars App Store"
```

For an APK, use `zipalign:/absolute/SDK/build-tools/36.1.0/zipalign` instead of
`bundletool:`. The Android checker remains a structural check, and the iOS helper
retains its offline revocation limitation. All underlying receipts still say
`store_ready: false`. A nonzero helper status fails the lane.

`android verify_release` is the separate strict offline AAB gate. It accepts an
explicit public certificate pin for independent verification, not a password or
key. It does not establish Play registration or app-signing identity.

## Validation and later release stages

`test_fastlane_android.py` evaluates the actual Fastfile with a mock Ruby DSL and
captures variadic command/environment arguments. It covers the safe build route,
required public options, stale/symlink/traversal destination refusal, secret and
legacy option refusal, helper failure without fallback/bootstrap, and retained
iOS/verification lanes. No helper, Godot, JDK, Keychain, device or network action
runs in these tests:

```sh
python3 -m unittest discover -s tools/release -p 'test_fastlane_android.py' -v
```

Ruby is required for this focused coverage; a missing Ruby produces an explicit
skip, not a signing or launch pass. Actual offline lane discovery uses the
installed pinned Fastlane dependencies and likewise invokes no build lane.

October 1 local validation passed Ruby syntax for Fastfile/Appfile/Gemfile,
offline dependency resolution and `bundle check`, actual seven-lane discovery,
read-only inventory, and the existing approved profile's signature/metadata
verification. Six negative invocations passed: missing version, relative
destination, invalid version, wrong-platform candidate, repeat build and changed
CMS-helper hash. Rejected preparation created no destination, every helper
failure propagated as a nonzero lane exit, and failures triggered no GitHub
issue search. Failure handling keeps the helper output visible and reports its
exit status as a local launch gate.

These checks did not run Godot, build/sign a new native candidate, start remote
CI or establish store readiness. Existing Python release-tool regressions
remain authoritative for snapshot integrity and export diagnostics. Successful
prepare/build invocation still needs the next coordinated native build window;
actual archive/IPA and device acceptance remain separate gates.

Add upload and promotion only after the remaining launch gates pass, with
explicit artifact hashes, exact version/build selection and receipt-backed
store identity. Promotion must select the tested uploaded build without a
rebuild. Keep automatic upload/promotion out of build lanes. Account-specific
credentials and Chancey's native project settings are not copied.
