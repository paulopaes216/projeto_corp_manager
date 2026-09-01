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
