# regional quote
./gcp-quota-manager.sh \
  --project-id angulartest-71992 \
  --quota-id C3-CPUS-per-project-region \
  --dimension-type region \
  --region us-east1 \
  --preferred-value 140

  # global quote
  ./gcp-quota-manager.sh \
  --project-id angulartest-71992 \
  --quota-id SOME-GLOBAL-QUOTA \
  --dimension-type global \
  --preferred-value 500

  # dry run execution
  ./gcp-quota-manager.sh \
  --project-id angulartest-71992 \
  --quota-id C3-CPUS-per-project-region \
  --dimension-type region \
  --region us-east1 \
  --preferred-value 32 \
  --dry-run


# examples
  maure@ciokma:/mnt/c/work/google/cloud-quota-automation$   # dry run execution
  ./gcp-quota-manager.sh \
  --project-id angulartest-71992 \
  --quota-id C3-CPUS-per-project-region \
  --dimension-type region \
  --region us-east1 \
  --preferred-value 32 \
  --dry-run
[INFO] Searching for existing quota preference...
[INFO] Existing preference found: inc-c3-cpus-pe-28

========================================
GCP QUOTA PLAN
========================================
Project:           angulartest-71992
Billing project:   angulartest-71992
Service:           compute.googleapis.com
Quota ID:          C3-CPUS-per-project-region
Dimension type:    region
Region:            us-east1
Requested value:   32
Preference ID:     inc-c3-cpus-pe-28
Granted value:     31
Current preferred: 31
Reconciling:
State:             Quota request approved to 31
Action:             UPDATE
Dry-run:            true
========================================

[INFO] DRY-RUN: no changes were made to Google Cloud.
maure@ciokma:/mnt/c/work/google/cloud-quota-automation$ ./gcp-quota-manager.sh \
  --project-id angulartest-71992 \
  --quota-id FIREWALLS-per-project \
  --dimension-type region \
  --region us-east1 \
  --preferred-value 32 \
  --dry-run
[INFO] Searching for existing quota preference...
[INFO] No existing quota preference found.

========================================
GCP QUOTA PLAN
========================================
Project:           angulartest-71992
Billing project:   angulartest-71992
Service:           compute.googleapis.com
Quota ID:          FIREWALLS-per-project
Dimension type:    region
Region:            us-east1
Requested value:   32
Preference ID:     NONE
Action:             CREATE
Dry-run:            true
========================================

[INFO] DRY-RUN: no changes were made to Google Cloud.

# regional
./gcp-quota-manager.sh \
  --project-id angulartest-71992 \
  --quota-id C3-CPUS-per-project-region \
  --dimension-type region \
  --region us-east1 \
  --preferred-value 32 \
  --dry-run

# global
./gcp-quota-manager.sh \
  --project-id angulartest-71992 \
  --quota-id FIREWALLS-per-project \
  --dimension-type global \
  --preferred-value 132 \
  --dry-run