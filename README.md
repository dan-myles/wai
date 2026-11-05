# wai

A native World of Warcraft addon for interacting with T3 Code.

Planned architecture: a Lua addon, a SavedVariables outbox, and a local bridge
that submits actions to T3 Code and publishes addon data snapshots.
Communication synchronizes through UI reloads.
