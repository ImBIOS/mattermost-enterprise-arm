use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Serialize, Deserialize)]
pub struct TelemetryEvent {
    pub instance_id: String,
    pub image_version: String,
    pub architecture: String,
    pub os: String,
    pub container_runtime: String,
    pub startup_time_ms: u64,
    pub db_type: String,
    pub telemetry_version: String,
    pub timestamp: Option<DateTime<Utc>>,
}

impl Default for TelemetryEvent {
    fn default() -> Self {
        Self {
            instance_id: Uuid::new_v4().to_string(),
            image_version: String::new(),
            architecture: String::new(),
            os: String::new(),
            container_runtime: String::new(),
            startup_time_ms: 0,
            db_type: String::new(),
            telemetry_version: String::from("1.0"),
            timestamp: Some(Utc::now()),
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TelemetryEventResponse {
    pub status: String,
    pub message: String,
}

#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct DeploymentRecord {
    pub id: i64,
    pub instance_id: String,
    pub image_version: String,
    pub architecture: String,
    pub container_runtime: String,
    pub startup_time_ms: i64,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MetricsResponse {
    pub total_deployments: u64,
    pub unique_instances: u64,
    pub architecture_breakdown: Vec<ArchitectureStat>,
    pub version_breakdown: Vec<VersionStat>,
    pub avg_startup_time_ms: f64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ArchitectureStat {
    pub architecture: String,
    pub count: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct VersionStat {
    pub version: String,
    pub count: i64,
}
