# Metrics Server

Pré-requisito do HPA nas duas opções. Instalar antes de aplicar qualquer `hpa.yaml`:

    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

No EKS gerenciado às vezes é preciso desabilitar a verificação de TLS entre o
Metrics Server e os kubelets (certificado self-signed dos nós). Se
`kubectl top pods` continuar vazio após 1-2 min, editar o Deployment
`metrics-server` no namespace `kube-system` e acrescentar aos args do container:

    --kubelet-insecure-tls
