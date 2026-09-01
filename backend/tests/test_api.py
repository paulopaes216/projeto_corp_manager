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
