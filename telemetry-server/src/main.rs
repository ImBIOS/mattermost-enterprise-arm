use actix_web::{web, App, HttpServer};
use anyhow::Result;
use env_logger::Env;
use log::info;

mod config;
mod db;
mod handlers;
mod models;

use config::Config;
use db::Db;
use std::sync::Arc;

#[actix_web::main]
async fn main() -> Result<()> {
    env_logger::init_from_env(Env::default().default_filter_or("info"));

    let config = Config::load()?;
    info!("Starting telemetry server on {}", config.server_address);

    let db = Db::new(&config.database_url).await?;
    let db = Arc::new(db);

    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(db.clone()))
            .wrap(actix_cors::Cors::permissive())
            .service(handlers::collect_telemetry)
            .service(handlers::get_metrics)
            .service(handlers::health_check)
            .service(handlers::get_deployments)
            .service(handlers::get_architecture_stats)
    })
    .bind(&config.server_address)?
    .run()
    .await?;

    Ok(())
}
