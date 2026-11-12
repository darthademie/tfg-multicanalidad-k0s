@echo off
setlocal enabledelayedexpansion

echo.
echo ========================================================
echo      REPARANDO IP DE JENKINS
echo ========================================================

echo [1/2] Buscando la nueva IP del contenedor Jenkins...
FOR /F "tokens=*" %%i IN ('podman inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" jenkins-local') DO SET JENKINS_IP=%%i
echo IP de Jenkins detectada: %JENKINS_IP%
echo.

echo [2/2] Generando YAML de Jenkins y aplicando al cluster...
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