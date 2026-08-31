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
