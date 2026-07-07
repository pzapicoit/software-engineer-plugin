# Python Development — Referencia detallada

Material de apoyo para la skill `python-development`. Leer solo la seccion necesaria.

## Estructura de proyecto

### API / microservicio (FastAPI)

```
proyecto/
├── pyproject.toml
├── README.md
├── .env.example
├── src/
│   └── paquete/
│       ├── __init__.py
│       ├── main.py              # instancia de FastAPI, monta routers
│       ├── config.py             # Settings (pydantic-settings)
│       ├── api/
│       │   ├── __init__.py
│       │   └── v1/
│       │       ├── __init__.py
│       │       └── routers/
│       │           └── items.py
│       ├── domain/                # entidades y logica de negocio pura
│       ├── services/               # casos de uso, orquestacion
│       ├── repositories/           # acceso a datos (SQLAlchemy)
│       ├── schemas/                # modelos Pydantic de entrada/salida
│       └── core/
│           ├── logging.py
│           └── exceptions.py
└── tests/
    ├── conftest.py
    ├── unit/
    └── integration/
```

### CLI (Typer)

```
proyecto/
├── pyproject.toml
├── src/
│   └── paquete/
│       ├── __init__.py
│       ├── cli.py          # app = typer.Typer(); comandos
│       └── core/
└── tests/
```

### `pyproject.toml` base

```toml
[project]
name = "paquete"
version = "0.1.0"
description = ""
requires-python = ">=3.11"
dependencies = [
    "fastapi>=0.115",
    "pydantic-settings>=2.5",
]

[dependency-groups]
dev = [
    "pytest>=8.0",
    "pytest-cov>=5.0",
    "pytest-asyncio>=0.24",
    "ruff>=0.7",
    "mypy>=1.11",
    "pre-commit>=3.8",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/paquete"]
```

## Configuracion de tooling

### Ruff (`[tool.ruff]` en `pyproject.toml` o `ruff.toml`)

```toml
[tool.ruff]
line-length = 100
target-version = "py311"

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B", "SIM", "N", "ASYNC"]
ignore = []

[tool.ruff.lint.isort]
known-first-party = ["paquete"]
```

### mypy (`[tool.mypy]` en `pyproject.toml`)

```toml
[tool.mypy]
python_version = "3.11"
strict = true
mypy_path = "src"
explicit_package_bases = true
```

### pytest (`[tool.pytest.ini_options]`)

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
asyncio_mode = "auto"
addopts = "-ra --cov=src --cov-report=term-missing"
```

### `.pre-commit-config.yaml`

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.7.4
    hooks:
      - id: ruff
        args: [--fix]
      - id: ruff-format
  - repo: https://github.com/pre-commit/mirrors-mypy
    rev: v1.13.0
    hooks:
      - id: mypy
        additional_dependencies: [pydantic]
```

## Ejemplos de arranque

### FastAPI minimo con capas separadas

```python
# src/paquete/config.py
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")

    database_url: str
    log_level: str = "INFO"


settings = Settings()
```

```python
# src/paquete/schemas/item.py
from pydantic import BaseModel


class ItemCreate(BaseModel):
    name: str
    price: float


class ItemRead(ItemCreate):
    id: int
```

```python
# src/paquete/api/v1/routers/items.py
from fastapi import APIRouter, HTTPException

from paquete.schemas.item import ItemCreate, ItemRead
from paquete.services.items import ItemService

router = APIRouter(prefix="/items", tags=["items"])


@router.post("", response_model=ItemRead, status_code=201)
async def create_item(payload: ItemCreate, service: ItemService) -> ItemRead:
    try:
        return await service.create(payload)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
```

```python
# src/paquete/main.py
from fastapi import FastAPI

from paquete.api.v1.routers import items

app = FastAPI(title="Paquete API")
app.include_router(items.router, prefix="/api/v1")
```

### Excepciones de dominio + handler global

```python
# src/paquete/core/exceptions.py
class DomainError(Exception):
    """Base para errores de negocio."""


class ItemNoEncontradoError(DomainError):
    def __init__(self, item_id: int) -> None:
        super().__init__(f"Item {item_id} no encontrado")
        self.item_id = item_id
```

### CLI minima con Typer

```python
# src/paquete/cli.py
import typer

app = typer.Typer(help="CLI de paquete")


@app.command()
def saludar(nombre: str, veces: int = 1) -> None:
    """Saluda a NOMBRE el numero de VECES indicado."""
    for _ in range(veces):
        typer.echo(f"Hola, {nombre}!")


if __name__ == "__main__":
    app()
```

### Logging estructurado basico

```python
# src/paquete/core/logging.py
import logging
import sys


def configure_logging(level: str = "INFO") -> None:
    logging.basicConfig(
        level=level,
        format='{"time":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","msg":"%(message)s"}',
        stream=sys.stdout,
    )
```
