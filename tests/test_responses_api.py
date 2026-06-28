import time

import pytest
from fastapi.testclient import TestClient
from gpt_oss.responses_api.api_server import create_api_server


@pytest.fixture
def test_client(harmony_encoding):
    fake_tokens = harmony_encoding.encode(
        "<|channel|>final<|message|>Hey there<|return|>", allowed_special="all"
    )
    token_queue = fake_tokens.copy()

    def stub_infer_next_token(
        tokens: list[int], temperature: float = 0.0, new_request: bool = False
    ) -> int:
        nonlocal token_queue
        next_tok = token_queue.pop(0)
        if len(token_queue) == 0:
            token_queue = fake_tokens.copy()
        time.sleep(0.1)
        return next_tok

    return TestClient(
        create_api_server(infer_next_token=stub_infer_next_token, encoding=harmony_encoding)
    )


def test_health_check(test_client):
    response = test_client.post(
        "/v1/responses",
        json={
            "model": "gpt-oss-120b",
            "input": "Hello, world!",
        },
    )
    print(response.json())
    assert response.status_code == 200
