# BAML Star Demo

This demo is an agentic topic-to-article workflow for showing BAML in the playground graph.

The main entrypoint is `BuildTopicPackage(topic)`. Its `//#` comments mark graph nodes:

- validate the contract
- create a typed topic plan with an LLM function
- fan out cover-image planning and research in parallel
- draft from structured research
- assemble a typed article package

Useful commands:

```bash
baml check
baml test
baml run -e 'BuildTopicPackageSafe("tiny")'
baml run -e 'demo_describe_targets()'
baml describe ArticlePackage --budget 160
baml generate
python python/render_brief.py
```

`python/render_brief.py` is only a caller sketch. It expects `baml generate` to create `python/baml_sdk` and the Python BAML runtime package to be installed in the active environment. For this toolchain, the generated SDK header says `pip install baml`.
