#!/usr/bin/env bash

set -euo pipefail

SERVICE="compute.googleapis.com"
PROJECT_ID=""
BILLING_PROJECT=""
QUOTA_ID=""
DIMENSION_TYPE=""
REGION=""
PREFERRED_VALUE=""
DRY_RUN=false

usage() {
  cat <<EOF
Usage:

Regional quota:
  $0 \\
    --project-id PROJECT_ID \\
    --quota-id QUOTA_ID \\
    --dimension-type region \\
    --region REGION \\
    --preferred-value VALUE [--dry-run]

Global quota:
  $0 \\
    --project-id PROJECT_ID \\
    --quota-id QUOTA_ID \\
    --dimension-type global \\
    --preferred-value VALUE [--dry-run]

Options:
  --project-id       GCP project ID
  --billing-project  Billing project ID (defaults to project-id)
  --quota-id         Quota ID
  --service          GCP service (default: compute.googleapis.com)
  --dimension-type   region | global
  --region           Region, required when dimension-type=region
  --preferred-value  Requested quota value
  --dry-run          Show what would happen without changing GCP
  --help             Show this help

Examples:

  $0 \\
    --project-id angulartest-71992 \\
    --quota-id C3-CPUS-per-project-region \\
    --dimension-type region \\
    --region us-east1 \\
    --preferred-value 140

  $0 \\
    --project-id angulartest-71992 \\
    --quota-id C3-CPUS-per-project-region \\
    --dimension-type region \\
    --region us-east1 \\
    --preferred-value 140 \\
    --dry-run
EOF
}

log() {
  echo "[INFO] $*"
}

error() {
  echo "[ERROR] $*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    --billing-project)
      BILLING_PROJECT="$2"
      shift 2
      ;;
    --quota-id)
      QUOTA_ID="$2"
      shift 2
      ;;
    --service)
      SERVICE="$2"
      shift 2
      ;;
    --dimension-type)
      DIMENSION_TYPE="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --preferred-value)
      PREFERRED_VALUE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      error "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$PROJECT_ID" ]] || error "--project-id is required"
[[ -n "$QUOTA_ID" ]] || error "--quota-id is required"
[[ -n "$DIMENSION_TYPE" ]] || error "--dimension-type is required"
[[ -n "$PREFERRED_VALUE" ]] || error "--preferred-value is required"

if [[ "$DIMENSION_TYPE" != "region" && "$DIMENSION_TYPE" != "global" ]]; then
  error "--dimension-type must be 'region' or 'global'"
fi

if [[ "$DIMENSION_TYPE" == "region" && -z "$REGION" ]]; then
  error "--region is required when --dimension-type=region"
fi

if [[ "$DIMENSION_TYPE" == "global" && -n "$REGION" ]]; then
  error "--region cannot be used when --dimension-type=global"
fi

if ! [[ "$PREFERRED_VALUE" =~ ^[0-9]+$ ]]; then
  error "--preferred-value must be an integer"
fi

if ! command -v gcloud >/dev/null 2>&1; then
  error "gcloud is not installed or is not in PATH"
fi

if [[ -z "$BILLING_PROJECT" ]]; then
  BILLING_PROJECT="$PROJECT_ID"
fi

PREFERENCE_ID=""
GRANTED_VALUE=""
CURRENT_PREFERRED_VALUE=""
RECONCILING=""
STATE_DETAIL=""

find_preference() {
  PREFERENCE_ID=""

  local preferences

  preferences="$(
    gcloud quotas preferences list \
      --project="$PROJECT_ID" \
      --billing-project="$BILLING_PROJECT" \
      --format="value(name.basename(),service,quotaId,dimensions.region)"
  )"

  while read -r preference_id service quota_id preference_region; do

    [[ -n "$preference_id" ]] || continue

    if [[ "$service" != "$SERVICE" ]]; then
      continue
    fi

    if [[ "$quota_id" != "$QUOTA_ID" ]]; then
      continue
    fi

    if [[ "$DIMENSION_TYPE" == "region" ]]; then
      if [[ "$preference_region" == "$REGION" ]]; then
        PREFERENCE_ID="$preference_id"
        break
      fi
    else
      if [[ -z "$preference_region" ]]; then
        PREFERENCE_ID="$preference_id"
        break
      fi
    fi

  done <<< "$preferences"
}

get_preference_details() {
  GRANTED_VALUE="$(
    gcloud quotas preferences describe "$PREFERENCE_ID" \
      --project="$PROJECT_ID" \
      --billing-project="$BILLING_PROJECT" \
      --format="value(quotaConfig.grantedValue)"
  )"

  CURRENT_PREFERRED_VALUE="$(
    gcloud quotas preferences describe "$PREFERENCE_ID" \
      --project="$PROJECT_ID" \
      --billing-project="$BILLING_PROJECT" \
      --format="value(quotaConfig.preferredValue)"
  )"

  RECONCILING="$(
    gcloud quotas preferences describe "$PREFERENCE_ID" \
      --project="$PROJECT_ID" \
      --billing-project="$BILLING_PROJECT" \
      --format="value(reconciling)"
  )"

  STATE_DETAIL="$(
    gcloud quotas preferences describe "$PREFERENCE_ID" \
      --project="$PROJECT_ID" \
      --billing-project="$BILLING_PROJECT" \
      --format="value(quotaConfig.stateDetail)"
  )"

  RECONCILING="${RECONCILING,,}"
}

create_preference() {
  log "Creating quota preference..."

  if [[ "$DIMENSION_TYPE" == "region" ]]; then
    gcloud quotas preferences create \
      --project="$PROJECT_ID" \
      --billing-project="$BILLING_PROJECT" \
      --service="$SERVICE" \
      --quota-id="$QUOTA_ID" \
      --preferred-value="$PREFERRED_VALUE" \
      --dimensions="region=$REGION"
  else
    gcloud quotas preferences create \
      --project="$PROJECT_ID" \
      --billing-project="$BILLING_PROJECT" \
      --service="$SERVICE" \
      --quota-id="$QUOTA_ID" \
      --preferred-value="$PREFERRED_VALUE"
  fi
}

update_preference() {
  log "Updating quota preference: $PREFERENCE_ID"

  if [[ "$DIMENSION_TYPE" == "region" ]]; then
    gcloud quotas preferences update "$PREFERENCE_ID" \
      --project="$PROJECT_ID" \
      --billing-project="$BILLING_PROJECT" \
      --preferred-value="$PREFERRED_VALUE" \
      --dimensions="region=$REGION"
  else
    gcloud quotas preferences update "$PREFERENCE_ID" \
      --project="$PROJECT_ID" \
      --billing-project="$BILLING_PROJECT" \
      --preferred-value="$PREFERRED_VALUE"
  fi
}

show_plan() {
  echo
  echo "========================================"
  echo "GCP QUOTA PLAN"
  echo "========================================"
  echo "Project:           $PROJECT_ID"
  echo "Billing project:   $BILLING_PROJECT"
  echo "Service:           $SERVICE"
  echo "Quota ID:          $QUOTA_ID"
  echo "Dimension type:    $DIMENSION_TYPE"

  if [[ "$DIMENSION_TYPE" == "region" ]]; then
    echo "Region:            $REGION"
  fi

  echo "Requested value:   $PREFERRED_VALUE"

  if [[ -n "$PREFERENCE_ID" ]]; then
    echo "Preference ID:     $PREFERENCE_ID"
    echo "Granted value:     $GRANTED_VALUE"
    echo "Current preferred: $CURRENT_PREFERRED_VALUE"
    echo "Reconciling:       $RECONCILING"
    echo "State:             ${STATE_DETAIL:-N/A}"
    echo "Action:             UPDATE"
  else
    echo "Preference ID:     NONE"
    echo "Action:             CREATE"
  fi

  echo "Dry-run:            $DRY_RUN"
  echo "========================================"
  echo
}

log "Searching for existing quota preference..."

find_preference

if [[ -n "$PREFERENCE_ID" ]]; then

  log "Existing preference found: $PREFERENCE_ID"

  get_preference_details

  if [[ "$RECONCILING" == "true" ]]; then
    show_plan
    error "Quota preference is currently reconciling. Wait until the current request finishes."
  fi

  if [[ -n "$GRANTED_VALUE" ]] && ! [[ "$GRANTED_VALUE" =~ ^[0-9]+$ ]]; then
    error "Unable to determine current granted quota value."
  fi

  if [[ -n "$CURRENT_PREFERRED_VALUE" ]] && ! [[ "$CURRENT_PREFERRED_VALUE" =~ ^[0-9]+$ ]]; then
    error "Unable to determine current preferred quota value."
  fi

  if [[ -n "$GRANTED_VALUE" && "$PREFERRED_VALUE" -lt "$GRANTED_VALUE" ]]; then
    error "Requested value ($PREFERRED_VALUE) cannot be lower than the granted value ($GRANTED_VALUE)."
  fi

  if [[ -n "$CURRENT_PREFERRED_VALUE" && "$PREFERRED_VALUE" -lt "$CURRENT_PREFERRED_VALUE" ]]; then
    error "Requested value ($PREFERRED_VALUE) cannot be lower than the current preferred value ($CURRENT_PREFERRED_VALUE)."
  fi

  if [[ -n "$CURRENT_PREFERRED_VALUE" && "$PREFERRED_VALUE" -eq "$CURRENT_PREFERRED_VALUE" ]]; then
    show_plan
    log "Requested value is already the current preferred value. No changes required."
    exit 0
  fi

  show_plan

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: no changes were made to Google Cloud."
    exit 0
  fi

  update_preference

else

  log "No existing quota preference found."

  show_plan

  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY-RUN: no changes were made to Google Cloud."
    exit 0
  fi

  create_preference
fi

echo
log "Quota operation completed."

echo
log "Retrieving final quota preference status..."

find_preference

if [[ -z "$PREFERENCE_ID" ]]; then
  error "Quota preference was not found after the operation."
fi

get_preference_details

echo
echo "========================================"
echo "FINAL STATUS"
echo "========================================"
echo "Preference ID:     $PREFERENCE_ID"
echo "Granted value:     ${GRANTED_VALUE:-N/A}"
echo "Preferred value:   ${CURRENT_PREFERRED_VALUE:-N/A}"
echo "Reconciling:       ${RECONCILING:-N/A}"
echo "State:             ${STATE_DETAIL:-N/A}"
echo "========================================"