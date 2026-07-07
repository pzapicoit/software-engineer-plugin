---
name: python-development
description: Aplica buenas practicas, convenciones y frameworks estandar de la industria para desarrollo en Python: gestion de dependencias (uv), estructura de proyecto (src layout), tipado estatico, testing con pytest, linting/formatting (ruff, mypy), frameworks web (FastAPI, Django), CLIs (Typer), ORMs (SQLAlchemy), async, logging, manejo de errores y seguridad. Usa siempre que se escriba, revise o refactorice codigo Python, se cree un proyecto Python nuevo, o el usuario pregunte por convenciones, librerias o arquitectura en Python.
---

# Python Development

Guia las decisiones tecnicas al escribir codigo Python: gestion de dependencias, estructura de proyecto, tooling de calidad, tipado, testing y eleccion de framework segun el tipo de proyecto. Aplica tanto a proyectos nuevos como a cambios en codigo Python existente.

## Cuando aplicar

- Se va a crear un proyecto o modulo Python desde cero.
- Se anade, revisa o refactoriza codigo Python en un proyecto existente.
- El usuario pregunta por convenciones, librerias, arquitectura o "buenas practicas" en Python.

Si el proyecto ya tiene convenciones propias (`pyproject.toml`, `.ruff.toml`, `setup.cfg`, o lo documentado en `.intermarkit/architecture.md`), respetalas por encima de las recomendaciones por defecto de esta skill.

## 1. Version y gestor de paquetes

- Python 3.11+ salvo restriccion del proyecto.
- Gestor por defecto: **uv** (rapido, sustituye a pip/venv/pip-tools/poetry). Si el proyecto ya usa Poetry, mantente coherente con lo existente en vez de migrar sin que lo pidan.
- Todo proyecto nuevo usa `pyproject.toml` (PEP 621) como unica fuente de metadatos y dependencias. No mezclar `requirements.txt` suelto con `pyproject.toml`, salvo lockfile de despliegue generado (`uv export`).

Comandos habituales:

```bash
uv init
uv add fastapi pydantic-settings
uv add --dev pytest pytest-cov ruff mypy pre-commit
uv run pytest
uv run ruff check . --fix
```

## 2. Estructura de proyecto

Usa **src layout** (evita imports accidentales del codigo sin instalar):

```
proyecto/
├── pyproject.toml
├── README.md
├── src/
│   └── paquete/
│       ├── __init__.py
│       └── ...
└── tests/
    └── test_*.py
```

Arbol completo por tipo de proyecto (API, CLI) y plantilla de `pyproject.toml`: ver [reference.md](reference.md#estructura-de-proyecto).

## 3. Estilo y calidad

- **Ruff** para linting + formatting (sustituye a flake8/isort/black en una sola herramienta).
- **mypy** en modo estricto (`strict = true`) para tipado estatico.
- **pre-commit** con hooks de ruff y mypy en cada commit.
- Tipar siempre: firmas de funciones publicas, atributos de clase, valores de retorno. Evitar `Any` salvo justificacion explicita en comentario.
- Nombres descriptivos, funciones pequenas y con una sola responsabilidad; preferir composicion sobre herencia profunda.

Configuracion de referencia (`ruff.toml`, `mypy` en `pyproject.toml`, `.pre-commit-config.yaml`): ver [reference.md](reference.md#configuracion-de-tooling).

## 4. Eleccion de framework segun tipo de proyecto

| Tipo de proyecto | Framework recomendado | Cuando usar otro |
|---|---|---|
| API REST / microservicio | **FastAPI** + Pydantic v2 | — |
| App web full-stack con admin/ORM propio | **Django** + Django REST Framework | Si el proyecto ya usa Django |
| CLI | **Typer** | `argparse` solo si es un script trivial de una funcion |
| Tareas asincronas / colas | **Celery** o `arq` (si el stack ya es async/await) | — |
| Scripts / automatizacion simple | Script plano con `argparse` o Typer | — |
| Testing | **pytest** + `pytest-cov` (+ `pytest-asyncio` si hay async) | — |
| Validacion y config | **Pydantic v2** / `pydantic-settings` | `dataclasses` para estructuras internas sin validacion externa |
| ORM | **SQLAlchemy 2.0** (estilo declarativo) | ORM nativo de Django si el proyecto ya es Django |
| Migraciones de BD | **Alembic** (con SQLAlchemy) | Migraciones nativas de Django si aplica |

No mezclar frameworks equivalentes en el mismo proyecto (p. ej. Flask y FastAPI a la vez, o SQLAlchemy y el ORM de Django).

Ejemplos minimos de app FastAPI y CLI con Typer: ver [reference.md](reference.md#ejemplos-de-arranque).

## 5. Testing

- Un test por comportamiento, nombrado `test_<que_verifica>`.
- Fixtures de pytest compartidas en `conftest.py`, no duplicadas en cada archivo.
- Cobertura orientativa minima: 80% en logica de negocio; no perseguir el 100% en glue code.
- Tests deterministas: mockear I/O externo (`unittest.mock`, `respx` para HTTP, `freezegun`/`time-machine` para fechas).
- Ejecutar con `uv run pytest --cov=src`.

## 6. Manejo de errores y logging

- Excepciones especificas del dominio (`class PedidoNoEncontradoError(Exception): ...`); nunca `except Exception` generico salvo en el borde de la aplicacion (handler global de errores).
- Logging con el modulo estandar `logging`, configurado en JSON estructurado si va a produccion; nunca `print()` para logs.
- Nunca silenciar excepciones (`except: pass`); si se captura, se loguea con contexto o se re-lanza.

## 7. Concurrencia async

- No mezclar codigo sincrono bloqueante (I/O de red o disco) dentro de funciones `async def` sin `await` o sin delegarlo a un executor (`asyncio.to_thread`).
- Un proyecto es async "de punta a punta" o no lo es: evitar un cliente HTTP sincrono dentro de una app FastAPI async (usar `httpx.AsyncClient`).

## 8. Seguridad

- Nunca hardcodear secretos; usar variables de entorno tipadas con `pydantic-settings`.
- Validar y sanear toda entrada externa en el borde de la aplicacion (modelos Pydantic en endpoints/CLI).
- Dependencias con versiones ancladas y auditadas periodicamente (`uv pip audit` / `pip-audit`).

## 9. Documentacion

- Docstrings estilo Google o NumPy (elegir uno y mantenerlo consistente en todo el proyecto) en funciones y clases publicas.
- README con: proposito del proyecto, instalacion (`uv sync`), como correr tests, como correr la app.

## 10. Checklist antes de dar por terminado codigo Python

- [ ] `uv run ruff check .` y `uv run ruff format .` sin errores
- [ ] `uv run mypy src` sin errores
- [ ] `uv run pytest` en verde con cobertura razonable
- [ ] Sin `print()`, `except: pass`, ni `Any` sin justificar
- [ ] Dependencias nuevas anadidas a `pyproject.toml`, no instaladas "a mano"

## Recursos adicionales

Plantillas completas (`pyproject.toml`, configuracion de ruff/mypy/pytest/pre-commit, arbol de proyecto por tipo, ejemplos minimos de FastAPI y Typer): ver [reference.md](reference.md).
