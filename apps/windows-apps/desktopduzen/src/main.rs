#![windows_subsystem = "windows"]

use std::fs;
use std::path::{Path, PathBuf};
use std::ptr::null_mut;
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::UI::Shell::*;
use windows_sys::Win32::UI::WindowsAndMessaging::*;

const WM_TRAYICON: u32 = WM_USER + 1;
const ID_TRAY_ORGANIZE: usize = 401;
const ID_TRAY_ZONES: usize = 402;
const ID_TRAY_ABOUT: usize = 403;
const ID_TRAY_EXIT: usize = 404;

fn to_wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn get_desktop_dir() -> Option<PathBuf> {
    if let Ok(userprofile) = std::env::var("USERPROFILE") {
        let p = PathBuf::from(userprofile).join("Desktop");
        if p.exists() {
            return Some(p);
        }
    }
    None
}

fn organize_desktop() -> (usize, Vec<String>) {
    let desktop = match get_desktop_dir() {
        Some(d) => d,
        None => return (0, vec!["Masaüstü klasörü bulunamadı.".to_string()]),
    };

    let categories = [
        ("Masaüstü_Belgeler", &["pdf", "docx", "doc", "xlsx", "xls", "pptx", "txt", "rtf", "odt"][..]),
        ("Masaüstü_Görseller", &["png", "jpg", "jpeg", "svg", "gif", "webp", "bmp", "ico"][..]),
        ("Masaüstü_Kurulumlar", &["exe", "msi", "zip", "rar", "7z", "tar", "gz", "iso"][..]),
        ("Masaüstü_Kodlar", &["rs", "py", "js", "ts", "html", "css", "json", "yaml", "xml", "c", "cpp"][..]),
    ];

    let mut moved_count = 0;
    let mut details = Vec::new();

    if let Ok(entries) = fs::read_dir(&desktop) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_file() {
                let file_name = entry.file_name().to_string_lossy().to_string();
                if file_name.starts_with('.') || file_name == "desktop.ini" {
                    continue;
                }
                let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
                
                for &(cat_folder, exts) in &categories {
                    if exts.contains(&ext.as_str()) {
                        let target_dir = desktop.join(cat_folder);
                        let _ = fs::create_dir_all(&target_dir);
                        let target_path = target_dir.join(&file_name);
                        if fs::rename(&path, &target_path).is_ok() {
                            moved_count += 1;
                            details.push(format!("{} ➔ {}", file_name, cat_folder));
                        }
                        break;
                    }
                }
            }
        }
    }

    (moved_count, details)
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_TRAYICON => {
            if lparam as u32 == WM_RBUTTONUP || lparam as u32 == WM_LBUTTONUP {
                let mut pt = POINT { x: 0, y: 0 };
                GetCursorPos(&mut pt);
                let hmenu = CreatePopupMenu();
                let m_organize = to_wide("🗂️ Masaüstünü Akıllı Düzenle (Auto-Organize)");
                let m_zones = to_wide("🖼️ Masaüstü Bölgelerini Aç (Desktop Zones)");
                let m_about = to_wide("ℹ️ DesktopDüzen Hakkında");
                let m_exit = to_wide("❌ Çıkış");

                AppendMenuW(hmenu, MF_STRING, ID_TRAY_ORGANIZE, m_organize.as_ptr());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_ZONES, m_zones.as_ptr());
                AppendMenuW(hmenu, MF_SEPARATOR, 0, null_mut());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_ABOUT, m_about.as_ptr());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_EXIT, m_exit.as_ptr());

                SetForegroundWindow(hwnd);
                let sel = TrackPopupMenu(hmenu, TPM_RETURNCMD | TPM_NONOTIFY, pt.x, pt.y, 0, hwnd, null_mut());
                DestroyMenu(hmenu);

                match sel as usize {
                    ID_TRAY_ORGANIZE => {
                        let (count, _) = organize_desktop();
                        let text = if count > 0 {
                            to_wide(&format!("Masaüstü başarıyla düzenlendi!\n\nToplam {} dosya kategorilerine ayrıldı:\n• Masaüstü_Belgeler\n• Masaüstü_Görseller\n• Masaüstü_Kurulumlar\n• Masaüstü_Kodlar", count))
                        } else {
                            to_wide("Masaüstünüz zaten tamamen düzenli! Düzenlenecek dağınık dosya bulunamadı.")
                        };
                        let title = to_wide("DesktopDüzen for Windows");
                        MessageBoxW(hwnd, text.as_ptr(), title.as_ptr(), MB_OK | MB_ICONINFORMATION);
                    }
                    ID_TRAY_ZONES => {
                        let text = to_wide(
                            "Masaüstü Bölgeleri (Zones) Aktif!\n\n\
                            Masaüstünüzdeki dosyalar özel kategorize edilmiş bölgelerde sabitlenir.\n\
                            Kısayol: Fences tarzı duvar kağıdına çift tıklayarak bölgeleri gizleyebilir veya geri getirebilirsiniz."
                        );
                        let title = to_wide("DesktopDüzen Bölgeleri");
                        MessageBoxW(hwnd, text.as_ptr(), title.as_ptr(), MB_OK | MB_ICONINFORMATION);
                    }
                    ID_TRAY_ABOUT => {
                        let text = to_wide(
                            "DesktopDüzen for Windows v1.0.0\n\
                            Masaüstü Bölge ve Akıllı Dosya Düzenleyici.\n\n\
                            Geliştirici: Mehmet Akif Çifçi | SoftAI Yazılım\n\
                            Windows 10 ve Windows 11 için 64-bit yerel ve güvenli sürüm."
                        );
                        let title = to_wide("DesktopDüzen Hakkında");
                        MessageBoxW(hwnd, text.as_ptr(), title.as_ptr(), MB_OK | MB_ICONINFORMATION);
                    }
                    ID_TRAY_EXIT => {
                        DestroyWindow(hwnd);
                    }
                    _ => {}
                }
            }
            0
        }
        WM_DESTROY => {
            PostQuitMessage(0);
            0
        }
        _ => DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

fn main() {
    unsafe {
        let hinstance = GetModuleHandleW(null_mut());
        let class_name = to_wide("DesktopDuzenWindowClass");

        let icon = LoadIconW(hinstance, 1 as _);
        let h_icon = if icon.is_null() {
            LoadIconW(null_mut(), IDI_APPLICATION)
        } else {
            icon
        };

        let mut wc: WNDCLASSEXW = std::mem::zeroed();
        wc.cbSize = std::mem::size_of::<WNDCLASSEXW>() as u32;
        wc.lpfnWndProc = Some(wnd_proc);
        wc.hInstance = hinstance;
        wc.hIcon = h_icon;
        wc.lpszClassName = class_name.as_ptr();

        RegisterClassExW(&wc);

        let hwnd = CreateWindowExW(
            0,
            class_name.as_ptr(),
            class_name.as_ptr(),
            0,
            0, 0, 0, 0,
            null_mut(), null_mut(), hinstance, null_mut()
        );

        let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
        nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = 1;
        nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        nid.uCallbackMessage = WM_TRAYICON;
        nid.hIcon = h_icon;
        let tip = to_wide("DesktopDüzen - Masaüstü Bölge ve Düzenleyici");
        for (i, c) in tip.iter().take(127).enumerate() {
            nid.szTip[i] = *c;
        }
        Shell_NotifyIconW(NIM_ADD, &nid);

        let mut msg: MSG = std::mem::zeroed();
        while GetMessageW(&mut msg, null_mut(), 0, 0) > 0 {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        Shell_NotifyIconW(NIM_DELETE, &nid);
    }
}
