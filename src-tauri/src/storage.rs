use neutrino_client_core::config::{ClientConfig, Secrets};
use serde::{Deserialize, Serialize};
use std::{
    path::{Path, PathBuf},
    sync::Mutex,
};
use tauri::Manager;

const SERVICE: &str = "fun.neutrino.proxy.desktop";
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Stored {
    schema_version: u32,
    config: ClientConfig,
    credential_id: String,
}
#[derive(Serialize, Deserialize)]
struct Credential {
    license: String,
    store_password: String,
}
pub struct Store {
    pub config: ClientConfig,
    pub secrets: Secrets,
    pub error: Option<String>,
    path: PathBuf,
    credential_id: String,
}
impl Store {
    pub fn load(app: &tauri::AppHandle) -> Self {
        let dir = app.path().app_config_dir().expect("应用配置目录不可用");
        let path = dir.join("config.json");
        let mut result = Self {
            config: ClientConfig::default(),
            secrets: Secrets::default(),
            error: None,
            path,
            credential_id: String::new(),
        };
        if result.path.exists() {
            match std::fs::read(&result.path)
                .ok()
                .and_then(|bytes| serde_json::from_slice::<Stored>(&bytes).ok())
            {
                Some(stored) if stored.schema_version == 1 => {
                    result.config = stored.config;
                    result.credential_id = stored.credential_id;
                    if !result.credential_id.is_empty() {
                        match keyring::Entry::new(SERVICE, &result.credential_id)
                            .and_then(|entry| entry.get_password())
                            .ok()
                            .and_then(|secret| serde_json::from_str::<Credential>(&secret).ok())
                        {
                            Some(secret) => {
                                result.secrets = Secrets {
                                    license: secret.license,
                                    store_password: secret.store_password,
                                }
                            }
                            None => {
                                result.error =
                                    Some("无法读取系统保存的凭证，请重新填写 License".into())
                            }
                        }
                    }
                }
                _ => result.error = Some("配置文件无法读取或版本不兼容，原文件已保留".into()),
            }
        }
        result
    }
    pub fn save(&mut self, config: ClientConfig, secrets: Secrets) -> Result<(), String> {
        let id = uuid::Uuid::new_v4().to_string();
        let entry =
            keyring::Entry::new(SERVICE, &id).map_err(|_| "系统安全存储不可用".to_owned())?;
        let credential = serde_json::to_string(&Credential {
            license: secrets.license.clone(),
            store_password: secrets.store_password.clone(),
        })
        .map_err(|_| "无法保存凭证".to_owned())?;
        entry
            .set_password(&credential)
            .map_err(|_| "无法写入系统安全存储，配置尚未保存".to_owned())?;
        let saved = (|| {
            std::fs::create_dir_all(self.path.parent().unwrap())
                .map_err(|_| "无法创建配置目录".to_owned())?;
            let value = Stored {
                schema_version: 1,
                config: config.clone(),
                credential_id: id.clone(),
            };
            let bytes =
                serde_json::to_vec_pretty(&value).map_err(|_| "无法序列化配置".to_owned())?;
            let temp = self.path.with_extension("json.tmp");
            use std::io::Write;
            let mut file =
                std::fs::File::create(&temp).map_err(|_| "无法写入配置文件".to_owned())?;
            file.write_all(&bytes)
                .and_then(|_| file.sync_all())
                .map_err(|_| "无法完成配置写入".to_owned())?;
            std::fs::rename(&temp, &self.path).map_err(|_| "无法替换配置文件".to_owned())?;
            Ok::<_, String>(())
        })();
        if let Err(error) = saved {
            let _ = entry.delete_credential();
            return Err(error);
        }
        if !self.credential_id.is_empty() {
            if let Ok(old) = keyring::Entry::new(SERVICE, &self.credential_id) {
                let _ = old.delete_credential();
            }
        }
        self.config = config;
        self.secrets = secrets;
        self.credential_id = id;
        self.error = None;
        Ok(())
    }
}
#[derive(Default)]
pub struct PendingImport(Mutex<Option<(String, ClientConfig, Secrets)>>);
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ImportPreview {
    id: String,
    pub config: ClientConfig,
    has_license: bool,
    notes: Vec<String>,
    can_apply: bool,
    imported_fields: Vec<&'static str>,
}
pub fn preview_import(app: &tauri::AppHandle, path: &Path) -> Result<ImportPreview, String> {
    if std::fs::metadata(path)
        .map_err(|_| "无法读取配置文件".to_owned())?
        .len()
        > 1024 * 1024
    {
        return Err("配置文件不能超过 1 MiB".into());
    }
    let bytes = std::fs::read(path).map_err(|_| "无法读取配置文件".to_owned())?;
    let state = app.state::<crate::AppState>();
    let (current, current_secrets) = {
        let store = state.stored.lock().unwrap();
        (store.config.clone(), store.secrets.clone())
    };
    let crate::config_import::ParsedImport {
        config,
        secrets,
        notes,
        can_apply,
        imported_fields,
    } = crate::config_import::parse_import(&bytes, path, &current, &current_secrets)?;
    let id = uuid::Uuid::new_v4().to_string();
    let preview = ImportPreview {
        id: id.clone(),
        config: config.clone(),
        has_license: !secrets.license.is_empty(),
        notes,
        can_apply,
        imported_fields,
    };
    *app.state::<PendingImport>().0.lock().unwrap() = if can_apply {
        Some((id, config, secrets))
    } else {
        None
    };
    Ok(preview)
}
pub fn take_import(app: &tauri::AppHandle, id: &str) -> Result<(ClientConfig, Secrets), String> {
    let pending = app.state::<PendingImport>();
    let mut pending = pending.0.lock().unwrap();
    if pending.as_ref().is_some_and(|(key, _, _)| key == id) {
        let (_, config, secrets) = pending.take().unwrap();
        Ok((config, secrets))
    } else {
        Err("导入预览已失效，请重新选择文件".into())
    }
}
