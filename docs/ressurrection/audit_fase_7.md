# botica — ressurrection_fase_7: análisis meticuloso

> **Fecha**: 2026-09-12
> **Rama**: `ressurrection_fase_7`
> **Tamaño**: 33 módulos, ~4,820 LOC

---

## 1. Dominio

botica provee **Doctor + Flags + Batteries**. Es **crítico** para zaguan:

- **`Botica.Doctor`** — zaguan tiene `Zaguan.Doctor` (423 LOC) propio, limitado.
  Migrar a botica le daría: parallel checks, batteries (PostgreSQL, Redis, Disk,
  Memory, llama_server — **482 LOC solo para llama_server battery**!), auto-fix.
- **`Botica.Flags`** — feature flags con ETS + deterministic rollout. Zaguan no tiene.

**Migración zaguan → botica**: masiva. Zaguan ganaría enormemente.

---

## 2. Análisis

### P0-1 — `Botica.Doctor.run/1` no cancela checks lentos en caso de caller crash

**Archivo**: `lib/botica/doctor.ex`
**Tipo**: reliability (similar a apero/trebejo)
**Impacto**: si el caller muere durante un check, los checks en Task siguen corriendo
hasta timeout.
**Decisión**: deferido — el caller tiene la responsabilidad.

### P0-2 — `Botica.Flags.Store` es un cuello de botella

**Archivo**: `lib/botica/flags.ex`
**Tipo**: scalability
**Impacto**: writes serializados via GenServer. Para sistemas con muchos writes
concurrentes, el GenServer es el cuello de botella. Reads son O(1) ETS — OK.
**Decisión**: deferido — OK para el caso de uso típico (mutaciones raras, reads frecuentes).

---

## 3. Auto-review

botica está **bien diseñado y bien implementado**. No requiere fixes urgentes.

**Decisión**: 1 commit — añadir tests para la API pública que aún no tiene
cobertura.
