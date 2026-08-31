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
