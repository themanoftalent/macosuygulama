#![windows_subsystem = "windows"]

use std::ptr::null_mut;
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::Graphics::Gdi::*;
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::System::Memory::*;
use windows_sys::Win32::System::SystemInformation::*;
use windows_sys::Win32::System::Threading::GetSystemTimes;
use windows_sys::Win32::UI::Shell::*;
use windows_sys::Win32::UI::WindowsAndMessaging::*;

const WM_TRAYICON: u32 = WM_USER + 1;
const ID_TIMER_POLL: usize = 1;
const ID_BTN_TASKMGR: isize = 901;
const ID_TRAY_OPEN: usize = 911;
const ID_TRAY_TASKMGR: usize = 912;
const ID_TRAY_ABOUT: usize = 913;
const ID_TRAY_EXIT: usize = 914;

static mut PREV_IDLE: u64 = 0;
static mut PREV_KERNEL: u64 = 0;
static mut PREV_USER: u64 = 0;
static mut CPU_PERCENT: u32 = 0;
static mut RAM_PERCENT: u32 = 0;
static mut RAM_USED_GB: f64 = 0.0;
static mut RAM_TOTAL_GB: f64 = 0.0;

fn to_wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

unsafe fn filetime_to_u64(ft: &FILETIME) -> u64 {
    ((ft.dwHighDateTime as u64) << 32) | (ft.dwLowDateTime as u64)
}

unsafe fn update_stats() {
    let mut idle: FILETIME = std::mem::zeroed();
    let mut kernel: FILETIME = std::mem::zeroed();
    let mut user: FILETIME = std::mem::zeroed();

    if GetSystemTimes(&mut idle, &mut kernel, &mut user) != 0 {
        let cur_idle = filetime_to_u64(&idle);
        let cur_kernel = filetime_to_u64(&kernel);
        let cur_user = filetime_to_u64(&user);

        let diff_idle = cur_idle.saturating_sub(PREV_IDLE);
        let diff_kernel = cur_kernel.saturating_sub(PREV_KERNEL);
        let diff_user = cur_user.saturating_sub(PREV_USER);

        let total_sys = diff_kernel + diff_user;
        if total_sys > 0 {
            let usage = ((total_sys - diff_idle.min(total_sys)) * 100) / total_sys;
            CPU_PERCENT = usage as u32;
        }

        PREV_IDLE = cur_idle;
        PREV_KERNEL = cur_kernel;
        PREV_USER = cur_user;
    }

    let mut mem: MEMORYSTATUSEX = std::mem::zeroed();
    mem.dwLength = std::mem::size_of::<MEMORYSTATUSEX>() as u32;
    if GlobalMemoryStatusEx(&mut mem) != 0 {
        RAM_PERCENT = mem.dwMemoryLoad;
        let total = mem.ullTotalPhys as f64 / (1024.0 * 1024.0 * 1024.0);
        let avail = mem.ullAvailPhys as f64 / (1024.0 * 1024.0 * 1024.0);
        RAM_TOTAL_GB = total;
        RAM_USED_GB = (total - avail).max(0.0);
    }
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_CREATE => {
            update_stats();
            SetTimer(hwnd, ID_TIMER_POLL, 1000, None);

            let button_class = to_wide("BUTTON");
            let btn_txt = to_wide("⚙️ Windows Görev Yöneticisi'ni Aç");
            CreateWindowExW(
                0, button_class.as_ptr(), btn_txt.as_ptr(),
                WS_CHILD | WS_VISIBLE | (BS_PUSHBUTTON as u32),
                25, 175, 300, 36, hwnd, ID_BTN_TASKMGR as HMENU, GetModuleHandleW(null_mut()), null_mut()
            );
            0
        }
        WM_TIMER => {
            if wparam == ID_TIMER_POLL {
                update_stats();

                // Update tray tooltip
                let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
                nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
                nid.hWnd = hwnd;
                nid.uID = 1;
                nid.uFlags = NIF_TIP;
                let tip = to_wide(&format!("AleBar: CPU %{} | RAM %{} ({:.1}/{:.1} GB)", CPU_PERCENT, RAM_PERCENT, RAM_USED_GB, RAM_TOTAL_GB));
                for (i, c) in tip.iter().take(127).enumerate() {
                    nid.szTip[i] = *c;
                }
                Shell_NotifyIconW(NIM_MODIFY, &nid);

                if IsWindowVisible(hwnd) != 0 {
                    let mut rc: RECT = RECT { left: 20, top: 40, right: 330, bottom: 160 };
                    InvalidateRect(hwnd, &rc, 1);
                }
            }
            0
        }
        WM_COMMAND => {
            let id = (wparam & 0xffff) as isize;
            if id == ID_BTN_TASKMGR {
                let op = to_wide("open");
                let target = to_wide("taskmgr.exe");
                ShellExecuteW(hwnd, op.as_ptr(), target.as_ptr(), null_mut(), null_mut(), SW_SHOW);
            }
            0
        }
        WM_PAINT => {
            let mut ps: PAINTSTRUCT = std::mem::zeroed();
            let hdc = BeginPaint(hwnd, &mut ps);

            SetTextColor(hdc, 0x00101010);

            let title = to_wide("⚡ AleBar - Sistem & Donanım Monitörü");
            TextOutW(hdc, 25, 15, title.as_ptr(), (title.len() - 1) as i32);

            // CPU Gauge
            let cpu_str = format!("İşlemci (CPU): %{}", CPU_PERCENT);
            let cpu_w = to_wide(&cpu_str);
            TextOutW(hdc, 25, 48, cpu_w.as_ptr(), (cpu_w.len() - 1) as i32);

            // CPU Bar
            let bar_w = 300;
            let bar_h = 16;
            let cpu_fill = (bar_w * (CPU_PERCENT.min(100) as i32)) / 100;
            let hbrush_bg = GetStockObject(LTGRAY_BRUSH) as HBRUSH;
            let mut rc_cpu_bg = RECT { left: 25, top: 72, right: 25 + bar_w, bottom: 72 + bar_h };
            FillRect(hdc, &rc_cpu_bg, hbrush_bg);
            let hbrush_cpu = CreateSolidBrush(if CPU_PERCENT > 80 { 0x002222D0 } else { 0x00D06020 });
            let mut rc_cpu_fill = RECT { left: 25, top: 72, right: 25 + cpu_fill, bottom: 72 + bar_h };
            FillRect(hdc, &rc_cpu_fill, hbrush_cpu);
            DeleteObject(hbrush_cpu as _);

            // RAM Gauge
            let ram_str = format!("Bellek (RAM): %{} ({:.1} GB / {:.1} GB)", RAM_PERCENT, RAM_USED_GB, RAM_TOTAL_GB);
            let ram_w = to_wide(&ram_str);
            TextOutW(hdc, 25, 105, ram_w.as_ptr(), (ram_w.len() - 1) as i32);

            // RAM Bar
            let ram_fill = (bar_w * (RAM_PERCENT.min(100) as i32)) / 100;
            let mut rc_ram_bg = RECT { left: 25, top: 129, right: 25 + bar_w, bottom: 129 + bar_h };
            FillRect(hdc, &rc_ram_bg, hbrush_bg);
            let hbrush_ram = CreateSolidBrush(if RAM_PERCENT > 85 { 0x002222D0 } else { 0x00208030 });
            let mut rc_ram_fill = RECT { left: 25, top: 129, right: 25 + ram_fill, bottom: 129 + bar_h };
            FillRect(hdc, &rc_ram_fill, hbrush_ram);
            DeleteObject(hbrush_ram as _);

            EndPaint(hwnd, &ps);
            0
        }
        WM_TRAYICON => {
            if lparam as u32 == WM_LBUTTONUP {
                if IsWindowVisible(hwnd) != 0 {
                    ShowWindow(hwnd, SW_HIDE);
                } else {
                    let mut work_area: RECT = std::mem::zeroed();
                    SystemParametersInfoW(SPI_GETWORKAREA, 0, &mut work_area as *mut RECT as *mut _, 0);
                    let win_w = 350;
                    let win_h = 240;
                    let x = work_area.right - win_w - 10;
                    let y = work_area.bottom - win_h - 10;
                    SetWindowPos(hwnd, HWND_TOPMOST, x, y, win_w, win_h, SWP_SHOWWINDOW);
                    SetForegroundWindow(hwnd);
                }
            } else if lparam as u32 == WM_RBUTTONUP {
                let mut pt = POINT { x: 0, y: 0 };
                GetCursorPos(&mut pt);
                let hmenu = CreatePopupMenu();
                let m_open = to_wide("📊 AleBar Performans Paneli");
                let m_taskmgr = to_wide("⚙️ Görev Yöneticisi");
                let m_about = to_wide("ℹ️ AleBar Hakkında");
                let m_exit = to_wide("❌ Çıkış");

                AppendMenuW(hmenu, MF_STRING, ID_TRAY_OPEN, m_open.as_ptr());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_TASKMGR, m_taskmgr.as_ptr());
                AppendMenuW(hmenu, MF_SEPARATOR, 0, null_mut());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_ABOUT, m_about.as_ptr());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_EXIT, m_exit.as_ptr());

                SetForegroundWindow(hwnd);
                let sel = TrackPopupMenu(hmenu, TPM_RETURNCMD | TPM_NONOTIFY, pt.x, pt.y, 0, hwnd, null_mut());
                DestroyMenu(hmenu);

                match sel as usize {
                    ID_TRAY_OPEN => {
                        ShowWindow(hwnd, SW_RESTORE);
                        SetForegroundWindow(hwnd);
                    }
                    ID_TRAY_TASKMGR => {
                        let op = to_wide("open");
                        let target = to_wide("taskmgr.exe");
                        ShellExecuteW(hwnd, op.as_ptr(), target.as_ptr(), null_mut(), null_mut(), SW_SHOW);
                    }
                    ID_TRAY_ABOUT => {
                        let text = to_wide(
                            "AleBar for Windows v1.0.0\n\
                            Görev Çubuğu Canlı Sistem & Donanım Monitörü.\n\n\
                            Geliştirici: Mehmet Akif Çifçi | SoftAI Yazılım\n\
                            Hafif, yerel ve sıfır telemetri."
                        );
                        let title = to_wide("AleBar Hakkında");
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
        let class_name = to_wide("AleBarWindowClass");
        let wnd_title = to_wide("AleBar for Windows - Sistem Monitörü");

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
            WS_POPUP | WS_BORDER,
            100, 100, 350, 240,
            null_mut(), null_mut(), hinstance, null_mut()
        );

        let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
        nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = 1;
        nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        nid.uCallbackMessage = WM_TRAYICON;
        nid.hIcon = h_icon;
        let tip = to_wide("AleBar - CPU & RAM Monitörü");
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
