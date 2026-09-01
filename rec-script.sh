#!/bin/bash
export LB="abc9bb709ba2943ea8099ae621c5939a-76d2e22c4f7f64c3.elb.us-east-1.amazonaws.com"
export KEY="tm_key_0ef67ab1083909aa9bb1ab94bba339697d424506208c24e9dfbadd8aa2dcba6d"
cd ~/fiap-tc-fase2

hr() { printf '\n\033[1;32m═══════════════════════════════════════════════\033[0m\n'; }
title() { hr; printf '\033[1;33m# %s\033[0m\n' "$1"; hr; sleep 1; }
run() { printf '\033[1;36m$ %s\033[0m\n' "$*"; sleep 0.4; eval "$@"; echo; sleep 1.5; }

clear
title "TECH CHALLENGE FASE 2 — TOGGLEMASTER — DEMONSTRAÇÃO"
sleep 2

title "1/8 — Ambiente local: docker compose (9 contêineres)"
run "docker compose ps --format 'table {{.Service}}\t{{.Status}}'"
sleep 2

title "2/8 — Cluster Kubernetes provisionado na AWS (EKS)"
run "kubectl get nodes"
sleep 2

title "3/8 — Os 5 microsserviços rodando como Pods"
run "kubectl get pods -A | grep -vE 'kube-system|ingress-nginx'"
sleep 2

title "4/8 — Nginx Ingress funcionando (curl real, via NLB)"
run "curl -s http://$LB/auth/health"
run "curl -s http://$LB/flags/health"
run "curl -s http://$LB/targeting/health"
run "curl -s http://$LB/evaluate/health"
sleep 2

title "5/8 — Fluxo completo: criar flag, criar regra, avaliar"
run "curl -s -X POST http://$LB/flags/flags -H \"Authorization: Bearer $KEY\" -H 'Content-Type: application/json' -d '{\"name\":\"demo-video\",\"description\":\"gravacao TC\",\"is_enabled\":true}'"
run "curl -s -X POST http://$LB/targeting/rules -H \"Authorization: Bearer $KEY\" -H 'Content-Type: application/json' -d '{\"flag_name\":\"demo-video\",\"rules\":{\"type\":\"PERCENTAGE\",\"value\":50}}'"
run "curl -s 'http://$LB/evaluate/evaluate?user_id=video-demo&flag_name=demo-video'"
sleep 2

title "6/8 — Escalabilidade: HPA do evaluation-service (baseline)"
run "kubectl get hpa -n evaluation"
sleep 1
printf '\033[1;35mGerando carga real com ab por ~90s — acompanhando o HPA...\033[0m\n\n'
ab -n 200000 -c 60 -t 90 "http://$LB/evaluate/evaluate?user_id=load&flag_name=demo-video" >/tmp/ab-video.log 2>&1 &
ABPID=$!
for i in $(seq 1 9); do
  sleep 10
  kubectl get hpa -n evaluation
done
wait $ABPID 2>/dev/null
sleep 2

title "7/8 — Fluxo assíncrono: evaluate -> SQS -> analytics-service -> DynamoDB"
run "aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT"
printf '\033[1;35mGerando 20 novas avaliacoes...\033[0m\n\n'
for i in $(seq 1 20); do
  curl -s "http://$LB/evaluate/evaluate?user_id=demo-$i&flag_name=demo-video" >/dev/null
done
sleep 22
run "aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT"
run "aws dynamodb scan --table-name ToggleMasterAnalytics --max-items 2"
sleep 2

title "8/8 — HPA voltando ao normal (scale-down automático)"
run "kubectl get hpa -n evaluation"
run "kubectl get pods -n evaluation"

hr
printf '\033[1;33mFIM DA DEMONSTRAÇÃO — TOGGLEMASTER TECH CHALLENGE FASE 2\033[0m\n'
hr
sleep 4
