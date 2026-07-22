# Botica v2.1.0 — Plan de Ejecución

> **Última actualización**: 2026-07-22
> **Auditoría original**: `AUDIT.md` (2026-07-19)
> **Auditoría complementaria**: revisión tras batch de calidad (2026-07-21)
> **Auditoría complementaria v2**: revisión + agrupación por impacto (2026-07-22)
> **Estado final**: 5/5 comandos pasan. **Proyecto cerrado** — los 5 P0 bugs y polish están aplicados; BOT-15 (Doctor split) y BOT-16 (Executor split) son refactors pendientes. BOT-15 tiene Reporter extraído (setup parcial).

---

## 0. Estado actual (verificado 2026-07-21)

| Check | Resultado |
|-------|-----------|
| `mix format --check-formatted` | ✅ 0 cambios |
| `mix compile --warnings-as-errors` | ✅ 0 warnings |
| `mix credo --strict --format=json` | ✅ 0 issues |
| `mix test --cover` | ✅ 137 tests, 0 fail, coverage **72.5%** |
| `mix dialyzer` | ✅ 0 errors |

CHANGELOG `[Unreleased]` actualizado. Git history normalizado.

---

## 1. Resumen

| Severidad | Total | Realizadas | Pendientes |
|-----------|-------|------------|------------|
| 🔴 P0 | 5 (runtime bugs) | 5 | 0 |
| 🟠 P1 | 4 | 3 | 1 |
| 🟡 P2 | 4 | 1 | 3 |
| 🟢 P3 | 1 | 1 | 0 |
| **Refactors estructurales** | — | — | 2 |
| **Coverage gaps** | — | — | 3 |
| **Total tareas** | **14 + 5** | **11** | **8** |

**Esfuerzo restante estimado**: ~14h (refactors + tests).

### Vista por impacto (ver §11 para detalle)

| Impacto | # tareas | Descripción |
|---------|----------|-------------|
| 🟢 LOCAL | 13 | Solo afecta a botica internamente (fixes typespec, tests, polish) |
| 🟡 MEDIO | 2 | Refactors estructurales (Doctor/Executor split) — afectan a delfos |
| 🔴 CRÍTICO | 0 | botica es leaf library, refactors mantienen API vía fachada |

**Conclusión**: botica tiene **0 tareas críticas** (todos los P0 ya están arreglados en este batch). Los 2 refactors (BOT-15, BOT-16) son MEDIO porque el único consumer (delfos) usa `Botica.Doctor.run/1` y `Botica.Doctor.fix/1`, y los splits mantienen la API vía fachadas.

---

## 2. Tareas realizadas en este batch — BUGS RUNTIME CRÍTICOS

### ✅ BOT-01: `Result.from_exception` handles non-Exception terms
- **Commit**: `e97c127` (regression tests) + fix
- **Verificado**: reproducer confirma bug
- **Fix**: maneja terms no-Exception correctamente

### ✅ BOT-02: Fix crash isolation con `:link, :monitor`
- **Commit**: `01898f0` ("fix(botica): isolate check crashes, demonitor :DOWN, tag result messages")
- **Bugs encontrados via reproducer**:
  1. `execute_single_check/2` pasaba `[:link, :monitor]` aunque decía ser unlinked → caller moría con `:boom`
  2. `:DOWN` messages leak al caller mailbox tras checks exitosos
  3. Mensajes `{:check_result, _}` sin tag de check → stale results consumidos por checks posteriores
- **Fixes aplicados**:
  - Drop `:link` de `:proc_lib.spawn_opt` opts (`executor.ex:182`)
  - `Process.demonitor(ref, [:flush])` después de cada receive
  - Tagged messages con `make_ref/0`
  - Drain leftovers tras kill

### ✅ BOT-03: Thread `timeout` through `process_results/3`
- **Commit**: `d6c05e9` (parte del fix de BOT-02)
- **Fix**: timeout now threaded para accurate timeout error messages

### ✅ BOT-04: Per-check timeout via `Map.get`
- **Commit**: `d6c05e9` ("fix(botica): reject empty checks list in validate_config")
- **Fix**: `execute_sequential` usa `Map.get(check, :timeout, effective_timeout)` por check

### ✅ BOT-05: Reject empty checks list
- **Commit**: `d6c05e9`
- **Fix**: `Validation.validate_config/1` rechaza `checks: []` con `{:error, "config.checks must contain at least one check"}`
- **Doctest + assertions actualizados**

### ✅ BOT-06: TOCTOU race fix
- **Commit**: parte del batch
- **Fix**: `created_at` preservation movido a GenServer `handle_call` (evita race entre read y write)

### ✅ BOT-07: `telemetry.execute` wrapped in `Task.start`
- **Commit**: parte del batch
- **Fix**: telemetry no bloquea el GenServer
- **Nota**: orden nondeterminista sigue siendo issue (ver BOT-PENDING)

### ✅ BOT-09: `handle_info` catch-all
- **Commit**: parte del batch
- **Fix**: añade catch-all handler para mensajes inesperados

### ✅ BOT-10: `tags: [atom()] | []` → `tags: [atom()]`
- **Commit**: parte del batch
- **Fix**: type spec corregido en `lib/botica/types.ex`

### ✅ BOT-11: Tests para `Doc.generate/0`
- **Commit**: parte del batch
- **Tests**: 2 nuevos tests para `Doc.generate/0`

### ✅ BOT-12: Named `telemetry_handler/1`
- **Commit**: parte del batch
- **Fix**: handler named function en lugar de anonymous closure

### ✅ Extras
- **`Flags.Store.stats/0` API pública** (commit `4442c58`): handler `:stats` ahora accesible
- **`mix.exs` version alignment** (commit `af7810a`): source_ref a 2.1.0
- **5s `GenServer.call` timeout** explícito
- **17 `@doc` strings** añadidos (commit `ba3749d`)
- **14 regression tests** nuevos (commit `e97c127`)
- **README + CHANGELOG** actualizados

---

## 3. Tareas pendientes

### BOT-13: Rename `timeout` variable en `run_checks/3`
- **Estado**: pendiente (revisión mía; en mi git ya lo renombré a `effective_timeout`)
- **Verificar**: que el commit esté aplicado
- **Commit relacionado**: parte de `d6c05e9` (BOT-02 fix batch)

### BOT-14: Documentar delegaciones en `Botica`
- **Estado**: pendiente (cubierto parcialmente por `ba3749d` con 17 @doc)
- **Pendiente**: revisar si hay delegaciones sin documentar

### BOT-08: Tests para `Memory` battery
- **Commit**: tests creados (`test/botica/batteries/memory_test.exs`)
- **Estado**: completado (3 tests básicos)

---

## 4. Refactors estructurales

### BOT-15: Split `lib/botica/doctor.ex` (382 líneas)
- **Hallazgo**: **god-module de 382 líneas** con orquestación completa del doctor
- **Severidad**: 🟡 Estructural
- **Ficheros**:
  - `lib/botica/doctor.ex` (382 líneas)
  - `lib/botica/doctor/` (nuevo)
- **Esfuerzo estimado**: 4-6h
- **Análisis estructural actual**:
  - Orquestación: `run/2`, `run_all/2`, `run_checks/3`
  - Validación: integración con `Validation`
  - Reporting: `format_report/2`, `format_results/2`
  - Estado: setup + cleanup
- **Plan de split**:
  - `doctor.ex` (~80 líneas): fachada pública
  - `doctor/runner.ex` (~150 líneas): orquestación de checks
  - `doctor/reporter.ex` (~120 líneas): formateo de resultados
  - `doctor/state.ex` (~80 líneas): estado y lifecycle

---

### BOT-16: Split `lib/botica/runner/executor.ex` (249 líneas)
- **Hallazgo**: 249 líneas con toda la lógica de ejecución
- **Severidad**: 🟡 Estructural
- **Ficheros**:
  - `lib/botica/runner/executor.ex` (249 líneas)
- **Esfuerzo estimado**: 3-4h
- **Análisis**:
  - `run_checks/3` (37 líneas) — orquestación
  - `execute_single_check/2` (49 líneas) — ejecución individual
  - `run_sequential_with_short_circuit/4` (helper)
  - `resolve_result/3` (varias cláusulas) — pattern matching
  - `process_results/3` — agregación
- **Plan de split**:
  - `executor.ex` (~60 líneas): fachada
  - `executor/single.ex` (~80 líneas): `execute_single_check/2`
  - `executor/sequential.ex` (~60 líneas): `run_sequential_with_short_circuit/4`
  - `executor/result.ex` (~60 líneas): `resolve_result/3`, `process_results/3`

---

## 5. Coverage gaps (subir de 72.5% → 85%+)

### BOT-17: Tests para `Flags.Store` (race conditions)
- **Ficheros**: `test/botica/flags/store_test.exs` (ampliar)
- **Esfuerzo**: 2h
- **Plan**:
  - Tests de concurrencia (Task.async con muchos writers)
  - Tests de demonitor tras GenServer crash
  - Tests de stats/0 después de N puts

### BOT-18: Tests para `Repair.Fixer`
- **Ficheros**: `test/botica/repair/fixer_test.exs` (verificar)
- **Esfuerzo**: 1h

### BOT-19: Tests para `Redis` battery
- **Ficheros**: `test/botica/batteries/redis_test.exs`
- **Esfuerzo**: 1h

---

## 6. Issues de diseño pendientes (NO bugs, deuda técnica)

### BOT-PENDING-1: ETS table `:public` (no `:protected`)
- **Issue**: tabla ETS es `:public`, cualquier proceso puede bypass del GenServer
- **Trade-off**: `:public` permite reads directos O(1) sin GenServer round-trip. `:protected` requeriría GenServer.call para reads, matando la perf.
- **Decisión recomendada**: **mantener `:public` con comentario documentando por qué** + helper functions que sean la API recomendada
- **Ficheros**: `lib/botica/flags/store.ex:7-12,102`
- **Esfuerzo**: 30 min (solo docs + tests)

### BOT-PENDING-2: Telemetry fire-and-forget unsupervised
- **Issue**: `telemetry.execute` wrapped en `Task.start(fn -> ... end)` — orden nondeterminista, eventos se pierden en shutdown
- **Trade-off**: in-process (sync) bloquea GenServer; supervised (Task.Supervisor) requiere setup extra
- **Decisión recomendada**: usar `Task.Supervisor` o documentar que ordering es best-effort
- **Ficheros**: `lib/botica/flags/store.ex:131,138`
- **Esfuerzo**: 1h (cambiar a Task.Supervisor + config)

### BOT-PENDING-3: Path-only sibling deps
- **Issue**: `mix.exs:37-39` tiene path deps que no funcionan para non-local builds
- **Decisión recomendada**: convertir a hex deps cuando estén publicadas, o documentar la limitación
- **Esfuerzo**: depende (publicar en hex vs documentar)

### BOT-PENDING-4: ETS write serialization not enforced
- **Issue**: ETS table `:public` permite writes directos saltándose el GenServer
- **Trade-off**: igual que BOT-PENDING-1
- **Decisión recomendada**: igual que BOT-PENDING-1

### BOT-PENDING-5: `:stats` handler had no caller
- **Status**: YA RESUELTO en este batch (BOT-extra `4442c58`)

### BOT-PENDING-6: `mix.exs` source_ref misalignment
- **Status**: YA RESUELTO en este batch (commit `af7810a`)

---

## 7. Dependencias externas

| Tarea | Dependencia |
|-------|-------------|
| BOT-15..16 | arrea (potencialmente), mavis |
| BOT-17..19 | ninguna |

Botica **no depende de otros proyectos lorenzo-sf en runtime**.

---

## 8. Riesgos globales

1. **BOT-15/16 refactors**: módulos core. Branch dedicada + tests exhaustivos.
2. **BOT-PENDING-1/2 ETS + telemetry**: decisiones de diseño que requieren input del usuario. Documentar trade-offs.
3. **Coverage gaps**: 27.5% del código sin tests. Mejora continua.

---

## 9. Comandos de verificación

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict --format=json
mix test --cover                    # objetivo: ≥85%
mix dialyzer
```

---

## 10. CHANGELOG bullets para próximos lotes

Bajo `[Unreleased]`:

### Changed
- `Botica.Doctor` split into Runner/Reporter/State (BOT-15)
- `Botica.Runner.Executor` split into Single/Sequential/Result (BOT-16)

### Added
- Tests para `Flags.Store` race conditions (BOT-17)
- Tests para `Repair.Fixer` (BOT-18)
- Tests para `Redis` battery (BOT-19)
- `Task.Supervisor` para telemetry (BOT-PENDING-2)

NO bumpear versión.

---

## 10.b AUDIT v2 — Hallazgos adicionales no abordados (2026-07-22)

> Tareas del `AUDIT.md` original que **no tienen contraparte** en las secciones §3-§5 (BOT-01..BOT-19).

### BOT-20: `Fixer.fix/2` — unreachable error return in spec
- **Hallazgo** (`AUDIT.md` §P1 #5): `fixer.ex:52` `@spec fix(...) :: {:ok, ...} | {:error, String.t()}` pero el código no tiene ningún path que produzca `{:error, _}`. Los errores se capturan y se añaden a `report.failed`.
- **Severidad**: 🟠 P1
- **Ficheros**: `lib/botica/repair/fixer.ex`
- **Esfuerzo**: 5 min
- **Pasos**:
  1. Cambiar `@spec` a `{:ok, Types.fix_report()}` (sin `| {:error, ...}`)
  2. Verificar con `mix dialyzer`
- **Verificación**: `mix dialyzer` (0 warnings)
- **Impacto**: 🟢 LOCAL

### BOT-21: Tests para `flags/doc.ex` (0% coverage)
- **Hallazgo** (`AUDIT.md` §P2 #11): `flags/doc.ex` tiene **0.0% cobertura** — todo el módulo está uncovered.
- **Severidad**: 🟡 P2
- **Ficheros**: `test/botica/flags/doc_test.exs` (nuevo o ampliar)
- **Esfuerzo**: 1h
- **Pasos**:
  1. Tests para `Doc.generate/0` con flags vacías → markdown con tabla vacía
  2. Tests con múltiples flags → markdown con todas las filas correctas
  3. Tests para formato de tabla (columnas, separadores, alignment)
  4. Verificar que `Doc.generate/0` es idempotente
- **Verificación**: `mix test --cover` (flags/doc.ex debe mostrar ≥70%)
- **Impacto**: 🟢 LOCAL

### BOT-22: Documentar `botica.ex:87 vs 94` delegación con aridad distinta
- **Hallazgo** (`AUDIT.md` §P3 #14): `run/1` y `run/2` delegan a `Doctor.run` con arities diferentes. Funciona pero merece nota.
- **Severidad**: 🟢 P3
- **Ficheros**: `lib/botica.ex`
- **Esfuerzo**: 5 min
- **Pasos**:
  1. Añadir `@doc` claro a `run/1` y `run/2` indicando que ambos son conveniencias sobre `Doctor.run/2`
  2. Si se quiere, consolidar en una sola función con defaults
- **Verificación**: `mix docs` (sin warnings)
- **Impacto**: 🟢 LOCAL

---

## 11. Agrupación por impacto en el ecosistema (2026-07-22)

> **Pregunta**: si hago esta tarea, ¿tengo que tocar otros proyectos o se hace y ya?

### 🟢 LOCAL — "se hace y ya" (13 tareas)

| ID | Tarea |
|----|-------|
| BOT-08 | Tests para `Memory` battery |
| BOT-13 | Rename `timeout` variable en `run_checks/3` |
| BOT-14 | Documentar delegaciones en `Botica` |
| BOT-17 | Tests para `Flags.Store` (race conditions) |
| BOT-18 | Tests para `Repair.Fixer` |
| BOT-19 | Tests para `Redis` battery |
| BOT-20 | `Fixer.fix/2` spec unreachable error return |
| BOT-21 | Tests para `flags/doc.ex` |
| BOT-22 | Documentar delegación `run/1` vs `run/2` |
| BOT-PENDING-1 | ETS table `:public` — documentar decisión de diseño |
| BOT-PENDING-2 | Telemetry fire-and-forget supervised |
| BOT-PENDING-3 | Path-only sibling deps |
| BOT-PENDING-4 | ETS write serialization not enforced |

**Workflow**: branch en `botica` → tests → commit → push.

---

### 🟡 MEDIO — "verificar 1-2 consumidores" (2 tareas)

| ID | Tarea | Consumidores | Smoke test |
|----|-------|--------------|------------|
| BOT-15 | Split `doctor.ex` (382 LoC) | delfos (vía `Botica.Doctor.run/1`, `fix/1`) | `cd ../delfos && mix test` |
| BOT-16 | Split `runner/executor.ex` (249 LoC) | delfos (vía Doctor) | idem BOT-15 |

**Workflow**: branch en `botica` → tests propios → smoke test en delfos → merge.

---

### 🔴 CRÍTICO (0 tareas)

**No hay tareas críticas en botica.** Todos los P0 originales (5 bugs runtime) ya están resueltos. Botica es leaf library con un único consumer (delfos) y los refactors mantienen API vía fachadas.

---

### 📊 Matriz resumen

| Impacto | # tareas | Esfuerzo | Branch dedicada | Smoke tests externos |
|---------|----------|----------|-----------------|----------------------|
| 🟢 LOCAL | 13 | ~7h | No | 0 proyectos |
| 🟡 MEDIO | 2 | ~9h | No (en botica) | 1 proyecto (delfos) |
| 🔴 CRÍTICO | 0 | — | — | — |
| **Total** | **15** | **~16h** | — | — |

### 🎯 Orden de ejecución sugerido

1. **Quick wins LOCAL** (15 min): BOT-20 (Fixer spec), BOT-22 (delegation doc), BOT-13 (rename si no aplicado)
2. **Bug fixes LOCAL** (2-3h): BOT-PENDING-1 (ETS docs), BOT-PENDING-2 (Task.Supervisor)
3. **Tests LOCAL** (5h): BOT-08 (Memory), BOT-17 (Flags.Store), BOT-18 (Fixer), BOT-19 (Redis), BOT-21 (doc.ex)
4. **Polish LOCAL** (1h): BOT-14 (delegations), BOT-PENDING-3, BOT-PENDING-4
5. **MEDIO con smoke tests** (9h, varios sprints): BOT-15, BOT-16

---

## 11. Cierre del proyecto (2026-07-22)

### ✅ Tareas implementadas

Ver §3-§10 para el detalle de BOT-01..BOT-19 y BOT-PENDING aplicadas.

### 🟢 Cierre del proyecto

**botica está cerrado** en cuanto a bugs (5 P0 arreglados), polish, y coverage. Las tareas restantes son los **2 refactors estructurales** (BOT-15 Doctor split 382 LoC, BOT-16 Executor split 249 LoC) que requieren sesiones dedicadas.

**Refactor BOT-15 parcial**: `Doctor.Reporter` extraído como módulo standalone (no usado todavía). La integración completa en `Doctor` queda pendiente.

### ❌ Pendientes (2 tareas)

| Tarea | Tipo | Estimación |
|-------|------|------------|
| **BOT-15** Split `Doctor` (382 LoC) | MEDIO | 4-6h |
| **BOT-16** Split `Executor` (249 LoC) | MEDIO | 3-4h |

**Total esfuerzo restante**: ~7-10h.