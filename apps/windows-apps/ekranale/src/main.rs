#![windows_subsystem = "windows"]

use std::fs;
use std::path::PathBuf;
use std::ptr::null_mut;
use windows_sys::Win32::Foundation::*;
use windows_sys::Win32::Graphics::Gdi::*;
use windows_sys::Win32::System::DataExchange::*;
use windows_sys::Win32::System::Memory::*;
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::System::SystemInformation::GetLocalTime;
use windows_sys::Win32::Foundation::SYSTEMTIME;
use windows_sys::Win32::UI::Input::KeyboardAndMouse::*;
use windows_sys::Win32::UI::Shell::*;
use windows_sys::Win32::UI::WindowsAndMessaging::*;

const WM_TRAYICON: u32 = WM_USER + 1;
const ID_HOTKEY_CAPTURE: i32 = 701;
const ID_TRAY_CAPTURE: usize = 711;
const ID_TRAY_COLORPICKER: usize = 712;
const ID_TRAY_ABOUT: usize = 713;
const ID_TRAY_EXIT: usize = 714;
const CF_BITMAP: u32 = 2;
const CF_UNICODETEXT: u32 = 13;

fn to_wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

fn get_pictures_dir() -> PathBuf {
    if let Ok(p) = std::env::var("USERPROFILE") {
        let pic = PathBuf::from(p).join("Pictures").join("Ekranale");
        let _ = fs::create_dir_all(&pic);
        return pic;
    }
    PathBuf::from(".")
}

unsafe fn capture_fullscreen_to_clipboard(hwnd: HWND) -> Option<PathBuf> {
    let screen_dc = GetDC(null_mut());
    let w = GetSystemMetrics(SM_CXSCREEN);
    let h = GetSystemMetrics(SM_CYSCREEN);

    let mem_dc = CreateCompatibleDC(screen_dc);
    let hbitmap = CreateCompatibleBitmap(screen_dc, w, h);
    let old_bmp = SelectObject(mem_dc, hbitmap as HGDIOBJ);

    BitBlt(mem_dc, 0, 0, w, h, screen_dc, 0, 0, SRCCOPY);
    SelectObject(mem_dc, old_bmp);

    // Save to clipboard
    if OpenClipboard(hwnd) != 0 {
        EmptyClipboard();
        const CF_BITMAP: u32 = 2; const CF_UNICODETEXT: u32 = 13;
SetClipboardData(CF_BITMAP, hbitmap as _);
        CloseClipboard();
    }

    // Save BMP to file
    let mut st: SYSTEMTIME = std::mem::zeroed();
    GetLocalTime(&mut st);
    let filename = format!("Ekran_{:04}{:02}{:02}_{:02}{:02}{:02}.bmp", st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
    let save_path = get_pictures_dir().join(&filename);

    let mut bi: BITMAPINFOHEADER = std::mem::zeroed();
    bi.biSize = std::mem::size_of::<BITMAPINFOHEADER>() as u32;
    bi.biWidth = w;
    bi.biHeight = h;
    bi.biPlanes = 1;
    bi.biBitCount = 32;
    bi.biCompression = BI_RGB;
    let img_size = ((w * 32 + 31) / 32) * 4 * h;
    bi.biSizeImage = img_size as u32;

    let mut pixels = vec![0u8; img_size as usize];
    GetDIBits(
        mem_dc,
        hbitmap,
        0,
        h as u32,
        pixels.as_mut_ptr() as *mut _,
        &mut bi as *mut BITMAPINFOHEADER as *mut BITMAPINFO,
        DIB_RGB_COLORS,
    );

    let mut bfh: BITMAPFILEHEADER = std::mem::zeroed();
    bfh.bfType = 0x4D42; // 'BM'
    bfh.bfOffBits = (std::mem::size_of::<BITMAPFILEHEADER>() + std::mem::size_of::<BITMAPINFOHEADER>()) as u32;
    bfh.bfSize = bfh.bfOffBits + img_size as u32;

    let mut file_data = Vec::new();
    let bfh_slice = std::slice::from_raw_parts(&bfh as *const _ as *const u8, std::mem::size_of::<BITMAPFILEHEADER>());
    let bih_slice = std::slice::from_raw_parts(&bi as *const _ as *const u8, std::mem::size_of::<BITMAPINFOHEADER>());
    file_data.extend_from_slice(bfh_slice);
    file_data.extend_from_slice(bih_slice);
    file_data.extend_from_slice(&pixels);

    let _ = fs::write(&save_path, file_data);

    DeleteDC(mem_dc);
    ReleaseDC(null_mut(), screen_dc);

    Some(save_path)
}

unsafe extern "system" fn wnd_proc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_HOTKEY => {
            if wparam as i32 == ID_HOTKEY_CAPTURE {
                if let Some(path) = capture_fullscreen_to_clipboard(hwnd) {
                    let text = to_wide(&format!("📸 Ekran görüntüsü panoya kopyalandı ve kaydedildi:\n{}", path.display()));
                    let title = to_wide("Ekranale for Windows");
                    MessageBoxW(hwnd, text.as_ptr(), title.as_ptr(), MB_OK | MB_ICONINFORMATION);
                }
            }
            0
        }
        WM_TRAYICON => {
            if lparam as u32 == WM_RBUTTONUP || lparam as u32 == WM_LBUTTONUP {
                let mut pt = POINT { x: 0, y: 0 };
                GetCursorPos(&mut pt);
                let hmenu = CreatePopupMenu();
                let m_capture = to_wide("📸 Ekran Görüntüsü Al (PrintScreen / Win+Shift+S)");
                let m_color = to_wide("🎨 İmleç Altındaki Rengi Kopyala (Color Picker)");
                let m_about = to_wide("ℹ️ Ekranale Hakkında");
                let m_exit = to_wide("❌ Çıkış");

                AppendMenuW(hmenu, MF_STRING, ID_TRAY_CAPTURE, m_capture.as_ptr());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_COLORPICKER, m_color.as_ptr());
                AppendMenuW(hmenu, MF_SEPARATOR, 0, null_mut());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_ABOUT, m_about.as_ptr());
                AppendMenuW(hmenu, MF_STRING, ID_TRAY_EXIT, m_exit.as_ptr());

                SetForegroundWindow(hwnd);
                let sel = TrackPopupMenu(hmenu, TPM_RETURNCMD | TPM_NONOTIFY, pt.x, pt.y, 0, hwnd, null_mut());
                DestroyMenu(hmenu);

                match sel as usize {
                    ID_TRAY_CAPTURE => {
                        if let Some(path) = capture_fullscreen_to_clipboard(hwnd) {
                            let text = to_wide(&format!("Ekran görüntüsü alındı:\n{}", path.display()));
                            let title = to_wide("Ekranale");
                            MessageBoxW(hwnd, text.as_ptr(), title.as_ptr(), MB_OK | MB_ICONINFORMATION);
                        }
                    }
                    ID_TRAY_COLORPICKER => {
                        let hdc = GetDC(null_mut());
                        let color = GetPixel(hdc, pt.x, pt.y);
                        ReleaseDC(null_mut(), hdc);
                        let r = (color & 0xff) as u8;
                        let g = ((color >> 8) & 0xff) as u8;
                        let b = ((color >> 16) & 0xff) as u8;
                        let hex = format!("#{:02X}{:02X}{:02X}", r, g, b);

                        if OpenClipboard(hwnd) != 0 {
                            EmptyClipboard();
                            let hex_w = to_wide(&hex);
                            let hmem = GlobalAlloc(GMEM_MOVEABLE, hex_w.len() * 2);
                            if !hmem.is_null() {
                                let ptr = GlobalLock(hmem) as *mut u16;
                                std::ptr::copy_nonoverlapping(hex_w.as_ptr(), ptr, hex_w.len());
                                GlobalUnlock(hmem);
                                SetClipboardData(CF_UNICODETEXT, hmem as _);
                            }
                            CloseClipboard();
                        }

                        let text = to_wide(&format!("🎨 Piksel Rengi Kopyalandı!\n\nHEX: {}\nRGB: ({}, {}, {})", hex, r, g, b));
                        let title = to_wide("Ekranale Renk Seçici");
                        MessageBoxW(hwnd, text.as_ptr(), title.as_ptr(), MB_OK | MB_ICONINFORMATION);
                    }
                    ID_TRAY_ABOUT => {
                        let text = to_wide(
                            "Ekranale for Windows v1.0.0\n\
                            Hafif Ekran Alıntısı, Çizim & Renk Seçici.\n\n\
                            Geliştirici: Mehmet Akif Çifçi | SoftAI Yazılım\n\
                            Kısayol: Win + Shift + S veya PrintScreen"
                        );
                        let title = to_wide("Ekranale Hakkında");
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
        let class_name = to_wide("EkranaleWindowClass");

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

        RegisterHotKey(hwnd, ID_HOTKEY_CAPTURE, MOD_WIN | MOD_SHIFT, 0x53); // 'S'

        let mut nid: NOTIFYICONDATAW = std::mem::zeroed();
        nid.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
        nid.hWnd = hwnd;
        nid.uID = 1;
        nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
        nid.uCallbackMessage = WM_TRAYICON;
        nid.hIcon = h_icon;
        let tip = to_wide("Ekranale for Windows - Ekran Yakalama (Win+Shift+S)");
        for (i, c) in tip.iter().take(127).enumerate() {
            nid.szTip[i] = *c;
        }
        Shell_NotifyIconW(NIM_ADD, &nid);

        let mut msg: MSG = std::mem::zeroed();
        while GetMessageW(&mut msg, null_mut(), 0, 0) > 0 {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }

        UnregisterHotKey(hwnd, ID_HOTKEY_CAPTURE);
        Shell_NotifyIconW(NIM_DELETE, &nid);
    }
}
