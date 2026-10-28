#!/usr/bin/env bash
# Tạo bản web chạy độc lập (PWA) trong web/dist từ web/smart-scan.html.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf dist && mkdir -p dist
cp static/manifest.webmanifest static/sw.js static/icon-*.png dist/
{
  printf '<!doctype html><html lang="vi"><head><meta charset="utf-8">'
  printf '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
  printf '<meta name="theme-color" content="#0B7A68"><meta name="apple-mobile-web-app-capable" content="yes">'
  printf '<meta name="apple-mobile-web-app-title" content="Smart Scan"><meta name="mobile-web-app-capable" content="yes">'
  printf '<link rel="manifest" href="manifest.webmanifest"><link rel="apple-touch-icon" href="icon-192.png"><link rel="icon" href="icon-192.png">'
  printf '<style>:root{color-scheme:light;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0;font:14px system-ui,sans-serif}img{max-width:100%%}[hidden]{display:none!important}</style>'
  printf '</head><body>'
  cat smart-scan.html
  printf '</body></html>'
} > dist/index.html
echo "Đã tạo web/dist"
