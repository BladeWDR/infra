#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# deploy_compose.sh
# 
# Helper script to deploy Docker Compose changes via Ansible.
# Automatically detects affected hosts from recent git changes (such as Renovate
# PR merges or git pull) and runs:
#   ansible-playbook site.yml --tags compose -l <detected_hosts> [extra_args...]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Ensure we have git available
if ! command -v git &>/dev/null; then
  echo "Error: git is required but not installed." >&2
  exit 1
fi

# Ensure we have ansible-playbook available
if ! command -v ansible-playbook &>/dev/null; then
  echo "Error: ansible-playbook is required but not found in PATH." >&2
  exit 1
fi

GIT_ROOT="$(git -C "$ANSIBLE_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$GIT_ROOT" ]]; then
  echo "Error: Not inside a git repository." >&2
  exit 1
fi

# Default options
AUTO_CONFIRM=false
DRY_RUN=false
MANUAL_HOSTS=""
GIT_RANGE=""
ANSIBLE_EXTRA_ARGS=()

show_help() {
  cat << 'EOF'
Usage: deploy_compose.sh [OPTIONS] [-- ANSIBLE_OPTIONS]

Automatically detects modified Docker Compose services from recent git history
and runs `ansible-playbook site.yml --tags compose -l <hosts>`.

Detection Strategy (default):
  1. Checks for unstaged or staged changes in working tree touching services/.
  2. If none, checks changes from ORIG_HEAD..HEAD (commits pulled via 'git pull').
  3. If ORIG_HEAD is not set or equal to HEAD, falls back to the latest commit (HEAD~1..HEAD).

Options:
  -p, --pull           Compare from ORIG_HEAD..HEAD (changes brought by last git pull)
  -1, --last           Compare only the latest commit (HEAD~1..HEAD)
  -r, --range <RANGE>  Specify custom git revision or range (e.g. HEAD~3..HEAD, main)
  -w, --working-tree   Check only uncommitted/staged working tree changes
  -l, --hosts <HOSTS>  Manually specify target host(s), bypassing git change detection
  -y, --yes            Skip confirmation prompt and proceed immediately
  -d, --dry-run        Print affected hosts and command without running Ansible
  -h, --help           Show this help message

Extra Ansible Arguments:
  Any extra arguments (or arguments after '--') are forwarded directly to ansible-playbook.
  Example:
    deploy_compose.sh --check
    deploy_compose.sh -p -- --diff -v
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -y|--yes)
      AUTO_CONFIRM=true
      shift
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -p|--pull)
      GIT_RANGE="pull"
      shift
      ;;
    -1|--last)
      GIT_RANGE="HEAD~1..HEAD"
      shift
      ;;
    -r|--range)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --range requires a git revision or range argument." >&2
        exit 1
      fi
      GIT_RANGE="$2"
      shift 2
      ;;
    -w|--working-tree)
      GIT_RANGE="working-tree"
      shift
      ;;
    -l|--hosts)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --hosts requires a hostname argument." >&2
        exit 1
      fi
      MANUAL_HOSTS="$2"
      shift 2
      ;;
    --)
      shift
      ANSIBLE_EXTRA_ARGS+=("$@")
      break
      ;;
    *)
      # Pass through any unknown options to ansible-playbook
      ANSIBLE_EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

cd "$ANSIBLE_DIR"

get_working_tree_files() {
  (
    git -C "$GIT_ROOT" diff --name-only HEAD 2>/dev/null || true
    git -C "$GIT_ROOT" ls-files --others --exclude-standard 2>/dev/null || true
  ) | sort -u
}

if [[ -n "$MANUAL_HOSTS" ]]; then
  TARGET_HOSTS="$MANUAL_HOSTS"
  echo "Using manually specified target hosts: $TARGET_HOSTS"
else
  # Auto-determine git range if not specified
  DETECT_SOURCE=""
  CHANGED_FILES=""

  if [[ "$GIT_RANGE" == "working-tree" ]]; then
    DETECT_SOURCE="working tree (modified, staged, and untracked)"
    CHANGED_FILES=$(get_working_tree_files)
  elif [[ "$GIT_RANGE" == "pull" ]]; then
    if ! git -C "$GIT_ROOT" rev-parse --verify ORIG_HEAD &>/dev/null; then
      echo "Error: ORIG_HEAD is not set in git. Have you run 'git pull' recently?" >&2
      exit 1
    fi
    DETECT_SOURCE="git pull (ORIG_HEAD..HEAD)"
    CHANGED_FILES=$(git -C "$GIT_ROOT" diff --name-only ORIG_HEAD HEAD)
  elif [[ -n "$GIT_RANGE" ]]; then
    DETECT_SOURCE="custom range ($GIT_RANGE)"
    if [[ "$GIT_RANGE" == *..* ]]; then
      CHANGED_FILES=$(git -C "$GIT_ROOT" diff --name-only "$GIT_RANGE")
    else
      CHANGED_FILES=$(git -C "$GIT_ROOT" diff --name-only "$GIT_RANGE~1" "$GIT_RANGE")
    fi
  else
    # Automatic detection sequence:
    DETECT_SOURCES=()
    COMBINED_FILES=()

    # 1. Check for pulled changes if ORIG_HEAD differs from HEAD
    ORIG_HEAD_VAL=$(git -C "$GIT_ROOT" rev-parse --verify ORIG_HEAD 2>/dev/null || true)
    HEAD_VAL=$(git -C "$GIT_ROOT" rev-parse --verify HEAD 2>/dev/null || true)
    
    if [[ -n "$ORIG_HEAD_VAL" && "$ORIG_HEAD_VAL" != "$HEAD_VAL" ]]; then
      PULLED_FILES=$(git -C "$GIT_ROOT" diff --name-only ORIG_HEAD HEAD 2>/dev/null || true)
      PULLED_SERVICES=$(echo "$PULLED_FILES" | grep -E '(^|/)services/' || true)
      if [[ -n "$PULLED_SERVICES" ]]; then
        DETECT_SOURCES+=("latest git pull (ORIG_HEAD..HEAD)")
        COMBINED_FILES+=("$PULLED_SERVICES")
      fi
    fi

    # 2. Check for local changes (modified, staged, or untracked)
    LOCAL_FILES=$(get_working_tree_files)
    LOCAL_SERVICES=$(echo "$LOCAL_FILES" | grep -E '(^|/)services/' || true)
    if [[ -n "$LOCAL_SERVICES" ]]; then
      DETECT_SOURCES+=("local working tree changes")
      COMBINED_FILES+=("$LOCAL_SERVICES")
    fi

    # 3. Fallback to latest commit if neither yielded any services
    if [[ ${#COMBINED_FILES[@]} -eq 0 ]]; then
      LATEST_COMMIT_FILES=$(git -C "$GIT_ROOT" diff --name-only HEAD~1 HEAD 2>/dev/null || true)
      DETECT_SOURCES+=("latest commit (HEAD~1..HEAD)")
      COMBINED_FILES+=("$LATEST_COMMIT_FILES")
    fi

    DETECT_SOURCE=$(printf " + %s" "${DETECT_SOURCES[@]}")
    DETECT_SOURCE="${DETECT_SOURCE# + }"
    CHANGED_FILES=$(printf "%s\n" "${COMBINED_FILES[@]}" | sort -u)
  fi

  echo "=========================================================="
  echo " Detection source: $DETECT_SOURCE"
  echo "=========================================================="

  # Extract unique service paths: services/<host>/<service>
  SERVICE_PAIRS=$(echo "$CHANGED_FILES" | grep -oP '(?<=services/)[^/]+/[^/]+' | sort -u || true)

  if [[ -z "$SERVICE_PAIRS" ]]; then
    echo "No Docker Compose services modified in detected changes."
    echo ""
    echo "Tips:"
    echo "  - To check your last git pull:   $0 --pull"
    echo "  - To check the last N commits:  $0 --range HEAD~3..HEAD"
    echo "  - To specify hosts manually:    $0 --hosts host1,host2"
    exit 0
  fi

  echo "Modified services detected:"
  CURRENT_HOST=""
  while IFS=/ read -r host svc; do
    if [[ "$host" != "$CURRENT_HOST" ]]; then
      echo "  • $host:"
      CURRENT_HOST="$host"
    fi
    echo "      - $svc"
  done <<< "$SERVICE_PAIRS"

  # Build comma-separated target hosts list
  TARGET_HOSTS=$(echo "$SERVICE_PAIRS" | cut -d'/' -f1 | sort -u | paste -sd, -)
  echo "----------------------------------------------------------"
  echo "Target host limit (-l): $TARGET_HOSTS"
  echo "=========================================================="
fi

# Build Ansible command array
CMD=(ansible-playbook site.yml --tags compose -l "$TARGET_HOSTS")
if [[ ${#ANSIBLE_EXTRA_ARGS[@]} -gt 0 ]]; then
  CMD+=("${ANSIBLE_EXTRA_ARGS[@]}")
fi

echo ""
echo "Command to execute:"
echo "  ${CMD[*]}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[Dry run] Exiting without running Ansible."
  exit 0
fi

if [[ "$AUTO_CONFIRM" != "true" ]]; then
  read -r -p "Proceed with deployment? [Y/n] " response
  response=${response:-Y}
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled."
    exit 0
  fi
fi

echo ""
echo "Running Ansible playbook..."
echo ""
exec "${CMD[@]}"
