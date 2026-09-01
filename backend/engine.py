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
