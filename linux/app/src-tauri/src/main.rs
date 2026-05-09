// Clawix Linux entry point. The real wiring lives in the lib crate so
// the binary stays a thin shell and unit tests target the lib.
#![cfg_attr(
    all(not(debug_assertions), target_os = "linux"),
    windows_subsystem = "windows"
)]

fn main() {
    clawix_linux_lib::run()
}
