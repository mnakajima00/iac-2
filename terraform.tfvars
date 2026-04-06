project_id = "brightwave-prod-418"
region     = "us-central1"

api_env_vars = {
  APP_ENV                         = "production"
  LOG_LEVEL                       = "info"
  LOG_FORMAT                      = "json"
  CORS_ORIGINS                    = "https://app.brightwave.io,https://brightwave.io"
  REQUEST_TIMEOUT_SECONDS         = "30"
  RATE_LIMIT_RPM                  = "600"
  OTEL_SERVICE_NAME               = "api-gateway"
  OTEL_EXPORTER_OTLP_ENDPOINT     = "https://otel-collector.brightwave.io:4317"
  USER_SERVICE_BASE_URL           = "https://user-service-xyzabc123-uc.a.run.app"
  BILLING_SERVICE_BASE_URL        = "https://billing-service-xyzabc123-uc.a.run.app"
  FEATURE_BILLING_V2              = "false"
}
