use anyhow::Result;
use serde::Deserialize;
use std::env;

#[derive(Debug, Deserialize)]
pub struct Config {
    pub server_address: String,
    pub database_url: String,
}

impl Config {
    pub fn load() -> Result<Self> {
        let server_address =
            env::var("SERVER_ADDRESS").unwrap_or_else(|_| String::from("0.0.0.0:8080"));

        let database_url = env::var("DATABASE_URL")
            .unwrap_or_else(|_| String::from("sqlite:///data/telemetry.db"));

        Ok(Self {
            server_address,
            database_url,
        })
    }
}
