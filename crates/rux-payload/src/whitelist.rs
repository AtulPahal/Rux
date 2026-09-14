use crate::fingerprint::fetch_fingerprint;
use crate::http::{execute_request, HttpRequest};
use crate::settings::SettingsStore;

pub use rux_core::config::DEFAULT_WHITELIST_URL;

/// Dynamically determine the whitelist verification endpoint URL.
pub fn get_whitelist_url_base() -> String {
    use rux_core::config as cfg;
    let store = SettingsStore::global();
    if let Some(url) = store.get_string(cfg::SETTINGS_WHITELIST_URL) {
        if !url.trim().is_empty() {
            return url;
        }
    }
    if let Ok(env_url) = std::env::var(cfg::ENV_WHITELIST_URL) {
        if !env_url.trim().is_empty() {
            return env_url;
        }
    }
    cfg::DEFAULT_WHITELIST_URL.to_string()
}

/// Whitelist authorization outcome.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WhitelistStatus {
    /// Device is authenticated and approved to run
    Authorized {
        is_booster: bool,
        early_access: bool,
    },
    /// Device not found or rejected by server
    Unauthorized(String),
    /// Failed to connect to verification server
    NetworkError(String),
}

/// Perform whitelist verification.
///
/// If `offlineMode` is enabled in settings (default), this function operates 100% locally
/// and returns [`WhitelistStatus::Authorized`] immediately without making any outbound network requests.
pub fn verify_whitelist() -> WhitelistStatus {
    let store = SettingsStore::global();

    // 1. Offline Mode: 100% local operation without external network dependency
    if store.get_bool(rux_core::config::SETTINGS_OFFLINE_MODE) {
        println!("[Whitelist] Running in Offline / Local Mode. Authorization granted.");
        return WhitelistStatus::Authorized {
            is_booster: true,
            early_access: true,
        };
    }

    // 2. Online Mode: query verification endpoint dynamically.
    // No endpoint is bundled (DEFAULT_WHITELIST_URL is empty): without explicit
    // configuration this fails closed instead of phoning an unknown server.
    let base_url = get_whitelist_url_base();
    if base_url.trim().is_empty() {
        return WhitelistStatus::NetworkError(
            "No whitelist endpoint configured (set whitelistUrl or RUX_WHITELIST_URL)".to_string(),
        );
    }
    let hwid = fetch_fingerprint();
    // Sanitize HWID (only keep alphanumeric hex characters to prevent query parameter injection)
    let sanitized_hwid: String = hwid.chars().filter(|c| c.is_ascii_hexdigit()).collect();

    let url = if base_url.ends_with('=') {
        format!("{}{}", base_url, sanitized_hwid)
    } else if base_url.contains('?') {
        format!("{}&hwid={}", base_url, sanitized_hwid)
    } else {
        format!("{}?hwid={}", base_url, sanitized_hwid)
    };

    let req = HttpRequest::new(url);
    let resp = execute_request(&req);

    if !resp.success || resp.body.is_empty() {
        return WhitelistStatus::NetworkError(format!(
            "Server connection failed (code: {})",
            resp.status_code
        ));
    }

    if resp
        .body
        .contains(rux_core::config::WHITELIST_COMPLETE_MARKER)
    {
        let is_booster = resp
            .body
            .contains(rux_core::config::WHITELIST_BOOSTER_MARKER);
        let early_access = resp
            .body
            .contains(rux_core::config::WHITELIST_EARLY_ACCESS_MARKER);
        WhitelistStatus::Authorized {
            is_booster,
            early_access,
        }
    } else {
        WhitelistStatus::Unauthorized(format!("HWID ticket rejected: 0x{}", sanitized_hwid))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_whitelist_offline_mode() {
        use rux_core::config as cfg;
        let store = SettingsStore::global();
        store.set(cfg::SETTINGS_OFFLINE_MODE, "true");
        let status = verify_whitelist();
        assert_eq!(
            status,
            WhitelistStatus::Authorized {
                is_booster: true,
                early_access: true,
            }
        );
    }

    #[test]
    fn test_dynamic_whitelist_url() {
        use rux_core::config as cfg;
        let store = SettingsStore::global();
        store.set(cfg::SETTINGS_WHITELIST_URL, "http://127.0.0.1:8080/whitelist?hwid=");
        assert_eq!(
            get_whitelist_url_base(),
            "http://127.0.0.1:8080/whitelist?hwid="
        );
        store.set(cfg::SETTINGS_WHITELIST_URL, "");
    }
}
