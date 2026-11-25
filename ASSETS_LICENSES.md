# Реестр сторонних библиотек и ассетов (`ASSETS_LICENSES.md`)

> В первом разделе указаны компоненты голосового пайплайна и движок. Во втором разделе перечислены кандидаты для мира игры. Для финальной сдачи внесите точные версии и имена каждого реально добавленного файла или пака.

## Движок и голосовой пайплайн

| Компонент | Автор / Источник | Лицензия | Использование |
|---|---|---|---|
| **Godot Engine 4** | Godot Engine Contributors (`github.com/godotengine/godot`) | **MIT** | Движок и экспорт Windows `.exe` |
| **Silero VAD v6.2.3 (`silero_vad.onnx`)** | [Silero Team](https://github.com/snakers4/silero-vad/blob/5cd7945676eb32225748052e2e6a0580e4686a08/LICENSE) | **MIT** | Детекция речи офлайн. `voice_vad.py` проверяет SHA-256 модели и скачивает уведомление `SILERO_LICENSE.txt` |
| **ONNX Runtime** | Microsoft (`github.com/microsoft/onnxruntime`) | **MIT** | Оффлайн-инференс обученной модели `spell_model.onnx` |
| **sounddevice** | [Matthias Geier и контрибьюторы](https://github.com/spatialaudio/python-sounddevice/blob/master/LICENSE) | **MIT** | Захват звука с микрофона |
| **PortAudio** | [PortAudio Contributors](https://github.com/PortAudio/portaudio/blob/master/LICENSE.txt) | **MIT** | Аудиобиблиотека в поставке `sounddevice` |
| **PyTorch / NumPy / SciPy / scikit-learn / matplotlib** | PyTorch, SciPy, scikit-learn & Matplotlib Teams | **BSD / PSF** | Тренировка аудио-CNN в Colab, Mel-спектрограммы и графики метрик |

PyInstaller используется при сборке Windows. Условия распространения сгенерированного `.exe` описаны в [лицензии и исключении PyInstaller](https://pyinstaller.org/en/stable/license.html).

## Кандидаты для мира игры

| Компонент | Автор / Источник | Лицензия | Использование |
|---|---|---|---|
| **Dialogue Manager** | Nathan Hoad (`github.com/nathanhoad/godot_dialogue_manager`) | **MIT** | Система диалогов Главы I и веток концовок |
| **Phantom Camera** | Marcus Skov (`github.com/ramokz/phantom-camera`) | **MIT** | Кинематографичное управление камерой |
| **KayKit Dungeon & Adventurers** | Kay Lousberg (`kaylousberg.com`) | **CC0** | 3D-модели башни и персонажей |
| **Quaternius Fantasy Monsters** | Quaternius (`quaternius.com`) | **CC0** | 3D-стражи этажей и духи |
| **Kenney Game Icons & Audio** | Kenney (`kenney.nl`) | **CC0** | Иконки рун, рамки HUD, базовые SFX |
| **Freesound (CC0 filter)** | Freesound Contributors (`freesound.org`) | **CC0** | Эмбиент башни и звуковые эффекты |
