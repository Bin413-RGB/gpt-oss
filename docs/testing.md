# Testing

Install the test dependencies and run the complete suite with:

```bash
python -m pip install -e '.[test]'
python -m pytest -q
```

Some Responses API tests require the Harmony vocabulary. `openai-harmony`
downloads that asset on first use and caches it outside this repository. If the
host cannot reach the vocabulary origin, only tests that consume the encoding
are skipped; collection and all independent tests continue.

Release and connected CI jobs should make the asset mandatory:

```bash
python -m pytest -q --require-harmony-vocab
```

The same strict behavior can be enabled without changing a shared command:

```bash
GPT_OSS_REQUIRE_HARMONY_VOCAB=1 python -m pytest -q
```

Strict mode turns an unavailable vocabulary into an explicit test failure. This
prevents an offline developer environment from blocking unrelated unit tests
without allowing release validation to pass with missing integration coverage.
