Write-Output "Ajustando CPU y RAM de la máquina podman/docker..."

Set-Content -Path "$env:USERPROFILE\.wslconfig" -Value "[wsl2]`nmemory=6GB`nprocessors=6`nswap=2GB"
wsl --shutdown

Write-Output "Todo listo!! Ejecuta la máquina docker/podman de nuevo"