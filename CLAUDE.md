# CLAUDE.md — Правила вайбкодинга (Echoes of Arcana)

Этот файл обязателен для Claude Code, Antigravity и всех 3 участников команды.

## 1. Стек и целевая среда
- **Движок:** Godot 4.3 / 4.4 Standard (только GDScript, типизированный синтаксис Godot 4). **Запрещено** использовать устаревший API Godot 3 (`KinematicBody`, `Spatial`, `yield`, `connect("sig", self, "fn")`, `export var`).
- **Целевая сборка:** автономный **Windows 10 `.exe`** (без требования устанавливать Python или библиотеки на компьютер жюри).
- **Voice AI:** Python 3.10+ (`ai_voice/`), обучение на T4 GPU через `ai_voice/train_in_colab.ipynb`, инференс через `onnxruntime` → `spell_model.onnx`, транспорт — UDP `127.0.0.1:5055`.

## 2. Разделение владения файлами (3 человека, 1 Mac + 2 Win)
Чтобы не ломать `.tscn` и не создавать конфликтов при `git merge`:
- **Участник 1 (Mac, `role:ai-mac`):** редактирует только `ai_voice/`, `docs/`, `README.md`, `ASSETS_LICENSES.md`, `PROJECT_DOCS_TEMPLATE.md`.
- **Участник 2 (Win #1, `role:gameplay-win1`):** владеет `godot_project/scripts/` и `godot_project/project.godot`.
- **Участник 3 (Win #2, `role:world-ui-win2`):** владеет `godot_project/scenes/`, `godot_project/assets/`, `godot_project/dialogue/`.
- **Правило `.tscn`:** не меняйте чужие `.tscn` файлы вручную в текстовом редакторе без согласования; новые механики оформляйте отдельными скриптами и модульными подсценами.

## 3. Неприкосновенные контракты автозагрузок (Autoloads)
В `godot_project/project.godot` подключены 3 синглтона (добавлять/переименовывать только по согласованию с Win #1):
1. `GameState` (`res://scripts/game_state.gd`):
   - Сигналы: `floor_changed(floor_num)`, `word_unlocked(word)`, `censorship_changed(censored)`, `ending_reached(ending_id)`.
2. `VoiceReceiver` (`res://scripts/voice_receiver.gd`):
   - Сигнал: `spell_heard(spell: String, confidence: float, volume: float, d20_result: Dictionary, is_whisper: bool)`
   - Сигнал: `silence_updated(silence_sec: float)`
   - Сигнал: `engine_status_changed(connected: bool)`
3. `AdaptiveAI` (`res://scripts/adaptive_ai.gd`):
   - Сложности: `Difficulty.APPRENTICE`, `Difficulty.MAGE`, `Difficulty.ARCHMAGE`.
   - Сигналы: `counter_shield_changed(blocked_spell)`, `taunt_triggered(message)`, `difficulty_changed(level)`, `adaptation_updated(stats)`.

## 4. Жёсткие требования джема (ломать запрещено)
1. **Нулевой краш без микрофона:** игра обязана запускаться и полностью проходиться, даже если на ПК нет микрофона и не запущен `voice_engine`. Клавиши `1` (Вирдан), `2` (Ноктар), `3` (Таргум), `Shift+1/2/3` (шёпот), удержание `0` (5 сек тишины) и `V` (Push-to-Talk) должны работать всегда.
2. **Кнопка жюри `F9`:** мгновенно переносит на Этаж 4 (Вершина Согласия / Босс Хранитель) для показа финала и двух концовок за 3 минуты.
3. **Только коммерчески безопасные лицензии:** строго `CC0`, `MIT`, `Apache-2.0`, `BSD`. **Никаких `CC-BY-NC` ассетов, фанартов из интернета и проприетарных моделей.** Каждый новый ассет сразу вносить в `ASSETS_LICENSES.md`.
4. **Правило ≤ 50% до старта джема (3 декабря, 13:00):** до открытия джема готовим только базовый каркас, AI-пайплайн и реестр лицензий; все предзаготовки честно перечисляем в `PROJECT_DOCS_TEMPLATE.md`.

## 5. Git-workflow
- Ветка `main` всегда должна запускаться без ошибок.
- Работаем в ветках по роли: `feat/ai-<task>`, `feat/gameplay-<task>`, `feat/world-<task>`.
- Всегда проверяйте `git status` перед коммитом: `.venv/`, `__pycache__/`, `.godot/`, крупные неиспользуемые бинарники в Git не пушим.
