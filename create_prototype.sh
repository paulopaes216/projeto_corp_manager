#!/usr/bin/env bash
set -e

# Cria estrutura de diretórios
mkdir -p backend/data
mkdir -p static
mkdir -p tests
mkdir -p .github/workflows

# README
cat > README.md <<'EOF'
# Projeto: Sistema Inteligente de Gestão e Otimização de Espaços Corporativos

Protótipo funcional (MVP) desenvolvido para o desafio ISTQB CT-AI.

Este repositório contém um backend (FastAPI) com um motor de alocação heurístico, um frontend estático simples para demonstração, testes automatizados e pipeline CI (GitHub Actions).

Principais componentes:
- Backend: backend/main.py, backend/engine.py
- Frontend: static/index.html
- Dados de exemplo: backend/data/sample_data.json
- Testes: tests/test_engine.py
- CI: .github/workflows/ci.yml

Como executar (local):
1. Instale Python 3.10+ e pip
2. Vá para a pasta backend
   cd backend
3. Instale dependências
   python -m venv .venv
   source .venv/bin/activate  # ou .venv\\Scripts\\activate no Windows
   pip install -r requirements.txt
4. Inicie a API
   uvicorn main:app --reload --host 0.0.0.0 --port 8000
5. Abra o frontend: abra static/index.html no navegador (ou acesse o servidor se servir estático)

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
EOF

# requirements
cat > backend/requirements.txt <<'EOF'
fastapi
uvicorn
pydantic
pytest
EOF

# backend/main.py
cat > backend/main.py <<'EOF'
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import time
import json
import uuid
from engine import AllocationEngine, Room, Team

app = FastAPI(title="Allocation Engine API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DATA_FILE = "data/sample_data.json"
EXECUTIONS_FILE = "data/executions.json"

# Load sample data
with open(DATA_FILE, "r", encoding="utf-8") as f:
    SAMPLE = json.load(f)

rooms_store: List[Room] = [Room(**r) for r in SAMPLE.get("rooms", [])]
teams_store: List[Team] = [Team(**t) for t in SAMPLE.get("teams", [])]
sectors_store = SAMPLE.get("sectors", [])

engine = AllocationEngine()

class ExecutionRecord(BaseModel):
    id: str
    timestamp: float
    user: str
    algorithm: str
    teams_analyzed: int
    rooms_analyzed: int
    teams_allocated: int
    teams_unallocated: int
    violations: int
    duration_s: float
    result_summary: Dict[str, Any]


@app.get("/api/rooms")
def get_rooms():
    return [r.dict() for r in rooms_store]

@app.get("/api/teams")
def get_teams():
    return [t.dict() for t in teams_store]

@app.post("/api/allocate")
def allocate(user: Optional[str] = "coordenador-geral"):
    start = time.time()
    result = engine.allocate(rooms_store, teams_store)
    duration = time.time() - start

    # build execution record
    record = ExecutionRecord(
        id=str(uuid.uuid4()),
        timestamp=time.time(),
        user=user,
        algorithm="allocation-engine-v1",
        teams_analyzed=len(teams_store),
        rooms_analyzed=len(rooms_store),
        teams_allocated=sum(1 for a in result['allocations'] if a['room'] is not None),
        teams_unallocated=sum(1 for a in result['allocations'] if a['room'] is None),
        violations=len(result.get('violations', [])),
        duration_s=duration,
        result_summary={
            'occupancy': result.get('occupancy', 0),
            'allocated': sum(1 for a in result['allocations'] if a['room'] is not None)
        }
    )

    # persist
    try:
        with open(EXECUTIONS_FILE, "r", encoding="utf-8") as f:
            executions = json.load(f)
    except FileNotFoundError:
        executions = []
    executions.append(record.dict())
    with open(EXECUTIONS_FILE, "w", encoding="utf-8") as f:
        json.dump(executions, f, indent=2)

    return {"record": record.dict(), "result": result}

@app.get("/api/executions")
def list_executions():
    try:
        with open(EXECUTIONS_FILE, "r", encoding="utf-8") as f:
            executions = json.load(f)
    except FileNotFoundError:
        executions = []
    return executions

@app.get("/api/monitor")
def monitor():
    # simple observability
    try:
        with open(EXECUTIONS_FILE, "r", encoding="utf-8") as f:
            executions = json.load(f)
    except FileNotFoundError:
        executions = []
    last = executions[-1] if executions else None
    avg_duration = sum(e['duration_s'] for e in executions)/len(executions) if executions else 0
    return {"runs": len(executions), "last_run": last, "avg_duration_s": avg_duration}

@app.post("/api/accept_allocation")
def accept_allocation(execution_id: str, user: Optional[str] = "coordenador-geral"):
    # For prototype, record acceptance as a new execution event
    try:
        with open(EXECUTIONS_FILE, "r", encoding="utf-8") as f:
            executions = json.load(f)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="No executions found")
    matches = [e for e in executions if e.get('id') == execution_id]
    if not matches:
        raise HTTPException(status_code=404, detail="Execution not found")
    # Append a manual intervention record
    record = {
        'id': str(uuid.uuid4()),
        'timestamp': time.time(),
        'user': user,
        'action': 'accept_allocation',
        'source_execution': execution_id
    }
    executions.append(record)
    with open(EXECUTIONS_FILE, "w", encoding="utf-8") as f:
        json.dump(executions, f, indent=2)
    return {"status": "accepted", "record": record}
EOF

# backend/engine.py
cat > backend/engine.py <<'EOF'
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import math

class Room(BaseModel):
    id: str
    floor: int
    capacity: int
    type: Optional[str] = "generic"
    resources: Optional[List[str]] = []
    accessible: bool = False
    available: bool = True

class Team(BaseModel):
    id: str
    sector: str
    size: int
    schedule: Optional[str] = None
    requirements: Optional[List[str]] = []
    priority: int = 1
    preferred_floor: Optional[int] = None
    needs_accessible: bool = False

class AllocationEngine:
    """Simple heuristic allocation engine.
    Strategy:
    - For each team (sorted by priority desc, size desc), find candidate rooms that satisfy mandatory constraints.
    - Score candidates by fit (capacity - size), floor preference, resource match, proximity (not implemented in prototype), and choose best.
    - If no candidate, mark unallocated with explanation.
    - Return allocations and basic occupancy metrics and violations.
    """

    def allocate(self, rooms: List[Room], teams: List[Team]) -> Dict[str, Any]:
        # working copies
        rooms_avail = [r for r in rooms if r.available]
        allocations = []
        violations = []
        room_assignment = {r.id: None for r in rooms_avail}

        # Sort teams: higher priority first, then larger teams
        teams_sorted = sorted(teams, key=lambda t: (-t.priority, -t.size))

        for team in teams_sorted:
            candidates = []
            for room in rooms_avail:
                # skip already assigned
                if room_assignment.get(room.id):
                    continue
                # capacity hard constraint
                if team.size > room.capacity:
                    continue
                # accessibility
                if team.needs_accessible and not room.accessible:
                    continue
                # resource constraints
                ok = True
                for req in (team.requirements or []):
                    if req not in (room.resources or []):
                        ok = False
                        break
                if not ok:
                    continue
                # floor constraint (if team has preferred floor, prefer but not mandatory)
                # candidate score: lower waste (capacity - size) better
                waste = room.capacity - team.size
                score = 100 - waste  # basic
                # prefer preferred_floor
                if team.preferred_floor is not None and team.preferred_floor == room.floor:
                    score += 20
                # resource bonus
                matched = len(set(team.requirements or []) & set(room.resources or []))
                score += matched * 10
                # small penalty for large rooms to avoid oversizing
                score -= max(0, waste - 10)
                candidates.append((score, room))

            if candidates:
                # choose best scoring candidate
                candidates.sort(key=lambda x: -x[0])
                chosen = candidates[0][1]
                room_assignment[chosen.id] = team.id
                allocations.append({
                    'team': team.dict(),
                    'room': chosen.dict(),
                    'justification': self._justify(team, chosen, candidates)
                })
            else:
                allocations.append({
                    'team': team.dict(),
                    'room': None,
                    'justification': {
                        'reason': 'no_candidate_found',
                        'details': 'Nenhuma sala disponível atende às restrições obrigatórias para essa equipe.'
                    }
                })

        # compute occupancy
        total_seats = sum(r.capacity for r in rooms_avail)
        allocated_seats = 0
        for a in allocations:
            if a['room']:
                allocated_seats += a['team']['size']
        occupancy = int((allocated_seats / total_seats) * 100) if total_seats > 0 else 0

        # violations: check for any team assigned to room where size > capacity (shouldn't happen)
        for a in allocations:
            if a['room']:
                if a['team']['size'] > a['room']['capacity']:
                    violations.append({'team': a['team']['id'], 'room': a['room']['id'], 'type': 'capacity_exceeded'})

        return {
            'allocations': allocations,
            'occupancy': occupancy,
            'violations': violations
        }

    def _justify(self, team: Team, room: Room, candidates: List[Any]) -> Dict[str, Any]:
        alternatives_evaluated = len(candidates)
        waste = room.capacity - team.size
        resources_ok = set(team.requirements or []) <= set(room.resources or [])
        pref_floor = team.preferred_floor is None or team.preferred_floor == room.floor
        return {
            'room_id': room.id,
            'room_capacity': room.capacity,
            'team_size': team.size,
            'occupancy_pct': round((team.size / room.capacity)*100, 1),
            'resources_matched': list(set(team.requirements or []) & set(room.resources or [])),
            'preferred_floor_ok': pref_floor,
            'waste_seats': waste,
            'alternatives_evaluated': alternatives_evaluated,
            'explanation': 'Sala selecionada por melhor equilíbrio entre capacidade, recursos e preferência.'
        }
EOF

# sample data
cat > backend/data/sample_data.json <<'EOF'
{
  "rooms": [
    { "id": "Sala-101", "floor": 1, "capacity": 10, "type": "meeting", "resources": ["projector"], "accessible": false, "available": true },
    { "id": "Sala-102", "floor": 1, "capacity": 30, "type": "training", "resources": ["projector","tv"], "accessible": true, "available": true },
    { "id": "Sala-201", "floor": 2, "capacity": 20, "type": "project", "resources": [], "accessible": false, "available": true },
    { "id": "Sala-301", "floor": 3, "capacity": 80, "type": "auditorium", "resources": ["stage","sound"], "accessible": true, "available": true },
    { "id": "Sala-402", "floor": 4, "capacity": 60, "type": "open", "resources": [], "accessible": false, "available": true },
    { "id": "Sala-503", "floor": 5, "capacity": 30, "type": "meeting", "resources": ["whiteboard"], "accessible": true, "available": true },
    { "id": "Sala-702", "floor": 7, "capacity": 20, "type": "project", "resources": [], "accessible": false, "available": true },
    { "id": "Sala-704", "floor": 7, "capacity": 45, "type": "project", "resources": [], "accessible": false, "available": true }
  ],
  "sectors": [
    { "name": "Tecnologia", "coordinator": "tech-lead", "total": 300 },
    { "name": "RH", "coordinator": "rh-lead", "total": 120 }
  ],
  "teams": [
    { "id": "Dev-A", "sector": "Tecnologia", "size": 42, "requirements": ["whiteboard"], "priority": 3, "preferred_floor": 7, "needs_accessible": false },
    { "id": "Dev-B", "sector": "Tecnologia", "size": 18, "requirements": [], "priority": 2, "preferred_floor": 7, "needs_accessible": false },
    { "id": "RH", "sector": "RH", "size": 28, "requirements": [], "priority": 2, "preferred_floor": 5, "needs_accessible": true },
    { "id": "Financeiro", "sector": "Financeiro", "size": 54, "requirements": [], "priority": 2, "preferred_floor": 4, "needs_accessible": false }
  ]
}
EOF

# executions file
cat > backend/data/executions.json <<'EOF'
[]
EOF

# frontend
cat > static/index.html <<'EOF'
<!doctype html>
<html lang="pt-BR">
  <head>
    <meta charset="utf-8" />
    <title>Demo - Gestão de Espaços</title>
    <style>
      body{font-family:Arial,Helvetica,sans-serif;margin:20px}
      .card{border:1px solid #ccc;padding:12px;margin:8px;border-radius:6px}
      table{border-collapse:collapse;width:100%}
      th,td{border:1px solid #ddd;padding:8px}
    </style>
  </head>
  <body>
    <h1>Sistema Inteligente de Gestão e Otimização de Espaços - Protótipo</h1>
    <div class="card">
      <button id="btnLoad">Carregar dados</button>
      <button id="btnAllocate">Gerar Alocação Otimizada</button>
    </div>

    <div class="card">
      <h2>Salas</h2>
      <pre id="rooms">-</pre>
    </div>

    <div class="card">
      <h2>Equipes</h2>
      <pre id="teams">-</pre>
    </div>

    <div class="card">
      <h2>Resultado da Alocação</h2>
      <div id="result">-</div>
    </div>

    <div class="card">
      <h2>Execuções</h2>
      <pre id="execs">-</pre>
    </div>

    <script>
      document.getElementById('btnLoad').onclick = async ()=>{
        const r = await fetch('/api/rooms');
        const rooms = await r.json();
        document.getElementById('rooms').textContent = JSON.stringify(rooms, null, 2);
        const t = await fetch('/api/teams');
        document.getElementById('teams').textContent = JSON.stringify(await t.json(), null, 2);
      }
      document.getElementById('btnAllocate').onclick = async ()=>{
        const r = await fetch('/api/allocate', {method:'POST'});
        const data = await r.json();
        document.getElementById('result').textContent = JSON.stringify(data, null, 2);
        const ex = await fetch('/api/executions');
        document.getElementById('execs').textContent = JSON.stringify(await ex.json(), null, 2);
      }
    </script>
  </body>
</html>
EOF

# tests
cat > tests/test_engine.py <<'EOF'
import json
from backend.engine import AllocationEngine, Room, Team

# Basic tests for engine

def load_sample():
    with open('backend/data/sample_data.json','r',encoding='utf-8') as f:
        return json.load(f)

def test_capacity_constraint():
    data = load_sample()
    rooms = [Room(**r) for r in data['rooms']]
    teams = [Team(**t) for t in data['teams']]
    engine = AllocationEngine()
    result = engine.allocate(rooms, teams)
    for a in result['allocations']:
        if a['room']:
            assert a['team']['size'] <= a['room']['capacity']

def test_adding_room_increases_or_equal():
    data = load_sample()
    rooms = [Room(**r) for r in data['rooms']]
    teams = [Team(**t) for t in data['teams']]
    engine = AllocationEngine()
    res1 = engine.allocate(rooms, teams)
    allocated1 = sum(1 for a in res1['allocations'] if a['room'])
    # add a room with capacity 100
    rooms.append(Room(id='Sala-999', floor=9, capacity=100, resources=[], accessible=True, available=True))
    res2 = engine.allocate(rooms, teams)
    allocated2 = sum(1 for a in res2['allocations'] if a['room'])
    assert allocated2 >= allocated1

def test_removing_restriction_increases_options():
    data = load_sample()
    rooms = [Room(**r) for r in data['rooms']]
    teams = [Team(**t) for t in data['teams']]
    # add a team with requirement that no room satisfies
    teams.append(Team(id='Team-X', sector='X', size=5, requirements=['nonexistent-equipment'], priority=1))
    engine = AllocationEngine()
    res1 = engine.allocate(rooms, teams)
    allocated1 = sum(1 for a in res1['allocations'] if a['room'])
    # remove requirement
    teams[-1].requirements = []
    res2 = engine.allocate(rooms, teams)
    allocated2 = sum(1 for a in res2['allocations'] if a['room'])
    assert allocated2 >= allocated1
EOF

# CI workflow
cat > .github/workflows/ci.yml <<'EOF'
name: CI

on: [push, pull_request]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      - name: Install dependencies
        run: |
          cd backend
          python -m pip install --upgrade pip
          pip install -r requirements.txt
      - name: Run tests
        run: |
          cd backend
          pytest -q
EOF