# Omarchy Add-ons

## NoGaps

После установки Omarchy открой терминал и выполни:

```bash
git clone https://github.com/AmirAdelevich/omarchy-addons.git
cd omarchy-addons
bash install-no-gaps.sh
```

Скрипт задаёт нулевые отступы по краям и между окнами в `hypr/looknfeel.lua`, сохраняет текущую толщину рамок и перечитывает настройки Hyprland.

Если на рабочем столе включена прокрутка (Scrolling), выбери плиточную раскладку Tiling (Dwindle) в меню раскладок Omarchy. В режиме прокрутки колонки могут оставлять место у краёв даже при нулевых отступах. Из режима Scrolling можно сразу вернуться в Tiling командой `omarchy-hyprland-workspace-layout-toggle back`, запущенной на нужном рабочем столе.

## Установка всего комплекта

На Omarchy x86-64 с GitHub CLI выполни:

```bash
gh repo clone AmirAdelevich/omarchy-addons && bash omarchy-addons/install-all.sh
```

Для доступа к приватному репозиторию войди в GitHub CLI через `gh auth login`.
Если репозиторий уже клонирован, выполни `git pull && bash install-all.sh` из его каталога.

Скрипт устанавливает Google Chrome и Visual Studio Code из AUR. Если Telegram Desktop ещё не установлен из репозитория Arch, скрипт устанавливает его из AUR. Tailscale устанавливается из репозитория Arch, а служба `tailscaled` включается автоматически. Для подключения к своей сети после установки выполни `sudo tailscale up`. Google Chrome назначается браузером по умолчанию для текущего пользователя.

Скрипт скачивает закреплённый архив из Releases, проверяет SHA-256 и устанавливает КриптоПро CSP с CAdES, JaCarta и Hiddify через pacman. Затем включает PC/SC, добавляет системную политику расширения CAdES для Google Chrome, включает прокрутку нажатием колёсика для текущего пользователя и применяет NoGaps. Pacman может запросить подтверждение. После установки полностью закрой и снова открой Chrome.

Архив релиза также содержит исходные пакеты для пересборки и файл `INSTALL.md` с диагностикой считывателя и проверкой лицензии КриптоПро.
