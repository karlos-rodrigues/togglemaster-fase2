# ToggleMaster — Tech Challenge Fase 2

Reescrita do ToggleMaster (monolito Flask da Fase 1) como 5 microsserviços
conteinerizados, orquestrados em Kubernetes na nuvem.

| Serviço | Linguagem | Porta | Estado |
|---|---|---|---|
| `auth-service` | Go | 8001 | chaves de API (PostgreSQL) |
| `flag-service` | Python | 8002 | CRUD das flags (PostgreSQL) |
| `targeting-service` | Python | 8003 | regras de segmentação (PostgreSQL, JSONB) |
| `evaluation-service` | Go | 8004 | hot path, decisão true/false (Redis + SQS) |
| `analytics-service` | Python | 8005 | worker SQS → DynamoDB |

O código-fonte dos 5 serviços vem de `https://github.com/FIAP-TCs`. **Os dois serviços
em Go não compilavam como entregues** — as 8 correções aplicadas estão em
[`PATCHES.md`](PATCHES.md).

## Ambiente

Todo o trabalho roda na VM isolada **`forge`**, não na workstation. O disco da VM fica
no SSD externo, junto do acervo da faculdade:

```
/media/udefault/6B7B-FF7D/FIAP - DevOps e Arquitetura Cloud - 4DCLT/tc-fase2/vm/
├── forge.qcow2        64 GB, auto-contido
├── seed.iso           cloud-init
└── noble-server-cloudimg-amd64.img
```

A VM roda em `qemu:///session` (libvirt de usuário), e não em `qemu:///system`. Isso é
deliberado: o SSD é exFAT, que não tem dono de arquivo — monta tudo como `udefault`
com permissão fixa. Em modo sistema o QEMU roda como `libvirt-qemu`, que não
conseguiria escrever ali, e o libvirt não pode corrigir com `chown` porque o
filesystem não suporta. Em modo sessão o QEMU roda como `udefault`, dono de tudo no
exFAT, e nada de global precisa ser alterado.

A rede é usermode do QEMU (`-netdev user`) com `hostfwd`, definida via
`<qemu:commandline>` — o `<portForward>` nativo do libvirt exigiria o backend `passt`,
que não está instalado na workstation.

```bash
# ciclo de vida
virsh -c qemu:///session start forge
virsh -c qemu:///session shutdown forge
virsh -c qemu:///session list --all

# acesso (portas redirecionadas do host para a VM)
ssh -p 2222 udefault@127.0.0.1     # SSH
# 8001-8005 -> mesmas portas na VM, então curl do host funciona direto
```

Instalados na VM: Docker CE + compose, kubectl, helm, eksctl, AWS CLI v2, `ab` e `wrk`.

> `hey` não foi instalado: o bucket S3 oficial devolve 403 e o release do GitHub não
> publica binário. O enunciado aceita `ab`, que está instalado, e o `wrk` cobre o
> mesmo caso com mais precisão.

## Etapa 1 — ambiente local (docker compose)

9 contêineres: 5 aplicações + 4 bancos (2 PostgreSQL, 1 Redis, 1 DynamoDB Local).

O enunciado pede 2 instâncias PostgreSQL locais para 3 serviços, então `postgres-flags`
hospeda dois bancos lógicos (`flag_db` e `targeting_db`). Na AWS viram 3 instâncias RDS
independentes, como a etapa 2 exige.

### 1. Configurar

```bash
cp .env.example .env
sed -i "s/^PG_PASSWORD=.*/PG_PASSWORD=$(openssl rand -hex 16)/" .env
sed -i "s/^MASTER_KEY=.*/MASTER_KEY=$(openssl rand -hex 24)/"  .env
# preencha AWS_SQS_URL com a fila criada na etapa 2
```

### 2. Subir

```bash
docker compose up -d --build
docker compose ps          # 9 contêineres
```

Criar a tabela no DynamoDB Local (roda e sai, não conta como 10º contêiner):

```bash
docker compose --profile bootstrap run --rm dynamodb-init
```

### 3. Chave de API de serviço

O `evaluation-service` precisa de uma chave para falar com o `flag-service` e o
`targeting-service`. Ela é criada em runtime, então a primeira subida é em duas etapas:

```bash
source .env
curl -sX POST http://localhost:8001/admin/keys \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -d '{"name": "evaluation-service-key"}' | jq -r .key
# grave o valor em SERVICE_API_KEY no .env, depois:
docker compose up -d --force-recreate evaluation-service
```

> **Cuidado:** não rode `set -a; . ./.env` antes do `docker compose`. Variável exportada
> no shell tem precedência sobre o arquivo `.env`, então o Compose injetaria o valor
> velho (vazio) e o `evaluation-service` levaria 401 do `flag-service`. Deixe o Compose
> ler o arquivo sozinho.

### 4. Fumaça

```bash
source .env
# flag + regra de 50%
curl -sX POST http://localhost:8002/flags -H "Authorization: Bearer $SERVICE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name":"enable-new-dashboard","description":"demo","is_enabled":true}'

curl -sX POST http://localhost:8003/rules -H "Authorization: Bearer $SERVICE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"flag_name":"enable-new-dashboard","rules":{"type":"PERCENTAGE","value":50}}'

# avaliação (o bucket é determinístico por user_id+flag_name)
curl -s "http://localhost:8004/evaluate?user_id=user-123&flag_name=enable-new-dashboard"
```

## Decisões de imagem

- **Go** (`auth`, `evaluation`): multi-stage, binário estático (`CGO_ENABLED=0`,
  `-trimpath -ldflags="-s -w"`), runtime `distroless/static:nonroot` — sem shell e sem
  gerenciador de pacotes na imagem final.
- **Python** (`flag`, `targeting`, `analytics`): multi-stage com virtualenv, runtime
  `python:3.11-slim`, usuário não-root (uid 10001), Gunicorn.
- `constraints.txt` trava `Werkzeug<3`: o `requirements.txt` da FIAP fixa `Flask==2.2.2`
  sem fixar o Werkzeug, e o Werkzeug 3.x quebra o import do Flask 2.2 na subida.
- `analytics-service` roda com **1 worker** do Gunicorn de propósito — o `app.py` sobe o
  consumidor SQS no import do módulo, então N workers seriam N consumidores da mesma fila
  dentro do mesmo pod, e a contagem de réplicas do HPA/KEDA deixaria de ser proporcional
  à vazão.
- `analytics-service` sobe o boto3 acima do pin da FIAP (ver
  `requirements-container.txt`) para poder apontar ao DynamoDB Local via
  `AWS_ENDPOINT_URL_DYNAMODB`, **sem editar o `app.py`**.

## Etapas 2 a 5

Pendentes da definição do ambiente de nuvem (Opção A — AWS Academy, ou Opção B — conta
pessoal). A escolha muda o provisionamento do cluster, o Ingress e a estratégia de
escalabilidade do `analytics-service` (HPA por CPU vs. KEDA por profundidade de fila).
