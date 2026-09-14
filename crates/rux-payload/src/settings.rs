use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::LazyLock;

static GLOBAL_STORE: LazyLock<SettingsStore> = LazyLock::new(SettingsStore::new);

/// Thread-safe global configuration store for the Rux Client payload.
#[derive(Debug)]
pub struct SettingsStore {
    inner: RwLock<HashMap<String, String>>,
}

impl Default for SettingsStore {
    fn default() -> Self {
        Self::new()
    }
}

impl SettingsStore {
    /// Create a new store initialized with functional defaults.
    pub fn new() -> Self {
        use rux_core::config as cfg;
        let mut map = HashMap::new();
        map.insert(cfg::SETTINGS_DEBUG_LIBRARY.to_string(), "true".to_string());
        map.insert(
            cfg::SETTINGS_EXECUTE_INSTANCES.to_string(),
            "false".to_string(),
        );
        map.insert(
            cfg::SETTINGS_COMPATIBILITY_MODE.to_string(),
            "false".to_string(),
        );
        map.insert(cfg::SETTINGS_HTTP_TRAFFIC.to_string(), "false".to_string());
        map.insert(cfg::SETTINGS_ROBLOX_RPC.to_string(), "false".to_string());
        map.insert(cfg::SETTINGS_DISCORD_RPC.to_string(), "false".to_string());
        map.insert(cfg::SETTINGS_MACSPLIT.to_string(), "true".to_string());
        map.insert(
            cfg::SETTINGS_SERVER_TELEPORTS.to_string(),
            "true".to_string(),
        );
        map.insert(
            cfg::SETTINGS_PLACE_RESTRICTIONS.to_string(),
            "true".to_string(),
        );
        map.insert(cfg::SETTINGS_OFFLINE_MODE.to_string(), "true".to_string());

        Self {
            inner: RwLock::new(map),
        }
    }

    /// Get the global singleton instance.
    pub fn global() -> &'static SettingsStore {
        &GLOBAL_STORE
    }

    /// Retrieve a boolean setting value (defaults to false if unset).
    pub fn get_bool(&self, key: &str) -> bool {
        let guard = self.inner.read();
        guard
            .get(key)
            .map(|v| v.eq_ignore_ascii_case("true") || v == "1")
            .unwrap_or(false)
    }

    /// Retrieve a string setting value.
    pub fn get_string(&self, key: &str) -> Option<String> {
        let guard = self.inner.read();
        guard.get(key).cloned()
    }

    /// Retrieve an integer setting value.
    pub fn get_number(&self, key: &str) -> Option<i64> {
        let guard = self.inner.read();
        guard.get(key).and_then(|v| v.parse::<i64>().ok())
    }

    /// Set or update a configuration setting.
    pub fn set(&self, key: impl Into<String>, value: impl Into<String>) {
        let mut guard = self.inner.write();
        guard.insert(key.into(), value.into());
    }

    /// Handle incoming setting event from IPC.
    pub fn handle_setting(&self, key: &str, value: &str) {
        self.set(key, value);
    }
}

/// Helper function to retrieve a boolean setting from the global store.
pub fn get_boolean(name: &str) -> bool {
    SettingsStore::global().get_bool(name)
}

/// Helper function to retrieve a string setting from the global store.
pub fn get_string(name: &str) -> String {
    SettingsStore::global().get_string(name).unwrap_or_default()
}

/// Helper function to retrieve an integer setting from the global store.
pub fn get_number(name: &str) -> i64 {
    SettingsStore::global().get_number(name).unwrap_or(0)
}

/// Helper function to update a setting in the global store.
pub fn handle_setting(key: &str, value: &str) {
    SettingsStore::global().handle_setting(key, value);
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn test_settings_store() {
        use rux_core::config as cfg;
        let store = SettingsStore::new();
        assert!(store.get_bool(cfg::SETTINGS_MACSPLIT));
        assert!(store.get_bool(cfg::SETTINGS_OFFLINE_MODE));
        assert!(!store.get_bool("nonExistent"));

        store.set("customToggle", "true");
        assert!(store.get_bool("customToggle"));

        store.set("portNum", "8080");
        assert_eq!(store.get_number("portNum"), Some(8080));
    }
}
