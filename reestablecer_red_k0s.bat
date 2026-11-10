@echo off
setlocal enabledelayedexpansion

echo.
echo ========================================================
echo   SCRIPT DE RESURRECCION DE RED k0s + NGINX + JENKINS
echo ========================================================
echo.
echo ¡ADVERTENCIA! Esto borrara todos los ingress actuales y restaurará
echo la red de k0s por completo.
echo Pulsa CTRL+C si quieres cancelar, o cualquier tecla para continuar.
pause >nul


echo [1/10] Purgando los pods zombies de Ingress (fuerza bruta)...
podman exec k0s-cluster k0s kubectl delete pods --all -n ingress-nginx --force --grace-period=0
echo.

echo [2/10] Borrando el Webhook de validacion fantasma...
podman exec k0s-cluster k0s kubectl delete validatingwebhookconfiguration ingress-nginx-admission --ignore-not-found
echo.

echo [3/10] Extrayendo el namespace corrupto...
podman exec k0s-cluster sh -c "k0s kubectl get namespace ingress-nginx -o json > /tmp/ingress.json"
echo.

echo [4/10] Eliminando el finalizer (con sed dentro del contenedor)...
podman exec k0s-cluster sh -c "sed -i 's/\"kubernetes\"//' /tmp/ingress.json"
echo.

echo [5/10] Destruyendo el namespace definitivamente...
podman exec k0s-cluster sh -c "k0s kubectl replace --raw /api/v1/namespaces/ingress-nginx/finalize -f /tmp/ingress.json"
echo.

echo [6/10] Reinstalando Ingress NGINX Bare-metal...
podman exec k0s-cluster k0s kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/baremetal/deploy.yaml
echo.

echo [7/10] Esperando 10 segundos a que NGINX se cree para parchear puertos...
timeout /t 10 /nobreak > nul
echo.

echo [8/10] Fijando los NodePorts a 30080 y 30443...
echo {"spec": {"ports": [{"name":"http","port": 80,"nodePort": 30080}, {"name":"https","port": 443,"nodePort": 30443}]}} > patch.json
type patch.json | podman exec -i k0s-cluster sh -c "cat > /tmp/patch.json"
podman exec k0s-cluster k0s kubectl patch svc ingress-nginx-controller -n ingress-nginx --patch-file /tmp/patch.json
del patch.json
echo.

echo [9/10] Buscando la nueva IP del contenedor Jenkins...
FOR /F "tokens=*" %%i IN ('podman inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" jenkins-local') DO SET JENKINS_IP=%%i
echo IP de Jenkins detectada: %JENKINS_IP%
echo.

echo [10/10] Generando YAML de Jenkins y aplicando al cluster...
(
echo apiVersion: v1
echo kind: Service
echo metadata:
echo   name: jenkins-external-svc
echo   namespace: default
echo spec:
echo   ports:
echo     - protocol: TCP
echo       port: 80
echo       targetPort: 8080
echo ---
echo apiVersion: v1
echo kind: Endpoints
echo metadata:
echo   name: jenkins-external-svc
echo   namespace: default
echo subsets:
echo   - addresses:
echo       - ip: %JENKINS_IP%
echo     ports:
echo       - port: 8080
echo ---
echo apiVersion: networking.k8s.io/v1
echo kind: Ingress
echo metadata:
echo   name: jenkins-ingress
echo   namespace: default
echo   annotations:
echo     nginx.ingress.kubernetes.io/ssl-redirect: "true"
echo     nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
echo     nginx.ingress.kubernetes.io/hsts: "true"
echo     nginx.ingress.kubernetes.io/hsts-include-subdomains: "true"
echo     nginx.ingress.kubernetes.io/hsts-max-age: "31536000"
echo spec:
echo   ingressClassName: nginx
echo   tls:
echo     - hosts:
echo         - jenkins.teleupm.com
echo       secretName: teleupm-tls-secret
echo   rules:
echo     - host: jenkins.teleupm.com
echo       http:
echo         paths:
echo           - path: /
echo             pathType: Prefix
echo             backend:
echo               service:
echo                 name: jenkins-external-svc
echo                 port:
echo                   number: 80
) > jenkins-ingress.yaml

type jenkins-ingress.yaml | podman exec -i k0s-cluster k0s kubectl apply -f -
echo.

echo ========================================================
echo   REPARACION COMPLETADA CON EXITO.
echo ========================================================
pause