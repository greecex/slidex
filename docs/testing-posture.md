# Testing posture

## Design principle: pure functions first

The core design principle that makes this project testable is strict separation between pure logic and side effects. Modules should assume nothing about external systems. Functions take data in, return data out. Side effects (HTTP calls, database writes, etc.) are pushed to the boundaries.

This means the bulk of the logic lives in pure functions that are trivial to test with simple input/output assertions.

## What to test

### Thoroughly (unit tests)

Use doctests liberally. Every public function should have at least one `@doc` example that doubles as a test. This serves as living documentation and catches regressions.

### Minimally or not at all

- **LiveView UI** - LiveView pages should contain only UI/presentation logic, no business logic. If a LiveView is doing something complex enough to warrant testing, that logic should be extracted into a context module and tested there instead. Full browser integration tests (Wallaby/Playwright) are expensive to write and maintain, and provide low value for an internal tool with a small user base.

## Testing tools

- ExUnit (built-in)
- Doctests (built-in, used heavily)

## Guiding rules

1. If a function does I/O, it should be a thin wrapper. Test the logic it delegates to, not the wrapper itself.
2. If you're reaching for mocks, ask whether the code can be restructured so the function under test is pure.
3. Every public function gets a `@doc` with at least one doctest.
4. Test behavior, not implementation. Assert on return values, not on internal calls.
