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