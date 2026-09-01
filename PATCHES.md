# Correções aplicadas ao código-fonte da FIAP

O código dos 5 microsserviços foi clonado de `https://github.com/FIAP-TCs` (5 repositórios,
`--depth 1`, em 28/08/2026). **Os dois serviços em Go não compilavam.** Nenhum dos defeitos
abaixo é ambíguo — são erros de compilação do `go build`, não escolhas de estilo.

Os 3 serviços em Python (`flag-service`, `targeting-service`, `analytics-service`) foram
clonados sem alteração.

## auth-service (Go)

| # | Arquivo | Defeito | Correção |
|---|---------|---------|----------|
| 1 | `go.mod:18` | `require github.com/jackc/pgx/v4/stdlib v4.18.3` — `stdlib` é um **pacote** dentro do módulo `pgx/v4`, não um módulo próprio. O Go rejeita: `version "v4.18.3" invalid: should be v0 or v1`. Trava qualquer comando `go`. | Linha removida. O pacote já vem via `github.com/jackc/pgx/v4`. |
| 2 | `main.go:10` | `"github.com/jackc/pgx/v4/stdlib"` importado sem `_`, mas nunca referenciado no código — é um driver, usado só pelo efeito colateral do `init()`. `imported and not used`. | Trocado para `_ "github.com/jackc/pgx/v4/stdlib"`. |
| 3 | `main.go:5` | `"fmt"` importado e não usado. | Removido. |
| 4 | `handlers.go:4-5` | `"crypto/sha256"` e `"encoding/hex"` importados e não usados — quem os usa é `key.go`, via `hashAPIKey()`. | Removidos. |
| 5 | `key.go:7` | `"fmt"` importado e não usado. | Removido. |

Além disso o repositório não tem `go.sum`; foi gerado com `go mod tidy`.

## evaluation-service (Go)

| # | Arquivo | Defeito | Correção |
|---|---------|---------|----------|
| 6 | `go.sum` | O arquivo é uma **cópia do `go.mod`** (começa com `module evaluation-service`). O Go rejeita: `malformed go.sum: wrong number of fields 2`. Trava qualquer comando `go`. | Arquivo descartado e regerado com `go mod tidy`. |
| 7 | `evaluator.go:106,133` | Usa `os.Getenv("SERVICE_API_KEY")` sem importar `"os"`. `undefined: os`. | `"os"` adicionado aos imports. |
| 8 | `evaluator.go:4` | `"context"` importado e não usado — o `ctx` usado nas chamadas ao Redis é a variável global declarada em `main.go`. | Removido. |

## Verificação

```
cd services/auth-service       && go build ./...   # ok
cd services/evaluation-service && go build ./...   # ok
```

## Observações de arquitetura (não corrigidas — são do desenho, não bugs)

- `evaluation-service` lê `SERVICE_API_KEY` com `os.Getenv` **a cada requisição**, dentro de
  `fetchFlag`/`fetchRule`, em vez de resolver uma vez no `main()` e guardar no `App`. Funciona,
  mas destoa do resto (todo o resto da config é injetado via struct `App`).
- `analytics-service` sobe o worker SQS numa thread daemon **no import do módulo**
  (`start_worker()` no escopo global). Sob Gunicorn com mais de um worker, cada processo abre
  seu próprio consumidor da mesma fila. Relevante para o dimensionamento no Kubernetes:
  1 pod = 1 worker Gunicorn é o que mantém o HPA/KEDA previsível.
- `evaluation-service` publica no SQS com `go a.sendEvaluationEvent(...)` sem
  `WaitGroup` nem contexto — se o pod morrer no meio de um rollout, o evento se perde. É
  aceitável para métrica de analytics; vale citar no relatório como trade-off consciente.
