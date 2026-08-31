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
