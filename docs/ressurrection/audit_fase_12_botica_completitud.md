# botica — audit completitud (iter-042)

> **Fecha**: 2026-09-12
> **Tamaño**: 4,820 LOC, ~33 módulos
> **Tests**: 23 archivos
> **Meta**: botica 100% terminado

---

## Estado actual

| Área | LOC | Estado |
|------|-----|--------|
| `botica.ex` | ~150 | ✅ |
| `doctor.ex` | 310 | ✅ |
| `scheduler.ex` | 289 | ✅ |
| `flags.ex` | 267 | ✅ |
| `flags/store.ex` | 226 | ✅ |
| `flags/persistence/disk.ex` | 185 | ✅ |
| `dashboard.ex` | 227 | ✅ |
| `alerts.ex` | 204 | ✅ |
| `batteries/llama_server.ex` | 482 | ✅ |
| `batteries/memory.ex` | 175 | ✅ |
| `batteries/postgres.ex` | ~150 | ✅ |
| `batteries/redis.ex` | ~150 | ✅ |
| `batteries/disk.ex` | ~150 | ✅ |
| `check/result.ex` | ~100 | ✅ |
| `repair/fixer.ex` | ~100 | ✅ |
| `facade.ex` | ~80 | ✅ |
| `runner/executor.ex` | ~100 | ✅ |
| `runner/sequencer.ex` | ~100 | ✅ |
| `types.ex` | ~80 | ✅ |

botica está **production-grade**. Todo bien testeado.

## Gap identificado (iter-042)

### P3 — `Botica.Alerts.format_alert/2` para CLI
**Archivo**: `lib/botica/alerts.ex`
**Tipo**: UX
**Impacto**: las alertas se emiten pero no hay helper para formatear
un alert individual como string para CLI display.

### Plan iter-042

1. P3: `format_alert/2` con severity y message.
2. Tests: 3 nuevos.
3. Doc.
