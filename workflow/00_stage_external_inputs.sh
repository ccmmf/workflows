#!/usr/bin/env bash
# 00_stage_external_inputs.sh: create run directory and stage user external inputs.
# Invoked as step 00 of the 'prepare' command. It:
#   - Ensures the run directory exists.
#   - Copies user-provided external files (from config.external_paths) into
#     the run directory so they are available to the workflow.
#
# Requires: yq (mikefarah/yq)
#
# Options (see --help): --repo-root (required); --manifest optional,
# defaults to <repo-root>/workflow/workflow_manifest.yaml.
# Run directory is either from --run-dir or from run_dir in the file given by
# --config (relative paths resolved with --invocation-cwd). external_paths
# entries are resolved from --invocation-cwd when relative.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: 00_stage_external_inputs.sh [OPTIONS]

Create the run directory (if needed) and copy user-provided external files
from the config's external_paths section into the run directory so they are
available to the workflow.

Required:
  --repo-root PATH      Repo root (workflows directory). Script changes to this directory.

Run directory (one of):
  --run-dir PATH        Run directory (absolute, or relative to --repo-root).
  --config PATH         User YAML config file; script reads run_dir from it (use with --invocation-cwd).

Optional:
  --manifest PATH       Path to workflow_manifest.yaml (default: <repo-root>/workflow/workflow_manifest.yaml).
  --invocation-cwd PATH Required when using --config with a relative run_dir or relative external_paths.
  -h, --help            Print this help and exit.
EOF
}

RUN_DIR=""
CONFIG_FILE=""
REPO_ROOT=""
MANIFEST=""
INVOCATION_CWD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir)
      [[ $# -lt 2 ]] && { echo "00_stage_external_inputs: --run-dir requires PATH." >&2; usage >&2; exit 1; }
      RUN_DIR="$2"; shift 2 ;;
    --config)
      [[ $# -lt 2 ]] && { echo "00_stage_external_inputs: --config requires PATH." >&2; usage >&2; exit 1; }
      CONFIG_FILE="$2"; shift 2 ;;
    --repo-root)
      [[ $# -lt 2 ]] && { echo "00_stage_external_inputs: --repo-root requires PATH." >&2; usage >&2; exit 1; }
      REPO_ROOT="$2"; shift 2 ;;
    --manifest)
      [[ $# -lt 2 ]] && { echo "00_stage_external_inputs: --manifest requires PATH." >&2; usage >&2; exit 1; }
      MANIFEST="$2"; shift 2 ;;
    --invocation-cwd)
      [[ $# -lt 2 ]] && { echo "00_stage_external_inputs: --invocation-cwd requires PATH." >&2; usage >&2; exit 1; }
      INVOCATION_CWD="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "00_stage_external_inputs: Unknown option: $1" >&2
      usage >&2
      exit 1 ;;
  esac
done

if [[ -z "$REPO_ROOT" ]]; then
  echo "00_stage_external_inputs: --repo-root is required." >&2
  usage >&2
  exit 1
fi

if [[ -z "$MANIFEST" ]]; then
  MANIFEST="${REPO_ROOT}/workflow/workflow_manifest.yaml"
fi

# Run directory: from --run-dir or from config file
if [[ -n "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "00_stage_external_inputs: Config file not found: $CONFIG_FILE" >&2
    exit 1
  fi
  RUN_DIR=$(yq eval '.run_dir' "$CONFIG_FILE") || {
    echo "00_stage_external_inputs: yq failed to read .run_dir from config: $CONFIG_FILE" >&2
    exit 1
  }
  if [[ -z "$RUN_DIR" || "$RUN_DIR" == "null" ]]; then
    echo "00_stage_external_inputs: run_dir not found or empty in config (expected .run_dir): $CONFIG_FILE" >&2
    exit 1
  fi
  if [[ "$RUN_DIR" != /* ]]; then
    if [[ -z "$INVOCATION_CWD" ]]; then
      echo "00_stage_external_inputs: --invocation-cwd is required when run_dir in config is relative." >&2
      exit 1
    fi
    RUN_DIR="${INVOCATION_CWD}/${RUN_DIR}"
  fi
elif [[ -z "$RUN_DIR" ]]; then
  echo "00_stage_external_inputs: Provide --run-dir or --config (with run_dir in the config file)." >&2
  usage >&2
  exit 1
fi

if [[ ! -f "$MANIFEST" ]]; then
  echo "00_stage_external_inputs: Manifest not found: $MANIFEST" >&2
  exit 1
fi

if ! command -v yq &>/dev/null; then
  echo "00_stage_external_inputs: yq is required to read the manifest and config." >&2
  exit 1
fi

cd "$REPO_ROOT"

# Show path for user: relative to INVOCATION_CWD if under it, else absolute
report_path() {
  local abs_path="$1"
  if [[ -n "$INVOCATION_CWD" && "$abs_path" == "$INVOCATION_CWD"/* ]]; then
    echo "${abs_path#"$INVOCATION_CWD"/}"
  else
    echo "$abs_path"
  fi
}

# Resolve an absolute run directory for staging.
RUN_DIR_ABS=$(if [[ "$RUN_DIR" = /* ]]; then echo "$RUN_DIR"; else echo "$REPO_ROOT/$RUN_DIR"; fi)

echo "00_stage_external_inputs: Ensuring run directory exists"
mkdir -p "$RUN_DIR_ABS"
RUN_DIR_ABS=$(cd "$RUN_DIR_ABS" && pwd)
RUN_DIR="$RUN_DIR_ABS"
echo "00_stage_external_inputs: Run directory: $(report_path "$RUN_DIR_ABS")"

# If no config or no external_paths, nothing more to do.
if [[ -z "$CONFIG_FILE" || ! -f "$CONFIG_FILE" ]]; then
  echo "00_stage_external_inputs: No config file provided; only run directory was created."
  echo "00_stage_external_inputs: Done."
  exit 0
fi

# external_paths is a mapping from manifest path keys to source file paths.
# Each key must match an entry in manifest.paths; the destination filename is
# derived from that manifest path (basename), not from the source filename.
# Parse the YAML block output of .external_paths line by line (yq v4 outputs plain
# scalars without quotes). Split on first ": " to get key and value.
external_block=$(yq eval '.external_paths' "$CONFIG_FILE" 2>/dev/null || echo "null")
if [[ -z "$external_block" || "$external_block" == "null" || "$external_block" == "{}" ]]; then
  echo "00_stage_external_inputs: No external_paths configured; nothing to copy."
  echo "00_stage_external_inputs: Done."
  exit 0
fi

echo "00_stage_external_inputs: Staging external inputs into run directory"

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # Split on first ": " — key is everything before, value everything after.
  key="${line%%: *}"
  src="${line#*: }"
  [[ -z "$key" || "$key" == "$line" ]] && continue  # no ": " found
  [[ -z "$src" || "$src" == "null" ]] && continue
  # Strip surrounding quotes that yq may preserve from the YAML source.
  src="${src#\"}" ; src="${src%\"}"

  # Resolve source: absolute as-is, relative to INVOCATION_CWD otherwise.
  if [[ "$src" != /* ]]; then
    if [[ -z "$INVOCATION_CWD" ]]; then
      echo "00_stage_external_inputs: --invocation-cwd is required when external_paths entries are relative." >&2
      exit 1
    fi
    src="${INVOCATION_CWD}/${src}"
  fi
  if [[ ! -f "$src" ]]; then
    echo "00_stage_external_inputs: external_paths.${key}: source file not found: ${src}" >&2
    exit 1
  fi

  # Destination: derived from the manifest path for the same key, not the source basename.
  # This enforces the manifest contract so downstream scripts always find files where expected.
  manifest_path=$(yq eval ".paths.${key}" "$MANIFEST" 2>/dev/null)
  if [[ -z "$manifest_path" || "$manifest_path" == "null" ]]; then
    echo "00_stage_external_inputs: external_paths key '${key}' has no corresponding entry in manifest.paths" >&2
    exit 1
  fi
  dest="${RUN_DIR_ABS}/$(basename "$manifest_path")"
  dest_dir=$(dirname "$dest")
  mkdir -p "$dest_dir"

  echo "00_stage_external_inputs: Copying $(report_path "$src") -> $(report_path "$dest")"
  cp -f "$src" "$dest"
done <<< "$external_block"

echo "00_stage_external_inputs: Done."

