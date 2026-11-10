#![windows_subsystem = "windows"]

use std::fs;
use std::path::PathBuf;
use std::ptr::null_mut;
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::Graphics::Gdi::*;
const SS_LEFT: u32 = 0;
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::UI::Input::KeyboardAndMouse::*;
use windows_sys::Win32::UI::Shell::*;
use windows_sys::Win32::UI::WindowsAndMessaging::*;

const WM_TRAYICON: u32 = WM_USER + 1;
const ID_BTN_CREATE: isize = 601;
const ID_HOTKEY_NEWFILE: i32 = 602;
const ID_TRAY_OPEN: usize = 611;
const ID_TRAY_ABOUT: usize = 612;
const ID_TRAY_EXIT: usize = 613;

static mut H_EDIT_NAME: HWND = null_mut();
static mut H_COMBO_TYPE: HWND = null_mut();
static mut H_LABEL_MSG: HWND = null_mut();

fn to_wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn get_desktop_dir() -> PathBuf {
    if let Ok(p) = std::env::var("USERPROFILE") {
        let desk = PathBuf::from(p).join("Desktop");
        if desk.exists() {
            return desk;
        }
    }
    PathBuf::from(".")
}

fn create_file_from_template(name: &str, ext_idx: usize) -> Result<PathBuf, String> {
    let extensions = [
        ("txt", "Yeni Metin Belgesi.txt", ""),
        ("md", "# Başlık\n\nBu dosya YeniDosyale ile oluşturuldu.\n", "# Başlık\n\n"),
        ("py", "#!/usr/bin/env python3\n\ndef main():\n    print(\"Merhaba Dünya!\")\n\nif __name__ == \"__main__\":\n    main()\n", ""),
        ("json", "{\n  \"name\": \"yenidosyale\",\n  \"version\": \"1.0.0\"\n}\n", ""),
        ("html", "<!DOCTYPE html>\n<html lang=\"tr\">\n<head>\n    <meta charset=\"UTF-8\">\n    <title>Yeni Belge</title>\n</head>\n<body>\n    <h1>Merhaba!</h1>\n</body>\n</html>\n", ""),
        ("csv", "Id,Ad,Tarih,Durum\n1,Örnek,2026-11-10,Aktif\n", ""),
    ];

    let safe_idx = ext_idx.min(extensions.len() - 1);
    let (ext, default_content, _) = extensions[safe_idx];
    let clean_name = if name.trim().is_empty() { "Yeni_Belge" } else { name.trim() };
    let full_filename = if clean_name.ends_with(&format!(".{}", ext)) {
        clean_name.to_string()
    } else {
        format!("{}.{}", clean_name, ext)
    };

    let target_path = get_desktop_dir().join(&full_filename);
    fs::write(&target_path, default_content).map_err(|e| e.to_string())?;
    Ok(target_path)
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_CREATE => {
            let static_class = to_wide("STATIC");
            let button_class = to_wide("BUTTON");
            let edit_class = to_wide("EDIT");
            let combo_class = to_wide("COMBOBOX");

            let title_text = to_wide("⚡ YeniDosyale - Hızlı Dosya & Şablon Oluşturucu");
            CreateWindowExW(
                0, static_class.as_ptr(), title_text.as_ptr(),
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                20, 15, 380, 20, hwnd, null_mut(), GetModuleHandleW(null_mut()), null_mut()
            );

            let lbl_name = to_wide("Dosya Adı:");
            CreateWindowExW(
                0, static_class.as_ptr(), lbl_name.as_ptr(),
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                20, 48, 80, 20, hwnd, null_mut(), GetModuleHandleW(null_mut()), null_mut()
            );

            let default_name = to_wide("Yeni_Not");
            H_EDIT_NAME = CreateWindowExW(
                WS_EX_CLIENTEDGE, edit_class.as_ptr(), default_name.as_ptr(),
                WS_CHILD | WS_VISIBLE | (ES_AUTOHSCROLL as u32),
                105, 45, 280, 24, hwnd, null_mut(), GetModuleHandleW(null_mut()), null_mut()
            );

            let lbl_type = to_wide("Şablon Türü:");
            CreateWindowExW(
                0, static_class.as_ptr(), lbl_type.as_ptr(),
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                20, 85, 80, 20, hwnd, null_mut(), GetModuleHandleW(null_mut()), null_mut()
            );

            H_COMBO_TYPE = CreateWindowExW(
                0, combo_class.as_ptr(), null_mut(),
                WS_CHILD | WS_VISIBLE | (CBS_DROPDOWNLIST as u32) | WS_VSCROLL,
                105, 82, 280, 160, hwnd, null_mut(), GetModuleHandleW(null_mut()), null_mut()
            );

            let types = [
                "Metin Belgesi (.txt)",
                "Markdown Notu (.md)",
                "Python Script (.py)",
                "JSON Veri Dosyası (.json)",
                "HTML Web Sayfası (.html)",
                "CSV Tablo Dosyası (.csv)",
            ];
            for t in types {
                let tw = to_wide(t);
                SendMessageW(H_COMBO_TYPE, CB_ADDSTRING, 0, tw.as_ptr() as LPARAM);
            }
            SendMessageW(H_COMBO_TYPE, CB_SETCURSEL, 0, 0);

            let btn_txt = to_wide("🚀 Masaüstünde Oluştur ve Aç");
            CreateWindowExW(
                0, button_class.as_ptr(), btn_txt.as_ptr(),
                WS_CHILD | WS_VISIBLE | (BS_PUSHBUTTON as u32),
                105, 125, 280, 36, hwnd, ID_BTN_CREATE as HMENU, GetModuleHandleW(null_mut()), null_mut()
            );

            let info_txt = to_wide("Kısayol: Win + Shift + N ile her an hızlıca açabilirsiniz.");
            H_LABEL_MSG = CreateWindowExW(
                0, static_class.as_ptr(), info_txt.as_ptr(),
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                20, 175, 380, 20, hwnd, null_mut(), GetModuleHandleW(null_mut()), null_mut()
            );

            0
        }
        WM_HOTKEY => {
            if wparam as i32 == ID_HOTKEY_NEWFILE {
                ShowWindow(hwnd, SW_RESTORE);
                SetForegroundWindow(hwnd);
            }
            0
        }
        WM_COMMAND => {
            let id = (wparam & 0xffff) as isize;
            if id == ID_BTN_CREATE {
                let mut buf = [0u16; 256];
                let len = GetWindowTextW(H_EDIT_NAME, buf.as_mut_ptr(), buf.len() as i32);
                let name = String::from_utf16_lossy(&buf[..len as usize]);
                let sel_type = SendMessageW(H_COMBO_TYPE, CB_GETCURSEL, 0, 0) as usize;

                match create_file_from_template(&name, sel_type) {
                    Ok(path) => {
                        let path_w = to_wide(&path.to_string_lossy());
                        let op_open = to_wide("open");
                        ShellExecuteW(hwnd, op_open.as_ptr(), path_w.as_ptr(), null_mut(), null_mut(), SW_SHOW);
                        let ok_msg = to_wide(&format!("✅ Oluşturuldu: {}", path.file_name().unwrap_or_default().to_string_lossy()));
                        SetWindowTextW(H_LABEL_MSG, ok_msg.as_ptr());
                    }
                    Err(e) => {
                        let err_msg = to_wide(&format!("Hata: {}", e));
                        SetWindowTextW(H_LABEL_MSG, err_msg.as_ptr());
                    }
                }
            }
            0
        }
        WM_TRAYICON => {
            if lparam as u32 == WM_RBUTTONUP || lparam as u32 == WM_LBUTTONUP {
                let mut pt = POINT { x: 0, y: 0 };
                GetCursorPos(&mut pt);
                let hmenu = CreatePopupMenu();
                let m_open = to_wide("⚡ Yeni Dosya Oluştur");
                let m_about = to_wide("ℹ️ YeniDosyale Hakkında");
                let m_exit = to_wide("❌ Çıkış");
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_OPEN, m_open.as_ptr());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_ABOUT, m_about.as_ptr());
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
                    ID_TRAY_ABOUT => {
                        let text = to_wide(
                            "YeniDosyale for Windows v1.0.0\n\
                            Hızlı Dosya ve Şablon Oluşturucu.\n\n\
                            Geliştirici: Mehmet Akif Çifçi | SoftAI Yazılım\n\
                            Kısayol: Win + Shift + N"
                        );
                        let title = to_wide("YeniDosyale Hakkında");
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

fn main() {
    unsafe {
        let hinstance = GetModuleHandleW(null_mut());
        let class_name = to_wide("YeniDosyaleWindowClass");
        let wnd_title = to_wide("YeniDosyale for Windows - Hızlı Dosya Oluşturucu");

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
        wc.hCursor = LoadCursorW(null_mut(), IDC_ARROW);
        wc.hbrBackground = (COLOR_WINDOW + 1) as HBRUSH;
        wc.lpszClassName = class_name.as_ptr();

        RegisterClassExW(&wc);

        let hwnd = CreateWindowExW(
            WS_EX_TOPMOST,
            class_name.as_ptr(),
            wnd_title.as_ptr(),
            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
            CW_USEDEFAULT, CW_USEDEFAULT, 430, 245,
            null_mut(), null_mut(), hinstance, null_mut()
        );

        RegisterHotKey(hwnd, ID_HOTKEY_NEWFILE, MOD_WIN | MOD_SHIFT, 0x4E); // 'N'

        let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
        nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = 1;
        nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        nid.uCallbackMessage = WM_TRAYICON;
        nid.hIcon = h_icon;
        let tip = to_wide("YeniDosyale for Windows (Win+Shift+N)");
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

        UnregisterHotKey(hwnd, ID_HOTKEY_NEWFILE);
        Shell_NotifyIconW(NIM_DELETE, &nid);
    }
}
