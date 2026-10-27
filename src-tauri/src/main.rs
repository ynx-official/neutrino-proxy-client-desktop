#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
mod app_settings;
mod config_import;
#[cfg(dev)]
mod dev_frontend;
mod storage;
mod tray;
use neutrino_client_core::{
    config::{validate, ClientConfig},
    Engine, Snapshot,
};
use serde::Deserialize;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Mutex,
};
use tauri::{Emitter, Manager};
use tauri_plugin_autostart::ManagerExt;

#[derive(Default)]
struct Navigation(Mutex<Option<String>>);

#[tauri::command]
fn take_navigation(state: tauri::State<Navigation>) -> Option<String> {
    state.0.lock().unwrap().take()
}

struct AppState {
    engine: Engine,
    stored: Mutex<storage::Store>,
    quitting: AtomicBool,
}
struct ApplicationSettings(Mutex<app_settings::Store>);

#[tauri::command]
async fn get_app_settings(app: tauri::AppHandle) -> Result<app_settings::AppSettings, String> {
    tauri::async_runtime::spawn_blocking(move || {
        app.state::<ApplicationSettings>()
            .0
            .lock()
            .unwrap()
            .snapshot(&app_settings::SystemAutoStart::new(&app.autolaunch()))
    })
    .await
    .map_err(|_| "无法读取应用设置".to_owned())?
}

#[tauri::command]
async fn save_app_settings(
    app: tauri::AppHandle,
    request: app_settings::Patch,
) -> Result<app_settings::AppSettings, String> {
    tauri::async_runtime::spawn_blocking(move || {
        app.state::<ApplicationSettings>().0.lock().unwrap().update(
            request,
            &app_settings::SystemAutoStart::new(&app.autolaunch()),
        )
    })
    .await
    .map_err(|_| "无法保存应用设置".to_owned())?
}
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SaveRequest {
    config: ClientConfig,
    license: Option<String>,
    store_password: Option<String>,
    connect: bool,
}

#[tauri::command]
fn get_snapshot(state: tauri::State<AppState>) -> Snapshot {
    state.engine.snapshot()
}
#[tauri::command]
async fn connect(state: tauri::State<'_, AppState>) -> Result<(), String> {
    connect_command(&state).await
}
#[tauri::command]
async fn disconnect(state: tauri::State<'_, AppState>) -> Result<(), String> {
    state.engine.disconnect().await;
    Ok(())
}
#[tauri::command]
async fn save_config(
    state: tauri::State<'_, AppState>,
    mut request: SaveRequest,
) -> Result<Snapshot, String> {
    let (config, secrets) = {
        let mut stored = state.stored.lock().unwrap();
        if request.config.client_id.trim().is_empty() {
            request.config.client_id = stored.config.client_id.clone();
        }
        let mut secrets = stored.secrets.clone();
        if let Some(license) = request.license {
            secrets.license = license;
        }
        if let Some(password) = request.store_password {
            secrets.store_password = password;
        }
        let errors = validate(&request.config, !secrets.license.is_empty());
        if !errors.is_empty() {
            return Err(errors.values().cloned().collect::<Vec<_>>().join("；"));
        }
        stored.save(request.config.clone(), secrets.clone())?;
        (request.config, secrets)
    };
    state.engine.configure(config.clone(), &secrets);
    state.engine.log("info", "配置", "连接配置已保存在本机");
    if request.connect {
        state.engine.connect(config, secrets).await?;
    }
    Ok(state.engine.snapshot())
}
#[tauri::command]
fn close_to_tray(window: tauri::WebviewWindow) -> Result<(), String> {
    window.destroy().map_err(|e| e.to_string())
}
#[tauri::command]
async fn quit_app(app: tauri::AppHandle, state: tauri::State<'_, AppState>) -> Result<(), String> {
    state.quitting.store(true, Ordering::SeqCst);
    state.engine.disconnect().await;
    app.exit(0);
    Ok(())
}
#[tauri::command]
async fn select_certificate(app: tauri::AppHandle) -> Result<Option<String>, String> {
    use tauri_plugin_dialog::DialogExt;
    tokio::task::spawn_blocking(move || {
        app.dialog()
            .file()
            .add_filter("信任证书", &["jks", "pem", "crt", "cer", "der"])
            .blocking_pick_file()
            .map(|f| {
                f.into_path()
                    .map(|p| p.to_string_lossy().into_owned())
                    .map_err(|e| e.to_string())
            })
            .transpose()
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn import_config(app: tauri::AppHandle) -> Result<Option<storage::ImportPreview>, String> {
    use tauri_plugin_dialog::DialogExt;
    tokio::task::spawn_blocking(move || {
        let Some(file) = app
            .dialog()
            .file()
            .add_filter("YAML 配置", &["yml", "yaml"])
            .blocking_pick_file()
        else {
            return Ok(None);
        };
        let path = file.into_path().map_err(|e| e.to_string())?;
        storage::preview_import(&app, &path).map(Some)
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
async fn apply_import(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
    id: String,
) -> Result<Snapshot, String> {
    let (config, secrets) = storage::take_import(&app, &id)?;
    {
        let mut stored = state.stored.lock().unwrap();
        stored.save(config.clone(), secrets.clone())?;
    }
    state.engine.configure(config, &secrets);
    state
        .engine
        .log("info", "配置", "旧配置已导入，请确认后连接");
    Ok(state.engine.snapshot())
}
#[tauri::command]
async fn export_logs(
    app: tauri::AppHandle,
    state: tauri::State<'_, AppState>,
) -> Result<bool, String> {
    use tauri_plugin_dialog::DialogExt;
    let logs = state.engine.snapshot().logs;
    tokio::task::spawn_blocking(move || {
        let Some(file) = app
            .dialog()
            .file()
            .set_file_name("neutrino-client-logs.txt")
            .blocking_save_file()
        else {
            return Ok(false);
        };
        let path = file.into_path().map_err(|e| e.to_string())?;
        let text = logs
            .iter()
            .map(|l| format!("{} [{}] {}: {}\n", l.time, l.level, l.source, l.message))
            .collect::<String>();
        std::fs::write(path, text).map_err(|_| "无法写入日志文件".to_owned())?;
        Ok(true)
    })
    .await
    .map_err(|e| e.to_string())?
}
fn show_window(app: &tauri::AppHandle) {
    let app = app.clone();
    // WebView2 creation must run outside synchronous native event handlers.
    tauri::async_runtime::spawn_blocking(move || {
        if let Err(error) = show_main(&app, None) {
            app.state::<AppState>().engine.log("error", "窗口", &error);
        }
    });
}
fn show_main(app: &tauri::AppHandle, route: Option<&str>) -> Result<(), String> {
    if let Some(route) = route {
        *app.state::<Navigation>().0.lock().unwrap() = Some(route.into());
    }
    if let Some(window) = app.get_webview_window("main") {
        window
            .unminimize()
            .and_then(|_| window.show())
            .and_then(|_| window.set_focus())
            .map_err(|e| e.to_string())?;
        if route.is_some() {
            window
                .emit_to("main", "main-navigate", ())
                .map_err(|e| e.to_string())?;
        }
        return Ok(());
    }
    let config = app
        .config()
        .app
        .windows
        .iter()
        .find(|window| window.label == "main")
        .ok_or("主窗口配置缺失")?;
    tauri::WebviewWindowBuilder::from_config(app, config)
        .and_then(|builder| builder.build())
        .map_err(|e| e.to_string())?;
    // The new page consumes the pending route after installing its router guard.
    Ok(())
}
fn main() {
    let context = tauri::generate_context!();
    #[cfg(dev)]
    let frontend = match context.config().build.dev_url.as_ref() {
        Some(url) => dev_frontend::ensure(
            url,
            std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .parent()
                .unwrap(),
        ),
        None => Ok(None),
    }
    .unwrap_or_else(|error| {
        eprintln!("{error}");
        std::process::exit(1);
    });
    // The UI is transient; background networking shares a small fixed worker pool.
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .max_blocking_threads(4)
        .thread_name("neutrino-io")
        .enable_all()
        .build()
        .expect("无法创建客户端异步运行时");
    tauri::async_runtime::set(runtime.handle().clone());
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            show_window(app)
        }))
        .plugin(
            tauri_plugin_autostart::Builder::new()
                .app_name(app_settings::STARTUP_NAME)
                .build(),
        )
        .setup(|app| {
            let store = storage::Store::load(app.handle());
            let preferences =
                app_settings::Store::load(app.path().app_config_dir()?.join("app-settings.json"));
            let engine = Engine::new();
            engine.configure(store.config.clone(), &store.secrets);
            if let Some(error) = store.error.as_ref() {
                engine.log("error", "配置", error);
            }
            if let Some(error) = preferences.error.as_ref() {
                engine.log("error", "应用设置", error);
            }
            let startup = (preferences.auto_connect && store.error.is_none())
                .then(|| (store.config.clone(), store.secrets.clone()));
            app.manage(ApplicationSettings(Mutex::new(preferences)));
            app.manage(AppState {
                engine: engine.clone(),
                stored: Mutex::new(store),
                quitting: AtomicBool::new(false),
            });
            app.manage(storage::PendingImport::default());
            app.manage(Navigation::default());
            tray::install(app)?;
            let mut changes = engine.subscribe();
            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                loop {
                    let snapshot = changes.borrow_and_update().clone();
                    tray::update(&handle, &snapshot);
                    if let Some(window) = handle.get_webview_window("main") {
                        let _ = window.emit_to("main", "client-state", snapshot);
                    }
                    if changes.changed().await.is_err() {
                        break;
                    }
                }
            });
            // Only process setup consumes this attempt; restoring a tray window and
            // changing either preference never start a connection themselves.
            if let Some((config, secrets)) = startup {
                tauri::async_runtime::spawn(async move {
                    if let Err(error) = engine.connect_on_startup(config, secrets).await {
                        engine.log("error", "启动", &error);
                    }
                });
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            take_navigation,
            get_snapshot,
            get_app_settings,
            save_app_settings,
            connect,
            disconnect,
            save_config,
            close_to_tray,
            quit_app,
            select_certificate,
            import_config,
            apply_import,
            export_logs
        ])
        .build(context)
        .expect("无法启动 Neutrino Proxy");
    let exit_code = app.run_return(|app, event| {
        if let tauri::RunEvent::ExitRequested {
            code: None, api, ..
        } = event
        {
            if !app.state::<AppState>().quitting.load(Ordering::SeqCst) {
                api.prevent_exit();
            }
        }
    });
    #[cfg(dev)]
    drop(frontend);
    std::process::exit(exit_code);
}
async fn connect_command(state: &AppState) -> Result<(), String> {
    if matches!(
        state.engine.snapshot().state.as_str(),
        "connected" | "connecting" | "authenticating" | "stopping"
    ) {
        return Ok(());
    }
    let (config, secrets) = {
        let store = state.stored.lock().unwrap();
        (store.config.clone(), store.secrets.clone())
    };
    state.engine.connect(config, secrets).await
}
