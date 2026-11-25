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

## Ассеты в `godot_project/assets`

| Пак или ассет | Автор и первоисточник | Лицензия | Файлы и назначение |
|---|---|---|---|
| **KayKit Dungeon Remastered 1.0** | Kay Lousberg, [репозиторий](https://github.com/KayKit-Game-Assets/KayKit-Dungeon-Remastered-1.0/tree/b0ca9bd96a8072ab36a3a5464f00ed1e06a16d07) | **CC0 1.0** | `models/kaykit_dungeon/` — 22 модуля и предмета для башни, включая полы, стены, арки, лестницу, колонны, ворота и знамёна. |
| **KayKit Adventurers 1.0** | Kay Lousberg, [репозиторий](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0/tree/672074b73ba276876a19e8816ecdc5241817ab47) | **CC0 1.0** | `models/kaykit_adventurers/` — `Mage.glb` для Рена, `Rogue_Hooded.glb` для стража Зала Эльфов. |
| **KayKit Skeletons 1.0** | Kay Lousberg, [репозиторий](https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0/tree/15b62b9bad122f72926c10fb14d622c73819fa54) | **CC0 1.0** | `models/kaykit_skeletons/Skeleton_Warrior.glb` — страж Склепа Памяти. |
| **Robot Enemy** | Quaternius, [Poly Pizza](https://poly.pizza/m/1gNo5ezvmr) | **CC0 1.0** | `models/quaternius/robot_enemy.glb` — модель Хранителя. |
| **Ghost Skull** | Quaternius, [Poly Pizza](https://poly.pizza/m/TX8r9WBXpe) | **CC0 1.0** | `models/quaternius/ghost_skull.glb` — дух Склепа Памяти. |
| **Interface Sounds** | Kenney, [страница пакета](https://kenney.nl/assets/interface-sounds), [архив OpenGameArt](https://opengameart.org/sites/default/files/kenney_interfaceSounds.zip) | **CC0 1.0** | `audio/kenney_interface/` — `click_001.ogg`, `confirmation_001.ogg`. |
| **RPG Audio** | Kenney, [страница пакета](https://kenney.nl/assets/rpg-audio), [архив OpenGameArt](https://opengameart.org/sites/default/files/RPGsounds_Kenney.zip) | **CC0 1.0** | `audio/kenney_rpg/` — `bookOpen.ogg`, `bookClose.ogg`, `chop.ogg`, `metalLatch.ogg`. |
| **Earth Element Magic Spell** | qubodup, [OpenGameArt](https://opengameart.org/content/earth-element-magic-spell), [исходная запись Freesound](https://freesound.org/people/qubodup/sounds/160691/) | **CC0 1.0** | `audio/spells/virdan.ogg` — звук заклинания «Вирдан». |
| **Magic Spell SFX** | JaggedStone, [OpenGameArt](https://opengameart.org/node/29772) | **CC0 1.0** | `audio/spells/noktar.ogg` и `audio/spells/targum.ogg` — исходные `magical_1.ogg` и `magical_2.ogg`. |
| **Loopable Dungeon Ambience** | JaggedStone, [OpenGameArt](https://opengameart.org/content/loopable-dungeon-ambience) | **CC0 1.0** | `audio/ambience/dungeon_ambient_1.ogg` — зацикливаемый эмбиент башни. |
| **Whispers in the Fog** | Ruhinre, [OpenGameArt](https://opengameart.org/content/whispers-in-the-fog) | **CC0 1.0** | `audio/ambience/whispers_in_the_fog.ogg` — зацикливаемая фоновая музыка. |

Модели и аудио скопированы без перекодирования. Двойное расширение `.gltf.glb` сокращено до `.glb`, а звуки заклинаний названы по словам Перворечи. При импорте Godot сохраняет текстуры внутри моделей KayKit и включает зацикливание эмбиента и фоновой музыки. Файлы `LICENSE.txt` из пакетов KayKit и Kenney лежат рядом с соответствующими ассетами.
