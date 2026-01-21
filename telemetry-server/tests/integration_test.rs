use mattermost_telemetry::db::Db;
use mattermost_telemetry::models::TelemetryEvent;
use std::sync::Arc;

#[tokio::test]
async fn test_telemetry_model_serialization() {
    let event = TelemetryEvent {
        instance_id: "test-uuid".to_string(),
        image_version: "v11.3.0".to_string(),
        architecture: "aarch64".to_string(),
        os: "Linux".to_string(),
        container_runtime: "docker".to_string(),
        startup_time_ms: 2500,
        db_type: "postgres".to_string(),
        telemetry_version: "1.0".to_string(),
        timestamp: None,
    };

    // Test serialization
    let serialized = serde_json::to_string(&event).unwrap();
    assert!(serialized.contains("test-uuid"));
    assert!(serialized.contains("v11.3.0"));
    assert!(serialized.contains("aarch64"));

    // Test deserialization
    let deserialized: TelemetryEvent = serde_json::from_str(&serialized).unwrap();
    assert_eq!(deserialized.instance_id, "test-uuid");
    assert_eq!(deserialized.image_version, "v11.3.0");
    assert_eq!(deserialized.architecture, "aarch64");
    assert_eq!(deserialized.startup_time_ms, 2500);
}

#[test]
fn test_telemetry_event_json_format() {
    use serde_json::json;

    let event = TelemetryEvent {
        instance_id: "abc123".to_string(),
        image_version: "v11.0.0".to_string(),
        architecture: "x86_64".to_string(),
        os: "Linux".to_string(),
        container_runtime: "docker".to_string(),
        startup_time_ms: 1500,
        db_type: "postgres".to_string(),
        telemetry_version: "1.0".to_string(),
        timestamp: None,
    };

    let json = json!({
        "instance_id": event.instance_id,
        "image_version": event.image_version,
        "architecture": event.architecture,
        "os": event.os,
        "container_runtime": event.container_runtime,
        "startup_time_ms": event.startup_time_ms,
        "db_type": event.db_type,
        "telemetry_version": event.telemetry_version
    });

    assert_eq!(json["instance_id"], "abc123");
    assert_eq!(json["image_version"], "v11.0.0");
    assert_eq!(json["architecture"], "x86_64");
    assert_eq!(json["startup_time_ms"], 1500);
}
