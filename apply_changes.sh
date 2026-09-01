#!/usr/bin/env bash
set -euo pipefail
echo "Aplicando alterações no repositório local..."

# Paths
BACKEND=backend
STATIC=static
GIT_MSG="Enhancements: alternatives, execution artifacts, interventions, dashboard, API tests and CI"

# Overwrite backend/engine.py
cat > $BACKEND/engine.py <<'PY'
from pydantic import BaseModel
from typing import List, Optional, Dict, Any

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
    """Simple heuristic allocation engine with explainability helpers."""

    def allocate(self, rooms: List[Room], teams: List[Team]) -> Dict[str, Any]:
        rooms_avail = [r for r in rooms if r.available]
        allocations = []
        violations = []
        room_assignment = {r.id: None for r in rooms_avail}
        teams_sorted = sorted(teams, key=lambda t: (-t.priority, -t.size))

        for team in teams_sorted:
            candidates = []
            for room in rooms_avail:
                if room_assignment.get(room.id):
                    continue
                if team.size > room.capacity:
                    continue
                if team.needs_accessible and not room.accessible:
                    continue
                ok = True
                for req in (team.requirements or []):
                    if req not in (room.resources or []):
                        ok = False
                        break
                if not ok:
                    continue
                waste = room.capacity - team.size
                score = 100 - waste
                if team.preferred_floor is not None and team.preferred_floor == room.floor:
                    score += 20
                matched = len(set(team.requirements or []) & set(room.resources or []))
                score += matched * 10
                score -= max(0, waste - 10)
                candidates.append((score, room))

            if candidates:
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

        total_seats = sum(r.capacity for r in rooms_avail)
        allocated_seats = sum(a['team']['size'] for a in allocations if a['room'])
        occupancy = int((allocated_seats / total_seats) * 100) if total_seats > 0 else 0

        for a in allocations:
            if a['room']:
                if a['team']['size'] > a['room']['capacity']:
                    violations.append({'team': a['team']['id'], 'room': a['room']['id'], 'type': 'capacity_exceeded'})

        return {
            'allocations': allocations,
            'occupancy': occupancy,
            'violations': violations
        }

    def evaluate_alternatives(self, team: Team, rooms: List[Room], k: int = 5) -> List[Dict[str, Any]]:
        candidates = []
        for room in rooms:
            if not room.available:
                continue
            if team.size > room.capacity:
                continue
            if team.needs_accessible and not room.accessible:
                continue
            ok = True
            for req in (team.requirements or []):
                if req not in (room.resources or []):
                    ok = False
                    break
            if not ok:
                continue
            waste = room.capacity - team.size
            score = 100 - waste
            if team.preferred_floor is not None and team.preferred_floor == room.floor:
                score += 20
            matched = len(set(team.requirements or []) & set(room.resources or []))
            score += matched * 10
            score -= max(0, waste - 10)
            candidates.append({'score': score, 'room': room.dict(), 'waste': waste, 'resources_matched': list(set(team.requirements or []) & set(room.resources or []))})

        candidates.sort(key=lambda x: -x['score'])
        return candidates[:k]

    def _justify(self, team: Team, room: Room, candidates: List[Any]) -> Dict[str, Any]:
        alternatives_evaluated = len(candidates)
        waste = room.capacity - team.size
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
PY

# Overwrite backend/main.py
cat > $BACKEND/main.py <<'PY'
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
import time
import json
import uuid
from engine import AllocationEngine, Room, Team
import os

app = FastAPI(title="Allocation Engine API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

static_path = os.path.join(os.path.dirname(__file__), '..', 'static')
app.mount("/static", StaticFiles(directory=static_path), name="static")

DATA_FILE = "data/sample_data.json"
EXECUTIONS_FILE = "data/executions.json"
INTERVENTIONS_FILE = "data/interventions.json"

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

    try:
        with open(EXECUTIONS_FILE, "r", encoding="utf-8") as f:
            executions = json.load(f)
    except FileNotFoundError:
        executions = []
    executions.append(record.dict())
    with open(EXECUTIONS_FILE, "w", encoding="utf-8") as f:
        json.dump(executions, f, indent=2, ensure_ascii=False)

    os.makedirs(os.path.dirname(EXECUTIONS_FILE), exist_ok=True)
    exec_filename = os.path.join(os.path.dirname(EXECUTIONS_FILE), f"execution_{record.id}.json")
    try:
        with open(exec_filename, "w", encoding="utf-8") as ef:
            json.dump({'record': record.dict(), 'result': result}, ef, indent=2, ensure_ascii=False)
    except Exception:
        pass

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
    try:
        with open(EXECUTIONS_FILE, "r", encoding="utf-8") as f:
            executions = json.load(f)
    except FileNotFoundError:
        executions = []
    last = executions[-1] if executions else None
    avg_duration = sum(e['duration_s'] for e in executions)/len(executions) if executions else 0
    total_runs = len(executions)
    total_allocated = sum(e.get('result_summary', {}).get('allocated', 0) for e in executions)
    avg_allocated = (total_allocated / total_runs) if total_runs > 0 else 0
    return {"runs": total_runs, "last_run": last, "avg_duration_s": avg_duration, "avg_allocated": avg_allocated}

@app.post("/api/accept_allocation")
def accept_allocation(execution_id: str, user: Optional[str] = "coordenador-geral"):
    try:
        with open(EXECUTIONS_FILE, "r", encoding="utf-8") as f:
            executions = json.load(f)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="No executions found")
    matches = [e for e in executions if e.get('id') == execution_id]
    if not matches:
        raise HTTPException(status_code=404, detail="Execution not found")
    record = {
        'id': str(uuid.uuid4()),
        'timestamp': time.time(),
        'user': user,
        'action': 'accept_allocation',
        'source_execution': execution_id
    }
    executions.append(record)
    with open(EXECUTIONS_FILE, "w", encoding="utf-8") as f:
        json.dump(executions, f, indent=2, ensure_ascii=False)
    return {"status": "accepted", "record": record}

@app.post("/api/intervene")
def intervene(execution_id: str, team_id: str, room_id: Optional[str] = None, action: Optional[str] = "assign", user: Optional[str] = "coordenador-geral"):
    intervention = {
        'id': str(uuid.uuid4()),
        'timestamp': time.time(),
        'user': user,
        'action': action,
        'team_id': team_id,
        'room_id': room_id,
        'source_execution': execution_id
    }
    try:
        with open(INTERVENTIONS_FILE, 'r', encoding='utf-8') as f:
            interventions = json.load(f)
    except FileNotFoundError:
        interventions = []
    interventions.append(intervention)
    with open(INTERVENTIONS_FILE, 'w', encoding='utf-8') as f:
        json.dump(interventions, f, indent=2, ensure_ascii=False)

    try:
        with open(EXECUTIONS_FILE, "r", encoding="utf-8") as f:
            executions = json.load(f)
    except FileNotFoundError:
        executions = []
    executions.append({'id': intervention['id'], 'timestamp': intervention['timestamp'], 'user': user, 'action': action, 'team_id': team_id, 'room_id': room_id, 'source_execution': execution_id})
    with open(EXECUTIONS_FILE, "w", encoding="utf-8") as f:
        json.dump(executions, f, indent=2, ensure_ascii=False)

    return {'status': 'recorded', 'intervention': intervention}

@app.get("/api/compare")
def compare():
    rooms = [r for r in rooms_store if r.available]
    rooms_sorted = sorted(rooms, key=lambda r: r.id)
    room_assign = {r.id: None for r in rooms_sorted}

    initial_alloc = []
    for team in teams_store:
        assigned = None
        for room in rooms_sorted:
            if room_assign[room.id]:
                continue
            if team.size <= room.capacity:
                if team.needs_accessible and not room.accessible:
                    continue
                if team.requirements:
                    ok = all(req in (room.resources or []) for req in team.requirements)
                    if not ok:
                        continue
                assigned = room
                room_assign[room.id] = team.id
                break
        initial_alloc.append({'team': team.dict(), 'room': assigned.dict() if assigned else None})

    optimized = engine.allocate(rooms_store, teams_store)

    def metrics(allocs, rooms_list):
        total_seats = sum(r.capacity for r in rooms_list)
        allocated_seats = sum(a['team']['size'] for a in allocs if a['room'])
        occupancy = int((allocated_seats / total_seats) * 100) if total_seats else 0
        teams_unallocated = sum(1 for a in allocs if not a['room'])
        seats_unused = total_seats - allocated_seats
        return {'occupancy': occupancy, 'allocated_seats': allocated_seats, 'teams_unallocated': teams_unallocated, 'seats_unused': seats_unused}

    metrics_initial = metrics(initial_alloc, rooms_sorted)
    allocs_for_metrics = [{'team': a['team'], 'room': a['room']} for a in optimized['allocations']]
    metrics_optimized = metrics(allocs_for_metrics, rooms_sorted)

    def build_table(allocs):
        rows = []
        for a in allocs:
            rows.append({
                'team_id': a['team']['id'],
                'team_size': a['team']['size'],
                'room_id': a['room']['id'] if a['room'] else None,
                'room_capacity': a['room']['capacity'] if a['room'] else None
            })
        return rows

    comparison = {
        'initial': metrics_initial,
        'optimized': metrics_optimized,
        'delta': {
            'occupancy_diff_pct': metrics_optimized['occupancy'] - metrics_initial['occupancy'],
            'allocated_seats_diff': metrics_optimized['allocated_seats'] - metrics_initial['allocated_seats'],
            'teams_unallocated_diff': metrics_optimized['teams_unallocated'] - metrics_initial['teams_unallocated']
        },
        'table_initial': build_table(initial_alloc),
        'table_optimized': build_table(optimized['allocations'])
    }
    return comparison

@app.get("/api/explain/{team_id}")
def explain(team_id: str, top_k: Optional[int] = 5):
    team_objs = [t for t in teams_store if t.id == team_id]
    if not team_objs:
        raise HTTPException(status_code=404, detail="Team not found")
    team = team_objs[0]
    optimized = engine.allocate(rooms_store, teams_store)
    justification = None
    for a in optimized['allocations']:
        if a['team']['id'] == team_id:
            justification = a['justification']
            break
    alternatives = engine.evaluate_alternatives(team, rooms_store, k=top_k)
    return {'team': team.dict(), 'justification': justification, 'alternatives': alternatives}
PY

# Ensure interventions file exists
mkdir -p $BACKEND/data
echo "[]" > $BACKEND/data/interventions.json

# Overwrite static/dashboard.html
cat > $STATIC/dashboard.html <<'HTML'
<!doctype html>
<html lang="pt-BR">
  <head>
    <meta charset="utf-8" />
    <title>Dashboard - Gestão de Espaços</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
      body{font-family:Arial,Helvetica,sans-serif;margin:20px}
      .row{display:flex;gap:16px}
      .card{border:1px solid #ccc;padding:12px;margin:8px;border-radius:6px;flex:1}
      pre{height:200px;overflow:auto;background:#fafafa;padding:8px}
      table{width:100%;border-collapse:collapse}
      th,td{border:1px solid #ddd;padding:6px}
    </style>
  </head>
  <body>
    <h1>Dashboard Executivo — Gestão de Espaços</h1>
    <div class="row">
      <div class="card">
        <h3>KPI</h3>
        <div id="kpis">Carregando...</div>
        <button id="btnRun">Gerar Alocação Otimizada</button>
      </div>
      <div class="card">
        <h3>Comparação: Antes x Depois</h3>
        <div id="compareSummary">-</div>
        <h4>Tabela otimizada</h4>
        <div style="overflow:auto;height:200px"><table id="tableOptim"/></div>
      </div>
    </div>

    <div class="row">
      <div class="card">
        <h3>Ocupação por Andar (simulação)</h3>
        <canvas id="chartFloor"></canvas>
      </div>
      <div class="card">
        <h3>Execuções</h3>
        <pre id="execs">-</pre>
        <h4>Intervenção manual</h4>
        <div>
          <label>Execution ID: <input id="intExec"/></label><br/>
          <label>Team ID: <input id="intTeam"/></label><br/>
          <label>Room ID: <input id="intRoom"/></label><br/>
          <button id="btnIntervene">Submeter Intervenção</button>
          <pre id="intResp">-</pre>
        </div>
      </div>
    </div>

    <div class="card">
      <h3>Salas</h3>
      <pre id="rooms">-</pre>
    </div>

    <script>
      async function loadData(){
        const rooms = await (await fetch('/api/rooms')).json();
        const teams = await (await fetch('/api/teams')).json();
        document.getElementById('rooms').textContent = JSON.stringify(rooms, null, 2);
        const monitor = await (await fetch('/api/monitor')).json();
        document.getElementById('execs').textContent = JSON.stringify(monitor, null, 2);

        document.getElementById('kpis').innerHTML = `\nTotal salas: ${rooms.length}\nTotal equipes: ${teams.length}\nExecuções: ${monitor.runs}\nDuração média (s): ${monitor.avg_duration_s.toFixed(3)}\nAlocação média: ${monitor.avg_allocated.toFixed(1)}`

        const comp = await (await fetch('/api/compare')).json();
        document.getElementById('compareSummary').textContent = `Ocupação (Antes): ${comp.initial.occupancy}% → (Depois): ${comp.optimized.occupancy}% → Δ ${comp.delta.occupancy_diff_pct}%`;

        const table = document.getElementById('tableOptim');
        table.innerHTML = '<tr><th>Equipe</th><th>Tamanho</th><th>Sala</th><th>Capacidade</th></tr>';
        for(const r of comp.table_optimized){
          const row = document.createElement('tr');
          row.innerHTML = `<td>${r.team_id}</td><td>${r.team_size}</td><td>${r.room_id || '-'}</td><td>${r.room_capacity || '-'}</td>`;
          table.appendChild(row);
        }

        const allocRes = await (await fetch('/api/allocate', {method:'POST'})).json();
        const allocs = allocRes.result.allocations;
        const floorMap = {};
        for(const a of allocs){
          if(a.room){
            const f = a.room.floor;
            floorMap[f] = (floorMap[f] || 0) + a.team.size;
          }
        }
        const labels = Object.keys(floorMap).sort((a,b)=>a-b);
        const data = labels.map(l=>floorMap[l]);

        const ctx = document.getElementById('chartFloor');
        new Chart(ctx, {
          type: 'bar',
          data: {
            labels: labels,
            datasets: [{label: 'Pessoas alocadas por andar', data: data, backgroundColor: 'rgba(54,162,235,0.5)'}]
          }
        });
      }

      document.getElementById('btnRun').onclick = async ()=>{
        const r = await fetch('/api/allocate', {method:'POST'});
        const data = await r.json();
        alert('Alocação gerada e registrada. ID: ' + data.record.id);
        await loadData();
      }

      document.getElementById('btnIntervene').onclick = async ()=>{
        const exec = document.getElementById('intExec').value;
        const team = document.getElementById('intTeam').value;
        const room = document.getElementById('intRoom').value || null;
        if(!exec || !team){
          alert('Informe execution id e team id');
          return;
        }
        const params = new URLSearchParams();
        params.append('execution_id', exec);
        params.append('team_id', team);
        if(room) params.append('room_id', room);
        params.append('action', 'assign');
        const resp = await fetch('/api/intervene?'+params.toString(), {method:'POST'});
        const j = await resp.json();
        document.getElementById('intResp').textContent = JSON.stringify(j, null, 2);
        await loadData();
      }

      loadData();
    </script>
  </body>
</html>
HTML

# Add backend API tests
mkdir -p $BACKEND/tests
cat > $BACKEND/tests/test_api.py <<'PY'
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_allocate_and_endpoints():
    r = client.post('/api/allocate')
    assert r.status_code == 200
    j = r.json()
    assert 'result' in j

    r2 = client.get('/api/explain/Dev-A')
    assert r2.status_code == 200
    ej = r2.json()
    assert 'alternatives' in ej

    r3 = client.get('/api/compare')
    assert r3.status_code == 200
    cj = r3.json()
    assert 'initial' in cj and 'optimized' in cj
PY

# Update CI workflow to produce junit xml and upload (fix path)
cat > .github/workflows/ci.yml <<'YML'
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
      - name: Run tests and generate junit
        run: |
          cd backend
          pytest -q --junitxml=report.xml
      - name: Upload test report
        uses: actions/upload-artifact@v4
        with:
          name: test-report
          path: backend/report.xml
YML

# Ensure interventions file exists in repo data
mkdir -p $BACKEND/data
if [ ! -f $BACKEND/data/interventions.json ]; then
  echo "[]" > $BACKEND/data/interventions.json
fi

# Git add / commit
git add -A
git commit -m "$GIT_MSG" || echo "Nothing to commit or commit failed."

echo "Alterações aplicadas localmente. Revise, rode os testes e faça 'git push origin main' se estiver tudo OK."