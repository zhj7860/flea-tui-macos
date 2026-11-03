// open(2) flags this tree declares itself, because it takes no libc crate.

// O_NOFOLLOW is architecture specific: on arm64 the x86_64 value 0o400000 is O_LARGEFILE, a no-op on
// 64-bit, so one hardcoded constant drops a symlink guard without failing anything. Darwin's value
// is the same on every architecture it runs.
#[cfg(target_os = "linux")]
#[cfg(target_arch = "x86_64")]
pub const O_NOFOLLOW: i32 = 0o400000;
#[cfg(target_os = "linux")]
#[cfg(target_arch = "aarch64")]
pub const O_NOFOLLOW: i32 = 0o100000;
#[cfg(target_os = "macos")]
pub const O_NOFOLLOW: i32 = 0x0100;
// A new architecture adds its own value from that target's asm/fcntl.h rather than inheriting one.
#[cfg(all(target_os = "linux", not(any(target_arch = "x86_64", target_arch = "aarch64"))))]
compile_error!("O_NOFOLLOW needs a verified value for this architecture");

// O_DIRECTORY is architecture specific for the same reason, and it is what refuses everything that is
// not a directory at the open rather than at a stat somebody could race.
#[cfg(target_os = "linux")]
#[cfg(target_arch = "x86_64")]
pub const O_DIRECTORY: i32 = 0o200000;
#[cfg(target_os = "linux")]
#[cfg(target_arch = "aarch64")]
pub const O_DIRECTORY: i32 = 0o40000;
#[cfg(target_os = "macos")]
pub const O_DIRECTORY: i32 = 0x0010_0000;

// open(2) O_NONBLOCK, 0o4000 on both Linux architectures flea is built for; a FIFO's open returns for the fstat to refuse it.
#[cfg(target_os = "linux")]
#[cfg(any(target_arch = "x86_64", target_arch = "aarch64"))]
pub const O_NONBLOCK: i32 = 0o4000;
#[cfg(target_os = "linux")]
#[cfg(not(any(target_arch = "x86_64", target_arch = "aarch64")))]
compile_error!("O_NONBLOCK needs a verified value for this architecture");
#[cfg(target_os = "macos")]
pub const O_NONBLOCK: i32 = 0x0004;

// O_CLOEXEC, which pipe2 and socketpair callers pass; Darwin spells it 0x01000000 rather than 0o2000000.
#[cfg(target_os = "linux")]
pub const O_CLOEXEC: i32 = 0o2_000_000;
#[cfg(target_os = "macos")]
pub const O_CLOEXEC: i32 = 0x0100_0000;
