# 1. Matar procesos zombie que retienen el Named Pipe
Stop-Process -Name "win-sshproxy" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "gvproxy" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "wslrelay" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "wsl" -Force -ErrorAction SilentlyContinue

# 2. Forzar el apagado completo del subsistema WSL (limpia pipes del kernel)
wsl --shutdown

# 3. Limpiar los archivos de socket temporales en el perfil de usuario
$PodmanTemp = Join-Path $env:TEMP "podman*"
Remove-Item $PodmanTemp -Force -Recurse -ErrorAction SilentlyContinue

# 4. Esperar un par de segundos a que el kernel de Windows libere los recursos
Start-Sleep -Seconds 2

# 5. Iniciar podman de cero limpiando configuraciones previas de red
podman machine start podman-machine-teleupm

