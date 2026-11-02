@echo off
chcp 65001 >nul

echo.
echo ========================================================
echo   DESTRUYENDO EL ENTORNO ON-PREMISE (LIMPIEZA TOTAL)
echo ========================================================
echo.
echo ¡ADVERTENCIA! Esto borrara todos los contenedores y los
echo volumenes. Se perdera el estado de Jenkins, k0s y ArgoCD.
echo Pulsa CTRL+C si quieres cancelar, o cualquier tecla para continuar.
pause >nul

echo.
echo [1/3] Deteniendo y borrando contenedores y volumenes...
podman compose down -v

echo.
echo [2/3] Eliminando los archivos YAML generados...
del argocd-ingress.yaml 2>nul
del jenkins-ingress.yaml 2>nul

echo.
echo [3/3] Forzando limpieza profunda (por si Compose falla)...
podman rm -f k0s-cluster jenkins-local 2>nul
podman volume rm k0s_data jenkins_home 2>nul

echo.
echo ========================================================
echo Entorno destruido de forma limpia. 
echo Ya puedes volver a lanzar arranque_cluster.bat cuando quieras.
echo ========================================================
echo.

pause