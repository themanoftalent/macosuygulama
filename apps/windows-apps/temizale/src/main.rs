#![windows_subsystem = "windows"]

use std::fs;
use std::path::PathBuf;
use std::ptr::null_mut;
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::Graphics::Gdi::*;
use windows_sys::Win32::UI::Input::KeyboardAndMouse::EnableWindow;
const SS_LEFT: u32 = 0;
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::UI::Shell::*;
use windows_sys::Win32::UI::WindowsAndMessaging::*;

const WM_TRAYICON: u32 = WM_USER + 1;
const ID_BTN_SCAN: isize = 101;
const ID_BTN_CLEAN: isize = 102;
const ID_BTN_RECYCLE: isize = 103;
const ID_TRAY_OPEN: usize = 201;
const ID_TRAY_CLEAN: usize = 202;
const ID_TRAY_EXIT: usize = 203;

static mut H_LABEL_STATUS: HWND = null_mut();
static mut H_LABEL_STATS: HWND = null_mut();
static mut H_BTN_CLEAN: HWND = null_mut();
static mut TOTAL_BYTES: u64 = 0;
static mut TOTAL_FILES: usize = 0;

fn get_temp_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Ok(temp) = std::env::var("TEMP") {
        dirs.push(PathBuf::from(temp));
    }
    if let Ok(local) = std::env::var("LOCALAPPDATA") {
        let p = PathBuf::from(local).join("Temp");
        if !dirs.contains(&p) {
            dirs.push(p);
        }
    }
    dirs
}

fn scan_temp() -> (usize, u64) {
    let mut count = 0;
    let mut bytes = 0;
    for dir in get_temp_dirs() {
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                if let Ok(meta) = entry.metadata() {
                    count += 1;
                    bytes += meta.len();
                }
            }
        }
    }
    (count, bytes)
}

fn clean_temp() -> (usize, u64) {
    let mut cleaned_count = 0;
    let mut cleaned_bytes = 0;
    for dir in get_temp_dirs() {
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if let Ok(meta) = entry.metadata() {
                    let size = meta.len();
                    if meta.is_file() {
                        if fs::remove_file(&path).is_ok() {
                            cleaned_count += 1;
                            cleaned_bytes += size;
                        }
                    } else if meta.is_dir() {
                        if fs::remove_dir_all(&path).is_ok() {
                            cleaned_count += 1;
                            cleaned_bytes += size;
                        }
                    }
                }
            }
        }
    }
    (cleaned_count, cleaned_bytes)
}

fn to_wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_CREATE => {
            let title_text = to_wide("Temizale - Windows Disk & Sistem Temizleyici v1.0.0");
            let desc_text = to_wide("Windows geçici klasörleri (%TEMP%), uygulama önbellekleri ve çöp kutusunu temizler.");
            let stats_init = to_wide("Tarama bekleniyor... 'Taramayı Başlat' düğmesine tıklayın.");
            let btn_scan_text = to_wide("🔍 Taramayı Başlat");
            let btn_clean_text = to_wide("🧹 Şimdi Temizle");
            let btn_recycle_text = to_wide("🗑️ Çöp Kutusunu Boşalt");
            let static_class = to_wide("STATIC");
            let button_class = to_wide("BUTTON");

            CreateWindowExW(
                0, static_class.as_ptr(), title_text.as_ptr(),
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                20, 20, 480, 25, hwnd, null_mut(), GetModuleHandleW(null_mut()), null_mut()
            );

            CreateWindowExW(
                0, static_class.as_ptr(), desc_text.as_ptr(),
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                20, 50, 480, 40, hwnd, null_mut(), GetModuleHandleW(null_mut()), null_mut()
            );

            H_LABEL_STATS = CreateWindowExW(
                0, static_class.as_ptr(), stats_init.as_ptr(),
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                20, 105, 480, 45, hwnd, null_mut(), GetModuleHandleW(null_mut()), null_mut()
            );

            CreateWindowExW(
                0, button_class.as_ptr(), btn_scan_text.as_ptr(),
                WS_CHILD | WS_VISIBLE | (BS_PUSHBUTTON as u32),
                20, 170, 140, 36, hwnd, ID_BTN_SCAN as HMENU, GetModuleHandleW(null_mut()), null_mut()
            );

            H_BTN_CLEAN = CreateWindowExW(
                0, button_class.as_ptr(), btn_clean_text.as_ptr(),
                WS_CHILD | WS_VISIBLE | (BS_PUSHBUTTON as u32) | WS_DISABLED,
                170, 170, 140, 36, hwnd, ID_BTN_CLEAN as HMENU, GetModuleHandleW(null_mut()), null_mut()
            );

            CreateWindowExW(
                0, button_class.as_ptr(), btn_recycle_text.as_ptr(),
                WS_CHILD | WS_VISIBLE | (BS_PUSHBUTTON as u32),
                320, 170, 170, 36, hwnd, ID_BTN_RECYCLE as HMENU, GetModuleHandleW(null_mut()), null_mut()
            );

            let note_text = to_wide("Not: Kilitli dosyalar ve sistem korumalı öğeler güvenli biçimde atlanır.");
            H_LABEL_STATUS = CreateWindowExW(
                0, static_class.as_ptr(), note_text.as_ptr(),
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                20, 225, 480, 25, hwnd, null_mut(), GetModuleHandleW(null_mut()), null_mut()
            );

            0
        }
        WM_COMMAND => {
            let id = LOWORD(wparam as u32) as isize;
            match id {
                ID_BTN_SCAN => {
                    let (files, bytes) = scan_temp();
                    TOTAL_FILES = files;
                    TOTAL_BYTES = bytes;
                    let mb = bytes as f64 / (1024.0 * 1024.0);
                    let info = format!("✅ Tarama tamamlandı: {} geçici dosya bulundu ({:.2} MB temizlenebilir).", files, mb);
                    let info_w = to_wide(&info);
                    SetWindowTextW(H_LABEL_STATS, info_w.as_ptr());
                    EnableWindow(H_BTN_CLEAN, 1);
                }
                ID_BTN_CLEAN => {
                    let (files, bytes) = clean_temp();
                    let mb = bytes as f64 / (1024.0 * 1024.0);
                    let info = format!("✨ Temizlik tamamlandı! {} dosya silindi ({:.2} MB alan kazanıldı).", files, mb);
                    let info_w = to_wide(&info);
                    SetWindowTextW(H_LABEL_STATS, info_w.as_ptr());
                    EnableWindow(H_BTN_CLEAN, 0);
                    let msg_box_text = to_wide(&format!("Temizleme işlemi başarıyla tamamlandı.\nKazanılan Alan: {:.2} MB\nSilinen Dosya: {}", mb, files));
                    let msg_box_title = to_wide("Temizale for Windows");
                    MessageBoxW(hwnd, msg_box_text.as_ptr(), msg_box_title.as_ptr(), MB_OK | MB_ICONINFORMATION);
                }
                ID_BTN_RECYCLE => {
                    SHEmptyRecycleBinW(hwnd, null_mut(), SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI);
                    let info_w = to_wide("🗑️ Windows Geri Dönüşüm Kutusu başarıyla boşaltıldı.");
                    SetWindowTextW(H_LABEL_STATUS, info_w.as_ptr());
                }
                _ => {}
            }
            0
        }
        WM_TRAYICON => {
            if lparam as u32 == WM_LBUTTONUP {
                ShowWindow(hwnd, SW_RESTORE);
                SetForegroundWindow(hwnd);
            } else if lparam as u32 == WM_RBUTTONUP {
                let mut pt = POINT { x: 0, y: 0 };
                GetCursorPos(&mut pt);
                let hmenu = CreatePopupMenu();
                let m_open = to_wide("Temizale Penceresini Aç");
                let m_clean = to_wide("Hızlı Temizlik Yap");
                let m_exit = to_wide("Çıkış");
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_OPEN, m_open.as_ptr());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_CLEAN, m_clean.as_ptr());
                AppendMenuW(hmenu, MF_SEPARATOR, 0, null_mut());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_EXIT, m_exit.as_ptr());

                SetForegroundWindow(hwnd);
                let sel = TrackPopupMenu(hmenu, TPM_RETURNCMD | TPM_NONOTIFY, pt.x, pt.y, 0, hwnd, null_mut());
                DestroyMenu(hmenu);

                match sel as usize {
                    ID_TRAY_OPEN => {
                        ShowWindow(hwnd, SW_RESTORE);
                        SetForegroundWindow(hwnd);
                    }
                    ID_TRAY_CLEAN => {
                        let (files, bytes) = clean_temp();
                        let mb = bytes as f64 / (1024.0 * 1024.0);
                        let tip = to_wide(&format!("Temizlik bitti: {:.1} MB kazanıldı.", mb));
                        let title = to_wide("Temizale");
                        MessageBoxW(hwnd, tip.as_ptr(), title.as_ptr(), MB_OK | MB_ICONINFORMATION);
                    }
                    ID_TRAY_EXIT => {
                        DestroyWindow(hwnd);
                    }
                    _ => {}
                }
            }
            0
        }
        WM_CLOSE => {
            ShowWindow(hwnd, SW_HIDE);
            0
        }
        WM_DESTROY => {
            PostQuitMessage(0);
            0
        }
        _ => DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

fn LOWORD(l: u32) -> u16 {
    (l & 0xffff) as u16
}

fn main() {
    unsafe {
        let hinstance = GetModuleHandleW(null_mut());
        let class_name = to_wide("TemizaleWindowClass");
        let wnd_title = to_wide("Temizale for Windows - Disk ve Sistem Temizleyici");

        let icon = LoadIconW(hinstance, 1 as _);
        let h_icon = if icon.is_null() {
            LoadIconW(null_mut(), IDI_APPLICATION)
        } else {
            icon
        };

        let mut wc: WNDCLASSEXW = std::mem::zeroed();
        wc.cbSize = std::mem::size_of::<WNDCLASSEXW>() as u32;
        wc.style = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc = Some(wnd_proc);
        wc.hInstance = hinstance;
        wc.hIcon = h_icon;
        wc.hCursor = LoadCursorW(null_mut(), IDC_ARROW);
        wc.hbrBackground = (COLOR_WINDOW + 1) as HBRUSH;
        wc.lpszClassName = class_name.as_ptr();

        RegisterClassExW(&wc);

        let hwnd = CreateWindowExW(
            0,
            class_name.as_ptr(),
            wnd_title.as_ptr(),
            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
            CW_USEDEFAULT, CW_USEDEFAULT, 530, 300,
            null_mut(), null_mut(), hinstance, null_mut()
        );

        let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
        nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = 1;
        nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        nid.uCallbackMessage = WM_TRAYICON;
        nid.hIcon = h_icon;
        let tip = to_wide("Temizale for Windows - Disk Temizleyici");
        for (i, c) in tip.iter().take(127).enumerate() {
            nid.szTip[i] = *c;
        }
        Shell_NotifyIconW(NIM_ADD, &nid);

        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);

        let mut msg: MSG = std::mem::zeroed();
        while GetMessageW(&mut msg, null_mut(), 0, 0) > 0 {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        Shell_NotifyIconW(NIM_DELETE, &nid);
    }
}
