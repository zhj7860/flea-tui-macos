use super::*;

// One libav thread per video, so the count reads 1 once the decoder loads.
#[test]
fn loading_the_decoder_forces_one_libav_thread() {
    let library = unsafe { dlopen(SONAME.as_ptr(), RTLD_NOW) };
    if library.is_null() {
        eprintln!("SKIP one libav thread: libffmpegthumbnailer.so.4 is not installed");
        return;
    }
    unsafe {
        let force_found = dlsym(library, c"av_cpu_force_count".as_ptr());
        assert!(!force_found.is_null(), "libavutil answers no av_cpu_force_count");
        let count_found = dlsym(library, c"av_cpu_count".as_ptr());
        assert!(!count_found.is_null(), "libavutil answers no av_cpu_count");
        let force: ForceCpuCount = std::mem::transmute(force_found);
        let count: unsafe extern "C" fn() -> c_int = std::mem::transmute(count_found);
        // A count of 0 or less means detect, so this reads the host's own count.
        force(0);
        let detected = count();
        if detected <= 1 {
            eprintln!("SKIP one libav thread: the host reports {detected} CPU, so forcing proves nothing");
            return;
        }
        assert!(Decoder::load(SONAME).is_some(), "the decoder library did not load");
        assert_eq!(count(), 1, "the decoder did not force one libav thread");
    }
}
