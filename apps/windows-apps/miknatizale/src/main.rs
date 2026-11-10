#![windows_subsystem = "windows"]

use std::ptr::null_mut;
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::UI::Input::KeyboardAndMouse::*;
use windows_sys::Win32::UI::Shell::*;
use windows_sys::Win32::UI::WindowsAndMessaging::*;

const WM_TRAYICON: u32 = WM_USER + 1;
const ID_TRAY_SHORTCUTS: usize = 301;
const ID_TRAY_ABOUT: usize = 302;
const ID_TRAY_EXIT: usize = 303;

const HOTKEY_LEFT: i32 = 1;
const HOTKEY_RIGHT: i32 = 2;
const HOTKEY_MAX: i32 = 3;
const HOTKEY_RESTORE: i32 = 4;
const HOTKEY_CENTER: i32 = 5;
const HOTKEY_TOPLEFT: i32 = 6;
const HOTKEY_TOPRIGHT: i32 = 7;
const HOTKEY_BOTLEFT: i32 = 8;
const HOTKEY_BOTRIGHT: i32 = 9;

fn to_wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

unsafe fn snap_active_window(mode: i32) {
    let hwnd = GetForegroundWindow();
    if hwnd.is_null() {
        return;
    }

    let mut work_area: RECT = std::mem::zeroed();
    SystemParametersInfoW(
        SPI_GETWORKAREA,
        0,
        &mut work_area as *mut RECT as *mut _,
        0,
    );

    let screen_w = work_area.right - work_area.left;
    let screen_h = work_area.bottom - work_area.top;

    match mode {
        HOTKEY_LEFT => {
            ShowWindow(hwnd, SW_RESTORE);
            SetWindowPos(
                hwnd,
                null_mut(),
                work_area.left,
                work_area.top,
                screen_w / 2,
                screen_h,
                SWP_NOZORDER | SWP_NOACTIVATE,
            );
        }
        HOTKEY_RIGHT => {
            ShowWindow(hwnd, SW_RESTORE);
            SetWindowPos(
                hwnd,
                null_mut(),
                work_area.left + (screen_w / 2),
                work_area.top,
                screen_w / 2,
                screen_h,
                SWP_NOZORDER | SWP_NOACTIVATE,
            );
        }
        HOTKEY_MAX => {
            ShowWindow(hwnd, SW_MAXIMIZE);
        }
        HOTKEY_RESTORE => {
            ShowWindow(hwnd, SW_RESTORE);
        }
        HOTKEY_CENTER => {
            ShowWindow(hwnd, SW_RESTORE);
            let target_w = (screen_w * 7) / 10;
            let target_h = (screen_h * 8) / 10;
            let x = work_area.left + (screen_w - target_w) / 2;
            let y = work_area.top + (screen_h - target_h) / 2;
            SetWindowPos(
                hwnd,
                null_mut(),
                x,
                y,
                target_w,
                target_h,
                SWP_NOZORDER | SWP_NOACTIVATE,
            );
        }
        HOTKEY_TOPLEFT => {
            ShowWindow(hwnd, SW_RESTORE);
            SetWindowPos(
                hwnd,
                null_mut(),
                work_area.left,
                work_area.top,
                screen_w / 2,
                screen_h / 2,
                SWP_NOZORDER | SWP_NOACTIVATE,
            );
        }
        HOTKEY_TOPRIGHT => {
            ShowWindow(hwnd, SW_RESTORE);
            SetWindowPos(
                hwnd,
                null_mut(),
                work_area.left + (screen_w / 2),
                work_area.top,
                screen_w / 2,
                screen_h / 2,
                SWP_NOZORDER | SWP_NOACTIVATE,
            );
        }
        HOTKEY_BOTLEFT => {
            ShowWindow(hwnd, SW_RESTORE);
            SetWindowPos(
                hwnd,
                null_mut(),
                work_area.left,
                work_area.top + (screen_h / 2),
                screen_w / 2,
                screen_h / 2,
                SWP_NOZORDER | SWP_NOACTIVATE,
            );
        }
        HOTKEY_BOTRIGHT => {
            ShowWindow(hwnd, SW_RESTORE);
            SetWindowPos(
                hwnd,
                null_mut(),
                work_area.left + (screen_w / 2),
                work_area.top + (screen_h / 2),
                screen_w / 2,
                screen_h / 2,
                SWP_NOZORDER | SWP_NOACTIVATE,
            );
        }
        _ => {}
    }
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_HOTKEY => {
            snap_active_window(wparam as i32);
            0
        }
        WM_TRAYICON => {
            if lparam as u32 == WM_RBUTTONUP || lparam as u32 == WM_LBUTTONUP {
                let mut pt = POINT { x: 0, y: 0 };
                GetCursorPos(&mut pt);
                let hmenu = CreatePopupMenu();
                let m_shortcuts = to_wide("⌨️ Kısayol Listesi (Shortcuts)");
                let m_about = to_wide("ℹ️ Miknatizale Hakkında");
                let m_exit = to_wide("❌ Çıkış");
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_SHORTCUTS, m_shortcuts.as_ptr());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_ABOUT, m_about.as_ptr());
                AppendMenuW(hmenu, MF_SEPARATOR, 0, null_mut());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_EXIT, m_exit.as_ptr());

                SetForegroundWindow(hwnd);
                let sel = TrackPopupMenu(hmenu, TPM_RETURNCMD | TPM_NONOTIFY, pt.x, pt.y, 0, hwnd, null_mut());
                DestroyMenu(hmenu);

                match sel as usize {
                    ID_TRAY_SHORTCUTS => {
                        let text = to_wide(
                            "Miknatizale Kısayol Tuşları:\n\n\
                            • Win + Alt + Sol Ok: Sol Yarıya Hizala (Left Half)\n\
                            • Win + Alt + Sağ Ok: Sağ Yarıya Hizala (Right Half)\n\
                            • Win + Alt + Yukarı Ok: Ekranı Kapla (Maximize)\n\
                            • Win + Alt + Aşağı Ok: Önceki Boyut (Restore)\n\
                            • Win + Alt + C: Ekranın Ortasına Yerleştir (Center)\n\
                            • Win + Alt + 1/2/3/4: Ekranın 4 Köşesine Böl (Quarter Tiling)"
                        );
                        let title = to_wide("Miknatizale for Windows - Kısayollar");
                        MessageBoxW(hwnd, text.as_ptr(), title.as_ptr(), MB_OK | MB_ICONINFORMATION);
                    }
                    ID_TRAY_ABOUT => {
                        let text = to_wide(
                            "Miknatizale for Windows v1.0.0\n\
                            Ultra hafif, sıfır gecikmeli pencere hizalama yöneticisi.\n\n\
                            Geliştirici: Mehmet Akif Çifçi | SoftAI Yazılım\n\
                            Local-first, sıfır telemetri, standart kullanıcı yetkisi."
                        );
                        let title = to_wide("Miknatizale Hakkında");
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
        let class_name = to_wide("MiknatizaleWindowClass");

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

        let mod_keys = MOD_WIN | MOD_ALT;
        RegisterHotKey(hwnd, HOTKEY_LEFT, mod_keys, VK_LEFT as u32);
        RegisterHotKey(hwnd, HOTKEY_RIGHT, mod_keys, VK_RIGHT as u32);
        RegisterHotKey(hwnd, HOTKEY_MAX, mod_keys, VK_UP as u32);
        RegisterHotKey(hwnd, HOTKEY_RESTORE, mod_keys, VK_DOWN as u32);
        RegisterHotKey(hwnd, HOTKEY_CENTER, mod_keys, 0x43); // 'C'
        RegisterHotKey(hwnd, HOTKEY_TOPLEFT, mod_keys, 0x31); // '1'
        RegisterHotKey(hwnd, HOTKEY_TOPRIGHT, mod_keys, 0x32); // '2'
        RegisterHotKey(hwnd, HOTKEY_BOTLEFT, mod_keys, 0x33); // '3'
        RegisterHotKey(hwnd, HOTKEY_BOTRIGHT, mod_keys, 0x34); // '4'

        let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
        nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = 1;
        nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        nid.uCallbackMessage = WM_TRAYICON;
        nid.hIcon = h_icon;
        let tip = to_wide("Miknatizale for Windows - Pencere Hizalama");
        for (i, c) in tip.iter().take(127).enumerate() {
            nid.szTip[i] = *c;
        }
        Shell_NotifyIconW(NIM_ADD, &nid);

        let mut msg: MSG = std::mem::zeroed();
        while GetMessageW(&mut msg, null_mut(), 0, 0) > 0 {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        for id in 1..=9 {
            UnregisterHotKey(hwnd, id);
        }
        Shell_NotifyIconW(NIM_DELETE, &nid);
    }
}
