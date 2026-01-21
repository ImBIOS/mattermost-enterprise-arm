use actix_web::{get, post, web, HttpResponse, Responder};

use crate::db::SharedDb;
use crate::models::{
    ArchitectureStat, MetricsResponse, TelemetryEvent, TelemetryEventResponse, VersionStat,
};

#[post("/collect")]
async fn collect_telemetry(
    db: web::Data<SharedDb>,
    event: web::Json<TelemetryEvent>,
) -> impl Responder {
    let event = event.into_inner();

    match db
        .insert_telemetry(
            &event.instance_id,
            &event.image_version,
            &event.architecture,
            &event.container_runtime,
            event.startup_time_ms,
            &event.db_type,
            &event.telemetry_version,
        )
        .await
    {
        Ok(_) => HttpResponse::Ok().json(TelemetryEventResponse {
            status: String::from("success"),
            message: String::from("Telemetry collected"),
        }),
        Err(e) => HttpResponse::InternalServerError().json(TelemetryEventResponse {
            status: String::from("error"),
            message: format!("Failed to collect telemetry: {}", e),
        }),
    }
}

#[get("/metrics")]
async fn get_metrics(db: web::Data<SharedDb>) -> impl Responder {
    let total_deployments = db.count_deployments().await.unwrap_or(0);
    let unique_instances = db.count_unique_instances().await.unwrap_or(0);
    let arch_stats = db.get_architecture_stats().await.unwrap_or_default();
    let version_stats = db.get_version_stats().await.unwrap_or_default();
    let avg_startup_time = db.get_avg_startup_time().await.unwrap_or(0.0);

    let architecture_breakdown: Vec<ArchitectureStat> = arch_stats
        .into_iter()
        .map(|(arch, count)| ArchitectureStat {
            architecture: arch,
            count,
        })
        .collect();

    let version_breakdown: Vec<VersionStat> = version_stats
        .into_iter()
        .map(|(version, count)| VersionStat { version, count })
        .collect();

    HttpResponse::Ok().json(MetricsResponse {
        total_deployments,
        unique_instances,
        architecture_breakdown,
        version_breakdown,
        avg_startup_time_ms: avg_startup_time,
    })
}

#[get("/health")]
async fn health_check() -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "healthy",
        "service": "mattermost-telemetry"
    }))
}

#[get("/deployments")]
async fn get_deployments(db: web::Data<SharedDb>) -> impl Responder {
    let deployments = db.get_recent_deployments(100).await.unwrap_or_default();
    HttpResponse::Ok().json(deployments)
}

#[get("/stats/architecture")]
async fn get_architecture_stats(db: web::Data<SharedDb>) -> impl Responder {
    let stats = db.get_architecture_stats().await.unwrap_or_default();
    let response: Vec<ArchitectureStat> = stats
        .into_iter()
        .map(|(arch, count)| ArchitectureStat {
            architecture: arch,
            count,
        })
        .collect();
    HttpResponse::Ok().json(response)
}
