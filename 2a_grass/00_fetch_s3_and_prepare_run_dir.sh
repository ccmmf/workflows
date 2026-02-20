#!/usr/bin/env bash
# 00_fetch_s3_and_prepare_run_dir.sh: fetch demo data from S3 and prepare run directory.
# Invoked by the 'get-demo-data' command (for users who do not have local data).
# All configuration is read from the workflow manifest or from environment variables set by the CLI.
#
# Required env (from CLI):
#   RUN_DIR    run directory (e.g. 2a_grass/run), relative to REPO_ROOT
#   REPO_ROOT  repo root (workflows directory)
#   MANIFEST   path to workflow_manifest.yaml
#   COMMAND    command name (e.g. get-demo-data)
#   STEP_INDEX step index in that command (e.g. 0)
#
# Requires: yq (mikefarah/yq), aws CLI

set -euo pipefail

RUN_DIR="${RUN_DIR:?RUN_DIR is required}"
REPO_ROOT="${REPO_ROOT:?REPO_ROOT is required}"
MANIFEST="${MANIFEST:?MANIFEST is required}"
COMMAND="${COMMAND:-prepare}"
STEP_INDEX="${STEP_INDEX:-0}"

if [[ ! -f "$MANIFEST" ]]; then
  echo "00_fetch_s3_and_prepare_run_dir: Manifest not found: $MANIFEST" >&2
  exit 1
fi

if ! command -v yq &>/dev/null; then
  echo "00_fetch_s3_and_prepare_run_dir: yq is required to read the manifest." >&2
  exit 1
fi

cd "$REPO_ROOT"

# Resolve a path relative to run_dir (RUN_DIR may be absolute or relative to REPO_ROOT).
resolve_run_path() {
  if [[ "$RUN_DIR" == /* ]]; then
    echo "${RUN_DIR}/${1}"
  else
    echo "${REPO_ROOT}/${RUN_DIR}/${1}"
  fi
}

# --- Read from manifest ---
s3_endpoint=$(yq eval '.s3.endpoint_url' "$MANIFEST")

# Artifact: url + filename from s3.artifact_02
artifact_url=$(yq eval '.s3.artifact_02.url' "$MANIFEST")
artifact_filename=$(yq eval '.s3.artifact_02.filename' "$MANIFEST")
artifact_s3_uri="${artifact_url}/${artifact_filename}"

# LandTrendr TIFs: two S3 resources and two local path segments from paths.landtrendr_raw_files
median_url=$(yq eval '.s3.median_tif.url' "$MANIFEST")
median_filename=$(yq eval '.s3.median_tif.filename' "$MANIFEST")
stdv_url=$(yq eval '.s3.stdv_tif.url' "$MANIFEST")
stdv_filename=$(yq eval '.s3.stdv_tif.filename' "$MANIFEST")
median_s3_uri="${median_url}/${median_filename}"
stdv_s3_uri="${stdv_url}/${stdv_filename}"

landtrendr_paths_raw=$(yq eval '.paths.landtrendr_raw_files' "$MANIFEST")
# Split comma-separated; first segment = median, second = stdv
landtrendr_segment_1="${landtrendr_paths_raw%%,*}"
landtrendr_segment_2="${landtrendr_paths_raw#*,}"

# Output path keys for this step: create these dirs (from manifest step.outputs)
output_keys=$(yq eval '.steps["'"$COMMAND"'"] | .['"$STEP_INDEX"'].outputs | .[]' "$MANIFEST" 2>/dev/null || true)

# --- Create run directory and output dirs from manifest ---
echo "00_fetch_s3_and_prepare_run_dir: Creating run directory and output dirs from manifest"
mkdir -p "$RUN_DIR"

while IFS= read -r path_key; do
  [[ -z "$path_key" ]] && continue
  path_value=$(yq eval '.paths["'"$path_key"'"]' "$MANIFEST" 2>/dev/null)
  [[ -z "$path_value" || "$path_value" == "null" ]] && continue
  resolved=$(resolve_run_path "$path_value")
  mkdir -p "$resolved"
done <<< "$output_keys"

# --- Download and extract artifact ---
if [[ -f "$artifact_filename" ]]; then
  echo "00_fetch_s3_and_prepare_run_dir: Artifact tarball already present: $artifact_filename"
else
  echo "00_fetch_s3_and_prepare_run_dir: Downloading artifact from S3"
  aws s3 cp --endpoint-url "$s3_endpoint" "$artifact_s3_uri" "./$artifact_filename"
fi

RUN_DIR_ABS=$(if [[ "$RUN_DIR" = /* ]]; then echo "$RUN_DIR"; else echo "$REPO_ROOT/$RUN_DIR"; fi)
echo "00_fetch_s3_and_prepare_run_dir: Extracting artifact into run directory"
tar -xzf "$artifact_filename" -C "$RUN_DIR_ABS"

# --- Download LandTrendr TIFs if not present (paths from manifest: first=median, second=stdv) ---
seg1=$(echo "$landtrendr_segment_1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
seg2=$(echo "$landtrendr_segment_2" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

download_tif() {
  local seg="$1"
  local s3_uri="$2"
  local label="$3"
  [[ -z "$seg" ]] && return 0
  resolved=$(resolve_run_path "$seg")
  if [[ -f "$resolved" ]]; then
    echo "00_fetch_s3_and_prepare_run_dir: Already present: $resolved"
  else
    mkdir -p "$(dirname "$resolved")"
    echo "00_fetch_s3_and_prepare_run_dir: Downloading $label from S3"
    aws s3 cp --endpoint-url "$s3_endpoint" "$s3_uri" "$resolved"
  fi
}
download_tif "$seg1" "$median_s3_uri" "median TIF"
download_tif "$seg2" "$stdv_s3_uri" "stdv TIF"

echo "00_fetch_s3_and_prepare_run_dir: Done."
