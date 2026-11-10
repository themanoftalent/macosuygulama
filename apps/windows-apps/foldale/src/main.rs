#![windows_subsystem = "windows"]

use std::ptr::null_mut;
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::System::DataExchange::*;
use windows_sys::Win32::System::Memory::*;
use windows_sys::Win32::Graphics::Gdi::*;const SS_LEFT: u32 = 0;
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::UI::Shell::*;
use windows_sys::Win32::UI::WindowsAndMessaging::*;

const WM_TRAYICON: u32 = WM_USER + 1;
const ID_BTN_CLEAR: isize = 501;
const ID_BTN_COPY_PATHS: isize = 502;
const ID_TRAY_TOGGLE: usize = 511;
const ID_TRAY_ABOUT: usize = 512;
const ID_TRAY_EXIT: usize = 513;

static mut H_LISTBOX: HWND = null_mut();
static mut H_STATUS: HWND = null_mut();
static mut DROPPED_PATHS: Vec<String> = Vec::new();

fn to_wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_CREATE => {
            DragAcceptFiles(hwnd, 1);
            let static_class = to_wide("STATIC");
            let button_class = to_wide("BUTTON");
            let list_class = to_wide("LISTBOX");

            let title_text = to_wide("📂 Foldale - Yüzen Dosya Tutucu & Taşıma Rafı");
            CreateWindowExW(
                0, static_class.as_ptr(), title_text.as_ptr(),
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                15, 12, 380, 20, hwnd, null_mut(), GetModuleHandleW(null_mut()), null_mut()
            );

            let sub_text = to_wide("Dosyaları veya klasörleri bu pencereye sürükleyip bırakın (Drag & Drop):");
            CreateWindowExW(
                0, static_class.as_ptr(), sub_text.as_ptr(),
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                15, 34, 380, 18, hwnd, null_mut(), GetModuleHandleW(null_mut()), null_mut()
            );

            H_LISTBOX = CreateWindowExW(
                WS_EX_CLIENTEDGE, list_class.as_ptr(), null_mut(),
                WS_CHILD | WS_VISIBLE | WS_VSCROLL | ((LBS_NOTIFY as u32) as u32) | (LBS_HASSTRINGS as u32),
                15, 58, 380, 180, hwnd, null_mut(), GetModuleHandleW(null_mut()), null_mut()
            );

            let btn_clear_txt = to_wide("🧹 Rafı Temizle");
            CreateWindowExW(
                0, button_class.as_ptr(), btn_clear_txt.as_ptr(),
                WS_CHILD | WS_VISIBLE | (BS_PUSHBUTTON as u32),
                15, 248, 120, 32, hwnd, ID_BTN_CLEAR as HMENU, GetModuleHandleW(null_mut()), null_mut()
            );

            let btn_copy_txt = to_wide("📋 Dosya Yollarını Kopyala");
            CreateWindowExW(
                0, button_class.as_ptr(), btn_copy_txt.as_ptr(),
                WS_CHILD | WS_VISIBLE | (BS_PUSHBUTTON as u32),
                145, 248, 180, 32, hwnd, ID_BTN_COPY_PATHS as HMENU, GetModuleHandleW(null_mut()), null_mut()
            );

            let init_status = to_wide("Raf boş. Dosya bekleniyor...");
            H_STATUS = CreateWindowExW(
                0, static_class.as_ptr(), init_status.as_ptr(),
                WS_CHILD | WS_VISIBLE | SS_LEFT,
                15, 290, 380, 20, hwnd, null_mut(), GetModuleHandleW(null_mut()), null_mut()
            );

            0
        }
        WM_DROPFILES => {
            let hdrop = wparam as HDROP;
            let count = DragQueryFileW(hdrop, 0xFFFFFFFF, null_mut(), 0);
            for i in 0..count {
                let mut buf = [0u16; 512];
                let len = DragQueryFileW(hdrop, i, buf.as_mut_ptr(), buf.len() as u32);
                if len > 0 {
                    let path = String::from_utf16_lossy(&buf[..len as usize]);
                    SendMessageW(H_LISTBOX, LB_ADDSTRING, 0, buf.as_ptr() as LPARAM);
                    DROPPED_PATHS.push(path);
                }
            }
            DragFinish(hdrop);

            let status_msg = format!("Toplam {} dosya rafta bekletiliyor.", DROPPED_PATHS.len());
            let status_w = to_wide(&status_msg);
            SetWindowTextW(H_STATUS, status_w.as_ptr());
            0
        }
        WM_COMMAND => {
            let id = (wparam & 0xffff) as isize;
            match id {
                ID_BTN_CLEAR => {
                    SendMessageW(H_LISTBOX, LB_RESETCONTENT, 0, 0);
                    DROPPED_PATHS.clear();
                    let status_w = to_wide("Raf temizlendi. Yeni dosyaları sürükleyin.");
                    SetWindowTextW(H_STATUS, status_w.as_ptr());
                }
                ID_BTN_COPY_PATHS => {
                    if !DROPPED_PATHS.is_empty() {
                        let text = DROPPED_PATHS.join("\r\n");
                        let text_w = to_wide(&text);
                        if OpenClipboard(hwnd) != 0 {
                            EmptyClipboard();
                            let hmem = GlobalAlloc(GMEM_MOVEABLE, text_w.len() * 2);
                            if !hmem.is_null() {
                                let ptr = GlobalLock(hmem) as *mut u16;
                                std::ptr::copy_nonoverlapping(text_w.as_ptr(), ptr, text_w.len());
                                GlobalUnlock(hmem);
                                SetClipboardData(13u32, hmem as _);
                            }
                            CloseClipboard();
                            let info_w = to_wide("✅ Tüm dosya yolları panoya kopyalandı!");
                            SetWindowTextW(H_STATUS, info_w.as_ptr());
                        }
                    }
                }
                _ => {}
            }
            0
        }
        WM_TRAYICON => {
            if lparam as u32 == WM_RBUTTONUP || lparam as u32 == WM_LBUTTONUP {
                let mut pt = POINT { x: 0, y: 0 };
                GetCursorPos(&mut pt);
                let hmenu = CreatePopupMenu();
                let m_toggle = to_wide("📂 Foldale Rafını Göster / Gizle");
                let m_about = to_wide("ℹ️ Foldale Hakkında");
                let m_exit = to_wide("❌ Çıkış");
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_TOGGLE, m_toggle.as_ptr());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_ABOUT, m_about.as_ptr());
                AppendMenuW(hmenu, MF_SEPARATOR, 0, null_mut());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_EXIT, m_exit.as_ptr());

                SetForegroundWindow(hwnd);
                let sel = TrackPopupMenu(hmenu, TPM_RETURNCMD | TPM_NONOTIFY, pt.x, pt.y, 0, hwnd, null_mut());
                DestroyMenu(hmenu);

                match sel as usize {
                    ID_TRAY_TOGGLE => {
                        if IsWindowVisible(hwnd) != 0 {
                            ShowWindow(hwnd, SW_HIDE);
                        } else {
                            ShowWindow(hwnd, SW_RESTORE);
                            SetForegroundWindow(hwnd);
                        }
                    }
                    ID_TRAY_ABOUT => {
                        let text = to_wide(
                            "Foldale for Windows v1.0.0\n\
                            Yüzen Geçici Dosya Tutucu & Taşıma Rafı.\n\n\
                            Geliştirici: Mehmet Akif Çifçi | SoftAI Yazılım\n\
                            Windows 10 & 11 için ultra hafif Drag-and-Drop çalışma rafı."
                        );
                        let title = to_wide("Foldale Hakkında");
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
        let class_name = to_wide("FoldaleWindowClass");
        let wnd_title = to_wide("Foldale for Windows - Dosya Taşıma Rafı");

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
            WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
            class_name.as_ptr(),
            wnd_title.as_ptr(),
            WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
            100, 100, 425, 360,
            null_mut(), null_mut(), hinstance, null_mut()
        );

        let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
        nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = 1;
        nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        nid.uCallbackMessage = WM_TRAYICON;
        nid.hIcon = h_icon;
        let tip = to_wide("Foldale for Windows - Yüzen Dosya Rafı");
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
