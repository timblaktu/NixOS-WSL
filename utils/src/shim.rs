use anyhow::Context;
use nix::errno::Errno;
use nix::mount::{mount, MsFlags};
use nix::sys::wait::{waitid, Id, WaitPidFlag};
use nix::unistd::Pid;
use std::env;
use std::fs::{create_dir_all, metadata, remove_dir_all, remove_file, OpenOptions};
use std::mem;
use std::os::unix::io::{FromRawFd, IntoRawFd};
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Command, Stdio};

// Constants for VSOCK communication
const AF_VSOCK: i32 = 40;
const SOCK_STREAM: i32 = 1;
const VMADDR_CID_ANY: u32 = 0xFFFFFFFF;
const PLUGIN_PORT: u32 = 5001;

#[repr(C)]
struct sockaddr_vm {
    svm_family: u16,
    svm_reserved1: u16,
    svm_port: u32,
    svm_cid: u32,
    svm_zero: [u8; 4],
}

fn communicate_with_plugin(config_content: &str) -> anyhow::Result<String> {
    log::trace!("Creating VSOCK server on port {}...", PLUGIN_PORT);
    
    // Create VSOCK socket
    let socket = unsafe { libc::socket(AF_VSOCK, SOCK_STREAM, 0) };
    if socket < 0 {
        return Err(anyhow::anyhow!("Failed to create VSOCK socket"));
    }

    // Set timeout on accept (5 seconds)
    let tv = libc::timeval {
        tv_sec: 5,
        tv_usec: 0,
    };
    unsafe {
        libc::setsockopt(
            socket,
            libc::SOL_SOCKET,
            libc::SO_RCVTIMEO,
            &tv as *const _ as *const libc::c_void,
            mem::size_of::<libc::timeval>() as libc::socklen_t,
        );
    }

    // Bind to port 5001, accept from any CID
    let addr = sockaddr_vm {
        svm_family: AF_VSOCK as u16,
        svm_reserved1: 0,
        svm_port: PLUGIN_PORT,
        svm_cid: VMADDR_CID_ANY,
        svm_zero: [0; 4],
    };

    let result = unsafe {
        libc::bind(
            socket,
            &addr as *const _ as *const libc::sockaddr,
            mem::size_of::<sockaddr_vm>() as libc::socklen_t,
        )
    };

    if result < 0 {
        unsafe { libc::close(socket); }
        return Err(anyhow::anyhow!("Failed to bind VSOCK socket to port {}", PLUGIN_PORT));
    }

    // Listen for connection
    let result = unsafe { libc::listen(socket, 1) };
    if result < 0 {
        unsafe { libc::close(socket); }
        return Err(anyhow::anyhow!("Failed to listen on VSOCK socket"));
    }

    log::trace!("Waiting for plugin connection...");

    // Accept connection
    let client = unsafe {
        libc::accept(socket, std::ptr::null_mut(), std::ptr::null_mut())
    };

    unsafe { libc::close(socket); }

    if client < 0 {
        return Err(anyhow::anyhow!("Accept timeout - no plugin connected"));
    }

    log::trace!("Plugin connected, sending configuration...");

    // Send configuration
    let result = unsafe {
        libc::send(
            client,
            config_content.as_ptr() as *const libc::c_void,
            config_content.len(),
            0,
        )
    };

    if result < 0 {
        unsafe { libc::close(client); }
        return Err(anyhow::anyhow!("Failed to send configuration"));
    }

    // Receive response
    let mut buffer = vec![0u8; 4096];
    let result = unsafe {
        libc::recv(
            client,
            buffer.as_mut_ptr() as *mut libc::c_void,
            buffer.len(),
            0,
        )
    };

    unsafe { libc::close(client); }

    if result <= 0 {
        return Err(anyhow::anyhow!("Failed to receive response"));
    }

    let response = String::from_utf8_lossy(&buffer[..result as usize]);
    Ok(response.to_string())
}

fn check_plugin_config() -> anyhow::Result<()> {
    let config_path = "/etc/nixos-wsl-plugin.ini";
    
    if !Path::new(config_path).exists() {
        log::trace!("No plugin configuration found at {}", config_path);
        return Ok(());
    }

    log::info!("Found WSL plugin configuration, processing disk requirements...");
    
    let config_content = std::fs::read_to_string(config_path)
        .context("Failed to read plugin config")?;

    // Use configparser to parse INI
    use configparser::ini::Ini;
    let mut config = Ini::new();
    let _parsed = config.read(config_content.clone());
    // Note: configparser returns a Result<HashMap, String> but we'll just check sections

    // Check if any disks are configured
    let sections = config.sections();
    let has_disks = sections.iter()
        .any(|name| name.starts_with("bare_disk_") || name.starts_with("vhdx_"));

    if !has_disks {
        log::trace!("No disk requirements configured");
        return Ok(());
    }

    // Communicate with plugin
    match communicate_with_plugin(&config_content) {
        Ok(response) if response.starts_with("STATUS ready") => {
            log::info!("Plugin reports all disks are ready");
            Ok(())
        }
        Ok(response) => {
            log::error!("Plugin response: {}", response);
            Err(anyhow::anyhow!("Disk requirements not met: {}", response))
        }
        Err(e) => {
            // Plugin communication failed - continue without validation
            log::warn!("Plugin communication failed: {}. Continuing without disk validation", e);
            Ok(())
        }
    }
}

fn unscrew_dev_shm() -> anyhow::Result<()> {
    log::trace!("Unscrewing /dev/shm...");

    let dev_shm = Path::new("/dev/shm");

    if dev_shm.is_symlink() {
        remove_file(dev_shm).context("When removing /dev/shm symlink")?;
    } else if dev_shm.is_dir() {
        remove_dir_all(dev_shm).context("When removing old /dev/shm")?;
    }

    create_dir_all("/dev/shm").context("When creating new /dev/shm")?;
    mount(
        Some("/run/shm"),
        "/dev/shm",
        None::<&str>,
        MsFlags::MS_MOVE,
        None::<&str>,
    )
    .context("When relocating /dev/shm")?;
    mount(
        Some("/dev/shm"),
        "/run/shm",
        None::<&str>,
        MsFlags::MS_BIND,
        None::<&str>,
    )
    .context("When bind mounting /run/shm to /dev/shm")?;

    Ok(())
}

fn real_main() -> anyhow::Result<()> {
    // Check and wait for plugin disk requirements before proceeding
    check_plugin_config()?;
    
    if metadata("/dev/shm")
        .context("When checking /dev/shm")?
        .is_symlink()
    {
        unscrew_dev_shm()?;
    } else {
        log::trace!("/dev/shm is not a symlink, leaving as-is...");
    };

    log::trace!("Remounting / shared...");

    mount(
        None::<&str>,
        "/",
        None::<&str>,
        MsFlags::MS_REC | MsFlags::MS_SHARED,
        None::<&str>,
    )
    .context("When remounting /")?;

    log::trace!("Remounting /nix/store read-only...");

    mount(
        Some("/nix/store"),
        "/nix/store",
        None::<&str>,
        MsFlags::MS_BIND,
        None::<&str>,
    )
    .context("When bind mounting /nix/store")?;

    mount(
        Some("/nix/store"),
        "/nix/store",
        None::<&str>,
        MsFlags::MS_BIND | MsFlags::MS_REMOUNT | MsFlags::MS_RDONLY,
        None::<&str>,
    )
    .context("When remounting /nix/store read-only")?;

    log::trace!("Running activation script...");

    let kmsg_fd = OpenOptions::new()
        .write(true)
        .open("/dev/kmsg")
        .context("When opening /dev/kmsg")?
        .into_raw_fd();

    let child = Command::new("/nix/var/nix/profiles/system/activate")
        .env("LANG", "C.UTF-8")
        // SAFETY: we just opened this
        .stdout(unsafe { Stdio::from_raw_fd(kmsg_fd) })
        .stderr(unsafe { Stdio::from_raw_fd(kmsg_fd) })
        .spawn()
        .context("When activating")?;

    let pid = Pid::from_raw(child.id() as i32);

    // If the child catches SIGCHLD, `waitid` will wait for it to exit, then return ECHILD.
    // Why? Because POSIX is terrible.
    let result = waitid(Id::Pid(pid), WaitPidFlag::WEXITED);
    match result {
        Ok(_) | Err(Errno::ECHILD) => {}
        Err(e) => return Err(e).context("When waiting"),
    };

    log::trace!("Spawning real systemd...");

    // if things go right, we will never return from here
    Err(
        Command::new("/nix/var/nix/profiles/system/systemd/lib/systemd/systemd")
            .arg0(env::args_os().next().expect("arg0 missing"))
            .arg("--log-target=kmsg") // log to dmesg
            .args(env::args_os().skip(1))
            .exec()
            .into(),
    )
}

fn main() {
    env::set_var("RUST_BACKTRACE", "1");
    kernlog::init().expect("Failed to set up logger...");
    let result = real_main();
    log::error!("Error: {:?}", result);
}
