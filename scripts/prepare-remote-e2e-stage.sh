#!/usr/bin/env bash
set -euo pipefail

target="${1:?target required}"
hold_minutes="${2:?hold minutes required}"
inputs_root="${3:?inputs root required}"
stage_root="${4:?stage root required}"
ios_scenario="${5:-none}"
macos_scenario="${6:-none}"
macos_audio_artifact="${7:-}"
macos_repetitions="${8:-3}"
macos_expected_version="${9:-}"
macos_expected_build="${10:-}"
runtime_helper_archive="${11:-$inputs_root/macos/runtime-helper/roma.runtime-e2e-harness.macos.zip}"
runtime_model_cache_path="${RUNTIME_E2E_MODEL_CACHE_PATH:-$HOME/Library/Caches/roma-runtime-e2e-models}"
runtime_empty_final_expectation="${RUNTIME_E2E_EMPTY_FINAL_EXPECTATION:-none}"
runtime_empty_final_baseline_evidence="${RUNTIME_E2E_EMPTY_FINAL_BASELINE_EVIDENCE:-}"
runtime_empty_final_baseline_run_id="${RUNTIME_E2E_EMPTY_FINAL_BASELINE_RUN_ID:-}"
distribution_expectation="${DISTRIBUTION_E2E_EXPECTATION:-fixed}"
expected_rejected_framework="${DISTRIBUTION_E2E_EXPECTED_REJECTED_FRAMEWORK:-}"
expected_main_uuid="${DISTRIBUTION_E2E_EXPECTED_MAIN_UUID:-}"
expected_rejected_framework_uuid="${DISTRIBUTION_E2E_EXPECTED_REJECTED_FRAMEWORK_UUID:-}"
framework_signature_baseline_evidence="${DISTRIBUTION_E2E_FRAMEWORK_SIGNATURE_BASELINE_EVIDENCE:-}"
framework_signature_baseline_run_id="${DISTRIBUTION_E2E_FRAMEWORK_SIGNATURE_BASELINE_RUN_ID:-}"
github_download_token="${GH_TOKEN:-}"
unset GH_TOKEN
source "$(cd "$(dirname "$0")" && pwd)/macos-bundle-manifest.sh"

case "$target" in
  both|macos|ios) ;;
  *)
    echo "Unsupported target: $target" >&2
    exit 2
    ;;
esac

if ! [[ "$hold_minutes" =~ ^[0-9]+$ ]] || (( hold_minutes < 0 || hold_minutes > 60 )); then
  echo "Hold minutes must be between 0 and 60" >&2
  exit 2
fi

case "$ios_scenario" in
  none|local-whisper-import) ;;
  *)
    echo "Unsupported iOS scenario: $ios_scenario" >&2
    exit 2
    ;;
esac

case "$macos_scenario" in
  none|runtime-smoke|runtime-e2e|distribution-e2e) ;;
  *)
    echo "Unsupported macOS scenario: $macos_scenario" >&2
    exit 2
    ;;
esac

case "$runtime_empty_final_expectation" in
  none|known-bad|fixed) ;;
  *)
    echo "Unsupported empty-final expectation: $runtime_empty_final_expectation" >&2
    exit 2
    ;;
esac

case "$distribution_expectation" in
  fixed|fixed-after-framework-signature|known-bad-framework-signature) ;;
  *)
    echo "Unsupported distribution E2E expectation: $distribution_expectation" >&2
    exit 2
    ;;
esac
if { [ "$distribution_expectation" = "known-bad-framework-signature" ] \
  || [ "$distribution_expectation" = "fixed-after-framework-signature" ]; } \
  && [ "$macos_scenario" != "distribution-e2e" ]; then
  echo "$distribution_expectation requires distribution-e2e" >&2
  exit 2
fi
if [ "$distribution_expectation" = "known-bad-framework-signature" ] \
  || [ "$distribution_expectation" = "fixed-after-framework-signature" ]; then
  case "$expected_rejected_framework" in
    whisper|MediaRemoteAdapter) ;;
    *)
      echo "known-bad framework signature requires whisper or MediaRemoteAdapter" >&2
      exit 2
      ;;
  esac
  for expected_uuid in "$expected_main_uuid" "$expected_rejected_framework_uuid"; do
    if ! [[ "$expected_uuid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
      echo "Known-bad framework signature proof requires source UUID inputs" >&2
      exit 2
    fi
  done
fi
if [ "$distribution_expectation" = "fixed-after-framework-signature" ]; then
  if [ "$runtime_empty_final_expectation" != "none" ]; then
    echo "Paired framework-signature proof requires normal passing runtime smoke" >&2
    exit 2
  fi
  if ! [[ "$framework_signature_baseline_run_id" =~ ^[0-9]+$ ]] \
    || [ ! -d "$framework_signature_baseline_evidence" ]; then
    echo "Paired framework-signature proof requires downloaded known-bad baseline evidence" >&2
    exit 2
  fi
elif [ -n "$framework_signature_baseline_evidence" ] \
  || [ -n "$framework_signature_baseline_run_id" ]; then
  echo "Framework-signature baseline evidence is only valid for paired fixed proof" >&2
  exit 2
fi
if [ "$runtime_empty_final_expectation" != "none" ] \
  && [ "$macos_scenario" != "runtime-smoke" ] \
  && [ "$macos_scenario" != "distribution-e2e" ]; then
  echo "An empty-final expectation requires runtime-smoke or distribution-e2e" >&2
  exit 2
fi

if [ "$macos_scenario" = "distribution-e2e" ] \
  || [ "$runtime_empty_final_expectation" != "none" ]; then
  runtime_model_cache_path=""
fi

if [ "$macos_scenario" = "distribution-e2e" ] && [ "$hold_minutes" -eq 0 ]; then
  echo "distribution-e2e requires time for Safari, Finder, and Gatekeeper interaction" >&2
  exit 2
fi
if [ "$macos_scenario" = "distribution-e2e" ] \
  && { [ -z "$macos_expected_version" ] || [ -z "$macos_expected_build" ]; }; then
  echo "distribution-e2e requires exact macOS product and build versions" >&2
  exit 2
fi
if [ -n "$macos_expected_version" ] \
  && ! [[ "$macos_expected_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "Invalid macOS product version: $macos_expected_version" >&2
  exit 2
fi
if [ -n "$macos_expected_build" ] \
  && ! [[ "$macos_expected_build" =~ ^[0-9A-Za-z]+$ ]]; then
  echo "Invalid macOS build version: $macos_expected_build" >&2
  exit 2
fi

if [ "$target" = "ios" ] && [ "$macos_scenario" != "none" ]; then
  echo "A macOS scenario requires the macos or both target" >&2
  exit 2
fi

if [ "$macos_scenario" = "runtime-e2e" ] && [ -z "$macos_audio_artifact" ]; then
  echo "runtime-e2e requires a private Namespace audio artifact" >&2
  exit 2
fi
if [ "$macos_scenario" != "none" ] && [ ! -f "$runtime_helper_archive" ]; then
  echo "A macOS runtime scenario requires the prebuilt runtime helper artifact" >&2
  exit 2
fi

case "$macos_repetitions" in
  1|3|5) ;;
  *)
    echo "macOS repetitions must be 1, 3, or 5" >&2
    exit 2
    ;;
esac
if [ "$runtime_empty_final_expectation" != "none" ] \
  && [ "$macos_repetitions" != "5" ]; then
  echo "An empty-final expectation requires five repetitions" >&2
  exit 2
fi
if [ "$runtime_empty_final_expectation" = "fixed" ]; then
  if ! [[ "$runtime_empty_final_baseline_run_id" =~ ^[0-9]+$ ]] \
    || [ ! -f "$runtime_empty_final_baseline_evidence/functional-smoke.json" ] \
    || [ ! -f "$runtime_empty_final_baseline_evidence/empty-final-e2e-contract.json" ] \
    || [ ! -f "$runtime_empty_final_baseline_evidence/empty-final-launch-events.tsv" ] \
    || [ ! -f "$runtime_empty_final_baseline_evidence/empty-final-termination-events.tsv" ] \
    || [ ! -f "$runtime_empty_final_baseline_evidence/voiceink-sha256.txt" ] \
    || [ ! -f "$runtime_empty_final_baseline_evidence/macos-artifact-metadata.json" ] \
    || [ ! -f "$runtime_empty_final_baseline_evidence/macos-app-run-metadata.json" ] \
    || [ ! -f "$runtime_empty_final_baseline_evidence/stage-manifest.json" ]; then
    echo "Fixed empty-final proof requires downloaded known-bad baseline evidence" >&2
    exit 2
  fi
elif [ -n "$runtime_empty_final_baseline_evidence" ] \
  || [ -n "$runtime_empty_final_baseline_run_id" ]; then
  echo "Known-bad baseline evidence is only valid for a fixed empty-final proof" >&2
  exit 2
fi

if [ "$target" = "macos" ] && [ "$ios_scenario" != "none" ]; then
  echo "An iOS scenario requires the ios or both target" >&2
  exit 2
fi

desktop="$HOME/Desktop"
evidence="$stage_root/evidence"
done_file="/tmp/voiceink-remote-e2e-stage-done"
ready_file="$stage_root/READY"
simulator_udid=""
macos_artifact_run_id=""
macos_artifact_id=""
macos_artifact_repository=""
macos_artifact_digest=""
macos_artifact_head_sha=""
macos_artifact_workflow_path=""
runtime_helper_run_id=""
runtime_helper_head_sha=""
runtime_helper_workflow_path=""
runtime_helper_artifact_id=""
runtime_helper_artifact_digest=""
runtime_helper_archive_sha256=""
macos_artifact_runner_name=""
runtime_helper_runner_name=""
runtime_empty_final_baseline_contract_sha256=""
stage_runner_label="${STAGE_RUNNER_LABEL:-}"
stage_runner_name="${STAGE_RUNNER_NAME:-}"
stage_runner_instance_id="${STAGE_RUNNER_INSTANCE_ID:-}"
stage_runner_boot_epoch="${STAGE_RUNNER_BOOT_EPOCH:-}"
stage_runner_boot_session_uuid="${STAGE_RUNNER_BOOT_SESSION_UUID:-}"
stage_runner_boot_age_seconds="${STAGE_RUNNER_BOOT_AGE_SECONDS:-}"
ios_artifact_run_id=""
macos_scenario_status=0
distribution_verdict="not-run"
framework_signature_pair_verdict="not-run"
ios_scenario_status=0
log_pids=()

mkdir -p "$desktop" "$evidence"
rm -f "$done_file"
if [ "$runtime_empty_final_expectation" = "fixed" ]; then
  runtime_empty_final_baseline_contract_sha256="$(
    shasum -a 256 \
      "$runtime_empty_final_baseline_evidence/empty-final-e2e-contract.json" \
      | awk '{print $1}'
  )"
fi

stop_logs() {
  for pid in "${log_pids[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap stop_logs EXIT

capture_desktop() {
  local phase="$1"
  local image="$evidence/desktop-$phase.png"
  local error_log="$evidence/desktop-$phase-screencapture.err"

  if ! /usr/sbin/screencapture -x "$image" 2> "$error_log"; then
    echo "Namespace VNC is available, but screencapture cannot see its display from the runner shell." \
      > "$evidence/desktop-$phase-controller-capture-required.txt"
  fi
}

prepare_macos() {
  local archive="$inputs_root/macos/unwrapped/roma.just.talk.app.zip"
  local actions_archive="$inputs_root/macos/distributed/roma.just.talk.app.zip"
  local app="$HOME/Applications/roma just talk.app"
  local preferences="$HOME/Library/Preferences/com.negentropi.RomaJustTalk.plist"
  local preferences_backup="$HOME/Library/Preferences/ccom.negentropi.RomaJustTalk.plist"

  test -f "$archive"
  read -r macos_artifact_run_id < "$inputs_root/macos/build-run-id.txt"
  macos_run_metadata="$inputs_root/macos/macos-app-run-metadata.json"
  test -f "$macos_run_metadata"
  jq -e \
    --arg run_id "$macos_artifact_run_id" \
    --arg repository "${GITHUB_REPOSITORY:-}" \
    '(.runId | tostring) == $run_id
      and .status == "completed"
      and .conclusion == "success"
      and (.event == "push" or .event == "workflow_dispatch")
      and ($repository == "" or .headRepository == $repository)
      and .workflowPath == ".github/workflows/voiceink-build.yml"
      and (.headSha | test("^[0-9a-f]{40}$"))' \
    "$macos_run_metadata" >/dev/null
  macos_artifact_head_sha="$(jq -r .headSha "$macos_run_metadata")"
  macos_artifact_workflow_path="$(jq -r .workflowPath "$macos_run_metadata")"
  cp "$macos_run_metadata" "$evidence/macos-app-run-metadata.json"

  test -f "$actions_archive"
  read -r macos_artifact_id \
    < "$inputs_root/macos/macos-artifact-id.txt"
  read -r macos_artifact_repository \
    < "$inputs_root/macos/macos-artifact-repository.txt"
  macos_artifact_metadata="$inputs_root/macos/macos-artifact-metadata.json"
  test -f "$macos_artifact_metadata"
  [[ "$macos_artifact_id" =~ ^[0-9]+$ ]]
  [ "$macos_artifact_repository" = "${GITHUB_REPOSITORY:-}" ]
  jq -e \
    --argjson artifact_id "$macos_artifact_id" \
    --arg run_id "$macos_artifact_run_id" '
      .id == $artifact_id
      and (.runId | tostring) == $run_id
      and .name == "roma.just.talk.app"
      and .expired == false
      and (.digest | test("^sha256:[0-9a-f]{64}$"))
    ' "$macos_artifact_metadata" >/dev/null
  macos_artifact_digest="$(jq -r .digest "$macos_artifact_metadata")"
  cp "$macos_artifact_metadata" "$evidence/macos-artifact-metadata.json"

  if [ "$macos_scenario" = "distribution-e2e" ]; then
    macos_run_jobs="$inputs_root/macos/macos-app-run-jobs.json"
    test -f "$macos_run_jobs"
    jq -e \
      --arg run_id "$macos_artifact_run_id" \
      '(.runId | tostring) == $run_id
        and .job.name == "Build release macOS app"
        and .job.status == "completed"
        and .job.conclusion == "success"
        and (.job.runnerName | startswith("nsc-runner-"))' \
      "$macos_run_jobs" >/dev/null
    macos_artifact_runner_name="$(jq -r .job.runnerName "$macos_run_jobs")"
    cp "$macos_run_jobs" "$evidence/macos-app-run-jobs.json"
  fi

  if [ "$macos_scenario" != "none" ]; then
    helper_run_metadata="$inputs_root/macos/runtime-helper-run-metadata.json"
    test -f "$helper_run_metadata"
    read -r runtime_helper_run_id \
      < "$inputs_root/macos/runtime-helper-run-id.txt"
    jq -e \
      --arg run_id "$runtime_helper_run_id" \
      --arg repository "${GITHUB_REPOSITORY:-}" \
      --arg expected_head_sha "${GITHUB_SHA:-}" \
      '(.runId | tostring) == $run_id
        and .status == "completed"
        and .conclusion == "success"
        and (.event == "push" or .event == "workflow_dispatch")
        and ($repository == "" or .headRepository == $repository)
        and ($expected_head_sha == "" or .headSha == $expected_head_sha)
        and .workflowPath == ".github/workflows/voiceink-build.yml"
        and (.headSha | test("^[0-9a-f]{40}$"))' \
      "$helper_run_metadata" >/dev/null
    runtime_helper_head_sha="$(jq -r .headSha "$helper_run_metadata")"
    runtime_helper_workflow_path="$(jq -r .workflowPath "$helper_run_metadata")"
    helper_artifact_metadata="$inputs_root/macos/runtime-helper-artifact-metadata.json"
    test -f "$helper_artifact_metadata"
    jq -e \
      --arg run_id "$runtime_helper_run_id" '
        (.runId | tostring) == $run_id
        and .name == "roma.runtime-e2e-harness.macos"
        and .expired == false
        and (.id | tostring | test("^[0-9]+$"))
        and (.digest | test("^sha256:[0-9a-f]{64}$"))
      ' "$helper_artifact_metadata" >/dev/null
    runtime_helper_artifact_id="$(jq -r .id "$helper_artifact_metadata")"
    runtime_helper_artifact_digest="$(jq -r .digest "$helper_artifact_metadata")"
    helper_artifact_archive_sha256="$inputs_root/macos/runtime-helper-artifact-archive.sha256"
    helper_artifact_archive="$inputs_root/macos/runtime-helper-artifact-archive.zip"
    test -f "$helper_artifact_archive_sha256"
    test -f "$helper_artifact_archive"
    grep -Eq \
      "^[0-9a-f]{64}  .+runtime-helper-artifact-archive\\.zip$" \
      "$helper_artifact_archive_sha256"
    helper_outer_archive_sha256="$(
      shasum -a 256 "$helper_artifact_archive" | awk '{print $1}'
    )"
    test "sha256:$helper_outer_archive_sha256" = "$runtime_helper_artifact_digest"
    test "$helper_outer_archive_sha256" = "$(
      awk 'NR == 1 { print $1 }' "$helper_artifact_archive_sha256"
    )"
    runtime_helper_archive_sha256="$(
      shasum -a 256 "$runtime_helper_archive" | awk '{print $1}'
    )"
    cp "$helper_run_metadata" "$evidence/runtime-helper-run-metadata.json"
    cp "$helper_artifact_metadata" "$evidence/runtime-helper-artifact-metadata.json"
    cp \
      "$helper_artifact_archive_sha256" \
      "$evidence/runtime-helper-artifact-archive.sha256"
    printf '%s  %s\n' \
      "$runtime_helper_archive_sha256" \
      "$runtime_helper_archive" \
      > "$evidence/runtime-helper-archive-sha256.txt"

    if [ "$macos_scenario" = "distribution-e2e" ]; then
      helper_run_jobs="$inputs_root/macos/runtime-helper-run-jobs.json"
      test -f "$helper_run_jobs"
      jq -e \
        --arg run_id "$runtime_helper_run_id" \
        '(.runId | tostring) == $run_id
          and .job.name == "Build reusable runtime E2E helper"
          and .job.status == "completed"
          and .job.conclusion == "success"
          and (.job.runnerName | startswith("nsc-runner-"))' \
        "$helper_run_jobs" >/dev/null
      runtime_helper_runner_name="$(jq -r .job.runnerName "$helper_run_jobs")"
      cp "$helper_run_jobs" "$evidence/runtime-helper-run-jobs.json"
    fi
  fi

  if [ "$distribution_expectation" = "fixed-after-framework-signature" ]; then
    baseline_root="$framework_signature_baseline_evidence"
    baseline_evidence="$baseline_root/evidence"
    baseline_stage_manifest="$baseline_evidence/stage-manifest.json"
    required_baseline_evidence=(
      "$baseline_stage_manifest"
      "$baseline_root/baseline-run-metadata.json"
      "$baseline_root/baseline-artifact-metadata.json"
      "$baseline_root/baseline-artifact-archive.zip"
      "$baseline_root/baseline-artifact-archive.sha256"
      "$baseline_evidence/macos-artifact-metadata.json"
      "$baseline_evidence/macos-app-run-metadata.json"
      "$baseline_evidence/macos-distribution-e2e/distribution-verdict.txt"
      "$baseline_evidence/macos-distribution-e2e/approval-window-dyld-report.ips"
      "$baseline_evidence/macos-distribution-e2e/approval-window-dyld-match.txt"
      "$baseline_evidence/macos-distribution-e2e/approval-window-started-at.txt"
      "$baseline_evidence/macos-distribution-e2e/approval-window-dyld-pid-correlation.txt"
      "$baseline_evidence/macos-distribution-e2e/expected-negative-control-identities.txt"
      "$baseline_evidence/macos-distribution-e2e/extracted-app-identity.txt"
      "$baseline_evidence/macos-distribution-e2e/source-artifact.txt"
      "$baseline_evidence/fresh-namespace-runner.txt"
    )
    for required_evidence in "${required_baseline_evidence[@]}"; do
      test -s "$required_evidence"
    done

    jq -e \
      --arg run_id "$framework_signature_baseline_run_id" \
      --arg head_sha "${GITHUB_SHA:-}" \
      --arg repository "${GITHUB_REPOSITORY:-}" \
      --arg workflow_path ".github/workflows/voiceink-remote-e2e-stage.yml" \
      --arg version "$macos_expected_version" \
      --arg build "$macos_expected_build" \
      --arg runner "$stage_runner_label" \
      --arg framework "$expected_rejected_framework" \
      --arg main_uuid "$expected_main_uuid" \
      --arg framework_uuid "$expected_rejected_framework_uuid" '
        .status == "completed"
          and .macOSScenario == "distribution-e2e"
          and .macOSScenarioExitCode == 0
          and .macOSDistributionExpectation == "known-bad-framework-signature"
          and .macOSDistributionVerdict == "expected_framework_signature_failure_reproduced"
          and .macOSExpectedVersion == $version
          and .macOSExpectedBuild == $build
          and .stageRunnerLabel == $runner
          and .macOSExpectedRejectedFramework == $framework
          and ((.macOSExpectedMainUUID | ascii_upcase) == ($main_uuid | ascii_upcase))
          and ((.macOSExpectedRejectedFrameworkUUID | ascii_upcase) == ($framework_uuid | ascii_upcase))
          and .githubRunId == $run_id
          and ($head_sha == "" or .githubSha == $head_sha)
          and ($repository == "" or .githubRepository == $repository)
          and .githubWorkflowPath == $workflow_path
          and (.macOSArtifactRunId | tostring | test("^[0-9]+$"))
          and (.macOSArtifactId | tostring | test("^[0-9]+$"))
          and (.macOSArtifactDigest | test("^sha256:[0-9a-f]{64}$"))
          and (.macOSArtifactHeadSha | test("^[0-9a-f]{40}$"))
          and .macOSArtifactWorkflowPath == ".github/workflows/voiceink-build.yml"
      ' "$baseline_stage_manifest" >/dev/null

    jq -e \
      --arg run_id "$framework_signature_baseline_run_id" \
      --arg head_sha "${GITHUB_SHA:-}" \
      --arg repository "${GITHUB_REPOSITORY:-}" '
        (.runId | tostring) == $run_id
          and .status == "completed"
          and .conclusion == "success"
          and ($head_sha == "" or .headSha == $head_sha)
          and ($repository == "" or .repository == $repository)
          and .workflowPath == ".github/workflows/voiceink-remote-e2e-stage.yml"
      ' "$baseline_root/baseline-run-metadata.json" >/dev/null
    jq -e \
      --arg run_id "$framework_signature_baseline_run_id" '
        (.runId | tostring) == $run_id
          and .name == "remote-e2e-stage-evidence"
          and .expired == false
          and (.id | tostring | test("^[0-9]+$"))
          and (.digest | test("^sha256:[0-9a-f]{64}$"))
      ' "$baseline_root/baseline-artifact-metadata.json" >/dev/null
    baseline_outer_sha="$(
      shasum -a 256 "$baseline_root/baseline-artifact-archive.zip" | awk '{print $1}'
    )"
    test "sha256:$baseline_outer_sha" = "$(
      jq -r .digest "$baseline_root/baseline-artifact-metadata.json"
    )"
    test "$baseline_outer_sha" = "$(
      awk 'NR == 1 { print $1 }' "$baseline_root/baseline-artifact-archive.sha256"
    )"

    baseline_app_run_id="$(jq -r .macOSArtifactRunId "$baseline_stage_manifest")"
    baseline_app_artifact_id="$(jq -r .macOSArtifactId "$baseline_stage_manifest")"
    baseline_app_digest="$(jq -r .macOSArtifactDigest "$baseline_stage_manifest")"
    baseline_app_head_sha="$(jq -r .macOSArtifactHeadSha "$baseline_stage_manifest")"
    baseline_app_repository="$(jq -r .macOSArtifactRepository "$baseline_stage_manifest")"
    baseline_app_workflow_path="$(jq -r .macOSArtifactWorkflowPath "$baseline_stage_manifest")"
    jq -e \
      --arg run_id "$baseline_app_run_id" \
      --arg artifact_id "$baseline_app_artifact_id" \
      --arg digest "$baseline_app_digest" '
        (.runId | tostring) == $run_id
          and (.id | tostring) == $artifact_id
          and .name == "roma.just.talk.app"
          and .digest == $digest
          and .expired == false
      ' "$baseline_evidence/macos-artifact-metadata.json" >/dev/null
    jq -e \
      --arg run_id "$baseline_app_run_id" \
      --arg repository "$baseline_app_repository" \
      --arg head_sha "$baseline_app_head_sha" \
      --arg workflow_path "$baseline_app_workflow_path" '
        (.runId | tostring) == $run_id
          and .headRepository == $repository
          and .headSha == $head_sha
          and .workflowPath == $workflow_path
          and .status == "completed"
          and .conclusion == "success"
      ' "$baseline_evidence/macos-app-run-metadata.json" >/dev/null

    baseline_identities="$baseline_evidence/macos-distribution-e2e/expected-negative-control-identities.txt"
    baseline_extracted_identity="$baseline_evidence/macos-distribution-e2e/extracted-app-identity.txt"
    baseline_distribution_verdict="$baseline_evidence/macos-distribution-e2e/distribution-verdict.txt"
    baseline_source_artifact="$baseline_evidence/macos-distribution-e2e/source-artifact.txt"
    grep -Fx "expected_rejected_framework=$expected_rejected_framework" \
      "$baseline_distribution_verdict"
    grep -Fxi "main_arm64_uuid=$expected_main_uuid" "$baseline_identities"
    grep -Fxi "framework_arm64_uuid=$expected_rejected_framework_uuid" "$baseline_identities"
    grep -Fxi "source_main_uuid=$expected_main_uuid" "$baseline_distribution_verdict"
    grep -Fxi "source_rejected_framework_uuid=$expected_rejected_framework_uuid" \
      "$baseline_distribution_verdict"
    grep -Eq '^app_short_version=[0-9A-Za-z][0-9A-Za-z._-]*$' "$baseline_identities"
    grep -Eq '^app_bundle_version=[0-9A-Za-z][0-9A-Za-z._-]*$' "$baseline_identities"
    baseline_short_version="$(sed -n 's/^app_short_version=//p' "$baseline_identities")"
    baseline_bundle_version="$(sed -n 's/^app_bundle_version=//p' "$baseline_identities")"
    test "$(grep -c '^app_short_version=' "$baseline_identities")" -eq 1
    test "$(grep -c '^app_bundle_version=' "$baseline_identities")" -eq 1
    grep -Fx "app_short_version=$baseline_short_version" "$baseline_extracted_identity"
    grep -Fx "app_bundle_version=$baseline_bundle_version" "$baseline_extracted_identity"
    grep -Fx "app_short_version=$baseline_short_version" "$baseline_distribution_verdict"
    grep -Fx "app_bundle_version=$baseline_bundle_version" "$baseline_distribution_verdict"
    baseline_crash_sha="$(
      shasum -a 256 \
        "$baseline_evidence/macos-distribution-e2e/approval-window-dyld-report.ips" \
        | awk '{print $1}'
    )"
    bash "$(dirname "$0")/verify-macos-framework-signature-crash.sh" \
      "$baseline_evidence/macos-distribution-e2e/approval-window-dyld-report.ips" \
      com.negentropi.RomaJustTalk "$macos_expected_version" "$macos_expected_build" \
      "$expected_main_uuid" "$expected_rejected_framework" "$expected_rejected_framework_uuid" \
      "$(cat "$baseline_evidence/macos-distribution-e2e/approval-window-started-at.txt")" \
      "$baseline_short_version" "$baseline_bundle_version" \
      > "$evidence/framework-signature-baseline-reverification.txt"
    grep -Eq '^verdict=matched pid=[1-9][0-9]* ' \
      "$baseline_evidence/macos-distribution-e2e/approval-window-dyld-match.txt"
    grep -Fq "crash_report_sha256=$baseline_crash_sha" \
      "$baseline_evidence/macos-distribution-e2e/approval-window-dyld-match.txt"
    grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
      "$baseline_evidence/macos-distribution-e2e/approval-window-started-at.txt"
    grep -Fx 'report_pid_dead=true' \
      "$baseline_evidence/macos-distribution-e2e/approval-window-dyld-pid-correlation.txt"
    grep -Fx 'running_roma_processes=0' \
      "$baseline_evidence/macos-distribution-e2e/approval-window-dyld-pid-correlation.txt"
    grep -Fx 'distribution_verdict=expected_framework_signature_failure_reproduced' \
      "$baseline_evidence/macos-distribution-e2e/distribution-verdict.txt"
    grep -Fx "github_artifact_run_id=$baseline_app_run_id" "$baseline_source_artifact"
    grep -Fx "github_artifact_id=$baseline_app_artifact_id" \
      "$baseline_source_artifact"
    grep -Fx "github_artifact_digest=$baseline_app_digest" \
      "$baseline_source_artifact"
    grep -Fx "github_actions_archive_sha256=${baseline_app_digest#sha256:}" \
      "$baseline_source_artifact"
    grep -Fx 'fresh_machine_provenance=passed' "$baseline_evidence/fresh-namespace-runner.txt"

    if [ "$baseline_app_run_id" = "$macos_artifact_run_id" ] \
      || [ "$baseline_app_artifact_id" = "$macos_artifact_id" ] \
      || [ "$baseline_app_digest" = "$macos_artifact_digest" ] \
      || [ "$baseline_app_head_sha" = "$macos_artifact_head_sha" ]; then
      echo "Paired framework-signature proof requires distinct baseline and candidate app artifacts" >&2
      exit 2
    fi
    jq -n \
      --arg baseline_stage_run_id "$framework_signature_baseline_run_id" \
      --arg baseline_app_run_id "$baseline_app_run_id" \
      --arg baseline_artifact_id "$baseline_app_artifact_id" \
      --arg baseline_digest "$baseline_app_digest" \
      --arg baseline_head_sha "$baseline_app_head_sha" \
      --arg candidate_run_id "$macos_artifact_run_id" \
      --arg candidate_artifact_id "$macos_artifact_id" \
      --arg candidate_digest "$macos_artifact_digest" \
      --arg candidate_head_sha "$macos_artifact_head_sha" \
      --arg tooling_sha "${GITHUB_SHA:-local}" \
      --arg macos_version "$macos_expected_version" \
      --arg macos_build "$macos_expected_build" \
      --arg runner_label "$stage_runner_label" \
      --arg framework "$expected_rejected_framework" \
      --arg main_uuid "$expected_main_uuid" \
      --arg framework_uuid "$expected_rejected_framework_uuid" \
      --arg baseline_short_version "$baseline_short_version" \
      --arg baseline_bundle_version "$baseline_bundle_version" '
        {
          pairingValidation: "passed",
          toolingSha: $tooling_sha,
          macOSVersion: $macos_version,
          macOSBuild: $macos_build,
          runnerLabel: $runner_label,
          rejectedFramework: $framework,
          reportedMainUUID: $main_uuid,
          reportedFrameworkUUID: $framework_uuid,
          baselineAppShortVersion: $baseline_short_version,
          baselineAppBundleVersion: $baseline_bundle_version,
          baseline: {
            stageRunId: $baseline_stage_run_id,
            appRunId: $baseline_app_run_id,
            artifactId: $baseline_artifact_id,
            digest: $baseline_digest,
            headSha: $baseline_head_sha,
            verdict: "expected_framework_signature_failure_reproduced"
          },
          candidate: {
            appRunId: $candidate_run_id,
            artifactId: $candidate_artifact_id,
            digest: $candidate_digest,
            headSha: $candidate_head_sha
          }
        }
      ' > "$evidence/paired-framework-signature-proof.json"
    cp "$baseline_root/baseline-artifact-archive.sha256" \
      "$evidence/paired-framework-signature-baseline-artifact-archive.sha256"
  fi

  if [ "$runtime_empty_final_expectation" = "fixed" ]; then
    baseline_stage_manifest="$runtime_empty_final_baseline_evidence/stage-manifest.json"
    jq -e \
      --arg repository "${GITHUB_REPOSITORY:-}" '
        (.macOSArtifactRunId | tostring | test("^[0-9]+$"))
        and (.macOSArtifactId | tostring | test("^[0-9]+$"))
        and ($repository == "" or .macOSArtifactRepository == $repository)
        and (.macOSArtifactDigest | test("^sha256:[0-9a-f]{64}$"))
        and (.macOSArtifactHeadSha | test("^[0-9a-f]{40}$"))
        and .macOSArtifactWorkflowPath == ".github/workflows/voiceink-build.yml"
      ' "$baseline_stage_manifest" >/dev/null
    baseline_app_run_id="$(jq -r .macOSArtifactRunId "$baseline_stage_manifest")"
    baseline_app_artifact_id="$(jq -r .macOSArtifactId "$baseline_stage_manifest")"
    baseline_app_digest="$(jq -r .macOSArtifactDigest "$baseline_stage_manifest")"
    baseline_app_head_sha="$(jq -r .macOSArtifactHeadSha "$baseline_stage_manifest")"
    baseline_app_repository="$(jq -r .macOSArtifactRepository "$baseline_stage_manifest")"
    baseline_app_workflow_path="$(jq -r .macOSArtifactWorkflowPath "$baseline_stage_manifest")"
    baseline_app_artifact_metadata="$runtime_empty_final_baseline_evidence/macos-artifact-metadata.json"
    jq -e \
      --arg run_id "$baseline_app_run_id" \
      --arg artifact_id "$baseline_app_artifact_id" \
      --arg digest "$baseline_app_digest" '
        (.runId | tostring) == $run_id
        and (.id | tostring) == $artifact_id
        and .name == "roma.just.talk.app"
        and .digest == $digest
        and .expired == false
      ' "$baseline_app_artifact_metadata" >/dev/null
    baseline_app_run_metadata="$runtime_empty_final_baseline_evidence/macos-app-run-metadata.json"
    jq -e \
      --arg run_id "$baseline_app_run_id" \
      --arg repository "$baseline_app_repository" \
      --arg head_sha "$baseline_app_head_sha" \
      --arg workflow_path "$baseline_app_workflow_path" '
        (.runId | tostring) == $run_id
        and .headRepository == $repository
        and .headSha == $head_sha
        and .workflowPath == $workflow_path
        and .status == "completed"
        and .conclusion == "success"
      ' "$baseline_app_run_metadata" >/dev/null
    baseline_artifact_metadata="$runtime_empty_final_baseline_evidence/baseline-artifact-metadata.json"
    baseline_artifact_archive="$runtime_empty_final_baseline_evidence/baseline-artifact-archive.zip"
    baseline_artifact_archive_sha256="$runtime_empty_final_baseline_evidence/baseline-artifact-archive.sha256"
    test -f "$baseline_artifact_metadata"
    test -f "$baseline_artifact_archive"
    test -f "$baseline_artifact_archive_sha256"
    baseline_outer_archive_sha256="$(
      shasum -a 256 "$baseline_artifact_archive" | awk '{print $1}'
    )"
    test "sha256:$baseline_outer_archive_sha256" = "$(
      jq -r .digest "$baseline_artifact_metadata"
    )"
    test "$baseline_outer_archive_sha256" = "$(
      awk 'NR == 1 { print $1 }' "$baseline_artifact_archive_sha256"
    )"
    if [ "$baseline_app_run_id" = "$macos_artifact_run_id" ] \
      || [ "$baseline_app_artifact_id" = "$macos_artifact_id" ] \
      || [ "$baseline_app_digest" = "$macos_artifact_digest" ] \
      || [ "$baseline_app_head_sha" = "$macos_artifact_head_sha" ]; then
      echo "Paired empty-final proof requires distinct baseline and candidate app artifacts" >&2
      exit 2
    fi
    jq -n \
      --arg baseline_run_id "$baseline_app_run_id" \
      --arg baseline_artifact_id "$baseline_app_artifact_id" \
      --arg baseline_repository "$baseline_app_repository" \
      --arg baseline_digest "$baseline_app_digest" \
      --arg baseline_head_sha "$baseline_app_head_sha" \
      --arg baseline_workflow_path "$baseline_app_workflow_path" \
      --arg candidate_run_id "$macos_artifact_run_id" \
      --arg candidate_artifact_id "$macos_artifact_id" \
      --arg candidate_repository "$macos_artifact_repository" \
      --arg candidate_digest "$macos_artifact_digest" \
      --arg candidate_head_sha "$macos_artifact_head_sha" \
      --arg candidate_workflow_path "$macos_artifact_workflow_path" '
        {
          baseline: {
            runId: $baseline_run_id,
            artifactId: $baseline_artifact_id,
            repository: $baseline_repository,
            digest: $baseline_digest,
            headSha: $baseline_head_sha,
            workflowPath: $baseline_workflow_path
          },
          candidate: {
            runId: $candidate_run_id,
            artifactId: $candidate_artifact_id,
            repository: $candidate_repository,
            digest: $candidate_digest,
            headSha: $candidate_head_sha,
            workflowPath: $candidate_workflow_path
          }
        }
      ' > "$evidence/paired-app-identity.json"
    cp \
      "$baseline_artifact_archive_sha256" \
      "$evidence/paired-known-bad-artifact-archive.sha256"
  fi
  if [ "$macos_scenario" = "runtime-smoke" ] \
    || [ "$macos_scenario" = "runtime-e2e" ]; then
    app="/Applications/roma just talk.app"
  fi
  mkdir -p "$(dirname "$app")" "$stage_root/macos"

  /usr/bin/log stream \
    --style compact \
    --predicate 'process == "roma just talk"' \
    > "$evidence/macos-app.log" 2>&1 &
  log_pids+=("$!")

  if [ "$macos_scenario" = "distribution-e2e" ]; then
    [ -n "$github_download_token" ]
    case "$stage_runner_label" in
      namespace-profile-*|nscloud-macos-*) ;;
      *)
        echo "distribution-e2e did not receive a Namespace runner label" >&2
        exit 2
        ;;
    esac
    case "$stage_runner_name" in
      nsc-runner-*) ;;
      *)
        echo "distribution-e2e did not receive a Namespace runner instance" >&2
        exit 2
        ;;
    esac
    test -n "$stage_runner_instance_id"
    [[ "$stage_runner_boot_epoch" =~ ^[0-9]+$ ]]
    [[ "$stage_runner_boot_session_uuid" =~ ^[0-9A-Fa-f-]{36}$ ]]
    [[ "$stage_runner_boot_age_seconds" =~ ^[0-9]+$ ]]
    if [ "$stage_runner_name" = "$macos_artifact_runner_name" ]; then
      echo "distribution stage reused the macOS artifact build machine" >&2
      exit 2
    fi
    if [ "$stage_runner_name" = "$runtime_helper_runner_name" ]; then
      echo "distribution stage reused the runtime-helper build machine" >&2
      exit 2
    fi
    if [ "$macos_artifact_runner_name" = "$runtime_helper_runner_name" ]; then
      echo "macOS artifact and runtime helper reused the same build machine" >&2
      exit 2
    fi
    {
      printf 'stage_runner_label=%s\n' "$stage_runner_label"
      printf 'stage_runner_name=%s\n' "$stage_runner_name"
      printf 'stage_runner_instance_id=%s\n' "$stage_runner_instance_id"
      printf 'stage_runner_boot_epoch=%s\n' "$stage_runner_boot_epoch"
      printf 'stage_runner_boot_session_uuid=%s\n' "$stage_runner_boot_session_uuid"
      printf 'stage_runner_boot_age_seconds_at_job_start=%s\n' "$stage_runner_boot_age_seconds"
      printf 'macos_artifact_runner_name=%s\n' "$macos_artifact_runner_name"
      printf 'runtime_helper_runner_name=%s\n' "$runtime_helper_runner_name"
      printf 'fresh_machine_provenance=passed\n'
    } > "$evidence/fresh-namespace-runner.txt"
    echo "$actions_archive" > "$stage_root/macos-actions-archive-path.txt"
    return
  fi

  ditto -x -k "$archive" "$stage_root/macos"
  test -d "$stage_root/macos/roma just talk.app"
  test ! -e "$app"
  ditto "$stage_root/macos/roma just talk.app" "$app"

  if [ "$macos_scenario" = "runtime-smoke" ] \
    || [ "$macos_scenario" = "runtime-e2e" ]; then
    local fallback_receipt="$evidence/landing-quarantine-fallback.txt"
    local quarantine_value=""
    local fallback_pid=""
    local fallback_deadline=0
    local executable="$app/Contents/MacOS/roma just talk"
    quarantine_value="0081;$(printf '%x' "$(date +%s)");Safari;"
    xattr -w com.apple.quarantine "$quarantine_value" "$app"
    xattr -w com.roma.runtime-e2e-preserved true "$executable"
    test "$(xattr -p com.apple.quarantine "$app")" = "$quarantine_value"
    shasum -a 256 "$executable" > "$evidence/landing-fallback-executable-before.sha256"

    /usr/bin/xattr -dr com.apple.quarantine "/Applications/roma just talk.app" \
      && /usr/bin/open "/Applications/roma just talk.app"

    if xattr -lr "$app" 2>/dev/null | grep -Fq 'com.apple.quarantine:'; then
      echo "Landing fallback left quarantine attributes in the app bundle" >&2
      exit 2
    fi
    printf 'quarantine_after=absent\n' \
      > "$evidence/landing-fallback-quarantine-after.txt"
    test "$(xattr -p com.roma.runtime-e2e-preserved "$executable")" = true
    shasum -a 256 "$executable" > "$evidence/landing-fallback-executable-after.sha256"
    cmp -s \
      "$evidence/landing-fallback-executable-before.sha256" \
      "$evidence/landing-fallback-executable-after.sha256"

    fallback_deadline=$((SECONDS + 30))
    while (( SECONDS < fallback_deadline )); do
      fallback_pid="$(pgrep -x "roma just talk" 2>/dev/null || true)"
      if [[ "$fallback_pid" =~ ^[0-9]+$ ]] \
        && RUNTIME_E2E_FALLBACK_PID="$fallback_pid" \
          /usr/bin/osascript -l JavaScript -e '
          ObjC.import("AppKit")
          const pid = Number(ObjC.unwrap(
            $.NSProcessInfo.processInfo.environment.objectForKey(
              "RUNTIME_E2E_FALLBACK_PID"
            )
          ))
          const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(pid)
          app ? ObjC.unwrap(app.finishedLaunching) : false
        ' 2>/dev/null | grep -Fx true; then
        break
      fi
      sleep 0.25
    done
    [[ "$fallback_pid" =~ ^[0-9]+$ ]]
    RUNTIME_E2E_FALLBACK_PID="$fallback_pid" \
      /usr/bin/osascript -l JavaScript -e '
      ObjC.import("AppKit")
      const pid = Number(ObjC.unwrap(
        $.NSProcessInfo.processInfo.environment.objectForKey(
          "RUNTIME_E2E_FALLBACK_PID"
        )
      ))
      const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(pid)
      app && ObjC.unwrap(app.finishedLaunching) ? ObjC.unwrap(app.terminate) : false
    ' | grep -Fx true
    fallback_deadline=$((SECONDS + 30))
    while pgrep -x "roma just talk" >/dev/null 2>&1; do
      if (( SECONDS >= fallback_deadline )); then
        echo "Roma did not terminate after the landing fallback launch" >&2
        exit 2
      fi
      sleep 0.25
    done
    {
      printf 'verdict=passed\n'
      printf 'app_path=%s\n' "$app"
      printf 'quarantine_before=%s\n' "$quarantine_value"
      printf 'quarantine_after=absent\n'
      printf 'unrelated_nested_xattr_after=true\n'
      printf 'launch_pid=%s\n' "$fallback_pid"
      printf 'application_finished_launching=true\n'
      printf 'termination=normal\n'
      printf 'command=/usr/bin/xattr -dr com.apple.quarantine "/Applications/roma just talk.app" && /usr/bin/open "/Applications/roma just talk.app"\n'
    } > "$fallback_receipt"
  else
    xattr -cr "$app"
  fi

  if [ -f "$preferences" ] && [ ! -f "$preferences_backup" ]; then
    mv "$preferences" "$preferences_backup"
  fi
  defaults delete com.negentropi.RomaJustTalk hasCompletedOnboarding 2>/dev/null || true
  defaults delete com.negentropi.RomaJustTalk macOSOnboardingStage 2>/dev/null || true
  defaults delete com.negentropi.RomaJustTalk macOSOnboardingPermissionKind 2>/dev/null || true
  killall cfprefsd 2>/dev/null || true

  if [ "$macos_scenario" = "none" ]; then
    open -na "$app"
  fi
  echo "$app" > "$stage_root/macos-app-path.txt"
}

prepare_ios() {
  local archive="$inputs_root/ios/roma.just.talk.ios-simulator.app.zip"
  local unpacked="$stage_root/ios"
  local app="$unpacked/roma just talk.app"

  test -f "$archive"
  read -r ios_artifact_run_id < "$inputs_root/ios/build-run-id.txt"
  mkdir -p "$unpacked"
  ditto -x -k "$archive" "$unpacked"
  test -d "$app"

  simulator_udid="$(
    xcrun simctl list devices available --json \
      | jq -r '[.devices[][] | select(.name | startswith("iPhone"))][0].udid'
  )"
  test -n "$simulator_udid"
  test "$simulator_udid" != "null"

  xcrun simctl shutdown "$simulator_udid" 2>/dev/null || true
  xcrun simctl erase "$simulator_udid"
  xcrun simctl boot "$simulator_udid"
  xcrun simctl bootstatus "$simulator_udid" -b
  xcrun simctl install "$simulator_udid" "$app"
  open -a Simulator
  xcrun simctl launch "$simulator_udid" com.negentropi.RomaJustTalk

  xcrun simctl spawn "$simulator_udid" log stream \
    --style compact \
    --predicate 'process == "roma just talk"' \
    > "$evidence/ios-app.log" 2>&1 &
  log_pids+=("$!")

  echo "$simulator_udid" > "$stage_root/ios-simulator-udid.txt"
}

case "$target" in
  both)
    prepare_macos
    prepare_ios
    ;;
  macos)
    prepare_macos
    ;;
  ios)
    prepare_ios
    ;;
esac

write_manifest() {
  local status="$1"
  local runtime_helper_executable_sha256=""
  if [ -f "$evidence/helper-sha256.txt" ]; then
    runtime_helper_executable_sha256="$(
      awk 'NR == 1 { print $1 }' "$evidence/helper-sha256.txt"
    )"
  fi

  cat > "$stage_root/stage-manifest.json" <<EOF
{
  "schemaVersion": 1,
  "status": "$status",
  "target": "$target",
  "macOSScenario": "$macos_scenario",
  "macOSScenarioExitCode": $macos_scenario_status,
  "macOSExpectedVersion": "$macos_expected_version",
  "macOSExpectedBuild": "$macos_expected_build",
  "macOSDistributionExpectation": "$distribution_expectation",
  "macOSExpectedRejectedFramework": "$expected_rejected_framework",
  "macOSExpectedMainUUID": "$expected_main_uuid",
  "macOSExpectedRejectedFrameworkUUID": "$expected_rejected_framework_uuid",
  "macOSDistributionVerdict": "$distribution_verdict",
  "macOSFrameworkSignatureBaselineRunId": "$framework_signature_baseline_run_id",
  "macOSFrameworkSignaturePairVerdict": "$framework_signature_pair_verdict",
  "macOSAudioArtifact": "$macos_audio_artifact",
  "macOSRepetitions": $macos_repetitions,
  "macOSEmptyFinalExpectation": "$runtime_empty_final_expectation",
  "macOSEmptyFinalBaselineRunId": "$runtime_empty_final_baseline_run_id",
  "macOSEmptyFinalBaselineContractSha256": "$runtime_empty_final_baseline_contract_sha256",
  "iOSScenario": "$ios_scenario",
  "iOSScenarioExitCode": $ios_scenario_status,
  "githubRunId": "${GITHUB_RUN_ID:-local}",
  "githubSha": "${GITHUB_SHA:-local}",
  "githubRef": "${GITHUB_REF:-local}",
  "githubRepository": "${GITHUB_REPOSITORY:-local}",
  "githubWorkflowPath": ".github/workflows/voiceink-remote-e2e-stage.yml",
  "stageRunnerLabel": "$stage_runner_label",
  "stageRunnerName": "$stage_runner_name",
  "stageRunnerInstanceId": "$stage_runner_instance_id",
  "stageRunnerBootEpoch": "$stage_runner_boot_epoch",
  "stageRunnerBootSessionUUID": "$stage_runner_boot_session_uuid",
  "stageRunnerBootAgeSecondsAtJobStart": "$stage_runner_boot_age_seconds",
  "macOSArtifactRunId": "$macos_artifact_run_id",
  "macOSArtifactId": "$macos_artifact_id",
  "macOSArtifactRepository": "$macos_artifact_repository",
  "macOSArtifactDigest": "$macos_artifact_digest",
  "macOSArtifactHeadSha": "$macos_artifact_head_sha",
  "macOSArtifactWorkflowPath": "$macos_artifact_workflow_path",
  "macOSArtifactRunnerName": "$macos_artifact_runner_name",
  "runtimeHelperRunId": "$runtime_helper_run_id",
  "runtimeHelperHeadSha": "$runtime_helper_head_sha",
  "runtimeHelperWorkflowPath": "$runtime_helper_workflow_path",
  "runtimeHelperArtifactId": "$runtime_helper_artifact_id",
  "runtimeHelperArtifactDigest": "$runtime_helper_artifact_digest",
  "runtimeHelperRunnerName": "$runtime_helper_runner_name",
  "runtimeHelperArchiveSha256": "$runtime_helper_archive_sha256",
  "runtimeHelperExecutableSha256": "$runtime_helper_executable_sha256",
  "iOSArtifactRunId": "$ios_artifact_run_id",
  "doneFile": "$done_file",
  "evidenceDirectory": "$evidence",
  "macOSBundleIdentifier": "com.negentropi.RomaJustTalk",
  "iOSBundleIdentifier": "com.negentropi.RomaJustTalk",
  "simulatorUDID": "$simulator_udid"
}
EOF
  cp "$stage_root/stage-manifest.json" "$evidence/stage-manifest.json"
}

write_manifest scenario-running

if [ "$macos_scenario" = "distribution-e2e" ]; then
  low_level_distribution_expectation="$distribution_expectation"
  if [ "$distribution_expectation" = "fixed-after-framework-signature" ]; then
    low_level_distribution_expectation="fixed"
  fi
  set +e
  GH_TOKEN="$github_download_token" \
  DISTRIBUTION_E2E_EXPECTATION="$low_level_distribution_expectation" \
  MACOS_ARTIFACT_RUN_ID="$macos_artifact_run_id" \
  MACOS_ARTIFACT_ID="$macos_artifact_id" \
  MACOS_ARTIFACT_REPOSITORY="$macos_artifact_repository" \
  MACOS_ARTIFACT_DIGEST="$macos_artifact_digest" \
    bash "$(dirname "$0")/run-macos-distribution-e2e.sh" \
      "$inputs_root/macos/distributed/roma.just.talk.app.zip" \
      "$inputs_root/macos/unwrapped/roma.just.talk.app.zip" \
      "$evidence" \
      "$stage_root" \
      "$macos_expected_version" \
      "$macos_expected_build" \
      "$hold_minutes"
  macos_scenario_status=$?
  github_download_token=""
  set -e

  if [ "$macos_scenario_status" -eq 0 ]; then
    distribution_verdict="$(
      sed -n 's/^distribution_verdict=//p' \
        "$evidence/macos-distribution-e2e/distribution-verdict.txt"
    )"
  fi

  if [ "$macos_scenario_status" -eq 0 ] \
    && [ "$distribution_expectation" = "known-bad-framework-signature" ]; then
    observed_rejected_framework="$(
      sed -n 's/^expected_rejected_framework=//p' \
        "$evidence/macos-distribution-e2e/distribution-verdict.txt"
    )"
    if [ "$distribution_verdict" != "expected_framework_signature_failure_reproduced" ] \
      || [ "$observed_rejected_framework" != "$expected_rejected_framework" ] \
      || [ ! -f "$stage_root/distribution-expected-terminal-failure.txt" ]; then
      echo "known-bad distribution E2E did not record the expected framework signature failure" >&2
      macos_scenario_status=1
    fi
  elif [ "$macos_scenario_status" -eq 0 ]; then
    read -r distribution_app < "$stage_root/macos-app-path.txt"
    distribution_bundle_manifest="$evidence/macos-distribution-e2e/extracted-app-files-after-gatekeeper.sha256"
    runtime_bundle_before="$evidence/macos-distribution-e2e/runtime-bundle-before.sha256"
    runtime_bundle_after="$evidence/macos-distribution-e2e/runtime-bundle-after.sha256"
    runtime_chain_verdict="$evidence/macos-distribution-e2e/runtime-chain-verdict.txt"
    runtime_repetitions=1
    if [ "$runtime_empty_final_expectation" != "none" ]; then
      runtime_repetitions="$macos_repetitions"
    fi
    distribution_launched_pid="$(
      sed -n 's/^launched_pid=//p' \
        "$evidence/macos-distribution-e2e/distribution-verdict.txt"
    )"
    write_macos_bundle_manifest "$distribution_app" "$runtime_bundle_before"
    runtime_status=0
    if ! cmp -s "$distribution_bundle_manifest" "$runtime_bundle_before"; then
      diff -u "$distribution_bundle_manifest" "$runtime_bundle_before" \
        > "$evidence/macos-distribution-e2e/distribution-runtime-bundle-before.diff" \
        || true
      runtime_status=1
    else
      set +e
      RUNTIME_E2E_REQUIRE_APP_TRANSLOCATION=true \
      RUNTIME_E2E_EXPECTED_MACOS_VERSION="$macos_expected_version" \
      RUNTIME_E2E_EXPECTED_MACOS_BUILD="$macos_expected_build" \
      RUNTIME_E2E_EXPECTED_FIRST_LAUNCH_PID="$distribution_launched_pid" \
      RUNTIME_E2E_MODEL_CACHE_PATH="$runtime_model_cache_path" \
      RUNTIME_E2E_EMPTY_FINAL_EXPECTATION="$runtime_empty_final_expectation" \
      RUNTIME_E2E_EMPTY_FINAL_BASELINE_EVIDENCE="$runtime_empty_final_baseline_evidence" \
        bash "$(dirname "$0")/run-macos-runtime-e2e.sh" \
        "$distribution_app" \
        "$macos_audio_artifact" \
        "$evidence" \
        "$runtime_repetitions" \
        "smoke" \
        "$runtime_helper_archive"
      runtime_status=$?
      set -e
    fi
    write_macos_bundle_manifest "$distribution_app" "$runtime_bundle_after"
    if ! cmp -s "$runtime_bundle_before" "$runtime_bundle_after"; then
      diff -u "$runtime_bundle_before" "$runtime_bundle_after" \
        > "$evidence/macos-distribution-e2e/runtime-bundle-mutation.diff" \
        || true
      runtime_status=1
    fi
    macos_scenario_status="$runtime_status"

    distribution_executable_sha256="$(
      sed -n 's/^executable_sha256=//p' \
        "$evidence/macos-distribution-e2e/extracted-app-identity.txt"
    )"
    runtime_executable_sha256="$(
      awk 'NR == 1 { print $1 }' "$evidence/voiceink-sha256.txt" 2>/dev/null || true
    )"
    distribution_bundle_manifest_sha256="$(
      shasum -a 256 "$distribution_bundle_manifest" | awk '{print $1}'
    )"
    runtime_bundle_before_sha256="$(
      shasum -a 256 "$runtime_bundle_before" | awk '{print $1}'
    )"
    runtime_bundle_after_sha256="$(
      shasum -a 256 "$runtime_bundle_after" | awk '{print $1}'
    )"
    if [ "$macos_scenario_status" -eq 0 ] \
      && [ -n "$distribution_executable_sha256" ] \
      && [ "$distribution_executable_sha256" = "$runtime_executable_sha256" ] \
      && [ "$distribution_bundle_manifest_sha256" = "$runtime_bundle_before_sha256" ] \
      && [ "$runtime_bundle_before_sha256" = "$runtime_bundle_after_sha256" ]; then
      runtime_transcription_verdict=passed
      if [ "$runtime_empty_final_expectation" = "known-bad" ]; then
        runtime_transcription_verdict=expected_failure_reproduced
      fi
      {
        printf 'runtime_transcription_verdict=%s\n' "$runtime_transcription_verdict"
        printf 'runtime_empty_final_expectation=%s\n' "$runtime_empty_final_expectation"
        printf 'runtime_process=separate_relaunch_of_same_artifact\n'
        printf 'runtime_model_source=first_launch_live_directory\n'
        printf 'runtime_first_launch_pid=%s\n' "$distribution_launched_pid"
        printf 'distribution_executable_sha256=%s\n' "$distribution_executable_sha256"
        printf 'runtime_executable_sha256=%s\n' "$runtime_executable_sha256"
        printf 'distribution_bundle_manifest_sha256=%s\n' "$distribution_bundle_manifest_sha256"
        printf 'runtime_bundle_before_sha256=%s\n' "$runtime_bundle_before_sha256"
        printf 'runtime_bundle_after_sha256=%s\n' "$runtime_bundle_after_sha256"
      } > "$runtime_chain_verdict"
    else
      {
        printf 'runtime_transcription_verdict=failed\n'
        printf 'runtime_empty_final_expectation=%s\n' "$runtime_empty_final_expectation"
        printf 'runtime_process=separate_relaunch_of_same_artifact\n'
        printf 'runtime_model_source=first_launch_live_directory\n'
        printf 'runtime_first_launch_pid=%s\n' "$distribution_launched_pid"
        printf 'runtime_exit_code=%s\n' "$macos_scenario_status"
        printf 'distribution_executable_sha256=%s\n' "$distribution_executable_sha256"
        printf 'runtime_executable_sha256=%s\n' "$runtime_executable_sha256"
        printf 'distribution_bundle_manifest_sha256=%s\n' "$distribution_bundle_manifest_sha256"
        printf 'runtime_bundle_before_sha256=%s\n' "$runtime_bundle_before_sha256"
        printf 'runtime_bundle_after_sha256=%s\n' "$runtime_bundle_after_sha256"
      } > "$runtime_chain_verdict"
      if [ "$macos_scenario_status" -eq 0 ]; then
        macos_scenario_status=1
      fi
    fi

    if [ "$macos_scenario_status" -eq 0 ] \
      && [ "$distribution_expectation" = "fixed-after-framework-signature" ]; then
      distribution_verdict="passed_after_framework_signature_baseline"
      framework_signature_pair_verdict="passed"
      {
        printf 'pair_verdict=passed\n'
        printf 'distribution_verdict=%s\n' "$distribution_verdict"
        printf 'baseline_stage_run_id=%s\n' "$framework_signature_baseline_run_id"
        printf 'baseline_verdict=expected_framework_signature_failure_reproduced\n'
        printf 'candidate_app_run_id=%s\n' "$macos_artifact_run_id"
        printf 'candidate_artifact_id=%s\n' "$macos_artifact_id"
        printf 'candidate_artifact_digest=%s\n' "$macos_artifact_digest"
        printf 'candidate_head_sha=%s\n' "$macos_artifact_head_sha"
        printf 'candidate_launch_and_runtime_smoke=passed\n'
      } > "$evidence/framework-signature-pair-verdict.txt"
    fi
  fi

  # The interaction window was consumed while the distribution scenario ran.
  hold_minutes=0
elif [ "$macos_scenario" != "none" ]; then
  macos_runtime_mode="full"
  if [ "$macos_scenario" = "runtime-smoke" ]; then
    macos_runtime_mode="smoke"
  fi
  set +e
  RUNTIME_E2E_MODEL_CACHE_PATH="$runtime_model_cache_path" \
  RUNTIME_E2E_EMPTY_FINAL_EXPECTATION="$runtime_empty_final_expectation" \
  RUNTIME_E2E_EMPTY_FINAL_BASELINE_EVIDENCE="$runtime_empty_final_baseline_evidence" \
    bash "$(dirname "$0")/run-macos-runtime-e2e.sh" \
    "/Applications/roma just talk.app" \
    "$macos_audio_artifact" \
    "$evidence" \
    "$macos_repetitions" \
    "$macos_runtime_mode" \
    "$runtime_helper_archive"
  macos_scenario_status=$?
  set -e
fi

if [ "$ios_scenario" = "local-whisper-import" ]; then
  set +e
  bash "$(dirname "$0")/run-ios-remote-stt-e2e.sh" \
    "$simulator_udid" \
    "$evidence"
  ios_scenario_status=$?
  set -e
fi

if [ "$macos_scenario_status" -ne 0 ] || [ "$ios_scenario_status" -ne 0 ]; then
  scenario_summary="A scripted scenario failed. Inspect the uploaded evidence before assigning ownership."
elif [ "$macos_scenario" = "none" ] && [ "$ios_scenario" = "none" ]; then
  scenario_summary="No scripted scenario ran."
else
  scenario_summary="The requested scripted scenario completed successfully."
fi

cat > "$desktop/REMOTE E2E STAGE READY.txt" <<EOF
roma just talk remote E2E stage

Target: $target
macOS scenario: $macos_scenario
iOS scenario: $ios_scenario
GitHub run: ${GITHUB_RUN_ID:-local}
Stage root: $stage_root

$scenario_summary
The desktop is ready for manual VNC or Computer Use interaction during the remaining hold.

To finish early, double-click:
Finish Remote E2E Stage.command
EOF

cat > "$desktop/Finish Remote E2E Stage.command" <<EOF
#!/usr/bin/env bash
touch "$done_file"
EOF
chmod +x "$desktop/Finish Remote E2E Stage.command"
ln -sfn "$stage_root" "$desktop/Remote E2E Stage"

if [ "$macos_scenario_status" -eq 0 ] && [ "$ios_scenario_status" -eq 0 ]; then
  write_manifest ready
else
  write_manifest scenario-failed
fi

touch "$ready_file"
capture_desktop ready
if [ -n "$simulator_udid" ]; then
  xcrun simctl io "$simulator_udid" screenshot "$evidence/ios-ready.png" 2>/dev/null || true
fi

echo "REMOTE E2E STAGE READY"
echo "Open Namespace dashboard -> this GitHub job -> Remote Display."
echo "Target: $target"
echo "macOS scenario: $macos_scenario (exit $macos_scenario_status)"
echo "iOS scenario: $ios_scenario (exit $ios_scenario_status)"
echo "Hold: $hold_minutes minutes"
echo "Finish early: double-click Finish Remote E2E Stage.command on the remote desktop."

deadline=$((SECONDS + hold_minutes * 60))
while (( SECONDS < deadline )) && [ ! -f "$done_file" ]; do
  remaining=$(((deadline - SECONDS + 59) / 60))
  echo "Stage alive; about $remaining minute(s) remaining."
  sleep 30
done

capture_desktop final
if [ -n "$simulator_udid" ]; then
  xcrun simctl io "$simulator_udid" screenshot "$evidence/ios-final.png" 2>/dev/null || true
fi
xcodebuild -version > "$evidence/xcode-version.txt"
sw_vers > "$evidence/macos-version.txt"
xcrun simctl list devices > "$evidence/simulator-devices.txt"

if [ -f "$done_file" ]; then
  echo "Remote E2E stage finished early."
else
  echo "Remote E2E stage hold expired."
fi

if [ "$macos_scenario_status" -eq 0 ] && [ "$ios_scenario_status" -eq 0 ]; then
  write_manifest completed
else
  write_manifest scenario-failed
fi

if [ "$macos_scenario_status" -ne 0 ]; then
  exit "$macos_scenario_status"
fi
if [ "$ios_scenario_status" -ne 0 ]; then
  exit "$ios_scenario_status"
fi
