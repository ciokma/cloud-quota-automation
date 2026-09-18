import os
import yaml
import google.auth
from google.cloud import cloudquotas_v1

# ==============================================================================
# CONFIGURATION & CONTROL FLAGS
# ==============================================================================
REQUEST_QUOTA_INCREASE = True  # Set to True to submit actual QuotaPreference requests to GCP.

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


def get_current_quota_info(client, project_id, service, quota_id):
    """Queries current quota details directly from GCP Cloud Quotas API."""
    quota_info_name = (
        f"projects/{project_id}"
        f"/locations/global"
        f"/services/{service}"
        f"/quotaInfos/{quota_id}"
    )
    
    print(f"[QUERY] Fetching quota details for '{quota_id}'...")
    try:
        quota_info = client.get_quota_info(name=quota_info_name)
        return quota_info
    except Exception as e:
        print(f"[ERROR] Failed to retrieve quota info for '{quota_id}': {e}")
        return None


def extract_region_quota_limit(quota_info, target_region):
    """Parses quota_info to find the current limit for a specific region."""
    if not quota_info or not quota_info.dimensions_infos:
        return 0

    for dim_info in quota_info.dimensions_infos:
        region_dim = dim_info.dimensions.get("region")
        if region_dim == target_region or target_region in dim_info.applicable_locations:
            if dim_info.details and dim_info.details.value:
                return dim_info.details.value
            for bucket in dim_info.quota_buckets:
                if bucket.effective_limit:
                    return bucket.effective_limit

    return 0


def request_quota_increase(client, project_id, region, service, quota_id, target_value, contact_email):
    """Submits a QuotaPreference request to GCP to increase the quota limit."""
    parent = f"projects/{project_id}/locations/global"
    
    clean_quota_id = quota_id.lower().replace("_", "-")
    preference_id = f"inc-{clean_quota_id[:10]}-{target_value}"
    
    quota_preference = cloudquotas_v1.QuotaPreference(
        service=service,
        quota_id=quota_id,
        contact_email=contact_email,
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
        print(f"[ACTION] Submitting quota preference request for {target_value} units in '{region}'...")
        response = client.create_quota_preference(request=request)
        print(f"[SUCCESS] Quota increase request created successfully!")
        print(f"         Resource Name: {response.name}")
        print(f"         Preferred Value: {response.quota_config.preferred_value}")
        print(f"         Reconciling Status: {response.reconciling}")
    except Exception as e:
        print(f"[ERROR] Failed to submit quota increase request: {e}")


def main():
    print("=" * 80)
    print("GCP QUOTA AUTOMATION - VCPU METRIC CHECK")
    print("=" * 80)
    
    # 1. Load configuration
    config = load_config("config.yaml")
    project_id = config.get("project_id")
    region = config.get("region")
    contact_email = config.get("contact_email", "") 
    spark_config = config.get("spark", {})
    
    print(f"Project ID    : {project_id}")
    print(f"Region        : {region}")
    print(f"Contact Email : {contact_email}")
    print(f"Flag Status   : REQUEST_QUOTA_INCREASE = {REQUEST_QUOTA_INCREASE}")
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
        service=SERVICE_NAME,
        quota_id=QUOTA_ID_C3_VCPU
    )
    
    if not quota_info:
        print("[ABORT] Could not retrieve current quota info.")
        return
    
    current_limit = extract_region_quota_limit(quota_info, region)

    print("-" * 80)
    print(f"Metric Display Name : {quota_info.metric_display_name}")
    print(f"Current Limit in GCP ({region}): {current_limit}")
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
            target_value=required_cpus,
            contact_email=contact_email
        )
    else:
        print("[NOTICE] REQUEST_QUOTA_INCREASE is set to False.")
        print("         No request was submitted to GCP. Set flag to True to auto-request.")


if __name__ == "__main__":
    main()