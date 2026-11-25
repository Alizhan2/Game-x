# Сборка автономного `voice_engine.exe` для Windows (для Участника 2)

Сборку выполняют на Windows x64. `voice_engine.exe` включает ONNX Runtime, модель заклинаний и Silero VAD. Игра запускает его рядом со своим `.exe`.

## Шаг 1. Подготовить окружение Python 3.11 / 3.12 (Windows)
```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install "numpy>=1.26" "onnxruntime>=1.18" "sounddevice>=0.4.6" "pyinstaller>=6.6"
```

## Шаг 2. Подготовить модели

Для проверки сборки используется базовый `ai_voice/spell_model.onnx`. После обучения на записи команды замените его проверенным экспортом из Colab. Из корня репозитория скачайте модель Silero и её лицензию.

```powershell
.\.venv\Scripts\python.exe ai_voice\voice_vad.py
```

## Шаг 3. Собрать `voice_engine.exe` через PyInstaller
```powershell
.\.venv\Scripts\python.exe -m PyInstaller --noconfirm ai_voice\voice_engine.spec
```
Готовый файл появится по пути `dist\voice_engine.exe`.

## Шаг 4. Положить рядом с игрой из Godot 4 и проверить без микрофона
1. Экспортируйте Godot-проект в `builds\EchoesOfArcana.exe`.
2. Скопируйте `dist\voice_engine.exe` и `ai_voice\SILERO_LICENSE.txt` в папку `builds\`.
3. `VoiceReceiver` (`godot_project/scripts/voice_receiver.gd`) сам запустит `voice_engine.exe --skip-calibration` при старте игры.
4. Перед запуском игры можно выполнить `voice_engine.exe --calibrate-only` с подключённым микрофоном. Профиль сохраняется в `%LOCALAPPDATA%\EchoesOfArcana\calibration_profile.json` и загружается при автозапуске.
5. Проверьте голос на Windows. При включённом Push-to-Talk держите `V` до срабатывания заклинания. На втором ПК без Python и с отключённым микрофоном проверьте `1 / 2 / 3`, `Shift + 1/2/3`, удержание `0` и `F9`.
