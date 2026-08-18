use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct EnvVar {
    pub key: String,
    pub value: String,
    pub encrypted: bool,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ProcessOutput {
    pub stdout: String,
    pub stderr: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RecentProject {
    pub path: String,
    pub name: String,
    #[serde(rename = "lastOpened")]
    pub last_opened: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct RecentStore {
    projects: Vec<RecentProject>,
}

fn get_augmented_path() -> String {
    let mut paths = vec![
        "/opt/homebrew/bin".to_string(),
        "/opt/homebrew/sbin".to_string(),
        "/usr/local/bin".to_string(),
        "/usr/bin".to_string(),
        "/bin".to_string(),
        "/usr/sbin".to_string(),
        "/sbin".to_string(),
    ];

    if let Some(home) = dirs::home_dir() {
        paths.push(home.join(".dotenvx/bin").to_string_lossy().to_string());
        paths.push(home.join(".cargo/bin").to_string_lossy().to_string());
        paths.push(home.join(".local/bin").to_string_lossy().to_string());
        paths.push(home.join(".bun/bin").to_string_lossy().to_string());
    }

    if let Ok(existing) = std::env::var("PATH") {
        for p in existing.split(':') {
            if !paths.contains(&p.to_string()) && !p.is_empty() {
                paths.push(p.to_string());
            }
        }
    }

    paths.join(":")
}

fn get_recent_file_path() -> Result<PathBuf, String> {
    let home = dirs::home_dir().ok_or_else(|| "Could not determine user home directory".to_string())?;
    Ok(home.join(".dotenvx-gui.json"))
}

fn find_dotenvx_executable() -> (String, Vec<String>) {
    let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"));
    let home_dotenvx = home.join(".dotenvx/bin/dotenvx");

    let candidates = [
        "/opt/homebrew/bin/dotenvx",
        "/usr/local/bin/dotenvx",
        home_dotenvx.to_str().unwrap_or(""),
    ];

    for candidate in candidates {
        if !candidate.is_empty() && Path::new(candidate).exists() {
            return (candidate.to_string(), Vec::new());
        }
    }

    ("dotenvx".to_string(), Vec::new())
}

fn execute_dotenvx(args: &[&str], cwd: Option<&Path>) -> Result<ProcessOutput, String> {
    let (exe, base_args) = find_dotenvx_executable();
    let mut cmd = Command::new(&exe);

    cmd.env("PATH", get_augmented_path());

    for arg in &base_args {
        cmd.arg(arg);
    }
    for arg in args {
        cmd.arg(arg);
    }

    if let Some(dir) = cwd {
        cmd.current_dir(dir);
    }

    let output = cmd.output().map_err(|e| format!("Failed to execute dotenvx ({}): {}", exe, e))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if !output.status.success() {
        let msg = if !stderr.trim().is_empty() {
            stderr.trim().to_string()
        } else if !stdout.trim().is_empty() {
            stdout.trim().to_string()
        } else {
            format!("Command failed with status {:?}", output.status.code())
        };
        return Err(msg);
    }

    Ok(ProcessOutput { stdout, stderr })
}

fn atomic_write(path: &Path, content: &str, mode: u32) -> Result<(), String> {
    let parent = path.parent().ok_or_else(|| "Invalid parent directory".to_string())?;
    let temp_file_name = format!(".tmp.{}.{}", std::process::id(), fastrand());
    let temp_path = parent.join(temp_file_name);

    {
        let mut file = fs::File::create(&temp_path).map_err(|e| e.to_string())?;
        fs::set_permissions(&temp_path, fs::Permissions::from_mode(mode)).map_err(|e| e.to_string())?;
        file.write_all(content.as_bytes()).map_err(|e| e.to_string())?;
        file.sync_all().map_err(|e| e.to_string())?;
    }

    fs::rename(&temp_path, path).map_err(|e| {
        let _ = fs::remove_file(&temp_path);
        e.to_string()
    })?;

    Ok(())
}

fn fastrand() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
    nanos as u64
}

fn validate_key_name(key: &str) -> Result<(), String> {
    let re = regex::Regex::new(r"^[A-Za-z_][A-Za-z0-9_]*$").map_err(|e| e.to_string())?;
    if !re.is_match(key) {
        return Err("Key must be a valid environment variable name (e.g. MY_KEY)".to_string());
    }
    Ok(())
}

#[tauri::command]
async fn pick_folder() -> Result<String, String> {
    let script = "POSIX path of (choose folder with prompt \"Select a project folder\")";
    let output = Command::new("osascript")
        .args(["-e", script])
        .output()
        .map_err(|e| format!("Failed to run folder picker: {}", e))?;

    if !output.status.success() {
        let err_msg = String::from_utf8_lossy(&output.stderr);
        if err_msg.contains("User canceled") || err_msg.contains("-128") {
            return Err("cancelled".to_string());
        }
        return Err(err_msg.trim().to_string());
    }

    let raw_path = String::from_utf8_lossy(&output.stdout);
    let selected_path = raw_path.trim().trim_end_matches('/').to_string();
    if selected_path.is_empty() {
        return Err("cancelled".to_string());
    }
    Ok(selected_path)
}

#[tauri::command]
fn get_files(dir: String) -> Result<Vec<String>, String> {
    let path = Path::new(&dir);
    if !path.is_dir() {
        return Err("Path is not a directory".to_string());
    }

    let mut files = Vec::new();
    let entries = fs::read_dir(path).map_err(|e| e.to_string())?;

    for entry in entries.flatten() {
        if let Ok(file_type) = entry.file_type() {
            if file_type.is_file() {
                let name = entry.file_name().to_string_lossy().to_string();
                if name.starts_with(".env") && name != ".env.keys" {
                    files.push(name);
                }
            }
        }
    }

    files.sort();
    Ok(files)
}

#[tauri::command]
fn read_env(file: String) -> Result<Vec<EnvVar>, String> {
    let path = Path::new(&file);
    if !path.is_file() {
        return Err("File does not exist or is not a regular file".to_string());
    }

    let content = fs::read_to_string(path).map_err(|e| e.to_string())?;
    let mut variables = Vec::new();

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }

        if let Some(equal_idx) = trimmed.find('=') {
            let key = trimmed[..equal_idx].trim().to_string();
            let mut value = trimmed[equal_idx + 1..].trim().to_string();

            if (value.starts_with('"') && value.ends_with('"'))
                || (value.starts_with('\'') && value.ends_with('\''))
            {
                if value.len() >= 2 {
                    value = value[1..value.len() - 1].to_string();
                }
            }

            let encrypted = value.starts_with("encrypted:");
            variables.push(EnvVar {
                key,
                value,
                encrypted,
            });
        }
    }

    Ok(variables)
}

#[tauri::command]
fn set_env(file: String, key: String, value: String) -> Result<ProcessOutput, String> {
    validate_key_name(&key)?;
    let path = Path::new(&file);
    let parent = path.parent();
    execute_dotenvx(&["set", &key, &value, "-f", &file], parent)
}

#[tauri::command]
fn unset_env(file: String, key: String) -> Result<String, String> {
    validate_key_name(&key)?;
    let path = Path::new(&file);
    if !path.is_file() {
        return Err("File does not exist".to_string());
    }

    let content = fs::read_to_string(path).map_err(|e| e.to_string())?;
    let mut new_lines = Vec::new();

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            new_lines.push(line.to_string());
            continue;
        }

        if let Some(equal_idx) = trimmed.find('=') {
            let line_key = trimmed[..equal_idx].trim();
            if line_key == key {
                continue; // Skip this variable
            }
        }
        new_lines.push(line.to_string());
    }

    let mut result_content = new_lines.join("\n");
    if !result_content.is_empty() && !result_content.ends_with('\n') {
        result_content.push('\n');
    }

    atomic_write(path, &result_content, 0o600)?;
    Ok("Unset successful".to_string())
}

#[tauri::command]
fn encrypt_env(file: String) -> Result<ProcessOutput, String> {
    let path = Path::new(&file);
    let parent = path.parent();
    execute_dotenvx(&["encrypt", "-f", &file], parent)
}

#[tauri::command]
fn decrypt_env(file: String) -> Result<ProcessOutput, String> {
    let path = Path::new(&file);
    let parent = path.parent();
    execute_dotenvx(&["decrypt", "-f", &file], parent)
}

#[tauri::command]
fn run_command(dir: String, cmd: String) -> Result<ProcessOutput, String> {
    let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".to_string());
    let path = Path::new(&dir);
    execute_dotenvx(&["run", "--", &shell, "-lc", &cmd], Some(path))
}

#[tauri::command]
fn get_recent() -> Result<Vec<RecentProject>, String> {
    let file = get_recent_file_path()?;
    if !file.exists() {
        return Ok(Vec::new());
    }

    let content = fs::read_to_string(&file).map_err(|e| e.to_string())?;
    let store: RecentStore = serde_json::from_str(&content).unwrap_or(RecentStore { projects: Vec::new() });
    Ok(store.projects)
}

#[tauri::command]
fn add_recent(project_path: String) -> Result<Vec<RecentProject>, String> {
    let file = get_recent_file_path()?;
    let mut projects = get_recent().unwrap_or_default();

    projects.retain(|p| p.path != project_path);

    let name = Path::new(&project_path)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| project_path.clone());

    let now = chrono_iso_now();

    projects.insert(
        0,
        RecentProject {
            path: project_path,
            name,
            last_opened: Some(now),
        },
    );

    projects.truncate(10);

    let store = RecentStore {
        projects: projects.clone(),
    };

    let serialized = serde_json::to_string_pretty(&store).map_err(|e| e.to_string())?;
    atomic_write(&file, &serialized, 0o600)?;

    Ok(projects)
}

fn chrono_iso_now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let d = SystemTime::now().duration_since(UNIX_EPOCH).unwrap();
    let secs = d.as_secs();
    format!("{}-01-01T00:00:00Z", 1970 + secs / 31536000)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_log::Builder::default().build())
        .invoke_handler(tauri::generate_handler![
            pick_folder,
            get_files,
            read_env,
            set_env,
            unset_env,
            encrypt_env,
            decrypt_env,
            run_command,
            get_recent,
            add_recent,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
