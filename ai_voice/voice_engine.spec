from pathlib import Path

base_dir = Path(SPECPATH)
assets = [base_dir / name for name in ("spell_model.onnx", "silero_vad.onnx", "SILERO_LICENSE.txt")]
missing = [path.name for path in assets if not path.is_file()]
if missing:
    raise SystemExit(f"Missing {', '.join(missing)}. See ai_voice/BUILD_WINDOWS.md.")

a = Analysis(
    [str(base_dir / "voice_engine.py")],
    pathex=[str(base_dir)],
    binaries=[],
    datas=[(str(path), ".") for path in assets],
    noarchive=False,
)
a.binaries = [entry for entry in a.binaries if not entry[0].lower().endswith("-asio.dll")]
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="voice_engine",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=True,
)
