use std::{collections::HashMap, sync::Arc};
use futures::StreamExt;
use tokio::sync::Mutex;
use zbus::{Connection, fdo::Result as ZbusResult, Proxy, MatchRule};
use zvariant::Value;
use crate::core::events::handlers::{handle_event, Event};
use crate::core::manager::Manager;
use crate::log::log_message;

pub async fn listen_for_suspend_events(idle_manager: Arc<Mutex<Manager>>) -> ZbusResult<()> {
    let connection = Connection::system().await?;
    let proxy = Proxy::new(
        &connection,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager"
    ).await?;
    
    let mut stream = proxy.receive_signal("PrepareForSleep").await?;
    log_message("Listening for D-Bus suspend events...");
    
    while let Some(signal) = stream.next().await {
        let going_to_sleep: bool = match signal.body().deserialize() {
            Ok(val) => val,
            Err(e) => {
                log_message(&format!("Failed to parse D-Bus suspend signal: {e:?}"));
                continue;
            }
        };
        
        let manager_arc = Arc::clone(&idle_manager);
        if going_to_sleep {
            handle_event(&manager_arc, Event::Suspend).await; 
        } else {
            handle_event(&manager_arc, Event::Wake).await;
        }
    }
    
    Ok(())
}

pub async fn listen_for_lid_events(idle_manager: Arc<Mutex<Manager>>) -> ZbusResult<()> {
    let connection = Connection::system().await?;
    log_message("Listening for D-Bus lid events via UPower...");
    
    // Create a match rule for PropertiesChanged signals from UPower
    let rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .interface("org.freedesktop.DBus.Properties")?
        .member("PropertiesChanged")?
        .path("/org/freedesktop/UPower")?
        .build();
    
    let mut stream = zbus::MessageStream::for_match_rule(
        rule,
        &connection,
        None,
    ).await?;
    
    while let Some(msg) = stream.next().await {
        let msg = match msg {
            Ok(m) => m,
            Err(e) => {
                log_message(&format!("Error receiving message: {e:?}"));
                continue;
            }
        };
        
        // Bind the body to a variable to extend its lifetime
        let body = msg.body();
        let (iface, changed, _): (String, HashMap<String, Value>, Vec<String>) =
            match body.deserialize() {
                Ok(val) => val,
                Err(e) => {
                    log_message(&format!("Failed to parse lid signal: {e:?}"));
                    continue;
                }
            };
        
        if iface == "org.freedesktop.UPower" {
            if let Some(val) = changed.get("LidIsClosed") {
                // Use Result-based pattern matching instead of Option
                match val.downcast_ref::<bool>() {
                    Ok(lid_closed) => {
                        let manager_arc = Arc::clone(&idle_manager);
                        if lid_closed {
                            handle_event(&manager_arc, Event::LidClosed).await;
                        } else {
                            handle_event(&manager_arc, Event::LidOpened).await;
                        }
                    }
                    Err(e) => {
                        log_message(&format!("Failed to downcast LidIsClosed value: {e:?}"));
                    }
                }
            }
        }
    }
    
    Ok(())
}

pub async fn listen_for_lock_events(idle_manager: Arc<Mutex<Manager>>) -> ZbusResult<()> {
    let connection = Connection::system().await?;
    log_message("Listening for D-Bus lock/unlock events...");
    
    // Get the session path for the current session
    let session_path = get_current_session_path(&connection).await?;
    
    log_message(&format!("Monitoring session: {}", session_path.as_str()));
    
    let proxy = Proxy::new(
        &connection,
        "org.freedesktop.login1",
        session_path.clone(),
        "org.freedesktop.login1.Session"
    ).await?;
    
    // Listen for Lock signal
    let mut lock_stream = proxy.receive_signal("Lock").await?;
    let manager_for_lock = Arc::clone(&idle_manager);
    
    // Listen for Unlock signal
    let mut unlock_stream = proxy.receive_signal("Unlock").await?;
    let manager_for_unlock = Arc::clone(&idle_manager);
    
    // Spawn task for Lock signals
    let lock_task = tokio::spawn(async move {
        while let Some(_signal) = lock_stream.next().await {
            log_message("Received Lock signal from loginctl");
            handle_event(&manager_for_lock, Event::LoginctlLock).await;
        }
    });
    
    // Spawn task for Unlock signals
    let unlock_task = tokio::spawn(async move {
        while let Some(_signal) = unlock_stream.next().await {
            log_message("Received Unlock signal from loginctl");
            handle_event(&manager_for_unlock, Event::LoginctlUnlock).await;
        }
    });
    
    let _ = tokio::try_join!(lock_task, unlock_task);
    Ok(())
}

async fn get_current_session_path(connection: &Connection) -> ZbusResult<zvariant::OwnedObjectPath> {
    let proxy = Proxy::new(
        connection,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager"
    ).await?;
    
    // Get the current user's UID
    let uid = unsafe { libc::getuid() };
    
    // Call ListSessions to find our session
    let sessions: Vec<(String, u32, String, String, zvariant::OwnedObjectPath)> = 
        proxy.call("ListSessions", &()).await?;
    
    // Find the session that matches our UID and return its path
    for (_session_id, session_uid, _username, _seat, path) in sessions {
        if session_uid == uid {
            return Ok(path);
        }
    }
    
    // Fallback: try to get the session from the PID
    let pid = std::process::id();
    let session_path: zvariant::OwnedObjectPath = proxy.call("GetSessionByPID", &(pid,)).await?;
    
    Ok(session_path)
}

// Combined listener that handles suspend, lid, and lock events
pub async fn listen_for_power_events(idle_manager: Arc<Mutex<Manager>>) -> ZbusResult<()> {
    let suspend_manager = Arc::clone(&idle_manager);
    let lid_manager = Arc::clone(&idle_manager);
    let lock_manager = Arc::clone(&idle_manager);
    
    let suspend_handle = tokio::spawn(async move {
        if let Err(e) = listen_for_suspend_events(suspend_manager).await {
            log_message(&format!("Suspend listener error: {e:?}"));
        }
    });
    
    let lid_handle = tokio::spawn(async move {
        if let Err(e) = listen_for_lid_events(lid_manager).await {
            log_message(&format!("Lid listener error: {e:?}"));
        }
    });
    
    let lock_handle = tokio::spawn(async move {
        if let Err(e) = listen_for_lock_events(lock_manager).await {
            log_message(&format!("Lock listener error: {e:?}"));
        }
    });
    
    let _ = tokio::try_join!(suspend_handle, lid_handle, lock_handle);
    Ok(())
}
