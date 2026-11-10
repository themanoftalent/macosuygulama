#![windows_subsystem = "windows"]

use std::ptr::null_mut;
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::Graphics::Gdi::*;
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::System::SystemInformation::GetLocalTime;
use windows_sys::Win32::Foundation::SYSTEMTIME;
use windows_sys::Win32::UI::Shell::*;
use windows_sys::Win32::UI::WindowsAndMessaging::*;

const WM_TRAYICON: u32 = WM_USER + 1;
const ID_TIMER_TICK: usize = 1;
const ID_BTN_PREV: isize = 801;
const ID_BTN_NEXT: isize = 802;
const ID_BTN_TODAY: isize = 803;

static mut CURRENT_YEAR: i32 = 2026;
static mut CURRENT_MONTH: i32 = 11;
static mut TODAY_DAY: i32 = 10;
static mut TODAY_MONTH: i32 = 11;
static mut TODAY_YEAR: i32 = 2026;

fn to_wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn days_in_month(year: i32, month: i32) -> i32 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0) {
                29
            } else {
                28
            }
        }
        _ => 30,
    }
}

// Zeller's congruence for day of week: 0 = Sunday, 1 = Monday, ...
fn day_of_week(year: i32, month: i32, day: i32) -> i32 {
    let mut y = year;
    let mut m = month;
    if m < 3 {
        m += 12;
        y -= 1;
    }
    let k = y % 100;
    let j = y / 100;
    let h = (day + (13 * (m + 1)) / 5 + k + k / 4 + j / 4 + 5 * j) % 7;
    // h: 0=Sat, 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri
    (h + 6) % 7 // Convert to 0 = Sunday, 1 = Monday ... 6 = Saturday
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_CREATE => {
            let mut st: SYSTEMTIME = std::mem::zeroed();
            GetLocalTime(&mut st);
            TODAY_YEAR = st.wYear as i32;
            TODAY_MONTH = st.wMonth as i32;
            TODAY_DAY = st.wDay as i32;
            CURRENT_YEAR = TODAY_YEAR;
            CURRENT_MONTH = TODAY_MONTH;

            let button_class = to_wide("BUTTON");
            let btn_prev_txt = to_wide("◀");
            let btn_next_txt = to_wide("▶");
            let btn_today_txt = to_wide("Bugün");

            CreateWindowExW(
                0, button_class.as_ptr(), btn_prev_txt.as_ptr(),
                WS_CHILD | WS_VISIBLE | (BS_PUSHBUTTON as u32),
                20, 75, 40, 26, hwnd, ID_BTN_PREV as HMENU, GetModuleHandleW(null_mut()), null_mut()
            );

            CreateWindowExW(
                0, button_class.as_ptr(), btn_today_txt.as_ptr(),
                WS_CHILD | WS_VISIBLE | (BS_PUSHBUTTON as u32),
                245, 75, 55, 26, hwnd, ID_BTN_TODAY as HMENU, GetModuleHandleW(null_mut()), null_mut()
            );

            CreateWindowExW(
                0, button_class.as_ptr(), btn_next_txt.as_ptr(),
                WS_CHILD | WS_VISIBLE | (BS_PUSHBUTTON as u32),
                305, 75, 40, 26, hwnd, ID_BTN_NEXT as HMENU, GetModuleHandleW(null_mut()), null_mut()
            );

            SetTimer(hwnd, ID_TIMER_TICK, 1000, None);
            0
        }
        WM_TIMER => {
            if wparam == ID_TIMER_TICK {
                let mut rc: RECT = RECT { left: 20, top: 15, right: 350, bottom: 65 };
                InvalidateRect(hwnd, &rc, 1);
            }
            0
        }
        WM_COMMAND => {
            let id = (wparam & 0xffff) as isize;
            match id {
                ID_BTN_PREV => {
                    CURRENT_MONTH -= 1;
                    if CURRENT_MONTH < 1 {
                        CURRENT_MONTH = 12;
                        CURRENT_YEAR -= 1;
                    }
                    InvalidateRect(hwnd, null_mut(), 1);
                }
                ID_BTN_NEXT => {
                    CURRENT_MONTH += 1;
                    if CURRENT_MONTH > 12 {
                        CURRENT_MONTH = 1;
                        CURRENT_YEAR += 1;
                    }
                    InvalidateRect(hwnd, null_mut(), 1);
                }
                ID_BTN_TODAY => {
                    CURRENT_YEAR = TODAY_YEAR;
                    CURRENT_MONTH = TODAY_MONTH;
                    InvalidateRect(hwnd, null_mut(), 1);
                }
                _ => {}
            }
            0
        }
        WM_PAINT => {
            let mut ps: PAINTSTRUCT = std::mem::zeroed();
            let hdc = BeginPaint(hwnd, &mut ps);

            let mut st: SYSTEMTIME = std::mem::zeroed();
            GetLocalTime(&mut st);

            let months_tr = [
                "Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
                "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"
            ];
            let month_name = months_tr[(CURRENT_MONTH - 1).clamp(0, 11) as usize];

            // Live Time
            let time_str = format!("{:02}:{:02}:{:02}", st.wHour, st.wMinute, st.wSecond);
            let time_w = to_wide(&time_str);
            SetTextColor(hdc, 0x00101010);
            TextOutW(hdc, 22, 18, time_w.as_ptr(), (time_w.len() - 1) as i32);

            // Live Date
            let date_str = format!("{} {} {}", st.wDay, months_tr[(st.wMonth - 1).clamp(0, 11) as usize], st.wYear);
            let date_w = to_wide(&date_str);
            TextOutW(hdc, 22, 40, date_w.as_ptr(), (date_w.len() - 1) as i32);

            // Month Header
            let header_str = format!("{} {}", month_name, CURRENT_YEAR);
            let header_w = to_wide(&header_str);
            TextOutW(hdc, 75, 80, header_w.as_ptr(), (header_w.len() - 1) as i32);

            // Weekday Columns: Pzt Sal Çar Per Cum Cmt Paz
            let days_header = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"];
            let start_x = 22;
            let start_y = 115;
            let col_w = 46;
            let row_h = 24;

            for (i, d) in days_header.iter().enumerate() {
                let dw = to_wide(d);
                if i >= 5 {
                    SetTextColor(hdc, 0x002222D0); // Weekend color
                } else {
                    SetTextColor(hdc, 0x00505050);
                }
                TextOutW(hdc, start_x + (i as i32 * col_w), start_y, dw.as_ptr(), (dw.len() - 1) as i32);
            }

            // Days Grid
            let total_days = days_in_month(CURRENT_YEAR, CURRENT_MONTH);
            // Day of week for 1st of month: 0=Sun, 1=Mon, ..., 6=Sat
            let dow1 = day_of_week(CURRENT_YEAR, CURRENT_MONTH, 1);
            // Shift to Monday-first: Mon=0, Tue=1 ... Sun=6
            let mut start_col = (dow1 + 6) % 7;

            let mut row = 0;
            for day in 1..=total_days {
                let x = start_x + (start_col * col_w);
                let y = start_y + 26 + (row * row_h);

                let is_today = day == TODAY_DAY && CURRENT_MONTH == TODAY_MONTH && CURRENT_YEAR == TODAY_YEAR;
                if is_today {
                    SetTextColor(hdc, 0x00008800); // Bold Green for Today
                } else if start_col >= 5 {
                    SetTextColor(hdc, 0x002222C0);
                } else {
                    SetTextColor(hdc, 0x00101010);
                }

                let day_w = to_wide(&format!("{:2}", day));
                TextOutW(hdc, x, y, day_w.as_ptr(), (day_w.len() - 1) as i32);

                start_col += 1;
                if start_col == 7 {
                    start_col = 0;
                    row += 1;
                }
            }

            EndPaint(hwnd, &ps);
            0
        }
        WM_TRAYICON => {
            if lparam as u32 == WM_LBUTTONUP || lparam as u32 == WM_RBUTTONUP {
                if IsWindowVisible(hwnd) != 0 {
                    ShowWindow(hwnd, SW_HIDE);
                } else {
                    // Position right above Windows taskbar at bottom right
                    let mut work_area: RECT = std::mem::zeroed();
                    SystemParametersInfoW(SPI_GETWORKAREA, 0, &mut work_area as *mut RECT as *mut _, 0);
                    let win_w = 370;
                    let win_h = 320;
                    let x = work_area.right - win_w - 10;
                    let y = work_area.bottom - win_h - 10;
                    SetWindowPos(hwnd, HWND_TOPMOST, x, y, win_w, win_h, SWP_SHOWWINDOW);
                    SetForegroundWindow(hwnd);
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
        let class_name = to_wide("AleCalWindowClass");
        let wnd_title = to_wide("AleCal for Windows - Görev Çubuğu Takvim");

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
            100, 100, 370, 320,
            null_mut(), null_mut(), hinstance, null_mut()
        );

        let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
        nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = 1;
        nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        nid.uCallbackMessage = WM_TRAYICON;
        nid.hIcon = h_icon;
        let tip = to_wide("AleCal for Windows - Hızlı Takvim");
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
