# Roteiro da Demonstração — Protótipo: Gestão e Otimização de Espaços Corporativos

Este documento descreve um roteiro passo-a-passo para demonstrar o protótipo, juntamente com evidências que atendem aos requisitos do desafio (explicabilidade, governança, observabilidade e testes).

Pré-requisitos
- Ter o repositório clonado localmente: `git clone https://github.com/paulopaes216/projeto_corp_manager.git`
- Python 3.10+ instalado
- A partir da raiz do repositório, ative o ambiente virtual e instale dependências:
  ```bash
  cd projeto_corp_manager/backend
  python -m venv .venv
  source .venv/bin/activate    # Windows: .venv\Scripts\activate
  pip install -r requirements.txt
  ```

Iniciar aplicação
1. Inicie a API (FastAPI):
   ```bash
   uvicorn main:app --reload --host 0.0.0.0 --port 8000
   ```
2. Sirva a interface estática em outra porta (opcional):
   ```bash
   cd ..  # voltar para o root do repo
   python -m http.server 8001
   # abra http://localhost:8001/static/index.html
   ```

Roteiro de demonstração
Etapa 1 — Abertura do dashboard
- Abra a página estática: `http://localhost:8001/static/index.html`.
- Clique em "Carregar dados" para visualizar as salas e equipes (GET /api/rooms e GET /api/teams).

Etapa 2 — Visualizar ocupação dos andares
- A versão MVP apresenta os dados tabulares. Para indicadores por andar, use o endpoint /api/monitor após uma execução.
- Alternativamente, exporte o resultado de `/api/allocate` e calcule ocupação por floor a partir do campo `room.floor`.

Etapa 3 — Alterar dados de equipe (exemplo)
- No arquivo `backend/data/sample_data.json` altere a propriedade `size` de uma equipe (ex.: Dev-B de 18 para 25) e salve.
- Recarregue na interface ou chame novamente `/api/teams`.

Etapa 4 — Definir restrições
- No MVP, restrições são definidas como atributos nas equipes (requirements, needs_accessible, preferred_floor).
- Para demonstrar, edite `sample_data.json` para adicionar `requirements` ou `needs_accessible:true` em uma equipe.

Etapa 5 — Gerar alocação otimizada
- Clique em "Gerar Alocação Otimizada" na interface (POST /api/allocate) ou execute:
  ```bash
  curl -X POST "http://localhost:8000/api/allocate"
  ```
- O retorno inclui `allocations` com justificativas por equipe.

Etapa 6 — Visualizar justificativa (explicabilidade)
- Para cada alocação, examine o campo `justification` (em `result.allocations[*].justification`).
- Exemplo de justificativa:
  - `occupancy_pct`: porcentagem prevista
  - `resources_matched`: lista de recursos atendidos
  - `preferred_floor_ok`: se a preferência de andar foi atendida
  - `alternatives_evaluated`: quantas alternativas foram consideradas
  - `explanation`: texto resumido do porquê da escolha

Etapa 7 — Intervenção humana
- Para aceitar uma alocação, use o endpoint `POST /api/accept_allocation?execution_id=<id>` (o protótipo grava um evento de intervenção no arquivo de execuções).
- Isso demonstra que a decisão final é humana e registrada (governança).

Etapa 8 — Monitoramento e observabilidade
- Consulte `GET /api/monitor` para obter métricas simples: número de execuções, duração média, último run.
- Arquivo `backend/data/executions.json` e `backend/data/execution_example.json` são evidências de governança: cada execução possui metadados (usuário, algoritmo, contagens, duração).

Etapa 9 — Tratamento de exceções
- Para demonstrar um caso impossível, crie uma equipe com `size` maior que qualquer `room.capacity` (por exemplo, 200) e gere alocação.
- O sistema deve marcar a equipe como `room: null` e fornecer justificativa com `reason: no_candidate_found`.

Evidências a apresentar
- execution_example.json (arquivo com uma execução de exemplo já com resultado sumarizado).
- backend/data/executions.json (histórico de execuções geradas durante a demo).
- Saídas dos testes: rodar `pytest` na pasta `backend` e apresentar relatório.

Critérios de aceitação (implementados no MVP)
1. Nenhuma sala recebe mais pessoas do que sua capacidade (testado automaticamente).
2. Restrições obrigatórias (acessibilidade, equipamentos) não são ignoradas.
3. Toda recomendação possui justificativa textual/numérica.
4. Equipes não alocadas possuem motivo registrado (`no_candidate_found`).
5. Tempo de execução é registrado e exposto via endpoint de monitoramento.

Checklist para a apresentação (2–5 minutos)
- Mostrar dashboard estático carregando dados.
- Executar "Gerar Alocação Otimizada" e abrir o JSON de resultado.
- Selecionar uma equipe e explicar justificativa apresentada.
- Demonstrar uma intervenção humana (aceitar alocação) e exibir o registro em `executions.json`.
- Mostrar testes (rodar `pytest`) e a pipeline CI (link para Actions no GitHub).

Observações finais e próximos passos recomendados
- Melhorar dashboard para gráficos por andar (ocupação, disponibilidade) e visualização de mapa de andares.
- Implementar endpoint específico de explicabilidade que retorne a comparação entre as melhores alternativas avaliadas.
- Adicionar autenticação/roles para permitir ações apenas por coordenadores.
- Registrar métricas em sistema de monitoramento (Prometheus/Grafana) para produção.

---
Arquivo gerado automaticamente pelo assistente para uso como roteiro da demonstração.