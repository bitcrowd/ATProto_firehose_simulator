# Architecture

This project is organized around five core components that define how simulation data is prepared, loaded, executed, and observed. This document is a high-level overview of those pieces and how they relate to each other.

## Workflow

At a high level, the system works in this order:

1. Define base data for a simulated user population.
2. Generate or import a simulation plan.
3. Run the plan through the player.
4. Observe simulation behavior through metrics exposed to Prometheus and Grafana.

## 1. Base Data

The base data component defines the starting shape of the simulated network. Its main job is to describe the userbase that will exist before simulation playback begins.

This includes userbase parameters such as user counts and follower density, along with JSON artifacts used to reuse generated userbases across runs.

Details: [Base Data](./architecture/base-data.md)

## 2. Simulation Plans

The simulation plan component defines what should happen over time during a run. It turns higher-level parameter inputs into concrete timed events for posts, follows, and sessions.

This layer supports generating plans from simulation-plan parameter JSON, importing full simulation plans from JSON, and exporting plans so they can be reused later.

Details: [Simulation Plans](./architecture/simulation-plans.md)

## 3. Bulk Creation

The bulk creation component materializes data directly into the target database. Its purpose is to seed the backing system with users, follows, posts, records, and related data without requiring live playback.

This layer can create a database userbase from base-data inputs, or it can take a simulation plan and insert the resulting data directly into the database.

Details: [Bulk Creation](./architecture/bulk-creation.md)

## 4. Player

The player is the runtime execution engine for simulation plans. It accepts a plan, starts a simulation run, and coordinates timed playback of sessions, posts, and follows.

This component is responsible for starting, stopping, and resetting simulation runs, and supports multiple concurrent players.

Details: [Player](./architecture/player.md)

## 5. Metrics

The metrics component provides observability for simulation activity. It collects counters and runtime measurements while plans are loaded and executed, then exposes that data for monitoring.

Metrics are aggregated inside the application and exposed through a Prometheus-compatible endpoint for visualization in Grafana.

Details: [Metrics](./architecture/metrics.md)
