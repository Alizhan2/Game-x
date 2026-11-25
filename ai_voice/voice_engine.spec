# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path

block_cipher = None
base_dir = Path(SPECPATH)
datas = []
model_file = base_dir / "spell_model.onnx"
if model_file.exists():
    datas.append((str(model_file), "."))

a = Analysis(
    [str(base_dir / "voice_engine.py")],
    pathex=[str(base_dir)],
    binaries=[],
    datas=datas,
    hiddenimports=["features", "onnxruntime", "sounddevice", "numpy"],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)
pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)
exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="voice_engine",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
)
