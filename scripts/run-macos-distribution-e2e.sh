#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 || $# -gt 7 ]]; then
  echo "usage: $0 <github-actions-download-zip> <expected-inner-app-zip> <evidence-directory> <stage-directory> [expected-macos-version] [expected-macos-build] [interaction-minutes]" >&2
  exit 2
fi

archive="$1"
expected_inner_archive="$2"
evidence="${3%/}"
stage_root="${4%/}"
expected_macos_version="${5:-}"
expected_macos_build="${6:-}"
interaction_minutes="${7:-30}"
github_download_token="${GH_TOKEN:-}"
distribution_expectation="${DISTRIBUTION_E2E_EXPECTATION:-fixed}"
expected_rejected_framework="${DISTRIBUTION_E2E_EXPECTED_REJECTED_FRAMEWORK:-}"
expected_main_uuid="${DISTRIBUTION_E2E_EXPECTED_MAIN_UUID:-}"
expected_rejected_framework_uuid="${DISTRIBUTION_E2E_EXPECTED_REJECTED_FRAMEWORK_UUID:-}"
source_main_uuid=""
source_rejected_framework_uuid=""
reported_crash_pid=""
operator_credential_file="${DISTRIBUTION_E2E_OPERATOR_CREDENTIAL_FILE:-}"
unset GH_TOKEN

if [[ ! "$interaction_minutes" =~ ^[0-9]+$ ]] || (( interaction_minutes < 1 || interaction_minutes > 60 )); then
  echo "Distribution E2E interaction minutes must be between 1 and 60" >&2
  exit 2
fi
case "$distribution_expectation" in
  fixed|known-bad-framework-signature) ;;
  *)
    echo "Unsupported distribution E2E expectation: $distribution_expectation" >&2
    exit 2
    ;;
esac
if [[ "$distribution_expectation" == known-bad-framework-signature ]]; then
  case "$expected_rejected_framework" in
    whisper|MediaRemoteAdapter) ;;
    *)
      echo "Known-bad framework signature proof requires whisper or MediaRemoteAdapter" >&2
      exit 2
      ;;
  esac
  for expected_uuid in "$expected_main_uuid" "$expected_rejected_framework_uuid"; do
    [[ "$expected_uuid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] \
      || { echo "Known-bad framework signature proof requires source UUID inputs" >&2; exit 2; }
  done
fi
if [[ -n "$operator_credential_file" ]]; then
  [[ -f "$operator_credential_file" ]] \
    || { echo "Distribution E2E operator credential file is missing" >&2; exit 2; }
  [[ "$(stat -f '%Lp' "$operator_credential_file")" == 600 ]] \
    || { echo "Distribution E2E operator credential file must be mode 600" >&2; exit 2; }
fi

repo_root="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.." && pwd)}"
verifier="$repo_root/scripts/verify-macos-distribution-launch.sh"
finder_extraction_classifier="$repo_root/scripts/macos-finder-extraction-state.sh"
source "$repo_root/scripts/macos-bundle-manifest.sh"
distribution_root="$stage_root/macos-distribution-e2e"
distribution_evidence="$evidence/macos-distribution-e2e"
desktop="$HOME/Desktop"
instructions="$desktop/GATEKEEPER ACTION REQUIRED.txt"
phase_file="$distribution_evidence/distribution-phase.txt"
verdict_file="$distribution_evidence/distribution-verdict.txt"
finder_extraction_confirmation="$distribution_root/finder-extraction-confirmed.txt"
finder_followup_confirmation="$distribution_root/finder-followup-extraction-confirmed.txt"
gatekeeper_confirmation="$distribution_root/gatekeeper-not-opened-confirmed.txt"
readiness_confirmation="$distribution_root/first-launch-ui-confirmed.txt"
finder_extraction_confirmation_command="$desktop/Confirm Finder Extraction Complete.command"
finder_followup_confirmation_command="$desktop/Confirm Finder Follow-up Extraction.command"
gatekeeper_confirmation_command="$desktop/Confirm Gatekeeper Not Opened.command"
readiness_confirmation_command="$desktop/Confirm Roma First Launch Ready.command"
disk_image="$distribution_root/roma-distribution-e2e.dmg"
reference_root="$distribution_root/expected-inner-reference"
volume_name="Roma Distribution E2E"
download_name="$(basename "$archive")"
app_name="roma just talk.app"
process_name="roma just talk"
bundle_identifier="com.negentropi.RomaJustTalk"
live_model_directory="$HOME/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2"
approval_process_monitor_pid=""
approval_log_pid=""
approval_stop_file="$distribution_root/approval-window-stop"
approval_first_pid_file="$distribution_root/approval-window-first-pid.txt"
approval_process_events="$distribution_evidence/approval-window-process-events.txt"
approval_log="$distribution_evidence/approval-window-unified-log.txt"

mkdir -p "$distribution_root" "$distribution_evidence" "$desktop"

mark_phase() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" | tee -a "$phase_file"
}

capture_failure_state() {
  ps -axo pid,ppid,state,etime,command \
    > "$distribution_evidence/processes-at-failure.txt" 2>&1 || true
  /usr/bin/log show --last 30m --style compact \
    --predicate 'process == "roma just talk" OR process == "syspolicyd" OR process == "CoreServicesUIAgent" OR process == "Archive Utility" OR process == "Finder" OR process == "Safari"' \
    > "$distribution_evidence/distribution-failure-unified-log.txt" 2>&1 || true

  if [[ -n "${extracted_app:-}" && -d "${extracted_app:-}" ]]; then
    xattr -lr "$extracted_app" \
      > "$distribution_evidence/extracted-app-xattrs-at-failure.txt" 2>&1 || true
    codesign --verify --deep --strict --verbose=4 "$extracted_app" \
      > "$distribution_evidence/extracted-app-codesign-at-failure.txt" 2>&1 || true
  fi

  crash_reports="$distribution_evidence/crash-reports"
  mkdir -p "$crash_reports"
  while IFS= read -r report; do
    cp "$report" "$crash_reports/" 2>/dev/null || true
  done < <(
    find "$HOME/Library/Logs/DiagnosticReports" -type f \
      \( -name 'roma just talk*.ips' -o -name 'roma just talk*.crash' \) \
      -mtime -1 -print 2>/dev/null
  )
}

fail() {
  local message="$1"
  {
    printf 'distribution_verdict=failed\n'
    printf 'failure=%s\n' "$message"
  } > "$verdict_file"
  capture_failure_state
  echo "$message" >&2
  exit 1
}

stop_approval_monitors() {
  touch "$approval_stop_file" 2>/dev/null || true
  if [[ -n "$approval_process_monitor_pid" ]]; then
    kill "$approval_process_monitor_pid" 2>/dev/null || true
    wait "$approval_process_monitor_pid" 2>/dev/null || true
    approval_process_monitor_pid=""
  fi
  if [[ -n "$approval_log_pid" ]]; then
    kill "$approval_log_pid" 2>/dev/null || true
    wait "$approval_log_pid" 2>/dev/null || true
    approval_log_pid=""
  fi
}

cleanup_background_processes() {
  stop_approval_monitors
}
trap cleanup_background_processes EXIT

write_confirmation_command() {
  local command_path="$1"
  local confirmation_path="$2"
  cat > "$command_path" <<EOF
#!/usr/bin/env bash
/bin/date -u +%Y-%m-%dT%H:%M:%SZ > "$confirmation_path"
EOF
  chmod +x "$command_path"
}

wait_for_path() {
  local path="$1"
  local description="$2"
  local deadline="$3"
  while (( SECONDS < deadline )); do
    if [[ -e "$path" ]]; then
      return 0
    fi
    sleep 2
  done
  fail "timed out waiting for $description: $path"
}

state_value() {
  local state_file="$1"
  local key="$2"
  awk -F '\t' -v key="$key" '$1 == key { sub(/^[^\t]*\t/, ""); print; exit }' \
    "$state_file"
}

resolve_github_artifact_download_url() {
  local artifact_id="${MACOS_ARTIFACT_ID:-}"
  local repository="${MACOS_ARTIFACT_REPOSITORY:-}"
  local api_endpoint=""
  local response_headers=""
  local response_status=""
  local redirect_url=""
  local redirect_host=""

  [[ "$artifact_id" =~ ^[0-9]+$ ]] \
    || fail "distribution E2E requires the selected GitHub artifact ID"
  [[ "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
    || fail "distribution E2E requires the selected GitHub repository"
  [[ -n "$github_download_token" ]] \
    || fail "distribution E2E requires a GitHub token for the browser download"

  api_endpoint="https://api.github.com/repos/$repository/actions/artifacts/$artifact_id/zip"
  if ! response_headers="$(
    curl --fail --silent --show-error \
      --dump-header - \
      --output /dev/null \
      --header "Authorization: Bearer $github_download_token" \
      --header "Accept: application/vnd.github+json" \
      --header "X-GitHub-Api-Version: 2022-11-28" \
      "$api_endpoint"
  )"; then
    fail "GitHub did not issue a browser download for artifact $artifact_id"
  fi
  response_status="$(
    printf '%s\n' "$response_headers" \
      | awk '/^HTTP\// { status = $2 } END { print status }'
  )"
  redirect_url="$(
    printf '%s\n' "$response_headers" \
      | awk '
          tolower($1) == "location:" {
            sub(/^[^:]*:[[:space:]]*/, "")
            sub(/\r$/, "")
            location = $0
          }
          END { print location }
        '
  )"
  unset response_headers
  [[ "$response_status" =~ ^30(2|3|7|8)$ ]] \
    || fail "GitHub artifact endpoint returned HTTP ${response_status:-unknown}, not a download redirect"
  case "$redirect_url" in
    https://*) ;;
    *) fail "GitHub artifact endpoint did not return an HTTPS download redirect" ;;
  esac
  redirect_host="$(
    DISTRIBUTION_E2E_DOWNLOAD_URL="$redirect_url" \
      ruby -ruri -e '
        uri = URI.parse(ENV.fetch("DISTRIBUTION_E2E_DOWNLOAD_URL"))
        abort unless uri.scheme == "https" && uri.host && !uri.host.empty?
        puts uri.host
      '
  )" || fail "could not validate the GitHub artifact download host"
  {
    printf 'artifact_id=%s\n' "$artifact_id"
    printf 'repository=%s\n' "$repository"
    printf 'artifact_api_endpoint=%s\n' "$api_endpoint"
    printf 'redirect_http_status=%s\n' "$response_status"
    printf 'redirect_host=%s\n' "$redirect_host"
    printf 'redirect_url_recorded=false\n'
  } > "$distribution_evidence/browser-download-origin.txt"
  printf '%s\n' "$redirect_url"
}

wait_for_matching_browser_download() {
  local wait_deadline="$1"
  local candidate=""
  local candidate_sha=""
  while (( SECONDS < wait_deadline )); do
    while IFS= read -r candidate; do
      [[ -f "$candidate" ]] || continue
      [[ "$(stat -f '%z' "$candidate" 2>/dev/null || true)" == "$source_size" ]] \
        || continue
      candidate_sha="$(shasum -a 256 "$candidate" 2>/dev/null | awk '{print $1}')"
      if [[ "$candidate_sha" == "$source_sha256" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done < <(find "$volume" -maxdepth 1 -type f -name '*.zip' -print 2>/dev/null)
    sleep 2
  done
  return 1
}

write_roma_crash_report_inventory() {
  local output="$1"
  local crash_root="$HOME/Library/Logs/DiagnosticReports"
  : > "$output"
  [[ -d "$crash_root" ]] || return 0
  find "$crash_root" -type f \
    \( -name 'roma just talk*.ips' -o -name 'roma just talk*.crash' \) \
    -print 2>/dev/null \
    | LC_ALL=C sort \
    > "$output"
}

monitor_roma_processes() {
  local seen=$'\n'
  local candidate_pid=""
  local process_details=""

  while [[ ! -e "$approval_stop_file" ]]; do
    while IFS= read -r candidate_pid; do
      [[ "$candidate_pid" =~ ^[0-9]+$ ]] || continue
      if [[ "$seen" == *$'\n'"$candidate_pid"$'\n'* ]]; then
        continue
      fi
      seen+="$candidate_pid"$'\n'
      process_details="$(
        ps -p "$candidate_pid" -o lstart= -o state= -o command= 2>/dev/null \
          || true
      )"
      printf '%s\t%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$candidate_pid" \
        "$process_details" \
        >> "$approval_process_events"
      if [[ ! -e "$approval_first_pid_file" ]]; then
        printf '%s\n' "$candidate_pid" > "$approval_first_pid_file"
      fi
    done < <(pgrep -x "$process_name" 2>/dev/null | LC_ALL=C sort -n || true)
    sleep 0.05
  done
}

start_approval_monitors() {
  rm -f "$approval_stop_file" "$approval_first_pid_file"
  : > "$approval_process_events"
  write_roma_crash_report_inventory \
    "$distribution_evidence/approval-window-crash-reports-before.txt"
  date -u +%Y-%m-%dT%H:%M:%SZ \
    > "$distribution_evidence/approval-window-started-at.txt"

  /usr/bin/log stream --style compact \
    --predicate 'process == "roma just talk" OR eventMessage CONTAINS[c] "com.negentropi.RomaJustTalk" OR eventMessage CONTAINS[c] "/roma just talk.app/"' \
    > "$approval_log" 2>&1 &
  approval_log_pid=$!
  monitor_roma_processes &
  approval_process_monitor_pid=$!
  sleep 1
  kill -0 "$approval_log_pid" 2>/dev/null \
    || fail "could not start approval-window unified-log monitor"
  kill -0 "$approval_process_monitor_pid" 2>/dev/null \
    || fail "could not start approval-window Roma process monitor"
}

wait_for_first_approval_pid() {
  local deadline="$1"
  while (( SECONDS < deadline )); do
    if [[ -s "$approval_first_pid_file" ]]; then
      cat "$approval_first_pid_file"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_for_pid_exit() {
  local pid="$1"
  local deadline="$2"
  while (( SECONDS < deadline )); do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

write_approval_window_crash_report_details() {
  local report=""
  while IFS= read -r report; do
    [[ -n "$report" && -f "$report" ]] || continue
    cp "$report" "$distribution_evidence/approval-window-dyld-report.ips"
    return 0
  done < "$distribution_evidence/approval-window-new-crash-reports.txt"
  return 1
}

wait_for_new_approval_window_crash_report() {
  local deadline="$1"
  local report_count=""
  local report_grace_deadline=0
  local report_path=""
  local report_sha_before=""
  local report_sha_after=""
  while (( SECONDS < deadline )); do
    write_roma_crash_report_inventory \
      "$distribution_evidence/approval-window-crash-reports-after.txt"
    comm -13 \
      "$distribution_evidence/approval-window-crash-reports-before.txt" \
      "$distribution_evidence/approval-window-crash-reports-after.txt" \
      > "$distribution_evidence/approval-window-new-crash-reports.txt"
    report_count="$(awk 'NF { count++ } END { print count + 0 }' \
      "$distribution_evidence/approval-window-new-crash-reports.txt")"
    # Gatekeeper creates a suspended PID before administrator authentication.
    # Only a report starts the completion grace period; approval uses the full deadline.
    if [[ "$report_count" -eq 1 ]]; then
      if (( report_grace_deadline == 0 )); then
        report_grace_deadline=$((SECONDS + 30))
      fi
      report_path="$(sed -n '1p' "$distribution_evidence/approval-window-new-crash-reports.txt")"
      if [[ -f "$report_path" ]]; then
        report_sha_before="$(shasum -a 256 "$report_path" | awk '{ print $1 }')"
        sleep 1
        report_sha_after="$(shasum -a 256 "$report_path" | awk '{ print $1 }')"
        if [[ "$report_sha_before" == "$report_sha_after" ]]; then
          cp "$report_path" "$distribution_evidence/approval-window-dyld-report.ips"
          if report_matches_expected_framework_signature_failure; then
            return 0
          fi
        fi
      fi
    fi
    if [[ "$report_count" -gt 1 ]]; then
      return 1
    fi
    if [[ -s "$distribution_evidence/approval-window-new-crash-reports.txt" ]]; then
      write_approval_window_crash_report_details
    fi
    if (( report_grace_deadline > 0 && SECONDS >= report_grace_deadline )); then
      return 1
    fi
    sleep 0.2
  done
  return 1
}

report_matches_expected_framework_signature_failure() {
  local report="$distribution_evidence/approval-window-dyld-report.ips"
  local approval_window_start_utc="$(cat "$distribution_evidence/approval-window-started-at.txt")"
  "$repo_root/scripts/verify-macos-framework-signature-crash.sh" \
    "$report" \
    "$bundle_identifier" \
    "$actual_macos_version" \
    "$actual_macos_build" \
    "$source_main_uuid" \
    "$expected_rejected_framework" \
    "$source_rejected_framework_uuid" \
    "$approval_window_start_utc" \
    "$extracted_app_short_version" \
    "$extracted_app_bundle_version" \
    > "$distribution_evidence/approval-window-dyld-match.txt"
}

validate_known_bad_approval_pid() {
  local sampled_pid=""
  local sampled_count=0
  reported_crash_pid="$(
    sed -n 's/^verdict=matched pid=\([1-9][0-9]*\) .*/\1/p' \
      "$distribution_evidence/approval-window-dyld-match.txt"
  )"
  [[ "$reported_crash_pid" =~ ^[1-9][0-9]*$ ]] \
    || fail "framework signature crash verifier did not report a launch PID"

  while IFS= read -r sampled_pid; do
    [[ -n "$sampled_pid" ]] || continue
    sampled_count=$((sampled_count + 1))
    [[ "$sampled_pid" == "$reported_crash_pid" ]] \
      || fail "approval monitor observed Roma PID $sampled_pid, not crash-report PID $reported_crash_pid"
  done < <(awk -F '\t' 'NF >= 2 && $2 ~ /^[1-9][0-9]*$/ { print $2 }' \
    "$approval_process_events" | LC_ALL=C sort -u)

  if ! wait_for_pid_exit "$reported_crash_pid" "$((SECONDS + 2))"; then
    fail "known-bad crash-report PID is still alive after its dyld abort"
  fi
  if pgrep -x "$process_name" >/dev/null 2>&1; then
    fail "Roma process remains after the expected framework-signature dyld abort"
  fi
  {
    printf 'report_pid=%s\n' "$reported_crash_pid"
    printf 'sampled_approval_pid_count=%s\n' "$sampled_count"
    printf 'report_pid_dead=true\n'
    printf 'running_roma_processes=0\n'
  } > "$distribution_evidence/approval-window-dyld-pid-correlation.txt"
}

read_arm64_uuid() {
  local binary="$1"
  xcrun dwarfdump --uuid "$binary" \
    | awk '/\(arm64\)/ { print toupper($2); exit }'
}

require_expected_framework_signature_failure() {
  local report_count=""
  wait_for_new_approval_window_crash_report "$deadline" \
    || fail "expected approved dyld abort did not create one complete Roma crash report"
  sleep 2
  write_roma_crash_report_inventory \
    "$distribution_evidence/approval-window-crash-reports-after.txt"
  comm -13 \
    "$distribution_evidence/approval-window-crash-reports-before.txt" \
    "$distribution_evidence/approval-window-crash-reports-after.txt" \
    > "$distribution_evidence/approval-window-new-crash-reports.txt"
  stop_approval_monitors
  report_count="$(awk 'NF { count++ } END { print count + 0 }' \
    "$distribution_evidence/approval-window-new-crash-reports.txt")"
  if [[ "$report_count" -ne 1 ]]; then
    fail "known-bad approval must create exactly one Roma dyld crash report"
  fi
  write_approval_window_crash_report_details
  if ! report_matches_expected_framework_signature_failure; then
    fail "approved launch did not reproduce the expected framework signature dyld failure"
  fi
  validate_known_bad_approval_pid
}

version_is_at_least() {
  local actual="$1"
  local minimum="$2"
  awk -v actual="$actual" -v minimum="$minimum" '
    BEGIN {
      actual_count = split(actual, actual_parts, ".")
      minimum_count = split(minimum, minimum_parts, ".")
      count = actual_count > minimum_count ? actual_count : minimum_count
      for (part_index = 1; part_index <= count; part_index++) {
        actual_part = actual_parts[part_index] + 0
        minimum_part = minimum_parts[part_index] + 0
        if (actual_part > minimum_part) exit 0
        if (actual_part < minimum_part) exit 1
      }
      exit 0
    }
  '
}

capture_tcc_rows() {
  local database="$1"
  local output="$2"
  local scope="$3"
  local row_count="0"
  local rows=""
  local query="select service,client,client_type,auth_value,auth_reason,last_modified from access where client='$bundle_identifier' order by service;"
  local count_query="select count(*) from access where client='$bundle_identifier';"
  local sqlite_command=(sqlite3)

  if [[ "$scope" == "system" ]]; then
    sqlite_command=(sudo sqlite3)
  fi
  if [[ -f "$database" ]]; then
    if ! row_count="$("${sqlite_command[@]}" "$database" "$count_query")"; then
      fail "could not inspect the $scope TCC database"
    fi
    if ! rows="$("${sqlite_command[@]}" -header -column "$database" "$query")"; then
      fail "could not capture the $scope TCC rows"
    fi
  fi
  [[ "$row_count" =~ ^[0-9]+$ ]] \
    || fail "invalid $scope TCC row count: $row_count"
  {
    printf 'database=%s\n' "$database"
    printf 'database_present=%s\n' "$([[ -f "$database" ]] && echo true || echo false)"
    printf 'row_count=%s\n' "$row_count"
    if [[ -n "$rows" ]]; then
      printf '%s\n' "$rows"
    fi
  } > "$output"
  [[ "$row_count" -eq 0 ]] \
    || fail "fresh-Mac precondition failed: Roma already has $scope TCC state"
}

test -f "$archive" || fail "GitHub Actions archive is missing: $archive"
test -f "$expected_inner_archive" \
  || fail "unwrapped app archive is missing: $expected_inner_archive"
test -x "$verifier" || fail "distribution launch verifier is missing: $verifier"
test -x "$finder_extraction_classifier" \
  || fail "Finder extraction classifier is missing: $finder_extraction_classifier"
[[ "$(uname -s)" == "Darwin" ]] || fail "distribution E2E requires macOS"
[[ "$(uname -m)" == "arm64" ]] || fail "distribution E2E requires Apple Silicon"
[[ -n "$expected_macos_version" && -n "$expected_macos_build" ]] \
  || fail "distribution E2E requires exact macOS product and build versions"
[[ "$expected_macos_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
  || fail "invalid expected macOS product version: $expected_macos_version"
[[ "$expected_macos_build" =~ ^[0-9A-Za-z]+$ ]] \
  || fail "invalid expected macOS build version: $expected_macos_build"

actual_macos_version="$(sw_vers -productVersion)"
actual_macos_build="$(sw_vers -buildVersion)"
{
  sw_vers
  uname -a
  printf 'architecture=%s\n' "$(uname -m)"
  printf 'expected_product_version=%s\n' "${expected_macos_version:-not-enforced}"
  printf 'expected_build_version=%s\n' "${expected_macos_build:-not-enforced}"
} > "$distribution_evidence/runner-identity.txt"
if [[ -n "$expected_macos_version" && "$actual_macos_version" != "$expected_macos_version" ]]; then
  fail "expected macOS $expected_macos_version, got $actual_macos_version"
fi
if [[ "$actual_macos_build" != "$expected_macos_build" ]]; then
  fail "expected macOS build $expected_macos_build, got $actual_macos_build"
fi

if pgrep -x "$process_name" >/dev/null 2>&1; then
  fail "fresh-Mac precondition failed: roma just talk is already running"
fi
if defaults read com.negentropi.RomaJustTalk \
  > "$distribution_evidence/preexisting-defaults.txt" 2>&1; then
  fail "fresh-Mac precondition failed: Roma preferences already exist"
fi
if [[ -e "$HOME/Applications/$app_name" || -e "/Applications/$app_name" ]]; then
  fail "fresh-Mac precondition failed: Roma is already installed"
fi
if [[ -e "$HOME/Library/Application Support/FluidAudio/Models" \
  || -L "$HOME/Library/Application Support/FluidAudio/Models" ]]; then
  fail "fresh-Mac precondition failed: Roma model state already exists"
fi
printf 'fluid_audio_models=absent\n' \
  > "$distribution_evidence/fresh-model-state.txt"
command -v sqlite3 >/dev/null \
  || fail "sqlite3 is required to inspect fresh-Mac TCC state"
capture_tcc_rows \
  "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
  "$distribution_evidence/fresh-tcc-user.txt" \
  user
capture_tcc_rows \
  "/Library/Application Support/com.apple.TCC/TCC.db" \
  "$distribution_evidence/fresh-tcc-system.txt" \
  system
if ! spctl --status > "$distribution_evidence/gatekeeper-status.txt" 2>&1; then
  fail "could not inspect Gatekeeper status"
fi
if ! grep -Fq 'assessments enabled' "$distribution_evidence/gatekeeper-status.txt"; then
  fail "Gatekeeper assessments are not enabled"
fi

source_sha256="$(shasum -a 256 "$archive" | awk '{print $1}')"
source_size="$(stat -f '%z' "$archive")"
expected_inner_sha256="$(shasum -a 256 "$expected_inner_archive" | awk '{print $1}')"
artifact_digest="${MACOS_ARTIFACT_DIGEST:-}"
[[ "$artifact_digest" =~ ^sha256:[0-9a-f]{64}$ ]] \
  || fail "distribution E2E requires the GitHub artifact digest"
[[ "sha256:$source_sha256" == "$artifact_digest" ]] \
  || fail "downloaded GitHub Actions archive does not match its artifact digest"
{
  printf 'github_actions_archive=%s\n' "$archive"
  printf 'github_actions_archive_sha256=%s\n' "$source_sha256"
  printf 'github_actions_archive_size=%s\n' "$source_size"
  printf 'expected_inner_archive=%s\n' "$expected_inner_archive"
  printf 'expected_inner_archive_sha256=%s\n' "$expected_inner_sha256"
  printf 'github_artifact_run_id=%s\n' "${MACOS_ARTIFACT_RUN_ID:-unknown}"
  printf 'github_artifact_id=%s\n' "${MACOS_ARTIFACT_ID:-unknown}"
  printf 'github_artifact_digest=%s\n' "$artifact_digest"
} > "$distribution_evidence/source-artifact.txt"

mark_phase prepare-expected-inner-reference
[[ ! -e "$reference_root" ]] \
  || fail "expected inner reference already exists: $reference_root"
mkdir -p "$reference_root"
if ! ditto -x -k "$expected_inner_archive" "$reference_root"; then
  fail "could not extract the hash-verified inner ZIP for reference"
fi
reference_app="$reference_root/$app_name"
[[ -f "$reference_app/Contents/Info.plist" ]] \
  || fail "hash-verified inner ZIP does not contain the expected app"
codesign --verify --deep --strict --verbose=4 "$reference_app" \
  > "$distribution_evidence/expected-inner-app-codesign.txt" 2>&1 \
  || fail "app inside the hash-verified inner ZIP fails strict deep signature verification"
write_macos_bundle_manifest \
  "$reference_app" \
  "$distribution_evidence/expected-inner-app-files.sha256"

mark_phase create-external-volume
[[ ! -e "$disk_image" ]] || fail "distribution disk image already exists: $disk_image"
hdiutil create -quiet -size 2g -fs APFS -volname "$volume_name" "$disk_image"
if ! hdiutil attach -nobrowse -plist "$disk_image" \
  > "$distribution_evidence/hdiutil-attach.plist"; then
  fail "could not attach the distribution disk image"
fi
volume="$({
  plutil -convert json -o - "$distribution_evidence/hdiutil-attach.plist" \
    | ruby -rjson -e '
      entities = JSON.parse(STDIN.read).fetch("system-entities")
      puts entities.map { |item| item["mount-point"] }.compact.first
    '
} 2>/dev/null || true)"
[[ -n "$volume" && -d "$volume" ]] || fail "could not resolve the external volume mount point"
diskutil info "$volume" > "$distribution_evidence/external-volume.txt"
grep -Fq 'APFS' "$distribution_evidence/external-volume.txt" \
  || fail "distribution volume is not APFS"
printf '%s\n' "$volume" > "$distribution_root/volume-path.txt"

downloaded_archive="$volume/$download_name"
deadline=$((SECONDS + interaction_minutes * 60))

mark_phase browser-download
defaults write com.apple.Safari DownloadsPath -string "$volume"
defaults write com.apple.Safari AutoOpenSafeDownloads -bool false
download_url="$(resolve_github_artifact_download_url)"
github_download_token=""

cat > "$instructions" <<EOF
roma just talk distribution E2E

Current step: browser download

Safari is downloading the selected artifact from GitHub Actions to an APFS volume.
If Safari asks whether GitHub's download host may download files, click Allow.

Do not copy the ZIP, clear quarantine, re-sign anything, or move the app.
This window will update for the Finder and Gatekeeper steps.
EOF
ln -sfn "$stage_root" "$desktop/Remote E2E Stage"
touch "$stage_root/READY"
echo "DISTRIBUTION E2E BROWSER ACTION REQUIRED"
echo "Open Remote Display and allow Safari's GitHub artifact download if prompted."
DISTRIBUTION_E2E_DOWNLOAD_URL="$download_url" \
  /usr/bin/osascript <<'APPLESCRIPT' \
    > "$distribution_evidence/safari-artifact-download.stdout.txt" \
    2> "$distribution_evidence/safari-artifact-download.stderr.txt"
set artifactURL to system attribute "DISTRIBUTION_E2E_DOWNLOAD_URL"
tell application "Safari"
  activate
  open location artifactURL
end tell
APPLESCRIPT
unset download_url
if ! downloaded_archive="$(wait_for_matching_browser_download "$deadline")"; then
  fail "timed out waiting for Safari to download the exact GitHub Actions artifact"
fi
download_name="$(basename "$downloaded_archive")"

downloaded_sha256="$(shasum -a 256 "$downloaded_archive" | awk '{print $1}')"
[[ "$downloaded_sha256" == "$source_sha256" ]] \
  || fail "Safari download does not match the GitHub Actions archive"
if ! archive_quarantine="$(xattr -p com.apple.quarantine "$downloaded_archive" 2>/dev/null)"; then
  fail "Safari download is missing quarantine"
fi
printf '%s\n' "$archive_quarantine" > "$distribution_evidence/downloaded-archive-quarantine.txt"
IFS=';' read -r _ _ archive_quarantine_agent _ <<< "$archive_quarantine"
[[ "$archive_quarantine_agent" == "Safari" ]] \
  || fail "expected Safari quarantine, got ${archive_quarantine_agent:-missing agent}"
{
  printf 'downloaded_archive=%s\n' "$downloaded_archive"
  printf 'downloaded_sha256=%s\n' "$downloaded_sha256"
  printf 'downloaded_size=%s\n' "$(stat -f '%z' "$downloaded_archive")"
} > "$distribution_evidence/browser-downloaded-artifact.txt"
mdls \
  -name kMDItemFSName \
  -name kMDItemContentType \
  -name kMDItemFSCreationDate \
  "$downloaded_archive" \
  > "$distribution_evidence/browser-downloaded-metadata.txt" 2>&1 || true

mark_phase finder-actions-artifact-extraction
[[ ! -e "$finder_extraction_confirmation" ]] \
  || fail "Finder extraction confirmation already exists"
write_confirmation_command \
  "$finder_extraction_confirmation_command" \
  "$finder_extraction_confirmation"
defaults read com.apple.archiveutility \
  > "$distribution_evidence/archive-utility-defaults-before.txt" 2>&1 \
  || true
if find "$volume" -type d -name "$app_name" -prune -print -quit 2>/dev/null \
  | grep -q .; then
  fail "fresh distribution volume already contains Roma before Finder extraction"
fi
cat > "$instructions" <<EOF
roma just talk distribution E2E

Current step: Finder and Archive Utility extraction

In the open Finder window, double-click:
$download_name

This is the outer ZIP supplied by GitHub Actions. Wait until Archive Utility
finishes and either "$app_name" or another app ZIP appears. Some macOS versions
recursively extract the nested ZIP in this one action. Then double-click:

Confirm Finder Extraction Complete.command

Run that confirmation only after Archive Utility finishes. Do not open a nested
ZIP yet. Do not use Terminal, move the app, clear quarantine, or re-sign it.
EOF
echo "DISTRIBUTION E2E FINDER ACTION REQUIRED"
echo "In Finder, double-click the outer GitHub Actions ZIP: $download_name."
open -a Finder "$volume"
wait_for_path \
  "$finder_extraction_confirmation" \
  "operator confirmation that Finder and Archive Utility finished" \
  "$deadline"
cp "$finder_extraction_confirmation" \
  "$distribution_evidence/finder-extraction-human-confirmation.txt"
ps -axo pid,ppid,state,lstart,command \
  > "$distribution_evidence/processes-after-finder-extraction.txt" 2>&1 \
  || true

finder_state_file="$distribution_root/finder-extraction-state.tsv"
finder_state_deadline=$((SECONDS + 60))
if (( finder_state_deadline > deadline )); then
  finder_state_deadline="$deadline"
fi
separate_state_first_seen=-1
recursive_state_first_seen=-1
while true; do
  "$finder_extraction_classifier" \
    "$volume" \
    "$downloaded_archive" \
    "$expected_inner_sha256" \
    "$app_name" \
    > "$finder_state_file" \
    || fail "could not classify Finder extraction output"
  finder_state="$(state_value "$finder_state_file" state)"
  case "$finder_state" in
    recursive)
      if (( recursive_state_first_seen < 0 )); then
        recursive_state_first_seen="$SECONDS"
      fi
      if (( SECONDS - recursive_state_first_seen >= 4 )) \
        && ! pgrep -x "Archive Utility" >/dev/null 2>&1; then
        break
      fi
      if (( SECONDS >= finder_state_deadline )); then
        fail "Archive Utility did not stabilize the recursively extracted app"
      fi
      sleep 2
      ;;
    separate)
      recursive_state_first_seen=-1
      if (( separate_state_first_seen < 0 )); then
        separate_state_first_seen="$SECONDS"
      fi
      if (( SECONDS - separate_state_first_seen >= 4 )) \
        && ! pgrep -x "Archive Utility" >/dev/null 2>&1; then
        break
      fi
      if (( SECONDS >= finder_state_deadline )); then
        fail "Archive Utility did not finish after exposing the exact inner ZIP"
      fi
      sleep 2
      ;;
    invalid)
      recursive_state_first_seen=-1
      separate_state_first_seen=-1
      cp "$finder_state_file" \
        "$distribution_evidence/finder-extraction-invalid-state.tsv"
      if (( SECONDS >= finder_state_deadline )); then
        fail "Finder extraction produced duplicate or unexpected output"
      fi
      sleep 2
      ;;
    pending)
      recursive_state_first_seen=-1
      separate_state_first_seen=-1
      if (( SECONDS >= finder_state_deadline )); then
        fail "Finder extraction produced neither the app nor the exact inner ZIP"
      fi
      sleep 2
      ;;
    *) fail "Finder extraction classifier returned unknown state: $finder_state" ;;
  esac
done
cp "$finder_state_file" \
  "$distribution_evidence/finder-extraction-first-action-state.tsv"

if [[ "$finder_state" == "recursive" ]]; then
  extraction_mode="archive-utility-recursive"
  extracted_app="$(state_value "$finder_state_file" app_path)"
else
  extraction_mode="finder-separate-inner-zip"
  inner_archive="$(state_value "$finder_state_file" inner_path)"
  if ! inner_quarantine="$(xattr -p com.apple.quarantine "$inner_archive" 2>/dev/null)"; then
    fail "Finder-extracted inner app ZIP did not inherit download quarantine"
  fi
  printf '%s\n' "$inner_quarantine" \
    > "$distribution_evidence/inner-archive-quarantine.txt"
  IFS=';' read -r _ _ inner_quarantine_agent _ <<< "$inner_quarantine"
  [[ "$inner_quarantine_agent" == "Safari" ]] \
    || fail "inner app ZIP did not preserve Safari quarantine"
  {
    printf 'inner_archive=%s\n' "$inner_archive"
    printf 'inner_archive_sha256=%s\n' "$expected_inner_sha256"
  } > "$distribution_evidence/inner-artifact.txt"

  mark_phase finder-inner-app-extraction
  [[ ! -e "$finder_followup_confirmation" ]] \
    || fail "Finder follow-up confirmation already exists"
  write_confirmation_command \
    "$finder_followup_confirmation_command" \
    "$finder_followup_confirmation"
  cat > "$instructions" <<EOF
roma just talk distribution E2E

Current step: Finder follow-up extraction

This Mac kept the nested app ZIP instead of recursively extracting it. In
Finder, double-click:
$inner_archive

Wait for "$app_name" to appear. Then double-click on the Desktop:

Confirm Finder Follow-up Extraction.command

Do not use Terminal, move the app, clear quarantine, or re-sign it.
EOF
  echo "DISTRIBUTION E2E FINDER FOLLOW-UP ACTION REQUIRED"
  echo "In Finder, double-click the inner app ZIP: $inner_archive"
  open -R "$inner_archive"
  wait_for_path \
    "$finder_followup_confirmation" \
    "operator confirmation of the Finder follow-up extraction" \
    "$deadline"
  cp "$finder_followup_confirmation" \
    "$distribution_evidence/finder-followup-human-confirmation.txt"
  finder_followup_deadline=$((SECONDS + 60))
  if (( finder_followup_deadline > deadline )); then
    finder_followup_deadline="$deadline"
  fi
  followup_recursive_first_seen=-1
  while true; do
    "$finder_extraction_classifier" \
      "$volume" \
      "$downloaded_archive" \
      "$expected_inner_sha256" \
      "$app_name" \
      > "$finder_state_file" \
      || fail "could not classify Finder follow-up extraction output"
    finder_state="$(state_value "$finder_state_file" state)"
    if [[ "$finder_state" == "recursive" ]]; then
      if (( followup_recursive_first_seen < 0 )); then
        followup_recursive_first_seen="$SECONDS"
      fi
      if (( SECONDS - followup_recursive_first_seen >= 4 )) \
        && ! pgrep -x "Archive Utility" >/dev/null 2>&1; then
        break
      fi
    else
      followup_recursive_first_seen=-1
    fi
    if [[ "$finder_state" == "invalid" ]]; then
      cp "$finder_state_file" \
        "$distribution_evidence/finder-followup-invalid-state.tsv"
      if (( SECONDS >= finder_followup_deadline )); then
        fail "Finder follow-up extraction produced duplicate or unexpected output"
      fi
    fi
    if (( SECONDS >= finder_followup_deadline )); then
      fail "Finder follow-up extraction did not produce one Roma app"
    fi
    sleep 2
  done
  cp "$finder_state_file" \
    "$distribution_evidence/finder-extraction-followup-state.tsv"
  extracted_app="$(state_value "$finder_state_file" app_path)"
fi

wait_for_path "$extracted_app/Contents/Info.plist" \
  "Finder and Archive Utility app extraction" "$deadline"
case "$extracted_app" in
  "$volume"/*) ;;
  *) fail "Finder-extracted app escaped the distribution volume: $extracted_app" ;;
esac
{
  printf 'mode=%s\n' "$extraction_mode"
  printf 'app=%s\n' "$extracted_app"
  printf 'downloaded_outer_sha256=%s\n' "$downloaded_sha256"
  printf 'expected_inner_sha256=%s\n' "$expected_inner_sha256"
  printf 'inner_zip_present_after_first_action=%s\n' \
    "$([[ "$(state_value "$distribution_evidence/finder-extraction-first-action-state.tsv" inner_count)" -gt 0 ]] && echo true || echo false)"
} > "$distribution_evidence/finder-extraction-mode.txt"
defaults read com.apple.archiveutility \
  > "$distribution_evidence/archive-utility-defaults-after.txt" 2>&1 \
  || true

codesign_deadline=$((SECONDS + 60))
while ! codesign --verify --deep --strict --verbose=4 "$extracted_app" \
  > "$distribution_evidence/extracted-app-codesign.txt" 2>&1; do
  if (( SECONDS >= codesign_deadline )); then
    fail "Finder-extracted app fails strict deep signature verification"
  fi
  sleep 2
done
"$finder_extraction_classifier" \
  "$volume" \
  "$downloaded_archive" \
  "$expected_inner_sha256" \
  "$app_name" \
  > "$distribution_evidence/finder-extraction-final-state.tsv" \
  || fail "could not classify the final Finder extraction output"
final_finder_state="$(
  state_value "$distribution_evidence/finder-extraction-final-state.tsv" state
)"
final_extracted_app="$(
  state_value "$distribution_evidence/finder-extraction-final-state.tsv" app_path
)"
[[ "$final_finder_state" == "recursive" && "$final_extracted_app" == "$extracted_app" ]] \
  || fail "Finder extraction output changed before signature verification finished"
if ! app_quarantine="$(xattr -p com.apple.quarantine "$extracted_app" 2>/dev/null)"; then
  fail "Finder extraction did not preserve app quarantine"
fi
printf '%s\n' "$app_quarantine" > "$distribution_evidence/extracted-app-quarantine.txt"
IFS=';' read -r _ _ app_quarantine_agent _ <<< "$app_quarantine"
[[ "$app_quarantine_agent" == "Safari" ]] \
  || fail "Finder extraction did not preserve Safari quarantine"
/usr/bin/log show --last "${interaction_minutes}m" --style compact \
  --predicate 'process == "Archive Utility" OR process == "Finder"' \
  > "$distribution_evidence/finder-archive-utility-unified-log.txt" 2>&1 \
  || true
codesign -dvvv "$extracted_app" > "$distribution_evidence/extracted-app-signature.txt" 2>&1 \
  || fail "could not inspect Finder-extracted app signature"
extracted_executable_name="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
    "$extracted_app/Contents/Info.plist"
)"
extracted_executable="$extracted_app/Contents/MacOS/$extracted_executable_name"
extracted_executable_sha256="$(shasum -a 256 "$extracted_executable" | awk '{print $1}')"
extracted_app_short_version="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$extracted_app/Contents/Info.plist"
)"
extracted_app_bundle_version="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "$extracted_app/Contents/Info.plist"
)"
[[ "$extracted_app_short_version" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]] \
  || fail "extracted app has no valid short version"
[[ "$extracted_app_bundle_version" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]] \
  || fail "extracted app has no valid bundle version"
app_minimum_system_version="$(
  /usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' \
    "$extracted_app/Contents/Info.plist" 2>/dev/null || true
)"
[[ "$app_minimum_system_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
  || fail "extracted app has no valid minimum macOS version"
{
  printf 'runner_product_version=%s\n' "$actual_macos_version"
  printf 'app_minimum_system_version=%s\n' "$app_minimum_system_version"
} > "$distribution_evidence/extracted-app-compatibility.txt"
if ! version_is_at_least "$actual_macos_version" "$app_minimum_system_version"; then
  fail "app requires macOS $app_minimum_system_version; runner is $actual_macos_version"
fi
{
  printf 'app=%s\n' "$extracted_app"
  printf 'executable=%s\n' "$extracted_executable"
  printf 'executable_sha256=%s\n' "$extracted_executable_sha256"
  printf 'app_short_version=%s\n' "$extracted_app_short_version"
  printf 'app_bundle_version=%s\n' "$extracted_app_bundle_version"
} > "$distribution_evidence/extracted-app-identity.txt"
if [[ "$distribution_expectation" == known-bad-framework-signature ]]; then
  extracted_framework_binary="$extracted_app/Contents/Frameworks/${expected_rejected_framework}.framework/Versions/Current/${expected_rejected_framework}"
  [[ -f "$extracted_framework_binary" ]] \
    || fail "expected rejected framework binary is absent from the distributed app"
  source_main_uuid="$(read_arm64_uuid "$extracted_executable")"
  source_rejected_framework_uuid="$(read_arm64_uuid "$extracted_framework_binary")"
  [[ "$source_main_uuid" =~ ^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$ ]] \
    || fail "could not read the distributed app arm64 UUID"
  [[ "$source_rejected_framework_uuid" =~ ^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$ ]] \
    || fail "could not read the distributed framework arm64 UUID"
  normalized_expected_main_uuid="$(printf '%s' "$expected_main_uuid" | tr '[:lower:]' '[:upper:]')"
  normalized_expected_framework_uuid="$(printf '%s' "$expected_rejected_framework_uuid" | tr '[:lower:]' '[:upper:]')"
  if [[ -n "$expected_main_uuid" && "$normalized_expected_main_uuid" != "$source_main_uuid" ]]; then
    fail "requested main UUID does not match the distributed app"
  fi
  if [[ -n "$expected_rejected_framework_uuid" \
    && "$normalized_expected_framework_uuid" != "$source_rejected_framework_uuid" ]]; then
    fail "requested framework UUID does not match the distributed app"
  fi
  expected_main_uuid="$source_main_uuid"
  expected_rejected_framework_uuid="$source_rejected_framework_uuid"
  {
    printf 'main_executable=%s\n' "$extracted_executable"
    printf 'main_arm64_uuid=%s\n' "$source_main_uuid"
    printf 'framework_binary=%s\n' "$extracted_framework_binary"
    printf 'framework_arm64_uuid=%s\n' "$source_rejected_framework_uuid"
    printf 'app_short_version=%s\n' "$extracted_app_short_version"
    printf 'app_bundle_version=%s\n' "$extracted_app_bundle_version"
  } > "$distribution_evidence/expected-negative-control-identities.txt"
fi
if ! compare_macos_bundle_to_manifest \
  "$extracted_app" \
  "$distribution_evidence/expected-inner-app-files.sha256" \
  "$distribution_evidence/extracted-app-files-before-gatekeeper.sha256" \
  "$distribution_evidence/extracted-app-source-mismatch.diff"; then
  fail "Finder-extracted app does not match the hash-verified inner ZIP"
fi
printf '%s\n' "$extracted_app" > "$stage_root/macos-app-path.txt"

mark_phase gatekeeper-first-block
[[ ! -e "$gatekeeper_confirmation" ]] \
  || fail "Gatekeeper confirmation already exists on a supposedly fresh stage"
write_confirmation_command \
  "$gatekeeper_confirmation_command" \
  "$gatekeeper_confirmation"
cat > "$instructions" <<EOF
roma just talk distribution E2E

Current step: prove the first Gatekeeper block

Finder will reveal "$app_name" while Gatekeeper still rejects it.
Double-click the app in Finder. When the real "Not Opened" dialog appears:

1. Click Done.
2. In Finder, double-click "Confirm Gatekeeper Not Opened.command" on the Desktop.

Do not run the confirmation command unless you actually saw that dialog.
EOF
set +e
spctl --assess --type execute --verbose=4 "$extracted_app" \
  > "$distribution_evidence/gatekeeper-assessment-before.txt" 2>&1
assessment_status=$?
set -e
printf '%s\n' "$assessment_status" > "$distribution_evidence/gatekeeper-assessment-before-exit-code.txt"
if [[ "$assessment_status" -eq 0 ]]; then
  fail "fresh-Mac Gatekeeper precondition failed: app was already trusted"
fi
if ! grep -Eiq 'rejected|not accepted|denied' \
  "$distribution_evidence/gatekeeper-assessment-before.txt"; then
  fail "Gatekeeper assessment failed without an explicit rejection result"
fi

set +e
open -R "$extracted_app" \
  > "$distribution_evidence/gatekeeper-finder-reveal.stdout.txt" \
  2> "$distribution_evidence/gatekeeper-finder-reveal.stderr.txt"
finder_reveal_status=$?
set -e
printf '%s\n' "$finder_reveal_status" \
  > "$distribution_evidence/gatekeeper-finder-reveal-exit-code.txt"
if [[ "$finder_reveal_status" -ne 0 ]]; then
  fail "Finder could not reveal the app for the first Gatekeeper-protected launch"
fi
wait_for_path \
  "$gatekeeper_confirmation" \
  "operator confirmation of the visible Gatekeeper Not Opened dialog" \
  "$deadline"
cp "$gatekeeper_confirmation" \
  "$distribution_evidence/gatekeeper-not-opened-human-confirmation.txt"
sleep 1
if pgrep -x "$process_name" >/dev/null 2>&1; then
  fail "first launch bypassed the expected fresh-Mac Gatekeeper block"
fi
ps -axo pid,ppid,state,etime,command \
  > "$distribution_evidence/processes-after-first-block.txt" 2>&1 || true

start_approval_monitors
cat > "$instructions" <<EOF
roma just talk distribution E2E

Current step: GATEKEEPER ACTION REQUIRED

1. Open System Settings, Privacy & Security.
2. Find the blocked "$process_name" launch and click Open Anyway.
3. Confirm Open. Authenticate if macOS asks.

$(if [[ -n "$operator_credential_file" ]]; then
  printf 'Open the Desktop credential file "%s" and use those image-account administrator credentials only if macOS asks.\n' \
    "$(basename "$operator_credential_file")"
else
  printf 'Use the authorized administrator credentials if macOS asks.\n'
fi)

Keep the app on $volume. Do not clear quarantine or re-sign it.
The test is waiting for the first approved AppTranslocation process.
EOF
echo "DISTRIBUTION E2E GATEKEEPER ACTION REQUIRED"
echo "In Remote Display: dismiss Not Opened, then Privacy & Security -> Open Anyway -> Open."
open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension" \
  > "$distribution_evidence/privacy-settings-open.txt" 2>&1 || true

if [[ "$distribution_expectation" == known-bad-framework-signature ]]; then
  mark_phase verify-known-bad-framework-signature-dyld-failure
  require_expected_framework_signature_failure
  write_macos_bundle_manifest \
    "$extracted_app" \
    "$distribution_evidence/extracted-app-files-after-known-bad-dyld.sha256"
  if ! cmp -s \
    "$distribution_evidence/extracted-app-files-before-gatekeeper.sha256" \
    "$distribution_evidence/extracted-app-files-after-known-bad-dyld.sha256"; then
    diff -u \
      "$distribution_evidence/extracted-app-files-before-gatekeeper.sha256" \
      "$distribution_evidence/extracted-app-files-after-known-bad-dyld.sha256" \
      > "$distribution_evidence/extracted-app-known-bad-dyld-mutation.diff" || true
    fail "approved known-bad launch changed the distributed app bundle"
  fi
  if ! app_quarantine_after_dyld="$(xattr -p com.apple.quarantine "$extracted_app" 2>/dev/null)"; then
    fail "approved known-bad launch removed app quarantine"
  fi
  printf '%s\n' "$app_quarantine_after_dyld" \
    > "$distribution_evidence/extracted-app-quarantine-after-known-bad-dyld.txt"
  IFS=';' read -r _ _ app_quarantine_after_dyld_agent _ <<< "$app_quarantine_after_dyld"
  [[ "$app_quarantine_after_dyld_agent" == "Safari" ]] \
    || fail "approved known-bad launch did not preserve Safari quarantine"
  cat > "$instructions" <<EOF
roma just talk distribution E2E

Expected known-bad framework signature failure reproduced.

After the user-approved Gatekeeper launch, the one AppTranslocated Roma process
aborted with the requested framework code-signature dyld report. Do not retry
the app or change its quarantine, signature, or system security settings.
EOF
  mark_phase complete
  {
    printf 'distribution_verdict=expected_framework_signature_failure_reproduced\n'
    printf 'distribution_expectation=%s\n' "$distribution_expectation"
    printf 'expected_rejected_framework=%s\n' "$expected_rejected_framework"
    printf 'source_main_uuid=%s\n' "$source_main_uuid"
    printf 'source_rejected_framework_uuid=%s\n' "$source_rejected_framework_uuid"
    printf 'app_short_version=%s\n' "$extracted_app_short_version"
    printf 'app_bundle_version=%s\n' "$extracted_app_bundle_version"
    printf 'github_actions_archive_sha256=%s\n' "$source_sha256"
    printf 'browser_downloaded_archive_sha256=%s\n' "$downloaded_sha256"
    printf 'inner_app_archive_sha256=%s\n' "$expected_inner_sha256"
    printf 'macos_version=%s\n' "$actual_macos_version"
    printf 'macos_build=%s\n' "$actual_macos_build"
    printf 'external_volume=%s\n' "$volume"
    printf 'source_app=%s\n' "$extracted_app"
    printf 'launched_pid=%s\n' "$reported_crash_pid"
    printf 'launch_verification=expected_dyld_abort\n'
  } > "$verdict_file"
  printf '%s\n' "$distribution_expectation" \
    > "$stage_root/distribution-expected-terminal-failure.txt"
  echo "macOS distribution E2E reproduced the expected $expected_rejected_framework signature failure: $extracted_app"
  exit 0
fi

if ! launched_pid="$(wait_for_first_approval_pid "$deadline")"; then
  fail "timed out waiting for the first user-approved Gatekeeper launch"
fi
printf '%s\n' "$launched_pid" > "$distribution_evidence/launched-pid.txt"

[[ ! -e "$readiness_confirmation" ]] \
  || fail "first-launch readiness confirmation already exists"
write_confirmation_command \
  "$readiness_confirmation_command" \
  "$readiness_confirmation"
cat > "$instructions" <<EOF
roma just talk distribution E2E

Current step: prove the approved first process reached usable UI

Confirm that Roma's first-launch or onboarding UI is visible and responds to
normal clicks. Then, without quitting or moving Roma, double-click:

Confirm Roma First Launch Ready.command

The test will verify this same PID through AppTranslocation after confirmation.
EOF
echo "DISTRIBUTION E2E FIRST-LAUNCH UI CONFIRMATION REQUIRED"
echo "Confirm the approved Roma UI responds, then run the Desktop confirmation command."
wait_for_path \
  "$readiness_confirmation" \
  "operator confirmation of responsive Roma first-launch UI" \
  "$deadline"
cp "$readiness_confirmation" \
  "$distribution_evidence/first-launch-ui-human-confirmation.txt"

mark_phase verify-apptranslocation-and-bundled-code
DISTRIBUTION_E2E_REQUIRE_TRANSLOCATION=true \
DISTRIBUTION_E2E_REQUIRE_APPKIT_FINISHED=true \
DISTRIBUTION_E2E_EXPECTED_MACOS_VERSION="$expected_macos_version" \
DISTRIBUTION_E2E_EXPECTED_MACOS_BUILD="$expected_macos_build" \
DISTRIBUTION_E2E_EXPECTED_QUARANTINE_AGENT=Safari \
  bash "$verifier" \
    "$extracted_app" \
    "$launched_pid" \
    "$distribution_evidence/launch-verification"

sleep 2
stop_approval_monitors
awk -F '\t' 'NF >= 2 { print $2 }' "$approval_process_events" \
  | LC_ALL=C sort -nu \
  > "$distribution_evidence/approval-window-distinct-pids.txt"
approval_pid_count="$(
  awk 'NF { count++ } END { print count + 0 }' \
    "$distribution_evidence/approval-window-distinct-pids.txt"
)"
if [[ "$approval_pid_count" -ne 1 ]] \
  || ! grep -Fxq "$launched_pid" \
    "$distribution_evidence/approval-window-distinct-pids.txt"; then
  fail "more than one Roma process appeared during the approval window"
fi
write_roma_crash_report_inventory \
  "$distribution_evidence/approval-window-crash-reports-after.txt"
comm -13 \
  "$distribution_evidence/approval-window-crash-reports-before.txt" \
  "$distribution_evidence/approval-window-crash-reports-after.txt" \
  > "$distribution_evidence/approval-window-new-crash-reports.txt"
if [[ -s "$distribution_evidence/approval-window-new-crash-reports.txt" ]]; then
  fail "a new Roma crash report appeared during the approved launch"
fi
if grep -Eiq \
  'Library not loaded|code signature .*not valid for use in process|Namespace DYLD|DYLD, Code 1' \
  "$approval_log"; then
  fail "dyld or code-signature failure appeared during the approval window"
fi
if [[ ! -d "$live_model_directory" \
  || -L "$(dirname "$live_model_directory")" \
  || -L "$live_model_directory" ]]; then
  fail "approved first launch did not create the live FluidAudio model directory"
fi
{
  printf 'live_model_state=created_by_verified_first_launch\n'
  printf 'first_launch_pid=%s\n' "$launched_pid"
  printf 'live_model_directory=%s\n' "$live_model_directory"
  find "$live_model_directory" -type f -print 2>/dev/null \
    | LC_ALL=C sort \
    || true
} > "$distribution_evidence/first-launch-live-model-state.txt"

write_macos_bundle_manifest \
  "$extracted_app" \
  "$distribution_evidence/extracted-app-files-after-gatekeeper.sha256"
if ! cmp -s \
  "$distribution_evidence/extracted-app-files-before-gatekeeper.sha256" \
  "$distribution_evidence/extracted-app-files-after-gatekeeper.sha256"; then
  diff -u \
    "$distribution_evidence/extracted-app-files-before-gatekeeper.sha256" \
    "$distribution_evidence/extracted-app-files-after-gatekeeper.sha256" \
    > "$distribution_evidence/extracted-app-files-gatekeeper.diff" || true
  fail "app bundle bytes changed between Finder extraction and approved launch"
fi

set +e
spctl --assess --type execute --verbose=4 "$extracted_app" \
  > "$distribution_evidence/gatekeeper-assessment-after.txt" 2>&1
assessment_after_status=$?
set -e
printf '%s\n' "$assessment_after_status" \
  > "$distribution_evidence/gatekeeper-assessment-after-exit-code.txt"

cat > "$instructions" <<EOF
roma just talk distribution E2E

Distribution launch passed.

The exact Safari-downloaded ZIP survived Finder extraction, Gatekeeper approval,
AppTranslocation, signature checks, and generic bundled-code mapping checks.
The stage will now run the deterministic transcription smoke against this same app.
EOF

mark_phase complete
{
  printf 'distribution_verdict=passed\n'
  printf 'distribution_expectation=%s\n' "$distribution_expectation"
  printf 'github_actions_archive_sha256=%s\n' "$source_sha256"
  printf 'browser_downloaded_archive_sha256=%s\n' "$downloaded_sha256"
  printf 'inner_app_archive_sha256=%s\n' "$expected_inner_sha256"
  printf 'macos_version=%s\n' "$actual_macos_version"
  printf 'macos_build=%s\n' "$actual_macos_build"
  printf 'external_volume=%s\n' "$volume"
  printf 'source_app=%s\n' "$extracted_app"
  printf 'launched_pid=%s\n' "$launched_pid"
  printf 'live_model_directory=%s\n' "$live_model_directory"
  printf 'live_model_state=created_by_verified_first_launch\n'
  printf 'launch_verification=passed\n'
} > "$verdict_file"

echo "macOS distribution E2E launch passed: $extracted_app"
