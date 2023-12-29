/*
provider "google" {
  project     = var.project_id
  credentials = file(var.gcp_auth_file)
  region      = var.gcp_region
}
data "google_compute_zones" "compute_zones" {
  region  = var.gcp_region
  project = var.project_id
}
locals {
  types  = ["public", "private"]
  subnets = {
    "01" = {
      ip          = element(var.ip_cidr_range, 0)
      region      = var.gcp_region
      description = "Subnet to be used in the D6 GKE cluster"
      secondary_ranges = {
        gke-pods     = element(var.ip_cidr_range_secondary, 0)
        gke-services = element(var.ip_cidr_range_secondary, 1)
      }
    }
  }
}
*/

# airflow.tf ##### Airflow HELM
resource "helm_release" "airflow" {
  count = var.deploy_airflow ? 1 : 0
  name       = "airflow"
  chart      = "airflow"
  repository = "https://airflow.apache.org"
  version    = var.airflow_version
  namespace  = var.k8s_airflow_namespace
  wait = false

  values = [
    templatefile(var.airflow_values_filepath, {}),
  ]

  #depends_on = [module.secrets.airflow_db_credentials_secret]
  #depends_on = [module.secrets.airflow_db_credentials]
  depends_on = [kubernetes_secret_v1.airflow_db_credentials]
}

/* Secret managment
# Secret managment # "terraform-gcp-airflow-module" gke.tf
module "secrets" {
  source = "./modules/secrets"
  deploy_cloud_sql = var.deploy_cloud_sql
  k8s_airflow_namespace = var.k8s_airflow_namespace
  #airflow_db_credentials_secret = var.airflow_db_credentials_secret
  broker_url_secret_name = var.broker_url_secret_name
  create_redis_secrets = var.create_redis_secrets
  k8s_airflow_fernet_key_secret_name = var.k8s_airflow_fernet_key_secret_name
  k8s_db_credentials_secret_name = var.k8s_db_credentials_secret_name
  redis_password_secret_name = var.redis_password_secret_name
  k8s_git_sync_secret_name = var.k8s_git_sync_secret_name
  k8s_webserver_secret_key_secret_name = var.k8s_webserver_secret_key_secret_name
}
*/

# gke.tf # put in modules/secrets
resource "random_password" "webserver_secret_key" {
  count   = var.deploy_cloud_sql ? 1 : 0
  length  = 12
  special = false
}

resource "kubernetes_secret_v1" "webserver_secret_key" {
  count = var.deploy_cloud_sql ? 1 : 0
  metadata {
    name      = var.k8s_webserver_secret_key_secret_name
    namespace = var.k8s_airflow_namespace
  }

  data = {
    (var.k8s_webserver_secret_key_secret_name) = random_password.webserver_secret_key[0].result
  }
}

resource "kubernetes_secret_v1" "airflow_db_credentials" {
  count = var.deploy_cloud_sql ? 1 : 0
  metadata {
    name      = var.k8s_db_credentials_secret_name
    namespace = var.k8s_airflow_namespace
  }

  data = {
    connection = "postgresql://${google_sql_user.db_user[0].name}:${random_password.db_password[0].result}@${google_sql_database_instance.airflow_db[0].first_ip_address}:5432/${var.sql_database_name}"
  }
}

resource "kubernetes_secret_v1" "fernet_key_secret" {
  count = var.deploy_cloud_sql ? 1 : 0
  metadata {
    name      = var.k8s_airflow_fernet_key_secret_name
    namespace = var.k8s_airflow_namespace
  }

  data = {
    fernet-key = base64encode(random_password.fernet_key[0].result)
  }
}

resource "kubernetes_secret_v1" "gitsync_creds" {
  count = var.deploy_github_keys ? 1 : 0
  metadata {
    name      = var.k8s_git_sync_secret_name
    namespace = var.k8s_airflow_namespace
  }
  data = {
    gitSshKey = tls_private_key.github_deploy_key[0].private_key_openssh
  }
}

resource "random_password" "redis_password" {
  count   = var.create_redis_secrets ? 1 : 0
  length  = 12
  special = false
}

resource "kubernetes_secret_v1" "redis_password" {
  count = var.create_redis_secrets ? 1 : 0
  metadata {
    name      = var.redis_password_secret_name
    namespace = var.k8s_airflow_namespace
  }
  data = {
    password = random_password.redis_password[0].result
  }
}

resource "kubernetes_secret_v1" "broker_url" {
  count = var.create_redis_secrets ? 1 : 0
  metadata {
    name      = var.broker_url_secret_name
    namespace = var.k8s_airflow_namespace
  }
  data = {
    connection = "redis://:${random_password.redis_password[0].result}@airflow-redis:6379/0"
  }
}


# cloud_sql.tf # put in modules/cloud_sql
resource "google_sql_database_instance" "airflow_db" {
  count            = var.deploy_cloud_sql ? 1 : 0
  name             = var.sql_instance_name
  database_version = var.sql_version

  project = var.project_id
  region  = var.region
  #region = "europe-west1"
  #region = var.gcp_region

  deletion_protection = false
  #deletion_protection = var.sql_delete_protection

  settings {
    tier              = var.sql_tier
    edition           = var.sql_edition
    availability_type = var.sql_availability_type

    ip_configuration {
      ipv4_enabled                                  = var.sql_private_network == null ? true : false
      private_network                               = var.sql_private_network
      enable_private_path_for_google_cloud_services = var.sql_private_network == null ? false : true
      allocated_ip_range                            = var.allocated_ip_range
      require_ssl                                   = var.require_ssl
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }
  }
}

resource "google_sql_database" "airflow" {
  count    = var.deploy_cloud_sql ? 1 : 0
  instance = google_sql_database_instance.airflow_db[0].name
  name     = var.sql_database_name
  project  = var.project_id
}

resource "google_sql_user" "db_user" {
  count    = var.deploy_cloud_sql ? 1 : 0
  name     = var.sql_user
  instance = google_sql_database_instance.airflow_db[0].name
  password = random_password.db_password[0].result
  project  = var.project_id
}

resource "random_password" "db_password" {
  count   = var.deploy_cloud_sql ? 1 : 0
  length  = 12
  special = false
}

resource "random_password" "fernet_key" {
  count            = var.deploy_cloud_sql ? 1 : 0
  length           = 32
  special          = false
  override_special = "_-"
}


# github.tf # put in modules/github
resource "tls_private_key" "github_deploy_key" {
  count     = var.deploy_github_keys ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "github_repository_deploy_key" "airflow_deploy_key" {
  count      = var.deploy_github_keys ? 1 : 0
  title      = "Repository test key"
  repository = var.dags_repository
  key        = sensitive(tls_private_key.github_deploy_key[0].public_key_openssh)
  read_only  = "true"
}


# logging.tf # put in modules/logging
resource "google_storage_bucket" "airflow_logs" {
  count                    = var.airflow_logs_bucket_name != null ? 1 : 0
  project                  = var.project_id
  name                     = var.airflow_logs_bucket_name
  location                 = var.airflow_logs_bucket_location
  public_access_prevention = "enforced"
}

resource "google_service_account" "airflow_logger" {
  count        = (var.airflow_logs_bucket_name != null && var.airflow_logs_sa != null) ? 1 : 0
  project      = var.project_id
  account_id   = var.airflow_logs_sa
  display_name = var.airflow_logs_sa
  description  = "Service account to write Airflow logs to Cloud Storage"
}

resource "google_storage_bucket_iam_member" "airflow_logger_admin" {
  count  = (var.airflow_logs_bucket_name != null && var.airflow_logs_sa != null) ? 1 : 0
  bucket = google_storage_bucket.airflow_logs[0].name
  role   = "roles/storage.admin"
  member = google_service_account.airflow_logger[0].member
}

