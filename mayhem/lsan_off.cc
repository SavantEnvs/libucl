// Leak detection is not the bug class this fleet fuzzes for, and -fsanitize=address always bundles
// LeakSanitizer in. Linked into every fuzz and -standalone binary (SPEC §6.2 item 15); ASan and UBSan
// stay fully active.
extern "C" int __lsan_is_turned_off() { return 1; }
