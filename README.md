# Echoes of Arcana — Эхо магии

Прототип Главы I (*«Башня Согласия»*) для **Dungeon GameJam SU 2026** (3–6 декабря 2026, Satbayev University, Алматы).

* **Жанр:** Fantasy Action-Adventure / RPG с атмосферой классических НРИ (D&D) и **голосовой магией Перворечи**.
* **Двойной ИИ:**
  1. **Локальный Voice AI (`ai_voice/`):** собственная 2D-CNN (обучена в Google Colab T4 → `spell_model.onnx`) + `Silero VAD` (MIT) + UDP-мост `127.0.0.1:5055`.
  2. **Живой ИИ-соперник (`AdaptiveAI`):** локальная марковская адаптация в реальном времени (учитывает спам и переходы игрока, ставит контр-щит и подстраивает сложность DDA).
* **Стек:** **Godot 4.3+** (GDScript, Forward+, автономный Windows `.exe`) + Python / ONNX Runtime.
* **Команда:** **3 человека (1 MacBook + 2 Windows)** — см. [GDD v1.0](docs/GDD_v1.0.md) и правила вайбкодинга в [CLAUDE.md](CLAUDE.md).

---

## Распределение ролей и зон (без merge-конфликтов)

| Участник | Платформа | Лейбл в GitHub | Ветки | Зона файлов | Основные задачи |
|---|---|---|---|---|---|
| **Участник 1 (AI / Docs)** | MacBook | `role:ai-mac` | `feat/ai-*` | `ai_voice/`, `docs/`, `ASSETS_LICENSES.md`, `PROJECT_DOCS_TEMPLATE.md` | Датасет, Google Colab (`ai_voice/train_in_colab.ipynb`) → ONNX, Push-to-Talk/Silero VAD, 3 секретных слова, видео, `qwrt.ca`, питч |
| **Участник 2 (Gameplay / Core)** | Windows #1 | `role:gameplay-win1` | `feat/gameplay-*` | `godot_project/scripts/`, `godot_project/project.godot` | `VoiceReceiver`, 3 заклинания + атака ЛКМ + `d20`, `AdaptiveAI` + 3 сложности, 4-фазный босс + концовки, сборка Windows `.exe` |
| **Участник 3 (World / UI / Audio)** | Windows #2 | `role:world-ui-win2` | `feat/world-*` | `godot_project/scenes/`, `godot_project/assets/`, `godot_project/dialogue/` | CC0 3D-ассеты (KayKit/Quaternius), 4 этажа Башни Согласия, D&D HUD и Гримуар, диалоги, CC0 SFX/музыка |

---

## Управление и аварийный режим для жюри

* `WASD` — перемещение • `Мышь` — камера и прицел • `ЛКМ` — обычная атака • `Space` — прыжок • `Shift` — бег/шёпот
* `V` — **Push-to-Talk** (удерживать для микрофона в шумном зале, если включён режим PTT)
* `Tab` — открыть Гримуар (лист персонажа D&D и словарь Перворечи)
* **Клавиатурный фолбэк (работает всегда, даже без микрофона):**
  * `1` — **Вирдан** (корни, удержание врагов)
  * `2` — **Ноктар** (дух памяти / раскрытие слабых точек и скрытых объектов)
  * `3` — **Таргум** (рунный щит против лучей и атак)
  * `Shift + 1/2/3` — произнести шёпотом
  * Удерживать `0` — 5 секунд тишины (вторая концовка)
  * `F9` — мгновенный переход на Этаж 4 (к боссу Хранителю / Архив-0 для демонстрации жюри)

---

## Быстрый старт (3 шага)

1. **Обучение или запуск Voice AI (`ai_voice/`):**
   * Для обучения модели на GPU: откройте [`ai_voice/train_in_colab.ipynb`](ai_voice/train_in_colab.ipynb) в Google Colab (T4 GPU) и сохраните полученный `spell_model.onnx`.
   * Локальный запуск:
     ```bash
     cd ai_voice
     python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
     python voice_engine.py --simulate   # тестовый поток команд в Godot без микрофона
     ```
2. **В Godot 4:** откройте `godot_project/project.godot` (одна версия **Godot 4.3 / 4.4 Standard** на всех ноутбуках) и нажмите **F5**.
3. **Документация и вайбкодинг:** прочитайте [`CLAUDE.md`](CLAUDE.md) перед тем, как просить Claude Code или Antigravity редактировать сцены и скрипты.

---

## Три секретных слова (заполняются 3 декабря в 13:00)

* **Слово #1:** `<вписать на открытии>` → `[СЛОТ #1: причина ошибки перевода в древнем договоре]`
* **Слово #2:** `<вписать на открытии>` → `[СЛОТ #2: артефакт/испытание в Зале Эльфов]`
* **Слово #3:** `<вписать на открытии>` → `[СЛОТ #3: символ на обложке Гримуара Миры]`
