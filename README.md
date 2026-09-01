[![CI](https://github.com/paulopaes216/projeto_corp_manager/actions/workflows/ci.yml/badge.svg)](https://github.com/paulopaes216/projeto_corp_manager/actions)

# Projeto: Sistema Inteligente de Gestão e Otimização de Espaços Corporativos

Protótipo funcional (MVP) desenvolvido para o desafio ISTQB CT-AI.

Este repositório contém um backend (FastAPI) com um motor de alocação heurístico, um frontend estático simples para demonstração, testes automatizados e pipeline CI (GitHub Actions).

Principais componentes:
- Backend: backend/main.py, backend/engine.py
- Frontend: static/index.html, static/dashboard.html
- Dados de exemplo: backend/data/sample_data.json
- Testes: tests/test_engine.py
- CI: .github/workflows/ci.yml

Como executar (local):
1. Instale Python 3.10+ e pip
2. Vá para a pasta backend
   cd backend
3. Instale dependências
   python -m venv .venv
   source .venv/bin/activate  # ou .venv\Scripts\activate no Windows
   pip install -r requirements.txt
4. Inicie a API
   uvicorn main:app --reload --host 0.0.0.0 --port 8000
5. Acesse o dashboard executivo:
   http://localhost:8000/static/dashboard.html

O motor de alocação gera justificativas, registra execuções em backend/data/executions.json e fornece observabilidade mínima (tempo de execução, contadores).

Critérios de aceitação incluídos (exemplos):
- Nenhuma sala receberá mais pessoas que sua capacidade.
- Restrições obrigatórias (acessibilidade, equipamentos obrigatórios e capacidade mínima) não serão ignoradas.
- Toda recomendação possui justificativa simplificada.
- Equipes não alocadas têm motivo registrado.
- Performance: otimização é executada em prazo aceitável (tempo medido e registrado).

Testes incluídos (pytest):
- test_capacity_constraint: garante que não aloca além da capacidade.
- test_adding_room_increases_or_equal: adicionar sala não diminui número de equipes alocadas.
- test_removing_restriction_increases_options: remover restrição não diminui possibilidades.

Evidências de governança: execuções salvas em backend/data/executions.json com metadados (usuário, algoritmo, contagens).

Observabilidade: endpoint /api/monitor retorna métricas simples.

Licença: MIT
