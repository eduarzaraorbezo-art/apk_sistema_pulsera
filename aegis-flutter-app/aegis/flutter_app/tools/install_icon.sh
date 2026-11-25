#!/usr/bin/env bash
# Ejecutar tras `flutter create .` : copia el ícono AEGIS a Android.
set -e
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  cp android_icons/mipmap-$d/ic_launcher*.png android/app/src/main/res/mipmap-$d/
done
echo "Ícono instalado."
