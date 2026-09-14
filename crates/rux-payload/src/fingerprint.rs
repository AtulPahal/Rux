use crate::crypto::sha1_hex;
use crate::settings::SettingsStore;
use std::ffi::c_int;

unsafe extern "C" {
    fn gethostuuid(uuid_out: *mut u8, timeout: *const libc::timespec) -> c_int;
}

/// Retrieve the raw Hardware UUID of the Mac as a standard formatted string:
/// `XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX`.
pub fn raw_hwid() -> Option<String> {
    let mut uuid_bytes = [0u8; 16];
    let timeout = libc::timespec {
        tv_sec: rux_core::config::GETHOSTUUID_TIMEOUT_SECS as libc::time_t,
        tv_nsec: 0,
    };

    let ret = unsafe { gethostuuid(uuid_bytes.as_mut_ptr(), &timeout) };
    if ret != 0 {
        return None;
    }

    Some(format!(
        "{:02x}{:02x}{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}-{:02x}{:02x}{:02x}{:02x}{:02x}{:02x}",
        uuid_bytes[0],
        uuid_bytes[1],
        uuid_bytes[2],
        uuid_bytes[3],
        uuid_bytes[4],
        uuid_bytes[5],
        uuid_bytes[6],
        uuid_bytes[7],
        uuid_bytes[8],
        uuid_bytes[9],
        uuid_bytes[10],
        uuid_bytes[11],
        uuid_bytes[12],
        uuid_bytes[13],
        uuid_bytes[14],
        uuid_bytes[15]
    ))
}

/// Computes the SHA-1 hardware fingerprint matching `fetch_fingerprint()` in the original client.
///
/// If `offlineMode` is enabled, returns a deterministic anonymous local identifier
/// to protect device privacy and prevent unauthorized external tracking.
pub fn fetch_fingerprint() -> String {
    let store = SettingsStore::global();

    // Check if offline/privacy mode is enabled
    if store.get_bool(rux_core::config::SETTINGS_OFFLINE_MODE) {
        return rux_core::config::ANONYMOUS_FINGERPRINT.to_string();
    }

    // Check if custom spoofed HWID is configured
    if let Some(spoofed) = store.get_string(rux_core::config::SETTINGS_SPOOFED_HWID) {
        if !spoofed.is_empty() {
            return sha1_hex(spoofed.as_bytes());
        }
    }

    if let Some(hwid) = raw_hwid() {
        sha1_hex(hwid.as_bytes())
    } else {
        rux_core::config::ANONYMOUS_FINGERPRINT.to_string()
    }
}

pub use rux_core::config::DEFAULT_FINGERPRINT_SUFFIX;

/// Dynamically determine the client fingerprint suffix.
pub fn get_fingerprint_suffix() -> String {
    use rux_core::config as cfg;
    let store = SettingsStore::global();
    if let Some(suffix) = store.get_string(cfg::SETTINGS_FINGERPRINT_SUFFIX) {
        if !suffix.trim().is_empty() {
            return suffix;
        }
    }
    if let Ok(env_suffix) = std::env::var(cfg::ENV_FINGERPRINT_SUFFIX) {
        if !env_suffix.trim().is_empty() {
            return env_suffix;
        }
    }
    cfg::DEFAULT_FINGERPRINT_SUFFIX.to_string()
}

/// Formatted fingerprint with client suffix matching `parsed_fingerprint()`.
pub fn parsed_fingerprint() -> String {
    format!("{}{}", fetch_fingerprint(), get_fingerprint_suffix())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_raw_hwid_format() {
        if let Some(hwid) = raw_hwid() {
            assert_eq!(hwid.len(), 36);
            assert_eq!(hwid.chars().filter(|&c| c == '-').count(), 4);
        }
    }

    #[test]
    fn test_fingerprint_offline_mode() {
        use rux_core::config as cfg;
        let store = SettingsStore::global();
        store.set(cfg::SETTINGS_OFFLINE_MODE, "true");
        let fp = fetch_fingerprint();
        assert_eq!(fp, cfg::ANONYMOUS_FINGERPRINT);

        store.set(cfg::SETTINGS_OFFLINE_MODE, "false");
        store.set(cfg::SETTINGS_SPOOFED_HWID, "test-device-uuid-1234");
        let spoofed_fp = fetch_fingerprint();
        assert_eq!(spoofed_fp.len(), 40);
    }

    #[test]
    fn test_dynamic_fingerprint_suffix() {
        use rux_core::config as cfg;
        let store = SettingsStore::global();
        store.set(cfg::SETTINGS_FINGERPRINT_SUFFIX, "customsuffix");
        assert!(parsed_fingerprint().ends_with("customsuffix"));
        store.set(cfg::SETTINGS_FINGERPRINT_SUFFIX, "");
    }
}
