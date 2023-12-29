/*
output "airflow_db_credentials_secret" {
	#value = var.k8s_db_credentials_secret_name
	value = kubernetes_secret_v1.airflow_db_credentials
}

output "airflow_webserver_secret_key_secret" {
	#value = var.k8s_db_credentials_secret_name
	value = kubernetes_secret_v1.airflow_webserver_secret_key
}

output "airflow_git_sync_secret" {
	#value = var.k8s_git_sync_secret_name
	value = kubernetes_secret_v1.gitsync_creds
}

output "airflow_fernet_key_secret" {
	#value = var.k8s_airflow_fernet_key_secret_name
	value =  kubernetes_secret_v1.fernet_key_secret
}

#output "airflow_logger_sa" {
#  value = google_service_account.airflow_logger[0].email
#}
*/
