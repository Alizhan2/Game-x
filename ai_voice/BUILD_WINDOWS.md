# Сборка автономного `voice_engine.exe` для Windows (для Участника 2)

На компьютере организаторов и жюри не должен требоваться Python. Этот гайд собирает `voice_engine.exe` со встроенным `onnxruntime` и моделью `spell_model.onnx` рядом с `EchoesOfArcana.exe`.

## Шаг 1. Подготовить окружение Python 3.11 / 3.12 (Windows)
```powershell
cd ai_voice
py -3.12 -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
```

## Шаг 2. Скопировать обученную модель из Google Colab
Поместите файл `spell_model.onnx` (полученный из `ai_voice/train_in_colab.ipynb`) в папку `ai_voice/spell_model.onnx`.

## Шаг 3. Собрать `voice_engine.exe` через PyInstaller
```powershell
pyinstaller --noconfirm ai_voice\voice_engine.spec
```
Готовый файл появится по пути `ai_voice\dist\voice_engine.exe`.

## Шаг 4. Положить рядом с игрой из Godot 4 и проверить без микрофона
1. Экспортируйте Godot-проект в `builds\EchoesOfArcana.exe`.
2. Скопируйте `ai_voice\dist\voice_engine.exe` и (при необходимости) `ai_voice\spell_model.onnx` в ту же папку `builds\`.
3. `VoiceReceiver` (`godot_project/scripts/voice_receiver.gd`) сам запустит `voice_engine.exe --skip-calibration` при старте игры.
4. Проверьте запуск `EchoesOfArcana.exe` на втором Windows-ПК, где **нет Python и отключён микрофон**: игра не должна вылетать, а клавиши `1 / 2 / 3`, `Shift + 1/2/3`, `0` и `F9` должны работать с первой секунды.
