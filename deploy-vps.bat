@echo off
setlocal
rem ============================================================
rem  deploy-vps.bat - DEPLOY RYUBOT SEKALI JALAN KE VPS
rem
rem  Langkah: upload semua source (termasuk .env) ke /opt/ryubot,
rem  lalu jalankan deploy-vps.sh di server (build -> migrate ->
rem  restart -> verify).
rem
rem  Pemakaian:
rem    deploy-vps.bat                            (pakai env RYUBOT_VPS_IP)
rem    deploy-vps.bat 203.0.113.10               (IP VPS)
rem ============================================================

set "IP=%~1"
if "%IP%"=="" set "IP=%RYUBOT_VPS_IP%"
if "%IP%"=="" (
  echo Pemakaian: deploy-vps.bat IP_VPS
  echo   atau set RYUBOT_VPS_IP=dulu, lalu cukup: deploy-vps.bat
  exit /b 1
)

set "SRC=%~dp0"
set "SRC=%SRC:~0,-1%"
set "DST=/opt/ryubot"

echo === [1/2] Upload source ke root@%IP%:%DST% (tar pipe) ===
tar -C "%SRC%" --exclude=bin --exclude=backup --exclude=.git -cf - . | ssh root@%IP% "mkdir -p %DST% && tar -xf - -C %DST%"
if errorlevel 1 (
  echo Upload GAGAL.
  exit /b 1
)

echo === [2/2] Deploy di server: build + migrate + restart + verify ===
ssh root@%IP% "bash %DST%/deploy-vps.sh"
if errorlevel 1 (
  echo Deploy GAGAL - cek output di atas.
  exit /b 1
)

echo === Selesai. Silakan buka https://ryuubot.com dengan Ctrl+F5. ===