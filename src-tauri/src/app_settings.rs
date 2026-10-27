use serde::{Deserialize, Serialize};
use std::{io::Write, path::PathBuf};

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    pub auto_start: bool,
    pub auto_connect: bool,
}

#[derive(Default, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Patch {
    pub auto_start: Option<bool>,
    pub auto_connect: Option<bool>,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct Stored {
    schema_version: u32,
    auto_connect: bool,
}

/// The OS owns login registration; it is deliberately absent from the JSON file.
pub trait AutoStart {
    fn enabled(&self) -> Result<bool, String>;
    fn set_enabled(&self, enabled: bool) -> Result<(), String>;
}

pub const STARTUP_NAME: &str = "Neutrino Proxy";

#[cfg(windows)]
fn complete_windows_registration(name: &str, executable: &std::path::Path) -> Result<(), String> {
    windows_registry::CURRENT_USER
        .create(r"SOFTWARE\Microsoft\Windows\CurrentVersion\Run")
        .and_then(|key| key.set_string(name, format!("\"{}\"", executable.display())))
        .map_err(|e| e.to_string())?;
    // The plugin prefers HKLM when elevated and leaves HKCU's Task Manager
    // override untouched. Restore approval for the quoted current-user entry too.
    windows_registry::CURRENT_USER
        .create(r"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run")
        .and_then(|key| {
            key.set_bytes(
                name,
                windows_registry::Type::Bytes,
                &[2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            )
        })
        .map_err(|e| e.to_string())
}

pub struct SystemAutoStart<'a> {
    manager: &'a tauri_plugin_autostart::AutoLaunchManager,
    #[cfg(windows)]
    name: &'a str,
}

impl<'a> SystemAutoStart<'a> {
    pub fn new(manager: &'a tauri_plugin_autostart::AutoLaunchManager) -> Self {
        Self {
            manager,
            #[cfg(windows)]
            name: STARTUP_NAME,
        }
    }
}

impl AutoStart for SystemAutoStart<'_> {
    fn enabled(&self) -> Result<bool, String> {
        self.manager
            .is_enabled()
            .map_err(|_| "无法读取系统开机自启设置，请重试".into())
    }
    fn set_enabled(&self, enabled: bool) -> Result<(), String> {
        let result = if enabled {
            self.manager.enable()
        } else {
            self.manager.disable()
        };
        result.map_err(|_| "无法更新系统开机自启设置，请检查系统权限后重试".to_owned())?;
        #[cfg(windows)]
        if enabled {
            // auto-launch 0.6 writes the executable unquoted. Complete registration
            // with a quoted path so installations under Program Files launch correctly.
            let registration = (|| -> Result<(), String> {
                let executable = std::env::current_exe().map_err(|e| e.to_string())?;
                complete_windows_registration(self.name, &executable)
            })();
            if registration.is_err() {
                let _ = self.manager.disable();
                return Err("无法完成开机自启注册，请检查系统权限后重试".into());
            }
        }
        Ok(())
    }
}

pub struct Store {
    path: PathBuf,
    pub auto_connect: bool,
    pub error: Option<String>,
}

impl Store {
    pub fn load(path: PathBuf) -> Self {
        let mut store = Self {
            path,
            auto_connect: false,
            error: None,
        };
        match std::fs::read(&store.path) {
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Ok(bytes) => match serde_json::from_slice::<Stored>(&bytes) {
                Ok(value) if value.schema_version == 1 => store.auto_connect = value.auto_connect,
                _ => store.error = Some("应用设置文件无法读取或版本不兼容，原文件已保留".into()),
            },
            Err(_) => store.error = Some("无法读取应用设置文件，请检查文件权限".into()),
        }
        store
    }

    pub fn snapshot(&self, os: &impl AutoStart) -> Result<AppSettings, String> {
        if let Some(error) = &self.error {
            return Err(error.clone());
        }
        Ok(AppSettings {
            auto_start: os.enabled()?,
            auto_connect: self.auto_connect,
        })
    }

    pub fn update(&mut self, patch: Patch, os: &impl AutoStart) -> Result<AppSettings, String> {
        if patch.auto_start.is_some() == patch.auto_connect.is_some() {
            return Err("每次只能修改一项应用设置".into());
        }
        let mut settings = self.snapshot(os)?;
        if let Some(enabled) = patch.auto_start {
            os.set_enabled(enabled)?;
            settings.auto_start = os.enabled()?;
            if settings.auto_start != enabled {
                return Err("系统未应用开机自启设置，请重试".into());
            }
        }
        if let Some(enabled) = patch.auto_connect {
            // Persist independently of config.json and the system credential store.
            // Do not change the in-memory preference until the replacement succeeds.
            let bytes = serde_json::to_vec_pretty(&Stored {
                schema_version: 1,
                auto_connect: enabled,
            })
            .map_err(|_| "无法序列化应用设置".to_owned())?;
            let parent = self.path.parent().ok_or("应用设置目录不可用")?;
            std::fs::create_dir_all(parent).map_err(|_| "无法创建应用设置目录".to_owned())?;
            let temp = self.path.with_extension("json.tmp");
            let saved = (|| -> std::io::Result<()> {
                let mut file = std::fs::File::create(&temp)?;
                file.write_all(&bytes)?;
                file.sync_all()?;
                drop(file);
                std::fs::rename(&temp, &self.path)
            })();
            if saved.is_err() {
                let _ = std::fs::remove_file(&temp);
                return Err("无法保存应用设置，修改尚未生效".into());
            }
            self.auto_connect = enabled;
            settings.auto_connect = enabled;
        }
        Ok(settings)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;
    struct Temp(PathBuf);
    impl Temp {
        fn new() -> Self {
            let path = std::env::temp_dir()
                .join(format!("neutrino-app-settings-{}", uuid::Uuid::new_v4()));
            std::fs::create_dir(&path).unwrap();
            Self(path)
        }
        fn store(&self) -> Store {
            Store::load(self.0.join("app-settings.json"))
        }
    }
    impl Drop for Temp {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }
    #[derive(Default)]
    struct Os {
        value: Cell<bool>,
        fail: Cell<bool>,
    }
    impl AutoStart for Os {
        fn enabled(&self) -> Result<bool, String> {
            Ok(self.value.get())
        }
        fn set_enabled(&self, enabled: bool) -> Result<(), String> {
            if self.fail.get() {
                return Err("OS denied".into());
            }
            self.value.set(enabled);
            Ok(())
        }
    }
    #[test]
    fn preferences_default_off_and_survive_restart_without_touching_connection_config() {
        let temp = Temp::new();
        let connection = temp.0.join("config.json");
        std::fs::write(&connection, b"existing connection and credential reference").unwrap();
        let os = Os::default();
        let mut store = temp.store();
        assert!(!store.snapshot(&os).unwrap().auto_start);
        assert!(!store.auto_connect);
        for enabled in [true, false, true] {
            store
                .update(
                    Patch {
                        auto_connect: Some(enabled),
                        ..Default::default()
                    },
                    &os,
                )
                .unwrap();
            assert_eq!(temp.store().auto_connect, enabled);
        }
        assert_eq!(
            std::fs::read(&connection).unwrap(),
            b"existing connection and credential reference"
        );
        let bytes = std::fs::read_to_string(&store.path).unwrap();
        assert!(!bytes.contains("autoStart"));
        assert!(!bytes.contains("license"));
    }
    #[test]
    fn autostart_uses_os_state_and_failed_changes_do_not_appear_saved() {
        let temp = Temp::new();
        let mut store = temp.store();
        let os = Os::default();
        let settings = store
            .update(
                Patch {
                    auto_start: Some(true),
                    ..Default::default()
                },
                &os,
            )
            .unwrap();
        assert!(settings.auto_start);
        assert!(!settings.auto_connect);
        assert!(!store.path.exists());
        os.value.set(false); // External system change must be reflected on the next read.
        assert!(!store.snapshot(&os).unwrap().auto_start);
        os.fail.set(true);
        assert!(store
            .update(
                Patch {
                    auto_start: Some(true),
                    ..Default::default()
                },
                &os
            )
            .is_err());
        assert!(!store.snapshot(&os).unwrap().auto_start);
    }
    #[test]
    fn failed_persistence_and_invalid_files_preserve_original_state() {
        let temp = Temp::new();
        let os = Os::default();
        let mut store = temp.store();
        store
            .update(
                Patch {
                    auto_connect: Some(true),
                    ..Default::default()
                },
                &os,
            )
            .unwrap();
        let original = std::fs::read(&store.path).unwrap();
        std::fs::create_dir(store.path.with_extension("json.tmp")).unwrap();
        assert!(store
            .update(
                Patch {
                    auto_connect: Some(false),
                    ..Default::default()
                },
                &os
            )
            .is_err());
        assert!(store.auto_connect);
        assert_eq!(std::fs::read(&store.path).unwrap(), original);
        for bytes in [
            b"invalid".as_slice(),
            br#"{"schemaVersion":99,"autoConnect":true}"#,
        ] {
            std::fs::write(&store.path, bytes).unwrap();
            let mut invalid = temp.store();
            assert!(!invalid.auto_connect);
            assert!(invalid
                .update(
                    Patch {
                        auto_connect: Some(true),
                        ..Default::default()
                    },
                    &os
                )
                .is_err());
            assert_eq!(std::fs::read(&store.path).unwrap(), bytes);
        }
    }
    #[test]
    fn ambiguous_patch_cannot_partially_change_system_settings() {
        let temp = Temp::new();
        let os = Os::default();
        let mut store = temp.store();
        assert!(store
            .update(
                Patch {
                    auto_start: Some(true),
                    auto_connect: Some(true)
                },
                &os
            )
            .is_err());
        assert!(!os.value.get());
        assert!(!store.path.exists());
    }

    #[cfg(windows)]
    #[test]
    fn windows_registration_clears_current_user_disable_after_system_registration() {
        use tauri_plugin_autostart::ManagerExt;
        const RUN: &str = r"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
        const APPROVAL: &str =
            r"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
        let name = format!("Neutrino registration test {}", uuid::Uuid::new_v4());
        struct Cleanup<'a>(&'a str);
        impl Drop for Cleanup<'_> {
            fn drop(&mut self) {
                for path in [RUN, APPROVAL] {
                    if let Ok(key) = windows_registry::CURRENT_USER.options().write().open(path) {
                        let _ = key.remove_value(self.0);
                    }
                }
            }
        }
        let _cleanup = Cleanup(&name);
        let app = tauri::test::mock_builder()
            .plugin(
                tauri_plugin_autostart::Builder::new()
                    .app_name(&name)
                    .build(),
            )
            .build(tauri::test::mock_context(tauri::test::noop_assets()))
            .unwrap();
        let run = windows_registry::CURRENT_USER.create(RUN).unwrap();
        let approval = windows_registry::CURRENT_USER.create(APPROVAL).unwrap();
        let executable = std::path::Path::new(r"C:\Program Files\Neutrino Proxy\client.exe");
        run.set_string(&name, format!("\"{}\"", executable.display()))
            .unwrap();
        approval
            .set_bytes(
                &name,
                windows_registry::Type::Bytes,
                &[3, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
            )
            .unwrap();
        let manager = app.autolaunch();
        assert!(!manager.is_enabled().unwrap());
        // Elevated registration refreshes HKLM only; this final step must also
        // restore the current user's approval independently of process privileges.
        complete_windows_registration(&name, executable).unwrap();
        assert!(
            manager.is_enabled().unwrap(),
            "current-user Task Manager disable must be cleared when enabling startup"
        );
        assert_eq!(
            run.get_string(&name).unwrap(),
            format!("\"{}\"", executable.display())
        );
    }

    #[cfg(windows)]
    #[test]
    fn windows_plugin_registers_and_removes_an_isolated_login_entry() {
        use tauri_plugin_autostart::ManagerExt;
        let name = format!("Neutrino settings test {}", uuid::Uuid::new_v4());
        let app = tauri::test::mock_builder()
            .plugin(
                tauri_plugin_autostart::Builder::new()
                    .app_name(&name)
                    .build(),
            )
            .build(tauri::test::mock_context(tauri::test::noop_assets()))
            .unwrap();
        let manager = app.autolaunch();
        let os = SystemAutoStart {
            manager: &manager,
            name: &name,
        };
        const APPROVAL: &str =
            r"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
        struct Cleanup<'a>(&'a tauri_plugin_autostart::AutoLaunchManager, &'a str);
        impl Drop for Cleanup<'_> {
            fn drop(&mut self) {
                let _ = self.0.disable();
                for root in [
                    windows_registry::CURRENT_USER,
                    windows_registry::LOCAL_MACHINE,
                ] {
                    if let Ok(key) = root.options().write().open(APPROVAL) {
                        let _ = key.remove_value(self.1);
                    }
                }
            }
        }
        let cleanup = Cleanup(&manager, &name);
        assert!(!os.enabled().unwrap());
        os.set_enabled(true).unwrap();
        assert!(os.enabled().unwrap());
        let run = windows_registry::CURRENT_USER
            .open(r"SOFTWARE\Microsoft\Windows\CurrentVersion\Run")
            .unwrap();
        let registered = run.get_string(&name).unwrap();
        let executable = std::env::current_exe().unwrap();
        assert_eq!(registered, format!("\"{}\"", executable.display()));
        let approval = windows_registry::CURRENT_USER.create(APPROVAL).unwrap();
        // Match Task Manager's disabled entry, including its nonzero disable time.
        approval
            .set_bytes(
                &name,
                windows_registry::Type::Bytes,
                &[3, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
            )
            .unwrap();
        assert!(!os.enabled().unwrap());
        os.set_enabled(true).unwrap();
        assert!(os.enabled().unwrap());
        assert_eq!(run.get_string(&name).unwrap(), registered);
        os.set_enabled(false).unwrap();
        assert!(!os.enabled().unwrap());
        assert!(run.get_string(&name).is_err());
        drop(cleanup);
        if let Ok(key) = windows_registry::CURRENT_USER.open(APPROVAL) {
            assert!(key.get_value(&name).is_err());
        }
    }
}
