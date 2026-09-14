//! Luau Initialization and Environment Scripts
//!
//! Standard Luau runtime scripts injected into the target environment.

/// Primary environment initialization script setting up exploit environment globals,
/// closures, table manipulation, and hook functions.
pub const INIT_SCRIPT: &str = r#"
getgenv().protect_cache = {}
getgenv().hooked_cache = {}

local fetch_setting = fetch_setting
getgenv().crypto = crypt

getgenv().hookfunction = newcclosure(function(func, hook)
    assert(func, 'expected function for argument #1')
    assert(hook, 'expected function for argument #2')
    table.insert(hooked_cache, func)

    if iscclosure(func) or iscclosure(hook) then
        table.insert(getreg(), hook)
        return swapfunction(func, newcclosure_s(hook))
    end

    return hookfunction_c(func, hook)
end)

getgenv().isfunctionhooked = newcclosure(function(func)
    return table.find(hooked_cache, func) ~= nil
end)

getgenv().hookfunc = hookfunction
getgenv().hookmetamethod = newcclosure(function(instance, metamethod, closure)
    local mt = getrawmetatable(instance)
    local old_metaclosure = hookfunction(mt[metamethod], closure)
    return old_metaclosure
end)

getgenv().clonetable = newcclosure(function(tbl)
    local clone = {}
    for i, v in tbl do
        clone[i] = v
    end
    return clone
end)

getgenv().getinfo = debug.getinfo
getgenv().getconstants = debug.getconstants
getgenv().getproto = debug.getproto

getgenv().isourclosure = isexecutorclosure
getgenv().is_synapse_function = isexecutorclosure
getgenv().isexploitclosure = isexecutorclosure
getgenv().isexecutorfunction = isexecutorclosure
getgenv().isexploitfunction = isexecutorclosure
getgenv().isourfunction = isexecutorclosure
getgenv().isgameclosure = function(cl)
    return not isexecutorclosure(cl)
end

getgenv().newlclosure = function(cl)
    return function(...)
        return cl(...)
    end
end
"#;

/// In-game RPC and player presence helper script.
pub const RPC_SCRIPT: &str = r#"
local HttpService = game:GetService('HttpService')
local RunService = game:GetService('RunService')
local Players = game:GetService('Players')

print('[Rux] In-game RPC initialized.')
"#;

/// Dynamically retrieve the environment initialization script.
pub fn get_init_script() -> String {
    if let Some(custom) =
        crate::settings::SettingsStore::global().get_string(rux_core::config::SETTINGS_INIT_SCRIPT)
    {
        if !custom.trim().is_empty() {
            return custom;
        }
    }
    if let Ok(path) = std::env::var(rux_core::config::ENV_INIT_SCRIPT_PATH) {
        if let Ok(content) = std::fs::read_to_string(path) {
            return content;
        }
    }
    INIT_SCRIPT.to_string()
}

/// Dynamically retrieve the RPC presence helper script.
pub fn get_rpc_script() -> String {
    if let Some(custom) =
        crate::settings::SettingsStore::global().get_string(rux_core::config::SETTINGS_RPC_SCRIPT)
    {
        if !custom.trim().is_empty() {
            return custom;
        }
    }
    RPC_SCRIPT.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_scripts_not_empty() {
        assert!(!INIT_SCRIPT.is_empty());
        assert!(!RPC_SCRIPT.is_empty());
    }
}
