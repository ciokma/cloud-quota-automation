pip install requeriments.txt
gcloud auth application-default login
gcloud services enable cloudquotas.googleapis.com
# error  when not enable quota
## message: "Cloud Quotas API has not been used in project angulartest-71992 before or it is disabled. Enable it by visiting https://console.developers.google.com/apis/api/cloudquotas.googleapis.com/overview?project=angulartest-71992 then retry. If you enabled this API recently, wait a few minutes for the action to propagate to our systems and retry."


# option 1
## Through Script Automation (Python + Cloud Client Library)
Enable API
gcloud services enable serviceusage.googleapis.com

## enable compute
gcloud services enable compute.googleapis.com --project=angulartest-71992

WSL
 gcloud auth login --no-launch-browser

 ## Get quota value

 gcloud quotas info describe "C3-CPUS-per-project-region" --service=compute.googleapis.com --project=angulartest-71992   --format="yaml(dimensionsInfos)"

  gcloud quotas info describe "FIREWALLS-per-project" --service=compute.googleapis.com --project=angulartest-71992   --format="yaml(dimensionsInfos)"

   gcloud quotas info describe "SSD-TOTAL-GB-per-project-region" --service=compute.googleapis.com --project=angulartest-71992   --format="yaml(dimensionsInfos)"

   
   gcloud quotas info describe "SECURITY-POLICY-CEVAL-RULES-per-project" --service=compute.googleapis.com --project=angulartest-71992   --format="yaml(dimensionsInfos)"

   gcloud quotas preferences list --project=angulartest-71992  --billing-preferences="angulartest-71992"


## Request quota increase
## us-east1
PS C:\Users\maure> gcloud quotas preferences create --project=angulartest-71992  --service=compute.googleapis.com --quota-id="C3-CPUS-per-project-region" --dimensions="region=us-east1" --preferred-value="25" --billing-project="angulartest-71992" --email="maurez89@yahoo.es" --justification="Production capacity increase for expected workload growth"

## us-central1
 gcloud quotas preferences create --project=angulartest-71992  --service=compute.googleapis.com --quota-id="C3-CPUS-per-project-region" --dimensions="region=us-central1" --preferred-value="25" --billing-project="angulartest-71992" --email="maurez89@yahoo.es" --justification="Production capacity increase for expected workload growth"
{
    "createTime":"2026-09-21T03:44:35.751249870Z",
    "dimensions":{
        "region":"us-central1"
    },
    "etag":"VZD0h4kGtBVFqBCSVxeS8VyMnLPwOusqggt19-pNMok",
    "name":"projects/angulartest-71992/locations/global/quotaPreferences/a545fb60-6658-4436-b1c7-70d9482116df",
    "quotaConfig":{
        "grantedValue":"24",
        "preferredValue":"25",
        "traceId":"1ba91a6e-d956-4e34-910a-c1d0a2b4200a"
    },
    "quotaId":"C3-CPUS-per-project-region",
    "reconciling":true,
    "service":"compute.googleapis.com",
    "updateTime":"2026-09-21T03:44:35.751249870Z"
}

## Monitor request
   PS C:\Users\maure> gcloud quotas preferences list --project=angulartest-71992  --billing-project="angulartest-71992"
---
createTime: '2026-09-21T03:44:35.751249870Z'
dimensions:
  region: us-central1
etag: dXda0oYnXfHj5vpyPv-EGF-NjvAyq7-YBHl8Oxda9Io
name: projects/angulartest-71992/locations/global/quotaPreferences/a545fb60-6658-4436-b1c7-70d9482116df
quotaConfig:
  grantedValue: '24'
  preferredValue: '25'
  stateDetail: Quota request denied
  traceId: 1ba91a6e-d956-4e34-910a-c1d0a2b4200a
quotaId: C3-CPUS-per-project-region
service: compute.googleapis.com
updateTime: '2026-09-21T03:44:39.476291574Z'
---
createTime: '2026-09-17T21:32:11.221718948Z'
dimensions:
  region: us-east1
etag: gm40EPHooD4X2bHWkzsNthuRRVlhe2cl3OLckjchZMQ
name: projects/angulartest-71992/locations/global/quotaPreferences/inc-c3-cpus-pe-28
quotaConfig:
  grantedValue: '24'
  preferredValue: '28'
  stateDetail: Quota request denied
  traceId: 2a91757a-c72b-4f95-b3d1-3a10fa86c4b2
quotaId: C3-CPUS-per-project-region
service: compute.googleapis.com
updateTime: '2026-09-17T21:32:14.907083234Z'

## enable quota adjuster
https://docs.cloud.google.com/capacity-planner/docs/enable-quota-adjuster
Preview

This product is subject to the "Pre-GA Offerings Terms" in the General Service Terms section of the Service Specific Terms. Pre-GA products are available "as is" and might have limited support.

gcloud projects add-iam-policy-binding angulartest-71992 `
  --member="user:maurez89@gmail.com" `
  --role="roles/capacityplanner.viewer"

  gcloud projects add-iam-policy-binding angulartest-71992 `
  --member="user:maurez89@gmail.com" `
  --role="roles/cloudquotas.admin"


  gcloud projects add-iam-policy-binding angulartest-71992 `
  --member="user:maurez89@gmail.com" `
  --role="roles/cloudquotas.admin"