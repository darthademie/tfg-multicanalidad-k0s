@echo off
chcp 65001 >nul

echo.
echo ========================================================
echo    PAUSANDO EL ENTORNO ON-PREMISE (SIN PERDER DATOS)
echo ========================================================
echo.
echo Este script detendra los contenedores y la maquina virtual
echo de Podman de forma segura para no corromper n8n ni Jenkins.
echo Todos tus flujos, pipelines y configuraciones se mantendran.

echo.
echo [1/2] Deteniendo los contenedores de Jenkins y k0s...
podman compose stop

echo.
echo [2/2] Apagando la maquina virtual de Podman (liberando RAM)...
podman machine stop podman-machine-teleupm

echo.
echo ========================================================
echo Entorno pausado correctamente. 
echo Ya puedes apagar Windows o usar la RAM para otras cosas.
echo ========================================================
echo.
pause