use std::env;
use std::path::PathBuf;
use std::process::Command;

fn main() {
    let target = env::var("TARGET").unwrap_or_default();
    if target.contains("windows") {
        let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());
        let res_path = out_dir.join("resource.o");
        let status = Command::new("x86_64-w64-mingw32-windres")
            .args(&["app.rc", "-O", "coff", "-o"])
            .arg(&res_path)
            .status();

        if let Ok(s) = status {
            if s.success() {
                println!("cargo:rustc-link-arg={}", res_path.display());
            }
        }
    }
    println!("cargo:rerun-if-changed=app.rc");
    println!("cargo:rerun-if-changed=app.manifest");
    println!("cargo:rerun-if-changed=app.ico");
}
