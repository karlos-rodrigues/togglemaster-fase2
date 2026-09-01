# Roteiro de gravação — vídeo de demonstração (até 20 min)

Comandos prontos pra copiar e colar, na ordem do enunciado. Rodar de dentro da VM `forge`
(`ssh -p 2222 udefault@127.0.0.1`, diretório `~/fiap-tc-fase2`).

## 1. Ambiente local — docker compose (até 2 min)

```bash
docker compose ps
```
Mostrar os 9 contêineres `healthy`. Já validado nesta sessão — ver Tabela 4 do relatório.

## 2. Cluster provisionado na nuvem (1 min)

```bash
kubectl get nodes
aws eks describe-cluster --name togglemaster --query 'cluster.{status:status,version:version}'
```

## 3. Os 5 microsserviços rodando como pods (1 min)

```bash
kubectl get pods -A | grep -vE 'kube-system|ingress-nginx'
```
Esperado: 9 pods, todos `1/1 Running` (5 serviços, alguns com 2 réplicas).

## 4. Nginx Ingress funcionando — curl real (2 min)

```bash
LB=abc9bb709ba2943ea8099ae621c5939a-76d2e22c4f7f64c3.elb.us-east-1.amazonaws.com
curl http://$LB/auth/health
curl http://$LB/flags/health
curl http://$LB/targeting/health
curl http://$LB/evaluate/health
```
Explicar o rewrite-target: o Ingress recebe /auth/health, o serviço só entende /health.

## 5. Fluxo completo — flag, regra e avaliação (2 min)

```bash
LB=abc9bb709ba2943ea8099ae621c5939a-76d2e22c4f7f64c3.elb.us-east-1.amazonaws.com
KEY="tm_key_0ef67ab1083909aa9bb1ab94bba339697d424506208c24e9dfbadd8aa2dcba6d"

curl -X POST http://$LB/flags/flags -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"name":"demo-video","description":"gravacao","is_enabled":true}'

curl -X POST http://$LB/targeting/rules -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"flag_name":"demo-video","rules":{"type":"PERCENTAGE","value":50}}'

curl "http://$LB/evaluate/evaluate?user_id=video-demo&flag_name=demo-video"
```

## 6. Gerar carga e mostrar o HPA escalando (3-4 min)

Num terminal, deixar rodando:
```bash
watch -n 2 kubectl get hpa -n evaluation
```
Em outro terminal, disparar a carga:
```bash
ab -n 200000 -c 60 -t 120 "http://abc9bb709ba2943ea8099ae621c5939a-76d2e22c4f7f64c3.elb.us-east-1.amazonaws.com/evaluate/evaluate?user_id=load&flag_name=demo-video"
```
Já validado nesta sessão: CPU foi de 1% para 273% e as réplicas de 2 para 4. Comentar o
trade-off HPA por CPU (Seção 7.2 e 8.4 do relatório).

## 7. Enviar mensagens e mostrar o HPA/consumo do analytics-service (2-3 min)

```bash
watch -n 2 kubectl get hpa -n analytics
for i in $(seq 1 30); do
  curl -s "http://abc9bb709ba2943ea8099ae621c5939a-76d2e22c4f7f64c3.elb.us-east-1.amazonaws.com/evaluate/evaluate?user_id=demo-$i&flag_name=demo-video" >/dev/null
done
```

## 8. Dados aparecendo no DynamoDB (1 min)

```bash
aws dynamodb scan --table-name ToggleMasterAnalytics --select COUNT
aws dynamodb scan --table-name ToggleMasterAnalytics --max-items 3
```

## 9. Falar (sem tela, ou com o relatório aberto) — 3-4 min

- Arquitetura geral (Seção 2 do relatório)
- Desafios: código não compilava (Seção 8.1), VPC isolada do eksctl (Seção 4/8.7),
  metrics-server colidindo com addon gerenciado (Seção 8.7)
- Por que HPA por CPU no analytics-service e não KEDA (Seção 8.4)
- Diferença de propósito entre RDS, ElastiCache e DynamoDB (Seção 8.5)

## Depois de gravar

```bash
# desligar os recursos que cobram por hora, se nao for continuar usando hoje
eksctl delete cluster --name togglemaster --region us-east-1
aws rds delete-db-instance --db-instance-identifier togglemaster-auth --skip-final-snapshot
aws rds delete-db-instance --db-instance-identifier togglemaster-flag --skip-final-snapshot
aws rds delete-db-instance --db-instance-identifier togglemaster-targeting --skip-final-snapshot
aws elasticache delete-cache-cluster --cache-cluster-id togglemaster-evaluation-cache
```
