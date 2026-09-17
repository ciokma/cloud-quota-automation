import os
import yaml
import google.auth
from google.cloud import cloudquotas_v1

# ==============================================================================
# CONFIGURATION & CONTROL FLAGS
# ==============================================================================
# Set to True to submit actual QuotaPreference requests to GCP.
# Set to False to run in Dry-Run / Audit mode only.
REQUEST_QUOTA_INCREASE = False

SERVICE_NAME = "compute.googleapis.com"
QUOTA_ID_C3_VCPU = "C3-CPUS-per-project-region"  # GCP Quota ID for C3 vCPUs


def load_config(config_path="config.yaml"):
    """Reads and parses the YAML configuration file."""
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Configuration file not found at: {config_path}")
    
    with open(config_path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def calculate_required_cpus(spark_config):
    """Calculates total vCPUs required based on Spark workers and CPU per worker."""
    workers = spark_config.get("workers", 0)
    cpu_per_worker = spark_config.get("cpu_per_worker", 0)
    
    total_cpus = workers * cpu_per_worker
    print(f"[CALCULATION] Workers: {workers} | CPU/Worker: {cpu_per_worker} => Total Required vCPUs: {total_cpus}")
    return total_cpus


def get_current_quota_info(client, project_id, region, service, quota_id):
    """Queries current quota details directly from GCP Cloud Quotas API."""
    # GCP Cloud Quotas API expects 'global' in the resource name path for quotaInfos
    quota_info_name = (
        f"projects/{project_id}"
        f"/locations/global"
        f"/services/{service}"
        f"/quotaInfos/{quota_id}"
    )
    
    print(f"[QUERY] Fetching quota details for '{quota_id}' (Target Region: '{region}')...")
    try:
        quota_info = client.get_quota_info(name=quota_info_name)
        return quota_info
    except Exception as e:
        print(f"[ERROR] Failed to retrieve quota info for '{quota_id}': {e}")
        return None

def request_quota_increase(client, project_id, region, service, quota_id, target_value):
    """Submits a QuotaPreference request to GCP to increase the quota limit."""
    parent = f"projects/{project_id}/locations/{region}"
    preference_id = f"inc-{quota_id.lower()[:15]}-{target_value}"
    
    quota_preference = cloudquotas_v1.QuotaPreference(
        service=service,
        quota_id=quota_id,
        dimensions={"region": region} if region != "global" else {},
        quota_config=cloudquotas_v1.QuotaConfig(
            preferred_value=target_value
        ),
    )
    
    request = cloudquotas_v1.CreateQuotaPreferenceRequest(
        parent=parent,
        quota_preference_id=preference_id,
        quota_preference=quota_preference,
    )
    
    try:
        print(f"[ACTION] Submitting quota preference request for {target_value} units...")
        response = client.create_quota_preference(request=request)
        print(f"[SUCCESS] Quota increase request created successfully!")
        print(f"          Resource Name: {response.name}")
        print(f"          Preferred Value: {response.quota_config.preferred_value}")
    except Exception as e:
        print(f"[ERROR] Failed to submit quota increase request: {e}")


def main():
    print("=" * 80)
    print("GCP QUOTA AUTOMATION - VCPU METRIC CHECK")
    print("=" * 80)
    
    # 1. Load configuration from config.yaml
    config = load_config("config.yaml")
    project_id = config.get("project_id")
    region = config.get("region")
    spark_config = config.get("spark", {})
    
    print(f"Project ID : {project_id}")
    print(f"Region     : {region}")
    print(f"Flag Status: REQUEST_QUOTA_INCREASE = {REQUEST_QUOTA_INCREASE}")
    print("-" * 80)
    
    # 2. Calculate target metric dynamically
    required_cpus = calculate_required_cpus(spark_config)
    
    # 3. Authenticate and initialize client
    credentials, _ = google.auth.default()
    client = cloudquotas_v1.CloudQuotasClient(credentials=credentials)
    
    # 4. Query current quota status
    quota_info = get_current_quota_info(
        client=client,
        project_id=project_id,
        region=region,
        service=SERVICE_NAME,
        quota_id=QUOTA_ID_C3_VCPU
    )
    
    if not quota_info:
        print("[ABORT] Could not retrieve current quota info.")
        return
    
    # Extract current quota limit from dimensions_infos
    current_limit = 0
    if quota_info.dimensions_infos:
        for dim_info in quota_info.dimensions_infos:
            if dim_info.details and dim_info.details.value:
                current_limit = dim_info.details.value
                break

    print("-" * 80)
    print(f"Metric Display Name : {quota_info.metric_display_name}")
    print(f"Current Limit in GCP: {current_limit}")
    print(f"Calculated Target   : {required_cpus}")
    print("-" * 80)
    
    # 5. Compare current vs required quota
    if current_limit >= required_cpus:
        print("[STATUS] OK - Current quota limit is sufficient for the workload.")
        return
    
    print(f"[WARNING] Current limit ({current_limit}) is lower than required ({required_cpus}).")
    
    # 6. Evaluate flag before requesting increase
    if REQUEST_QUOTA_INCREASE:
        request_quota_increase(
            client=client,
            project_id=project_id,
            region=region,
            service=SERVICE_NAME,
            quota_id=QUOTA_ID_C3_VCPU,
            target_value=required_cpus
        )
    else:
        print("[NOTICE] REQUEST_QUOTA_INCREASE is set to False.")
        print("         No request was submitted to GCP. Set flag to True to auto-request.")


if __name__ == "__main__":
    main()