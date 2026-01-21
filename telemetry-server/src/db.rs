use anyhow::{Context, Result};
use sqlx::SqlitePool;
use std::sync::Arc;

use crate::models::DeploymentRecord;

pub struct Db {
    pool: SqlitePool,
}

impl Db {
    pub async fn new(database_url: &str) -> Result<Self> {
        let pool = SqlitePool::connect(database_url)
            .await
            .context("Failed to connect to database")?;

        sqlx::query(
            "CREATE TABLE IF NOT EXISTS deployments (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                instance_id TEXT NOT NULL,
                image_version TEXT NOT NULL,
                architecture TEXT NOT NULL,
                container_runtime TEXT NOT NULL,
                startup_time_ms INTEGER NOT NULL,
                db_type TEXT NOT NULL,
                telemetry_version TEXT NOT NULL,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )",
        )
        .execute(&pool)
        .await
        .context("Failed to create deployments table")?;

        sqlx::query("CREATE INDEX IF NOT EXISTS idx_instance_id ON deployments(instance_id)")
            .execute(&pool)
            .await
            .context("Failed to create instance_id index")?;

        sqlx::query("CREATE INDEX IF NOT EXISTS idx_created_at ON deployments(created_at)")
            .execute(&pool)
            .await
            .context("Failed to create created_at index")?;

        Ok(Self { pool })
    }

    pub async fn insert_telemetry(
        &self,
        instance_id: &str,
        image_version: &str,
        architecture: &str,
        container_runtime: &str,
        startup_time_ms: u64,
        db_type: &str,
        telemetry_version: &str,
    ) -> Result<i64> {
        let record = sqlx::query(
            "INSERT INTO deployments (
                instance_id, image_version, architecture, container_runtime,
                startup_time_ms, db_type, telemetry_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(instance_id)
        .bind(image_version)
        .bind(architecture)
        .bind(container_runtime)
        .bind(startup_time_ms as i64)
        .bind(db_type)
        .bind(telemetry_version)
        .execute(&self.pool)
        .await
        .context("Failed to insert deployment")?;

        Ok(record.last_insert_rowid())
    }

    pub async fn count_deployments(&self) -> Result<u64> {
        let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM deployments")
            .fetch_one(&self.pool)
            .await
            .context("Failed to count deployments")?;
        Ok(count as u64)
    }

    pub async fn count_unique_instances(&self) -> Result<u64> {
        let count: i64 = sqlx::query_scalar("SELECT COUNT(DISTINCT instance_id) FROM deployments")
            .fetch_one(&self.pool)
            .await
            .context("Failed to count unique instances")?;
        Ok(count as u64)
    }

    pub async fn get_architecture_stats(&self) -> Result<Vec<(String, i64)>> {
        let stats = sqlx::query_as::<_, (String, i64)>(
            "SELECT architecture, COUNT(*) as count FROM deployments GROUP BY architecture",
        )
        .fetch_all(&self.pool)
        .await
        .context("Failed to get architecture stats")?;
        Ok(stats)
    }

    pub async fn get_version_stats(&self) -> Result<Vec<(String, i64)>> {
        let stats = sqlx::query_as::<_, (String, i64)>(
            "SELECT image_version, COUNT(*) as count FROM deployments GROUP BY image_version",
        )
        .fetch_all(&self.pool)
        .await
        .context("Failed to get version stats")?;
        Ok(stats)
    }

    pub async fn get_avg_startup_time(&self) -> Result<f64> {
        let avg: f64 = sqlx::query_scalar("SELECT AVG(startup_time_ms) FROM deployments")
            .fetch_one(&self.pool)
            .await
            .context("Failed to get avg startup time")?;
        Ok(avg)
    }

    pub async fn get_recent_deployments(&self, limit: i64) -> Result<Vec<DeploymentRecord>> {
        let records = sqlx::query_as::<_, DeploymentRecord>(
            "SELECT * FROM deployments ORDER BY created_at DESC LIMIT ?",
        )
        .bind(limit)
        .fetch_all(&self.pool)
        .await
        .context("Failed to get recent deployments")?;
        Ok(records)
    }

    pub async fn get_time_series_data(&self, _interval_minutes: i64) -> Result<Vec<(String, i64)>> {
        let data = sqlx::query_as::<_, (String, i64)>(
            "SELECT strftime('%Y-%m-%d %H:%M', created_at, 'localtime') as time_bucket,
                    COUNT(*) FROM deployments
                    WHERE created_at >= datetime('now', '-24 hours')
                    GROUP BY time_bucket
                    ORDER BY time_bucket",
        )
        .fetch_all(&self.pool)
        .await
        .context("Failed to get time series data")?;
        Ok(data)
    }
}

pub type SharedDb = Arc<Db>;
