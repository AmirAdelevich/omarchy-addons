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
