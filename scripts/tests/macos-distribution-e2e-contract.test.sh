#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/scripts/run-macos-distribution-e2e.sh"
FINDER_STATE="$ROOT/scripts/macos-finder-extraction-state.sh"
FINDER_STATE_TEST="$ROOT/scripts/tests/macos-finder-extraction-state.test.sh"
PREPARER="$ROOT/scripts/prepare-remote-e2e-stage.sh"
WORKFLOW="$ROOT/.github/workflows/voiceink-remote-e2e-stage.yml"
BUILD_WORKFLOW="$ROOT/.github/workflows/voiceink-build.yml"
RUNTIME_RUNNER="$ROOT/scripts/run-macos-runtime-e2e.sh"
RUNTIME_PREFLIGHT="$ROOT/Tools/RuntimeE2EHarness/Sources/RuntimeE2EHarness/RuntimePreflight.swift"
RENDERED_OBSERVER="$ROOT/Tools/RuntimeE2EHarness/Sources/RuntimeE2EHarness/RuntimeRenderedTextObserver.swift"
VOICEINK_SESSION="$ROOT/Tools/RuntimeE2EHarness/Sources/RuntimeE2EHarness/RuntimeVoiceInkSession.swift"
HANDOFF_HELPER="$ROOT/scripts/macos-distribution-runtime-handoff.sh"
HANDOFF_TEST="$ROOT/scripts/tests/macos-distribution-runtime-handoff.test.sh"
EMPTY_FINAL_VERIFIER="$ROOT/scripts/verify-runtime-empty-final-regression.sh"
EMPTY_FINAL_VERIFIER_TEST="$ROOT/scripts/tests/verify-runtime-empty-final-regression.test.sh"
APFS_OWNER_VERIFIER="$ROOT/scripts/macos-apfs-volume-owner.sh"
APFS_OWNER_VERIFIER_TEST="$ROOT/scripts/tests/macos-apfs-volume-owner.test.sh"
OPERATOR_CLEANER="$ROOT/scripts/cleanup-macos-gatekeeper-operator.sh"
OPERATOR_CLEANER_TEST="$ROOT/scripts/tests/cleanup-macos-gatekeeper-operator.test.sh"

require_text() {
  local file="$1"
  local text="$2"
  if ! grep -Fq -- "$text" "$file"; then
    echo "missing distribution E2E contract in $file: $text" >&2
    exit 1
  fi
}

reject_text() {
  local file="$1"
  local pattern="$2"
  if grep -Eq -- "$pattern" "$file"; then
    echo "forbidden distribution E2E shortcut in $file: $pattern" >&2
    exit 1
  fi
}

eval "$(sed -n '/^version_is_at_least()/,/^}/p' "$RUNNER")"
version_is_at_least 26.3.1 14.4
version_is_at_least 14.4 14.4
version_is_at_least 14.4.1 14.4
if version_is_at_least 14.2.1 14.4; then
  echo "macOS 14.2.1 must not satisfy a 14.4 minimum" >&2
  exit 1
fi
if version_is_at_least 14.4 14.4.1; then
  echo "macOS 14.4 must not satisfy a 14.4.1 minimum" >&2
  exit 1
fi

test -x "$RUNNER"
test -x "$FINDER_STATE"
test -x "$FINDER_STATE_TEST"
test -x "$ROOT/scripts/verify-macos-distribution-launch.sh"
test -x "$HANDOFF_TEST"
test -x "$EMPTY_FINAL_VERIFIER"
test -x "$EMPTY_FINAL_VERIFIER_TEST"
test -x "$APFS_OWNER_VERIFIER"
test -x "$APFS_OWNER_VERIFIER_TEST"
test -x "$OPERATOR_CLEANER"
test -x "$OPERATOR_CLEANER_TEST"
bash "$APFS_OWNER_VERIFIER_TEST"
bash "$OPERATOR_CLEANER_TEST"

EMPTY_FINAL_POLICY_ROOT="$(
  mktemp -d "${TMPDIR:-/tmp}/roma-empty-final-policy.XXXXXX"
)"
EMPTY_FINAL_POLICY_OUTPUT="$EMPTY_FINAL_POLICY_ROOT/output.txt"
trap 'rm -rf "$EMPTY_FINAL_POLICY_ROOT"' EXIT
for transcription_expectation in known-bad fixed; do
  if DISTRIBUTION_E2E_EXPECTATION=fixed-after-framework-signature \
    DISTRIBUTION_E2E_EXPECTED_REJECTED_FRAMEWORK=whisper \
    DISTRIBUTION_E2E_EXPECTED_MAIN_UUID=DD61BD03-E85F-3824-9A93-5386BCE534B2 \
    DISTRIBUTION_E2E_EXPECTED_REJECTED_FRAMEWORK_UUID=73A2EE0D-7421-3340-95D9-48D385E4747B \
    RUNTIME_E2E_EMPTY_FINAL_EXPECTATION="$transcription_expectation" \
    bash "$PREPARER" macos 30 /nonexistent/inputs /nonexistent/stage none \
      distribution-e2e "" 5 26.4.1 25E253 > "$EMPTY_FINAL_POLICY_OUTPUT" 2>&1; then
    echo "Framework-signature proof accepted a separate transcription expectation" >&2
    exit 1
  fi
  grep -Fq 'Paired framework-signature proof requires normal passing runtime smoke' \
    "$EMPTY_FINAL_POLICY_OUTPUT"
done

if RUNTIME_E2E_EMPTY_FINAL_EXPECTATION=known-bad \
  RUNTIME_E2E_MODEL_CACHE_PATH=/tmp/forbidden-roma-model-cache \
  bash "$RUNTIME_RUNNER" \
    /nonexistent/roma.app \
    "" \
    /nonexistent/evidence \
    5 \
    smoke \
    >"$EMPTY_FINAL_POLICY_OUTPUT" 2>&1; then
  echo "Empty-final proof accepted an external model cache" >&2
  exit 1
fi
if ! grep -Fq \
  "Empty-final regression proof must use the normal FluidAudio model directory" \
  "$EMPTY_FINAL_POLICY_OUTPUT"; then
  echo "Empty-final model-cache rejection happened after an unrelated preflight failure" >&2
  cat "$EMPTY_FINAL_POLICY_OUTPUT" >&2
  exit 1
fi

EMPTY_FINAL_FAKE_HOME="$EMPTY_FINAL_POLICY_ROOT/home"
EMPTY_FINAL_FAKE_CACHE="$EMPTY_FINAL_POLICY_ROOT/cache/parakeet-tdt-0.6b-v2"
mkdir -p \
  "$EMPTY_FINAL_FAKE_HOME/Library/Application Support/FluidAudio/Models" \
  "$EMPTY_FINAL_FAKE_CACHE"
ln -s \
  "$EMPTY_FINAL_FAKE_CACHE" \
  "$EMPTY_FINAL_FAKE_HOME/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2"
if HOME="$EMPTY_FINAL_FAKE_HOME" \
  RUNTIME_E2E_EMPTY_FINAL_EXPECTATION=known-bad \
  RUNTIME_E2E_MODEL_CACHE_PATH= \
  bash "$RUNTIME_RUNNER" \
    /nonexistent/roma.app \
    "" \
    /nonexistent/evidence \
    5 \
    smoke \
    >"$EMPTY_FINAL_POLICY_OUTPUT" 2>&1; then
  echo "Empty-final proof accepted a symlinked model directory" >&2
  exit 1
fi
if ! grep -Fq \
  "Empty-final regression proof requires non-symlinked FluidAudio model storage" \
  "$EMPTY_FINAL_POLICY_OUTPUT"; then
  echo "Empty-final model symlink rejection happened after an unrelated preflight failure" >&2
  cat "$EMPTY_FINAL_POLICY_OUTPUT" >&2
  exit 1
fi

if HOME="$EMPTY_FINAL_POLICY_ROOT/clean-home" \
  RUNTIME_E2E_EMPTY_FINAL_EXPECTATION=fixed \
  RUNTIME_E2E_MODEL_CACHE_PATH= \
  bash "$RUNTIME_RUNNER" \
    /nonexistent/roma.app \
    "" \
    /nonexistent/evidence \
    5 \
    smoke \
    >"$EMPTY_FINAL_POLICY_OUTPUT" 2>&1; then
  echo "Fixed proof accepted a missing known-bad baseline" >&2
  exit 1
fi
if ! grep -Fq \
  "Fixed empty-final proof requires known-bad baseline evidence" \
  "$EMPTY_FINAL_POLICY_OUTPUT"; then
  echo "Fixed baseline rejection happened after an unrelated preflight failure" >&2
  cat "$EMPTY_FINAL_POLICY_OUTPUT" >&2
  exit 1
fi

eval "$(sed -n '/^write_empty_final_process_events()/,/^}/p' "$RUNTIME_RUNNER")"
runtime_launch_events="$EMPTY_FINAL_POLICY_ROOT/raw-launches.tsv"
runtime_termination_events="$EMPTY_FINAL_POLICY_ROOT/raw-terminations.tsv"
empty_final_launch_events="$EMPTY_FINAL_POLICY_ROOT/filtered-launches.tsv"
empty_final_termination_events="$EMPTY_FINAL_POLICY_ROOT/filtered-terminations.tsv"
empty_final_expectation=known-bad
prewarm_pid=900
printf '%s\n' \
  $'2026-09-04T10:00:00Z\t900\ta\ta\t/source\t/running' \
  $'2026-09-04T10:01:00Z\t901\tb\tb\t/source\t/running' \
  > "$runtime_launch_events"
printf '%s\n' \
  $'2026-09-04T10:00:30Z\t900' \
  $'2026-09-04T10:01:30Z\t901' \
  > "$runtime_termination_events"
write_empty_final_process_events
if [ "$(awk -F '\t' '{ print $2 }' "$empty_final_launch_events")" != 901 ] \
  || [ "$(awk -F '\t' '{ print $2 }' "$empty_final_termination_events")" != 901 ]; then
  echo "Empty-final lifecycle evidence did not exclude the model-prewarm process" >&2
  exit 1
fi

require_text "$WORKFLOW" 'distribution-e2e'
require_text "$WORKFLOW" 'macos_expected_version'
require_text "$WORKFLOW" 'macos_expected_build'
require_text "$WORKFLOW" 'macos_distribution_expectation'
require_text "$WORKFLOW" 'macos_expected_rejected_framework'
require_text "$WORKFLOW" 'macos_expected_main_uuid'
require_text "$WORKFLOW" 'macos_expected_rejected_framework_uuid'
require_text "$WORKFLOW" 'known-bad-framework-signature'
require_text "$WORKFLOW" 'fixed-after-framework-signature'
require_text "$WORKFLOW" 'macos_framework_signature_baseline_run_id'
require_text "$WORKFLOW" 'STAGE_MACOS_FRAMEWORK_SIGNATURE_BASELINE_RUN_ID'
require_text "$WORKFLOW" 'STAGE_MACOS_DISTRIBUTION_EXPECTATION: ${{ inputs.macos_distribution_expectation || '\''fixed'\'' }}'
require_text "$WORKFLOW" 'developer_dir'
require_text "$WORKFLOW" 'macos_empty_final_expectation:'
require_text "$WORKFLOW" 'macos_empty_final_baseline_run_id:'
require_text "$WORKFLOW" 'STAGE_MACOS_EMPTY_FINAL_EXPECTATION: ${{ inputs.macos_empty_final_expectation || '\''none'\'' }}'
require_text "$WORKFLOW" 'Download matched known-bad empty-final evidence'
require_text "$WORKFLOW" 'baseline-reverification.txt'
require_text "$WORKFLOW" 'empty-final-launch-events.tsv'
require_text "$WORKFLOW" 'empty-final-termination-events.tsv'
require_text "$WORKFLOW" '- "scripts/run-macos-distribution-e2e.sh"'
require_text "$WORKFLOW" '- "scripts/verify-runtime-empty-final-regression.sh"'
require_text "$WORKFLOW" '- "scripts/tests/verify-runtime-empty-final-regression.test.sh"'
require_text "$WORKFLOW" '- "scripts/macos-finder-extraction-state.sh"'
require_text "$WORKFLOW" '- "scripts/macos-bundle-manifest.sh"'
require_text "$WORKFLOW" '- "scripts/verify-macos-distribution-launch.sh"'
require_text "$WORKFLOW" '- "scripts/verify-macos-framework-signature-crash.sh"'
require_text "$WORKFLOW" '- "scripts/tests/macos-distribution-e2e-contract.test.sh"'
require_text "$WORKFLOW" '- "scripts/tests/macos-distribution-runtime-handoff.test.sh"'
require_text "$WORKFLOW" '- "scripts/macos-distribution-runtime-handoff.sh"'
require_text "$WORKFLOW" 'bash scripts/tests/macos-distribution-runtime-handoff.test.sh'
require_text "$WORKFLOW" '- "scripts/tests/macos-finder-extraction-state.test.sh"'
require_text "$WORKFLOW" 'bash scripts/tests/macos-finder-extraction-state.test.sh'
require_text "$WORKFLOW" 'bash scripts/tests/verify-macos-framework-signature-crash.test.sh'
require_text "$WORKFLOW" '- "scripts/tests/verify-macos-distribution-launch.test.sh"'
require_text "$WORKFLOW" 'bash scripts/tests/verify-runtime-empty-final-regression.test.sh'
require_text "$WORKFLOW" 'roma.runtime-e2e-harness.macos'
require_text "$WORKFLOW" 'runtime_helper_run_id'
require_text "$WORKFLOW" 'runtime-helper-run-metadata.json'
require_text "$WORKFLOW" 'runtime-helper-artifact-metadata.json'
require_text "$WORKFLOW" 'runtime-helper-artifact-archive.zip'
require_text "$WORKFLOW" 'runtime-helper-artifact-archive.sha256'
require_text "$WORKFLOW" 'Runtime helper artifact must be checksum-verified'
require_text "$WORKFLOW" 'baseline-artifact-archive.zip'
require_text "$WORKFLOW" 'baseline-artifact-archive.sha256'
require_text "$WORKFLOW" 'Baseline evidence archive does not match its artifact digest'
require_text "$WORKFLOW" 'macos-app-run-metadata.json'
require_text "$WORKFLOW" 'macos-app-run-jobs.json'
require_text "$WORKFLOW" 'runtime-helper-run-jobs.json'
require_text "$WORKFLOW" 'macos-artifact-id.txt'
require_text "$WORKFLOW" 'macos-artifact-repository.txt'
require_text "$WORKFLOW" 'macos-artifact-metadata.json'
require_text "$WORKFLOW" 'select(.digest | test("^sha256:[0-9a-f]{64}$"))'
require_text "$WORKFLOW" 'GH_TOKEN: ${{ github.token }}'
require_text "$WORKFLOW" '.conclusion == "success"'
require_text "$WORKFLOW" '.head_repository.full_name == $repository'
require_text "$WORKFLOW" '(.event == "push" or .event == "workflow_dispatch")'
require_text "$WORKFLOW" '$GITHUB_SHA'
require_text "$WORKFLOW" 'nsc-runner-'
require_text "$WORKFLOW" 'namespace-profile-*|nscloud-macos-*'
require_text "$WORKFLOW" 'sysctl -n kern.boottime'
require_text "$WORKFLOW" 'sysctl -n kern.bootsessionuuid'
require_text "$WORKFLOW" "sed -E 's/^\\{ sec = ([0-9]+),.*/\\1/'"
require_text "$WORKFLOW" "startsWith(inputs.macos_runner, 'namespace-profile-')"
require_text "$WORKFLOW" "startsWith(inputs.macos_runner, 'nscloud-macos-')"
require_text "$WORKFLOW" 'provisioning-context.txt'
require_text "$WORKFLOW" 'Verify distribution E2E Gatekeeper administrator'
require_text "$WORKFLOW" 'Prepare distribution E2E Gatekeeper credential'
require_text "$WORKFLOW" 'STAGE_RUNNER_VERIFIED_FRESH=true'
require_text "$WORKFLOW" 'sudo -n -v'
require_text "$WORKFLOW" '/usr/sbin/sysadminctl'
require_text "$WORKFLOW" 'dseditgroup -o checkmember'
require_text "$WORKFLOW" 'dscl . -authonly'
require_text "$WORKFLOW" '/usr/bin/expect -c'
require_text "$WORKFLOW" 'log_user 0'
require_text "$WORKFLOW" 'auth_prompt_count != 1'
require_text "$WORKFLOW" 'OPERATOR_USERNAME="runner"'
require_text "$WORKFLOW" 'account_generated_uid=%s'
require_text "$WORKFLOW" 'NAMESPACE_RUNNER_PASSWORD: ${{ secrets.NAMESPACE_MACOS_RUNNER_PASSWORD }}'
require_text "$WORKFLOW" 'ROMA_OPERATOR_PASSWORD_FILE="$OPERATOR_PASSWORD_FILE"'
require_text "$WORKFLOW" 'unset NAMESPACE_RUNNER_PASSWORD'
require_text "$WORKFLOW" 'stat -f '\''%Su'\'' /dev/console'
require_text "$WORKFLOW" '-secureTokenStatus "$OPERATOR_USERNAME"'
require_text "$WORKFLOW" 'Secure token is ENABLED'
require_text "$WORKFLOW" 'diskutil apfs listUsers /'
require_text "$WORKFLOW" 'scripts/macos-apfs-volume-owner.sh'
require_text "$WORKFLOW" 'chmod 600 "$OPERATOR_PASSWORD_FILE" "$OPERATOR_CREDENTIAL_FILE"'
require_text "$WORKFLOW" 'refusing to overwrite a Gatekeeper credential target'
require_text "$WORKFLOW" 'sudo -n /bin/test -L "$isolated_target"'
require_text "$WORKFLOW" 'distribution-operator-setup.txt'
require_text "$WORKFLOW" 'DISTRIBUTION_E2E_EXPECTATION: ${{ env.STAGE_MACOS_DISTRIBUTION_EXPECTATION }}'
require_text "$WORKFLOW" 'Download matched known-bad framework-signature evidence'
require_text "$WORKFLOW" '.name == "remote-e2e-stage-evidence" and .expired == false'
require_text "$WORKFLOW" 'select(length == 1)'
require_text "$WORKFLOW" 'Framework-signature baseline archive does not match its artifact digest'
require_text "$WORKFLOW" '.head_sha == $head_sha'
require_text "$WORKFLOW" '.githubRepository == $repository'
require_text "$WORKFLOW" '.githubWorkflowPath == $workflow_path'
require_text "$WORKFLOW" 'approval-window-dyld-report.ips'
require_text "$WORKFLOW" 'approval-window-dyld-match.txt'
require_text "$WORKFLOW" 'approval-window-started-at.txt'
require_text "$WORKFLOW" 'approval-window-dyld-pid-correlation.txt'
require_text "$WORKFLOW" 'expected-negative-control-identities.txt'
require_text "$WORKFLOW" 'source-artifact.txt'
require_text "$WORKFLOW" 'DISTRIBUTION_E2E_FRAMEWORK_SIGNATURE_BASELINE_EVIDENCE'
require_text "$WORKFLOW" 'Remove distribution E2E credential file'
require_text "$WORKFLOW" "if: always() && env.STAGE_MACOS_SCENARIO == 'distribution-e2e'"
require_text "$WORKFLOW" 'scripts/cleanup-macos-gatekeeper-operator.sh'
reject_text "$WORKFLOW" 'test-unprivileged'
require_text "$WORKFLOW" '$RUNNER_TEMP/roma-runtime-e2e-cold-model-cache'
require_text "$WORKFLOW" 'test ! -e "$COLD_CACHE"'
require_text "$WORKFLOW" 'test ! -L "$COLD_CACHE"'
require_text "$WORKFLOW" 'cold_model_cache_preexisting=true'
require_text "$WORKFLOW" 'cold_model_cache_preexisting=false'
require_text "$WORKFLOW" 'RUNTIME_E2E_MODEL_CACHE_PATH=$COLD_CACHE'
cache_exclusion_count="$(
  grep -Fc "env.STAGE_MACOS_SCENARIO != 'distribution-e2e'" "$WORKFLOW"
)"
if [ "$cache_exclusion_count" -ne 2 ]; then
  echo "distribution E2E must skip both persistent and cold runtime model caches" >&2
  exit 1
fi
empty_final_cache_exclusion_count="$(
  grep -Fc "env.STAGE_MACOS_EMPTY_FINAL_EXPECTATION == 'none'" "$WORKFLOW"
)"
if [ "$empty_final_cache_exclusion_count" -ne 2 ]; then
  echo "Empty-final proof must skip both runtime model caches" >&2
  exit 1
fi
require_text "$BUILD_WORKFLOW" 'roma.runtime-e2e-harness.macos'
require_text "$BUILD_WORKFLOW" 'bash scripts/tests/macos-distribution-runtime-handoff.test.sh'
require_text "$BUILD_WORKFLOW" 'bash scripts/tests/macos-finder-extraction-state.test.sh'
require_text "$BUILD_WORKFLOW" '- "scripts/verify-runtime-empty-final-regression.sh"'
require_text "$BUILD_WORKFLOW" '- "scripts/tests/verify-runtime-empty-final-regression.test.sh"'
require_text "$BUILD_WORKFLOW" 'bash scripts/tests/verify-runtime-empty-final-regression.test.sh'
require_text "$BUILD_WORKFLOW" 'bash scripts/tests/verify-macos-framework-signature-crash.test.sh'
require_text "$ROOT/Makefile" 'bash scripts/tests/verify-runtime-empty-final-regression.test.sh'
require_text "$ROOT/Makefile" 'bash scripts/tests/verify-macos-framework-signature-crash.test.sh'

require_text "$PREPARER" 'none|runtime-smoke|runtime-e2e|distribution-e2e'
require_text "$PREPARER" 'requires distribution-e2e'
require_text "$PREPARER" 'fixed-after-framework-signature'
require_text "$PREPARER" 'Paired framework-signature proof requires downloaded known-bad baseline evidence'
require_text "$PREPARER" 'Framework-signature baseline evidence is only valid for paired fixed proof'
require_text "$PREPARER" 'paired-framework-signature-proof.json'
require_text "$PREPARER" 'Paired framework-signature proof requires distinct baseline and candidate app artifacts'
require_text "$PREPARER" 'DISTRIBUTION_E2E_EXPECTATION="$low_level_distribution_expectation"'
require_text "$PREPARER" 'low_level_distribution_expectation="fixed"'
require_text "$PREPARER" 'passed_after_framework_signature_baseline'
require_text "$PREPARER" 'framework-signature-pair-verdict.txt'
require_text "$PREPARER" 'candidate_launch_and_runtime_smoke=passed'
require_text "$PREPARER" 'macOSFrameworkSignatureBaselineRunId'
require_text "$PREPARER" 'macOSFrameworkSignaturePairVerdict'
require_text "$PREPARER" 'githubRepository'
require_text "$PREPARER" 'githubWorkflowPath'
require_text "$PREPARER" 'distribution-expected-terminal-failure.txt'
require_text "$PREPARER" 'expected_framework_signature_failure_reproduced'
require_text "$PREPARER" 'macOSDistributionExpectation'
require_text "$PREPARER" 'macOSExpectedRejectedFramework'
require_text "$PREPARER" 'macOSExpectedMainUUID'
require_text "$PREPARER" 'macOSExpectedRejectedFrameworkUUID'
require_text "$PREPARER" 'macOSDistributionVerdict'
require_text "$PREPARER" 'run-macos-distribution-e2e.sh'
require_text "$PREPARER" 'run-macos-runtime-e2e.sh'
require_text "$PREPARER" 'app="/Applications/roma just talk.app"'
require_text "$PREPARER" '/usr/bin/xattr -dr com.apple.quarantine "/Applications/roma just talk.app"'
require_text "$PREPARER" '&& /usr/bin/open "/Applications/roma just talk.app"'
require_text "$PREPARER" 'landing-quarantine-fallback.txt'
require_text "$PREPARER" 'unrelated_nested_xattr_after=true'
require_text "$PREPARER" 'application_finished_launching=true'
require_text "$PREPARER" "' 2>/dev/null | grep -Fx true; then"
require_text "$PREPARER" 'macos_expected_version'
require_text "$PREPARER" 'runtime-helper/roma.runtime-e2e-harness.macos.zip'
require_text "$PREPARER" 'runtime-helper-run-metadata.json'
require_text "$PREPARER" 'runtime-helper-artifact-metadata.json'
require_text "$PREPARER" 'runtimeHelperArtifactId'
require_text "$PREPARER" 'runtimeHelperArtifactDigest'
require_text "$PREPARER" 'paired-app-identity.json'
require_text "$PREPARER" 'Paired empty-final proof requires distinct baseline and candidate app artifacts'
require_text "$PREPARER" 'baseline_app_artifact_metadata'
require_text "$PREPARER" 'baseline_app_run_metadata'
require_text "$PREPARER" 'macOSArtifactDigest'
require_text "$PREPARER" 'macos-app-run-jobs.json'
require_text "$PREPARER" 'runtime-helper-run-jobs.json'
require_text "$PREPARER" 'runtime-helper-archive-sha256.txt'
require_text "$PREPARER" 'runtimeHelperRunId'
require_text "$PREPARER" 'runtimeHelperHeadSha'
require_text "$PREPARER" 'distribution_bundle_manifest_sha256'
require_text "$PREPARER" 'runtime_bundle_after_sha256'
require_text "$PREPARER" 'stage_runner_boot_age_seconds_at_job_start'
require_text "$PREPARER" 'if [ "$macos_artifact_runner_name" = "$runtime_helper_runner_name" ]; then'
require_text "$PREPARER" 'MACOS_ARTIFACT_ID="$macos_artifact_id"'
require_text "$PREPARER" 'MACOS_ARTIFACT_REPOSITORY="$macos_artifact_repository"'
require_text "$PREPARER" 'MACOS_ARTIFACT_DIGEST="$macos_artifact_digest"'
require_text "$PREPARER" 'github_download_token="${GH_TOKEN:-}"'
require_text "$PREPARER" 'unset GH_TOKEN'
require_text "$PREPARER" '|| [ "$runtime_empty_final_expectation" != "none" ]; then'
require_text "$PREPARER" 'runtime_model_cache_path=""'
require_text "$PREPARER" 'runtime_model_source=first_launch_live_directory'
require_text "$PREPARER" 'RUNTIME_E2E_EXPECTED_FIRST_LAUNCH_PID="$distribution_launched_pid"'
require_text "$PREPARER" 'runtime_empty_final_expectation="${RUNTIME_E2E_EMPTY_FINAL_EXPECTATION:-none}"'
require_text "$PREPARER" 'RUNTIME_E2E_EMPTY_FINAL_EXPECTATION="$runtime_empty_final_expectation"'
require_text "$PREPARER" 'RUNTIME_E2E_EMPTY_FINAL_BASELINE_EVIDENCE="$runtime_empty_final_baseline_evidence"'
require_text "$PREPARER" '"macOSEmptyFinalExpectation": "$runtime_empty_final_expectation"'
require_text "$PREPARER" '"macOSEmptyFinalBaselineRunId": "$runtime_empty_final_baseline_run_id"'
require_text "$PREPARER" 'empty-final-launch-events.tsv'
require_text "$PREPARER" 'empty-final-termination-events.tsv'

require_text "$RUNTIME_RUNNER" 'prebuilt_helper_archive'
require_text "$RUNTIME_RUNNER" 'RUNTIME_E2E_APP="$helper_app"'
require_text "$RUNTIME_RUNNER" 'helper-host-loadability.txt'
require_text "$RUNTIME_RUNNER" 'helper-host-launch.exit-code.txt'
require_text "$RUNTIME_RUNNER" 'RuntimeE2EHarness" --help'
require_text "$ROOT/Tools/RuntimeE2EHarness/Info.plist" '<string>14.0</string>'
require_text "$RENDERED_OBSERVER" 'contentFilter: filter'
require_text "$RENDERED_OBSERVER" 'configuration: configuration'
reject_text "$RUNTIME_PREFLIGHT" 'macOS 15\.2 or newer'
require_text "$RUNTIME_RUNNER" 'runtime-translocation-new-crash-reports.txt'
require_text "$RUNTIME_RUNNER" 'runtime-translocation-termination-events.tsv'
require_text "$RUNTIME_RUNNER" 'DISTRIBUTION_E2E_CAPTURE_MAPPED_CODE_UNTIL_EXIT=true'
require_text "$VOICEINK_SESSION" 'RUNTIME_E2E_VOICEINK_TERMINATION_EVENTS'
require_text "$RUNTIME_RUNNER" 'source "$repo_root/scripts/macos-distribution-runtime-handoff.sh"'
require_text "$RUNTIME_RUNNER" 'distribution_runtime_validate_handoff'
require_text "$RUNTIME_RUNNER" 'distribution-runtime-handoff.txt'
require_text "$RUNTIME_RUNNER" 'first_launch_termination=normal'
require_text "$RUNTIME_RUNNER" 'empty_final_expectation="${RUNTIME_E2E_EMPTY_FINAL_EXPECTATION:-none}"'
require_text "$RUNTIME_RUNNER" 'runtime-empty-final-regression-verdict.txt'
require_text "$RUNTIME_RUNNER" 'verify-runtime-empty-final-regression.sh'
require_text "$RUNTIME_RUNNER" 'empty-final-e2e-contract.json'
require_text "$RUNTIME_RUNNER" 'paired-known-bad-reverification.txt'
require_text "$RUNTIME_RUNNER" 'write_empty_final_process_events'
require_text "$RUNTIME_RUNNER" 'empty-final-launch-events.tsv'
require_text "$RUNTIME_RUNNER" 'empty-final-termination-events.tsv'
require_text "$RUNTIME_RUNNER" 'empty_final_verifier_arguments+=("$baseline_report" "$baseline_contract")'
require_text "$RUNTIME_RUNNER" 'Paired empty-final proof requires different baseline and candidate app executables'
require_text "$HANDOFF_HELPER" 'requires only the verified first-launch PID'
require_text "$HANDOFF_HELPER" 'must not use an external model cache'
require_text "$HANDOFF_HELPER" 'did not create the live model directory'

distribution_termination_line="$(
  grep -n '^  terminate_runtime_voiceink_pid "$expected_first_launch_pid"' \
    "$RUNTIME_RUNNER" \
    | head -n 1 \
    | cut -d: -f1
)"
model_prepare_line="$(
  grep -n '^runtime_prepare_pinned_model \\' "$RUNTIME_RUNNER" \
    | head -n 1 \
    | cut -d: -f1
)"
if [ -z "$distribution_termination_line" ] \
  || [ -z "$model_prepare_line" ] \
  || [ "$distribution_termination_line" -ge "$model_prepare_line" ]; then
  echo "distribution E2E must stop first launch before model hydration" >&2
  exit 1
fi

require_text "$RUNNER" 'com.apple.quarantine'
require_text "$RUNNER" 'Safari'
require_text "$RUNNER" 'Finder'
require_text "$RUNNER" 'Double-click the app in Finder.'
require_text "$RUNNER" 'open -R "$extracted_app"'
require_text "$RUNNER" 'gatekeeper-finder-reveal-exit-code.txt'
require_text "$RUNNER" 'APFS'
require_text "$RUNNER" 'AppTranslocation'
require_text "$RUNNER" 'DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=true'
require_text "$RUNNER" 'DISTRIBUTION_E2E_REQUIRE_APPKIT_FINISHED=true'
require_text "$RUNNER" 'verify-macos-distribution-launch.sh'
require_text "$RUNNER" 'macos-bundle-manifest.sh'
require_text "$RUNNER" 'GATEKEEPER ACTION REQUIRED'
require_text "$RUNNER" 'Confirm Finder Extraction Complete.command'
require_text "$RUNNER" 'Confirm Finder Follow-up Extraction.command'
require_text "$RUNNER" '/bin/date -u +%Y-%m-%dT%H:%M:%SZ > "$confirmation_path"'
require_text "$RUNNER" 'archive-utility-recursive'
require_text "$RUNNER" 'finder-extraction-mode.txt'
require_text "$RUNNER" 'expected-inner-app-files.sha256'
require_text "$RUNNER" 'compare_macos_bundle_to_manifest'
require_text "$RUNNER" 'Finder-extracted app does not match the hash-verified inner ZIP'
require_text "$RUNNER" 'macos-finder-extraction-state.sh'
require_text "$RUNNER" 'ditto -x -k "$expected_inner_archive" "$reference_root"'
require_text "$RUNNER" 'Confirm Gatekeeper Not Opened.command'
require_text "$RUNNER" 'Confirm Roma First Launch Ready.command'
require_text "$RUNNER" 'finder-archive-utility-unified-log.txt'
require_text "$RUNNER" 'extracted-app-compatibility.txt'
require_text "$RUNNER" 'app requires macOS'
require_text "$RUNNER" 'approval-window-process-events.txt'
require_text "$RUNNER" 'approval-window-new-crash-reports.txt'
require_text "$RUNNER" 'approval-window-unified-log.txt'
require_text "$RUNNER" 'fresh-tcc-user.txt'
require_text "$RUNNER" 'fresh-tcc-system.txt'
require_text "$RUNNER" 'api.github.com/repos/$repository/actions/artifacts/$artifact_id/zip'
require_text "$RUNNER" 'Authorization: Bearer $github_download_token'
require_text "$RUNNER" 'browser-download-origin.txt'
require_text "$RUNNER" 'open location artifactURL'
require_text "$RUNNER" 'wait_for_matching_browser_download'
require_text "$RUNNER" 'downloaded GitHub Actions archive does not match its artifact digest'
require_text "$RUNNER" 'unset GH_TOKEN'
require_text "$RUNNER" 'approved first launch did not create the live FluidAudio model directory'
require_text "$RUNNER" 'first-launch-live-model-state.txt'
require_text "$RUNNER" 'live_model_state=created_by_verified_first_launch'
require_text "$RUNNER" 'DISTRIBUTION_E2E_EXPECTATION'
require_text "$RUNNER" 'DISTRIBUTION_E2E_EXPECTED_REJECTED_FRAMEWORK'
require_text "$RUNNER" 'known-bad-framework-signature'
require_text "$RUNNER" 'approval-window-dyld-report.ips'
require_text "$RUNNER" 'approval-window-started-at.txt'
require_text "$RUNNER" 'approval-window-dyld-pid-correlation.txt'
require_text "$RUNNER" 'extracted-app-files-after-known-bad-dyld.sha256'
require_text "$RUNNER" 'extracted-app-quarantine-after-known-bad-dyld.txt'
require_text "$RUNNER" 'verify-macos-framework-signature-crash.sh'
require_text "$ROOT/scripts/verify-macos-framework-signature-crash.sh" 'termination.namespace == "DYLD"'
require_text "$ROOT/scripts/verify-macos-framework-signature-crash.sh" 'whisper|MediaRemoteAdapter'
require_text "$ROOT/scripts/verify-macos-framework-signature-crash.sh" 'not valid for use in process'
require_text "$ROOT/scripts/verify-macos-framework-signature-crash.sh" 'proc_launch_time < approval_time - 2'
require_text "$RUNNER" 'expected_framework_signature_failure_reproduced'
require_text "$RUNNER" 'app_short_version='
require_text "$RUNNER" 'app_bundle_version='
require_text "$RUNNER" 'DISTRIBUTION_E2E_OPERATOR_CREDENTIAL_FILE'
require_text "$RUNNER" 'Open the Desktop credential file'

reject_text "$WORKFLOW" 'sudo[[:space:]].*passwd'
reject_text "$WORKFLOW" 'sudo[[:space:]].*dscl[[:space:]].*-passwd'
reject_text "$WORKFLOW" 'sysadminctl[[:space:]].*-addUser'
reject_text "$WORKFLOW" 'sysadminctl[[:space:]].*-deleteUser'
reject_text "$WORKFLOW" 'OPERATOR_PASSWORD="runner"'
reject_text "$WORKFLOW" 'ROMA_OPERATOR_PASSWORD="\$OPERATOR_PASSWORD"'
reject_text "$WORKFLOW" '-password[[:space:]]+"\$OPERATOR_PASSWORD"'
reject_text "$WORKFLOW" 'dscl[[:space:]].*-authonly[^\n]*"\$OPERATOR_PASSWORD"'
reject_text "$WORKFLOW" 'cat[[:space:]]+"\$OPERATOR_CREDENTIAL_FILE"'
reject_text "$WORKFLOW" 'upload.*operator.*credential'
reject_text "$WORKFLOW" 'file delete -force -- \$password_file'

secret_unset_line="$(grep -nF 'unset NAMESPACE_RUNNER_PASSWORD' "$WORKFLOW" | cut -d: -f1)"
cleanup_trap_line="$(grep -nF 'trap cleanup_created_credential_targets EXIT' "$WORKFLOW" | cut -d: -f1)"
identity_stat_line="$(grep -nF 'PASSWORD_FILE_IDENTITY="$(stat' "$WORKFLOW" | cut -d: -f1)"
password_write_line="$(grep -nF 'printf '\''%s'\'' "$CREDENTIAL_PASSWORD" >&7' "$WORKFLOW" | cut -d: -f1)"
credential_identity_line="$(grep -nF 'CREDENTIAL_FILE_IDENTITY="$(stat' "$WORKFLOW" | cut -d: -f1)"
credential_write_line="$(grep -nF 'printf '\''Password: %s\n'\'' "$CREDENTIAL_PASSWORD"' "$WORKFLOW" | cut -d: -f1)"
expect_auth_line="$(grep -nF 'ROMA_OPERATOR_PASSWORD_FILE="$OPERATOR_PASSWORD_FILE" /usr/bin/expect' "$WORKFLOW" | cut -d: -f1)"
password_cleanup_line="$(grep -nF '"$OPERATOR_PASSWORD_FILE" "$PASSWORD_FILE_IDENTITY" operator-password' "$WORKFLOW" | tail -n 1 | cut -d: -f1)"
password_absent_line="$(grep -nF 'test ! -e "$OPERATOR_PASSWORD_FILE"' "$WORKFLOW" | cut -d: -f1)"
trap_disarm_line="$(grep -nF 'trap - EXIT' "$WORKFLOW" | cut -d: -f1)"
if ! [[ "$secret_unset_line" =~ ^[0-9]+$ \
  && "$cleanup_trap_line" =~ ^[0-9]+$ \
  && "$identity_stat_line" =~ ^[0-9]+$ \
  && "$password_write_line" =~ ^[0-9]+$ \
  && "$credential_identity_line" =~ ^[0-9]+$ \
  && "$credential_write_line" =~ ^[0-9]+$ \
  && "$expect_auth_line" =~ ^[0-9]+$ \
  && "$password_cleanup_line" =~ ^[0-9]+$ \
  && "$password_absent_line" =~ ^[0-9]+$ \
  && "$trap_disarm_line" =~ ^[0-9]+$ ]] \
  || (( secret_unset_line >= cleanup_trap_line )) \
  || (( secret_unset_line >= identity_stat_line )) \
  || (( secret_unset_line >= expect_auth_line )) \
  || (( identity_stat_line >= password_write_line )) \
  || (( credential_identity_line >= credential_write_line )) \
  || (( password_cleanup_line <= expect_auth_line )) \
  || (( password_cleanup_line >= password_absent_line )) \
  || (( trap_disarm_line <= password_absent_line )); then
  echo "Namespace password setup or cleanup ordering is unsafe" >&2
  exit 1
fi

reject_text "$RUNNER" 'xattr[[:space:]]+-(c|d|cr|dr)'
reject_text "$RUNNER" 'codesign[[:space:]].*--(force|sign)'
reject_text "$RUNNER" 'unzip[[:space:]]'
reject_text "$RUNNER" 'kill[[:space:]]+-CONT'
reject_text "$RUNNER" 'Sparkle'
reject_text "$RUNNER" 'ExFAT'
reject_text "$RUNNER" 'http://127\.0\.0\.1'
reject_text "$RUNNER" 'python3[[:space:]]+-m[[:space:]]+http\.server'
reject_text "$RUNNER" 'browser-download-url\.txt'
reject_text "$RUNNER" 'Confirm (First|Second) Finder Extraction\.command'
reject_text "$RUNNER" '/usr/bin/date'
reject_text "$RUNNER" 'tell application "Finder"'

ditto_extraction_count="$(grep -Ec 'ditto[[:space:]].*-x' "$RUNNER")"
if [[ "$ditto_extraction_count" -ne 1 ]]; then
  echo "distribution E2E must use one CLI extraction, only for the expected reference bundle" >&2
  exit 1
fi

echo "macOS distribution E2E contract checks passed"
