#!/bin/zsh
set -e

cd "$(dirname "$0")"

python3 tools/deploy.py davinci-toggle-color-effects_v_1.lua

echo
echo "Installed davinci-toggle-color-effects_v_1.lua."
echo "Restart DaVinci Resolve if it is already open."
