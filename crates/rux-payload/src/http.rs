use crate::fingerprint::fetch_fingerprint;
use crate::settings::SettingsStore;
use std::collections::HashMap;
use std::ffi::CString;

pub use rux_core::config::{
    DEFAULT_HTTP_MAX_RESPONSE_SIZE as DEFAULT_MAX_RESPONSE_SIZE,
    DEFAULT_HTTP_TIMEOUT_SECS as DEFAULT_HTTP_TIMEOUT,
};

/// Response structure matching Lua `http_response` representation.
#[derive(Debug, Clone, Default)]
pub struct HttpResponse {
    pub success: bool,
    pub status_code: i32,
    pub status_message: String,
    pub headers: HashMap<String, String>,
    pub body: String,
}

/// Request parameters matching Lua `http_request` table.
#[derive(Debug, Clone)]
pub struct HttpRequest {
    pub url: String,
    pub method: String,
    pub headers: HashMap<String, String>,
    pub body: Option<String>,
}

impl HttpRequest {
    pub fn new(url: impl Into<String>) -> Self {
        Self {
            url: url.into(),
            method: "GET".to_string(),
            headers: HashMap::new(),
            body: None,
        }
    }

    pub fn with_method(mut self, method: impl Into<String>) -> Self {
        self.method = method.into();
        self
    }
}

// System libcurl FFI definitions
#[allow(clippy::upper_case_acronyms)]
type CURL = libc::c_void;
#[allow(clippy::upper_case_acronyms)]
type CURLcode = libc::c_int;

#[repr(C)]
struct curl_slist {
    data: *mut libc::c_char,
    next: *mut curl_slist,
}

const CURLOPT_URL: libc::c_int = 10002;
const CURLOPT_WRITEFUNCTION: libc::c_int = 20011;
const CURLOPT_WRITEDATA: libc::c_int = 10001;
const CURLOPT_HTTPHEADER: libc::c_int = 10023;
const CURLOPT_POSTFIELDS: libc::c_int = 10015;
const CURLOPT_POSTFIELDSIZE: libc::c_int = 60;
const CURLOPT_CUSTOMREQUEST: libc::c_int = 10036;
const CURLOPT_TIMEOUT: libc::c_int = 13;
const CURLOPT_FOLLOWLOCATION: libc::c_int = 52;
const CURLOPT_PROTOCOLS: libc::c_int = 181;
const CURLOPT_REDIR_PROTOCOLS: libc::c_int = 182;
const CURLINFO_RESPONSE_CODE: libc::c_int = 0x200000 + 2;

// Restrict protocols to HTTP and HTTPS to prevent SSRF (e.g. file://, gopher://, dict://)
const CURLPROTO_HTTP: libc::c_long = 1;
const CURLPROTO_HTTPS: libc::c_long = 2;

#[link(name = "curl")]
unsafe extern "C" {
    fn curl_easy_init() -> *mut CURL;
    fn curl_easy_setopt(curl: *mut CURL, option: libc::c_int, ...) -> CURLcode;
    fn curl_easy_perform(curl: *mut CURL) -> CURLcode;
    fn curl_easy_getinfo(curl: *mut CURL, info: libc::c_int, ...) -> CURLcode;
    fn curl_easy_cleanup(curl: *mut CURL);
    fn curl_slist_append(list: *mut curl_slist, string: *const libc::c_char) -> *mut curl_slist;
    fn curl_slist_free_all(list: *mut curl_slist);
}

unsafe extern "C" fn write_callback(
    ptr: *mut libc::c_char,
    size: libc::size_t,
    nmemb: libc::size_t,
    userdata: *mut libc::c_void,
) -> libc::size_t {
    let total = size.saturating_mul(nmemb);
    if !userdata.is_null() && !ptr.is_null() && total > 0 {
        let vec = &mut *(userdata as *mut Vec<u8>);

        let max_size = SettingsStore::global()
            .get_number(rux_core::config::SETTINGS_HTTP_MAX_RESPONSE_SIZE)
            .filter(|&s| s > 0)
            .map(|s| s as usize)
            .unwrap_or(DEFAULT_MAX_RESPONSE_SIZE);

        // Prevent memory exhaustion DoS: abort transfer if response exceeds max size
        if vec.len().saturating_add(total) > max_size {
            return 0; // Aborts curl transfer with CURLE_WRITE_ERROR
        }

        let slice = std::slice::from_raw_parts(ptr as *const u8, total);
        vec.extend_from_slice(slice);
    }
    total
}

/// Execute a full HTTP request matching Lua `request` / `http_request`.
pub fn execute_request(req: &HttpRequest) -> HttpResponse {
    let mut response = HttpResponse::default();
    let store = SettingsStore::global();

    unsafe {
        let curl = curl_easy_init();
        if curl.is_null() {
            response.status_message = "Failed to initialize cURL".to_string();
            return response;
        }

        let mut body_bytes: Vec<u8> = Vec::new();
        let url_c = CString::new(req.url.clone()).unwrap_or_default();
        curl_easy_setopt(curl, CURLOPT_URL, url_c.as_ptr());
        curl_easy_setopt(
            curl,
            CURLOPT_WRITEFUNCTION,
            write_callback as *const () as usize,
        );
        curl_easy_setopt(
            curl,
            CURLOPT_WRITEDATA,
            &mut body_bytes as *mut _ as *mut libc::c_void,
        );

        // Dynamically configured timeout
        let timeout = store
            .get_number(rux_core::config::SETTINGS_HTTP_TIMEOUT)
            .filter(|&t| t > 0)
            .unwrap_or(DEFAULT_HTTP_TIMEOUT);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, timeout);

        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1i64);

        // Enforce safe protocols (HTTP/HTTPS only) to prevent SSRF
        let allowed_protocols = CURLPROTO_HTTP | CURLPROTO_HTTPS;
        curl_easy_setopt(curl, CURLOPT_PROTOCOLS, allowed_protocols);
        curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS, allowed_protocols);

        // Headers
        let mut header_list: *mut curl_slist = std::ptr::null_mut();

        // Check if caller supplied custom User-Agent
        let has_custom_ua = req
            .headers
            .iter()
            .any(|(k, _)| k.eq_ignore_ascii_case("user-agent"));

        if !has_custom_ua {
            let default_ua = store
                .get_string(rux_core::config::SETTINGS_USER_AGENT)
                .or_else(|| std::env::var(rux_core::config::ENV_HTTP_USER_AGENT).ok())
                .unwrap_or_else(|| rux_core::config::DEFAULT_HTTP_USER_AGENT.to_string());

            if let Ok(ua) = CString::new(format!("User-Agent: {}", default_ua)) {
                header_list = curl_slist_append(header_list, ua.as_ptr());
            }
        }

        // Only inject hardware fingerprint if offlineMode is disabled
        if !store.get_bool(rux_core::config::SETTINGS_OFFLINE_MODE) {
            let fp = fetch_fingerprint();
            let fp_header = store
                .get_string(rux_core::config::SETTINGS_FINGERPRINT_HEADER)
                .unwrap_or_else(|| rux_core::config::DEFAULT_FINGERPRINT_HEADER.to_string());
            if let Ok(h) = CString::new(format!("{}: {}", fp_header, fp)) {
                header_list = curl_slist_append(header_list, h.as_ptr());
            }
            if store.get_bool(rux_core::config::SETTINGS_COMPATIBILITY_MODE) {
                let compat_header = store
                    .get_string(rux_core::config::SETTINGS_COMPAT_FINGERPRINT_HEADER)
                    .unwrap_or_else(|| {
                        rux_core::config::DEFAULT_COMPAT_FINGERPRINT_HEADER.to_string()
                    });
                if let Ok(h) = CString::new(format!("{}: {}", compat_header, fp)) {
                    header_list = curl_slist_append(header_list, h.as_ptr());
                }
            }
        }

        // Add user-provided headers
        for (k, v) in &req.headers {
            if let Ok(h) = CString::new(format!("{}: {}", k, v)) {
                header_list = curl_slist_append(header_list, h.as_ptr());
            }
        }

        if !header_list.is_null() {
            curl_easy_setopt(curl, CURLOPT_HTTPHEADER, header_list);
        }

        // Method and Body
        let method = req.method.to_uppercase();
        let method_c = CString::new(method.clone()).unwrap_or_default();
        curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, method_c.as_ptr());

        if let Some(body) = &req.body {
            curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body.as_ptr() as *const _ as usize);
            curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, body.len() as libc::c_long);
        }

        let res = curl_easy_perform(curl);
        if res == 0 {
            let mut code: libc::c_long = 0;
            curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &mut code);
            response.status_code = code as i32;
            response.status_message = format!("HTTP {}", code);
            response.body = String::from_utf8_lossy(&body_bytes).to_string();
            response.success = response.status_code >= 200 && response.status_code < 400;
        } else {
            response.status_code = 0;
            response.status_message = format!("cURL error code: {}", res);
            response.success = false;
        }

        if !header_list.is_null() {
            curl_slist_free_all(header_list);
        }
        curl_easy_cleanup(curl);
    }

    response
}

/// Download string from URL matching `game:HttpGet(url)` / `receive_string()`.
pub fn receive_string(url: &str) -> String {
    let req = HttpRequest::new(url);
    let resp = execute_request(&req);
    if resp.success {
        resp.body
    } else {
        resp.status_message
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_http_request_struct() {
        let req = HttpRequest::new("http://localhost:8080/test");
        assert_eq!(req.method, "GET");
        assert_eq!(req.url, "http://localhost:8080/test");
    }

    #[test]
    fn test_custom_user_agent_setting() {
        let store = SettingsStore::global();
        store.set(rux_core::config::SETTINGS_USER_AGENT, "CustomAgent/2.0");
        assert_eq!(
            store
                .get_string(rux_core::config::SETTINGS_USER_AGENT)
                .unwrap(),
            "CustomAgent/2.0"
        );
        store.set(rux_core::config::SETTINGS_USER_AGENT, "");
    }
}
