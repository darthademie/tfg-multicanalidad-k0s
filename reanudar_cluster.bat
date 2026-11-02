@echo off
chcp 65001 >nul

echo.
echo ========================================================
echo      REANUDANDO EL ENTORNO ON-PREMISE (CON DATOS)
echo ========================================================

echo [1/2] Arrancando la maquina virtual de Podman...
podman machine start podman-machine-teleupm

echo.
echo [2/2] Levantando los contenedores de Jenkins y k0s...
podman compose up -d

echo.
echo ========================================================
echo Entorno reanudado con exito. 
echo NOTA: k0s tardara unos ~30-45 segundos en levantar 
echo internamente todos los pods (n8n, frontend, SBT, ArgoCD).
echo ========================================================
echo.
pause