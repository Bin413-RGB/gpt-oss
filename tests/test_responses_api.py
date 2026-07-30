def test_health_check(api_client):
    response = api_client.post(
        "/v1/responses",
        json={
            "model": "gpt-oss-120b",
            "input": "Hello, world!",
        },
    )
    assert response.status_code == 200
