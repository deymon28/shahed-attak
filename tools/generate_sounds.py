"""Compatibility entrypoint for the recorded-source audio pipeline."""
if __package__:
    from .process_audio import SOUND_SPECS, audit_ogg, find_ffmpeg, generate_all, main
else:
    from process_audio import SOUND_SPECS, audit_ogg, find_ffmpeg, generate_all, main

if __name__ == '__main__':
    raise SystemExit(main())
