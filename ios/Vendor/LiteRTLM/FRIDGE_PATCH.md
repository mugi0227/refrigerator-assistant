# Deferred native release

Upstream: john-rocky/swift-litert-lm, pinned at
`1c12d404153b8e261d48da584f6f80465e294ac2` (Apache-2.0).
`UPSTREAM.json` records each original file's SHA-256. LICENSE and NOTICE are retained.

Only the native release calls in Conversation.swift and Engine.swift are changed,
plus the new DeferredNativeRelease.swift helper. Initialization, sampling, streaming,
model configuration and the precompiled LiteRT-LM 0.15.0 artifact/checksum stay upstream.

CI 38042457897 captured callback_thread -> streamCallback -> StreamContext.deinit ->
Conversation.deinit -> litert_lm_conversation_delete -> SessionAdvanced destructor.
That destructor waited for callback_thread_pool while running on that pool's callback.
The first BLUE-47 request then stopped; text warmup had already completed.

Native destruction now runs on one separate serial queue. Conversation cleanup holds
its parent Engine alive until the C conversation is deleted; engine cleanup follows
on the same queue. No timed delay or conversation accumulation is used.

The Foundation regression reproduces a destructor waiting for its own callback.
The model smoke test exercises text, two image sizes, conversation renewal and unload.
Physical iPhone image-error recovery still requires a device check.
