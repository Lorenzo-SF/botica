# Botica — Code Quality Audit

> **Generated**: 2026-07-18 | **Stack**: Elixir 1.19 / OTP 28  
> **Scope**: Full codebase audit — security, correctness, typespecs, coverage, OTP compliance

---

## Summary

| Metric | Value |
|--------|-------|
| **Coverage** | 68.9% |
| **Credo issues** | 2 (style: store.ex unaliased, store_test.exs unsorted alias) |
| **Dialyzer** | not run |
| **Test count** | 118 pass, 0 fail |
| **P0 findings** | 2 |
| **P1 findings** | 4 |
| **P2 findings** | 5 |
| **P3 findings** | 4 |

---

## 🔴 P0 — Critical

### 1. `Result.from_exception` called with non-Exception term

**File**: `executor.ex:205–209`

```elixir
{:error, %{error: exc}} -> Result.from_exception(check, exc)
```

When `Task.async_stream` returns `{:exit, reason}`, the `reason` is an exit tuple (e.g. `{:timeout, task}` or `{:noproc, ...}`), **not** an `Exception.t()`. Passing it to `from_exception` (`result.ex:61`) calls `Exception.message/1` which pattern-matches on `%Exception{}` and **will crash**.

**Fix**: Guard with `is_struct(exc, Exception)` or coerce via `Exception.format_exit/1` before passing.

```elixir
{:error, %{error: exc}} ->
  safe_exc = if is_struct(exc, Exception), do: exc, else: RuntimeError.exception(inspect(exc))
  Result.from_exception(check, safe_exc)
```

---

### 2. Linked `Task.async` can kill the caller

**File**: `executor.ex:172–195`

```elixir
task = Task.async(fn -> ... end)   # LINKED to caller
result = Task.await(task, effective_timeout)
```

If the task process dies with a non-normal exit before `Task.await`, the exit signal propagates to the calling process because `Task.async` links. The `catch :exit, _reason` only catches the timeout exit. A crashing check function (throwing, linked process dying) propagates unhandled.

**Fix**: Use `Task.Supervisor.async_nolink` or wrap in `Task.async_nolink`.

---

## 🟠 P1 — High

### 3. Timeout message uses wrong timeout value

**File**: `executor.ex:119–131`, line 206

When `Task.async_stream` reports `{:exit, :timeout}`, `process_results` calls:
```elixir
Result.from_timeout(check, @default_timeout)   # always 30_000ms
```

But the actual per-check timeout could be 100ms. The message says `"check exceeded 30000ms"` — **lies**.

**Fix**: Thread the effective timeout value through to `process_results`.

---

### 4. `execute_sequential/1` ignores per-check timeout

**File**: `executor.ex:79`

Always passes `@default_timeout` (30s) regardless of `check.timeout`.

**Fix**: Use `Keyword.get(check, :timeout, @default_timeout)`.

---

### 5. `Fixer.fix/2` — unreachable error return in spec

**File**: `fixer.ex:52`

```elixir
@spec fix(Types.check_results(), keyword()) :: {:ok, Types.fix_report()} | {:error, String.t()}
```

Function has no code path that produces `{:error, String.t()}`. Errors are caught and folded into `report.failed`. Spec should be just `{:ok, Types.fix_report()}`.

---

### 6. TOCTOU race in `Flags.define/2`

**File**: `flags.ex:88–97`

```elixir
created_at = case Store.get(name) do
  {:ok, existing} -> existing.created_at
  :error -> nil
end
# ... build flag ...
Store.put(flag)   # write
```

Between the read and the GenServer `handle_call`, a concurrent `define/2` call could insert a flag. The second call sees no flag, sets `created_at = nil`, then overwrites. Minor consequence (wrong `created_at`), but a correctness bug.

**Fix**: Move `created_at` logic into the GenServer `handle_call` so it's serialized.

---

## 🟡 P2 — Medium

### 7. Telemetry handlers block the GenServer

**File**: `store.ex:128, 135`

`:telemetry.execute` is called **inside** `handle_call` — slow telemetry handlers block all flag mutations. Consider `Task.start` to fire-and-forget.

---

### 8. Battery modules tested via integration only

| Module | Coverage | Gap |
|--------|----------|-----|
| `redis.ex` | 30.9% | PONG parsing never unit-tested with mock output |
| `memory.ex` | 46.9% | All parsing logic uncovered |
| `postgresql.ex` | 58.6% | No unit test with synthetic output |
| `disk.ex` | 76.4% | Index-arithmetic edge cases untested |

All rely on `@tag :integration` tests that skip in CI if services aren't running.

---

### 9. Missing `handle_info` catch-all in Store GenServer

**File**: `store.ex`

No `handle_info` clause. If the GenServer receives an unexpected message, it crashes. Adding a no-op catch-all improves resilience.

---

### 10. Typespec issues

| File:Line | Issue |
|-----------|-------|
| `types.ex:43` | `tags: [atom()] \| []` — `[atom()]` already allows `[]` |
| `executor.ex:44` | Return spec missing `{:error, String.t()}` for invalid config path |
| `fixer.ex:52` | `{:error, _}` unreachable (P1-5) |

---

### 11. `doc.ex` is completely untested

**File**: `flags/doc.ex` — **0.0% coverage**. Entire module uncovered.

---

## 🟢 P3 — Low

### 12. Anonymous telemetry handler warnings

**File**: `store_test.exs:49–66`

Every test setup re-attaches anonymous function handlers. Produces 6 performance warnings per run:
> "The function passed as a handler ... is a local function ... may cause a performance penalty"

**Fix**: Use `{Module, :function}` tuple.

### 13. `timeout` variable shadows parameter

**File**: `executor.ex:96`

```elixir
timeout = Keyword.get(opts, :timeout, @default_timeout)
```

Shadows the outer `timeout` parameter. Works correctly but confusing.

### 14. `botica.ex:87 vs 94` — same delegation, different arity

`run/1` and `run/2` delegate to `Doctor.run` with different arities. Works but worth noting.

---

## 📊 Coverage Detail

| Module | Coverage | Gap Description |
|--------|----------|-----------------|
| `doctor.ex` | ~85% | Core engine well tested |
| `executor.ex` | 87.0% | Timeout path uncovered |
| `fixer.ex` | 78.5% | `:ok` return path, error catch uncovered |
| `flags/store.ex` | ~90% | Good |
| `flags/config.ex` | 25.0% | `get/0` not tested with `Application.put_env` |
| `flags/doc.ex` | 0.0% | Completely untested |
| `batteries/disk.ex` | 76.4% | Edge cases in parsing |
| `batteries/memory.ex` | 46.9% | Parsing logic untested |
| `batteries/postgresql.ex` | 58.6% | Mock output test needed |
| `batteries/redis.ex` | 30.9% | PONG parsing untested |
| **Overall** | **68.9%** | |

---

## 🔧 Top 5 Fixes (Priority Order)

1. **Guard `from_exception` against non-Exception terms** (`executor.ex:205`) — crash P0
2. **Replace `Task.async` with `Task.async_nolink`** — prevents caller crash on task failure
3. **Fix timeout message** to use actual per-check timeout instead of hardcoded default
4. **Add unit tests for battery parsing logic** — inject mock command output directly
5. **Move TOCTOU-prone `created_at` into GenServer** — fix `Flags.define/2` race

---

## 📝 Architecture Notes

- **Good**: Clean behaviour-based check system, parallel execution via Task.async_stream
- **Good**: Auto-repair pipeline with streaming progress reports
- **Good**: ETS-backed feature flags with GenServer serialization
- **Weak**: Task linking strategy is unsafe for production workloads
- **Weak**: Battery modules mix parsing logic with OS command execution — hard to unit test
- **Weak**: No contract tests for check behaviours across batteries

---

## Cómo usar esta auditoría

### Interpretación

- **P0 (🔴)**: Debe corregirse antes de cualquier release. Riesgo de crash, seguridad, o pérdida de datos.
- **P1 (🟠)**: Debe corregirse en el próximo ciclo. Degradación significativa de calidad o seguridad.
- **P2 (🟡)**: Debe corregirse cuando se toque el módulo afectado. Deuda técnica.
- **P3 (🟢)**: Conveniencia o estilo. Bajo impacto.

### Flujo de trabajo autónomo

Este documento, junto con `ARCHITECTURE.md` (diseño del proyecto) e `INDEX.md` (navegación de docs), contiene toda la información necesaria para abordar las correcciones de forma autónoma:

1. **Lee ARCHITECTURE.md** primero — entiende el diseño, subsistemas y decisiones clave.
2. **Lee INDEX.md** — localiza los archivos y módulos relevantes.
3. **Vuelve a esta auditoría** — prioriza por severidad (P0 → P1 → P2 → P3).
4. **Para cada hallazgo**: el fichero y línea están indicados. El código fuente relevante está en `lib/`.
5. **Ejecuta `mix test --cover`** antes y después para medir el impacto.
6. **Ejecuta `mix credo --all`** para garantizar que no introduces nuevas violaciones.
7. **Si el hallazgo implica cambiar una interfaz pública**, verifica los proyectos consumidores (listados en ARCHITECTURE.md §consumed-by).

### Dependencias entre proyectos

Botica depende de **trebejo** (probes de red y comandos shell), **arrea** (ejecución de comandos), y **apero** (utilidades base). Se recomienda leer las auditorías en este orden:
1. `../apero/docs/AUDIT.md` — fundación
2. `../arrea/docs/AUDIT.md` — orquestación
3. `../trebejo/docs/AUDIT.md` — comandos shell
4. Este documento — diagnóstico

Botica es consumido por **delfos** (comando doctor). Si modificas una interfaz pública de botica (checks, batteries, flags), verifica que delfos sigue compilando.

### Checklist por severidad

**Al corregir un P0**:
- [ ] Aísla la causa raíz (línea exacta)
- [ ] Escribe un test que reproduzca el fallo **antes** de corregir
- [ ] Aplica la corrección
- [ ] Verifica que el test pasa
- [ ] Ejecuta `mix test --cover` — la cobertura no debe disminuir
- [ ] Ejecuta `mix credo --all` — cero nuevas violaciones
- [ ] Si cambia una interfaz pública, verifica proyectos consumidores

**Al corregir un P1**:
- [ ] Identifica todos los lugares donde se aplica el patrón (grep por el código similar)
- [ ] Testea el cambio (unitario + integración si aplica)
- [ ] Verifica `mix test --cover` no baja
- [ ] Si afecta a consumidores, ejecuta sus tests también

**Al corregir P2/P3**:
- [ ] Corrige cuando toques el módulo por otra razón (boy-scout rule)
- [ ] No merecen un esfuerzo dedicado si no hay un bug reportado
