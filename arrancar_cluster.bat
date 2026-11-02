@echo off
chcp 65001 >nul

echo.
echo ========================================================
echo      ARRANCANDO EL ENTORNO ON-PREMISE
echo ========================================================
echo.
echo Este script creará los contenedores y la infraestructura
echo local de k0s desde 0.
echo ¡ADVERTENCIA! Esto recreará todo lo mencionado si
echo Pulsa CTRL+C si quieres cancelar, o cualquier tecla para continuar.
pause >nul

rem 1. Levantar los contenedores
echo.
echo [1/8] Levantando contenedores con Podman Compose...
podman compose up -d

rem ############### CONFIGURACION DE JENKINS ###############

echo.
echo [2/8] Instalando el cliente de Docker dentro de Jenkins...
podman exec -u root jenkins-local bash -c "apt-get update && apt-get install -y docker.io"

echo Esperando a que Jenkins genere la contrasena inicial...
podman exec jenkins-local bash -c "while [ ! -f /var/jenkins_home/secrets/initialAdminPassword ]; do sleep 2; done"

echo.
echo ========================================================
echo Contrasenia inicial de Jenkins:
podman exec jenkins-local cat /var/jenkins_home/secrets/initialAdminPassword
echo ========================================================

rem ############### ESPERA DE K0S E INGRESS ###############

echo.
echo [3/8] Esperando a que el cluster k0s termine de arrancar...
podman exec k0s-cluster sh -c "until k0s kubectl get nodes >/dev/null 2>&1; do sleep 3; done"
podman exec k0s-cluster k0s kubectl wait --for=condition=Ready node --all --timeout=120s

echo.
echo [4/8] Instalando Ingress-NGINX y enlazando puertos 30080/30443...
podman exec k0s-cluster k0s kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/baremetal/deploy.yaml
podman exec k0s-cluster sh -c "k0s kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' -p='[{\"op\": \"replace\", \"path\": \"/spec/ports/0/nodePort\", \"value\": 30080}, {\"op\": \"replace\", \"path\": \"/spec/ports/1/nodePort\", \"value\": 30443}]'"

rem ############### CONFIGURACION DE ARGOCD ###############

echo.
echo [5/8] Instalando y configurando ArgoCD...
podman exec k0s-cluster sh -c "k0s kubectl create namespace argocd --dry-run=client -o yaml | k0s kubectl apply -f -"
podman exec k0s-cluster k0s kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

rem Configurar ArgoCD en modo 'insecure'
podman exec k0s-cluster sh -c "k0s kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{\"data\":{\"server.insecure\":\"true\"}}'"

rem Reiniciar el servidor de ArgoCD
podman exec k0s-cluster k0s kubectl rollout restart deployment argocd-server -n argocd

echo.
echo Esperando a que ArgoCD descargue sus imagenes y genere la contrasena (puede tardar 1-2 min)...
podman exec k0s-cluster sh -c "until k0s kubectl -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; do sleep 5; done"

echo.
echo ========================================================
echo Contrasenia de ArgoCD (usuario: admin):
podman exec k0s-cluster sh -c "k0s kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo"
echo ========================================================

rem ############### ENRUTAR JENKINS POR INGRESS ###############

echo.
echo [6/8] Configurando Ingress para Jenkins (https://jenkins.teleupm.com)
echo y ArgoCD (https://argocd.teleupm.com)...

echo.
echo Esperando a que el controlador de Ingress y su Webhook esten operativos...
podman exec k0s-cluster k0s kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

rem Pequeña pausa extra ejecutada dentro de Linux para asegurar que el puerto 443 del Webhook ya acepta trafico
podman exec k0s-cluster sh -c "sleep 10"

rem Obtenemos automaticamente la IP interna del contenedor
for /f "delims=" %%i in ('podman inspect -f "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}" jenkins-local') do set JENKINS_IP=%%i
echo IP interna detectada para Jenkins: %JENKINS_IP%

rem Generamos el YAML de Jenkins dinamicamente (para que pille la variable) y lo aplicamos
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
echo    nginx.ingress.kubernetes.io/ssl-redirect: "true"
echo    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
echo    nginx.ingress.kubernetes.io/hsts: "true"
echo    nginx.ingress.kubernetes.io/hsts-include-subdomains: "true"
echo    nginx.ingress.kubernetes.io/hsts-max-age: "31536000"
echo spec:
echo   ingressClassName: nginx
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

rem Generamos el YAML de ArgoCD localmente y lo inyectamos (-i) al clúster
(
echo apiVersion: networking.k8s.io/v1
echo kind: Ingress
echo metadata:
echo   name: argocd-ingress
echo   namespace: argocd
echo   annotations:
echo    nginx.ingress.kubernetes.io/ssl-redirect: "true"
echo    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
echo    nginx.ingress.kubernetes.io/hsts: "true"
echo    nginx.ingress.kubernetes.io/hsts-include-subdomains: "true"
echo    nginx.ingress.kubernetes.io/hsts-max-age: "31536000"
echo spec:
echo   ingressClassName: nginx
echo   rules:
echo     - host: argocd.teleupm.com
echo       http:
echo         paths:
echo           - path: /
echo             pathType: Prefix
echo             backend:
echo               service:
echo                 name: argocd-server
echo                 port:
echo                   number: 80
) > argocd-ingress.yaml

type argocd-ingress.yaml | podman exec -i k0s-cluster k0s kubectl apply -f -

echo.
echo [7/8] Creando namespace para aplicaciones

podman exec k0s-cluster k0s kubectl create namespace apps

echo.
echo [8/8] Desplegando gestor web, N8N y backend de Telegram...

type workloads\teleupm-n8n-deployment.yaml | podman exec -i k0s-cluster k0s kubectl apply -f -
type workloads\teleupm-front-deployment.yaml | podman exec -i k0s-cluster k0s kubectl apply -f -
type workloads\teleupm-sbt-deployment.yaml | podman exec -i k0s-cluster k0s kubectl apply -f -

echo.
echo ========================================================
echo Todo listo!! Ya puedes probar el acceso al cluster
echo Jenkins: https://jenkins.teleupm.com
echo Argo CD: https://argocd.teleupm.com
echo Frontend web: https://teleupm.com
echo Flujos N8N:   https://teleupm.com/flujos
echo ========================================================
echo.

echo ========================================================
echo Ten en cuenta que algunas funcionalidades como N8N
echo son más pesadas y pueden tardar en arrancar.
echo.
echo Espera 1-5 minutos antes de probar para no dar por
echo fallido el despliegue en vano
echo ========================================================

pause