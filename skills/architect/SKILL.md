---
name: architect
description: Analiza el codigo existente para documentar arquitectura, stack tecnico y comportamiento funcional en .intermarkit/architecture.md y .intermarkit/functional.md. Si el proyecto esta vacio (greenfield), ayuda a decidir el stack junto al usuario y lo documenta. Usa siempre antes de implementar cualquier tarea si estos ficheros no existen o estan desactualizados.
---

# Architect

Documentas la arquitectura, el stack tecnico y el comportamiento funcional de un proyecto antes de que se implemente ningun cambio. Nunca se implementa codigo sin que esta documentacion exista y este razonablemente actualizada.

## Cuando actuar

- Los ficheros `.intermarkit/architecture.md` o `.intermarkit/functional.md` no existen
- El usuario pide explicitamente entender la arquitectura, el stack, o documentarlo
- Tras archivar un cambio OpenSpec que introduce un modulo, dependencia o patron nuevo (mantenimiento incremental)

## Paso 1: Determinar si el proyecto es brownfield o greenfield

Explora el repositorio (ignora `.git`, `.intermarkit`, `openspec`, `node_modules`, `.venv`, `dist`, `build`).

- **Brownfield** — hay codigo fuente real (mas que ficheros de config vacios o un README)
- **Greenfield** — el repo esta practicamente vacio, sin stack definido

## Paso 2A: Brownfield — analizar el codigo existente

Antes de escribir nada, revisa el codigo:

1. Identifica manifiestos de dependencias (`package.json`, `requirements.txt`, `pyproject.toml`, `pom.xml`, `go.mod`, `Gemfile`, etc.) para determinar lenguaje(s) y librerias/frameworks principales.
2. Identifica infraestructura: `Dockerfile`, `docker-compose.yml`, ficheros de CI/CD (`.github/workflows`, `.gitlab-ci.yml`), IaC (`terraform/`, `k8s/`).
3. Mapea la estructura de carpetas para inferir el patron arquitectonico (monolito, microservicios, capas, hexagonal, MVC, etc.) y los modulos/dominios principales.
4. Lee los puntos de entrada principales (`main`, `index`, `app.py`, controllers, routers) para entender los flujos funcionales clave: que hace el sistema, que dominios de negocio cubre, que entidades principales maneja.
5. Si existen tests, revisalos: indican comportamiento esperado y casos de uso reales.

No te limites a leer un fichero: cruza informacion entre el manifiesto de dependencias, la estructura de carpetas y el codigo real. La documentacion debe reflejar lo que el codigo REALMENTE hace, no suposiciones.

## Paso 2B: Greenfield — ayudar a definir el stack

Si el repo esta vacio o casi vacio, no inventes el stack: pregunta al usuario. Como minimo:

- Tipo de proyecto (API, web app, aplicacion movil, CLI, libreria, servicio background...)
- Lenguaje y runtime preferido
- Framework(s) principal(es) (backend y frontend si aplica)
- Base de datos / persistencia
- Como se va a desplegar (cloud, contenedores, serverless, on-premise)
- Cualquier restriccion o estandar de la consultora IntermarkIt que deba respetarse

Con las respuestas, documenta el stack decidido en `.intermarkit/architecture.md` como punto de partida. No generes codigo de scaffolding salvo que el usuario lo pida explicitamente; el objetivo aqui es dejar la decision documentada antes de empezar a implementar.

## Paso 3: Generar o actualizar los ficheros

Crea el directorio `.intermarkit/` si no existe.

### `.intermarkit/architecture.md`

```markdown
# Arquitectura y Stack Tecnico

> Generado/actualizado por el agente IntermarkIt (skill architect). Ultima actualizacion: <fecha ISO>

## Stack tecnologico
- Lenguaje(s):
- Framework(s):
- Base de datos / persistencia:
- Infraestructura y despliegue:
- CI/CD:
- Librerias/dependencias clave:

## Arquitectura
<diagrama mermaid si el sistema tiene mas de un componente/servicio>

## Modulos y capas principales
- <modulo>: <responsabilidad>

## Decisiones y convenciones tecnicas
- <decision relevante y su justificacion>
```

### `.intermarkit/functional.md`

```markdown
# Documentacion Funcional

> Generado/actualizado por el agente IntermarkIt (skill architect). Ultima actualizacion: <fecha ISO>

## Proposito del sistema
<que problema resuelve, para quien>

## Dominios / modulos funcionales
- <dominio>: <que cubre>

## Flujos principales
1. <flujo de usuario o de negocio relevante>

## Entidades clave
- <entidad>: <descripcion breve>
```

Ambos ficheros deben ser concisos: prioriza informacion util y verificable sobre relleno. Si algo no se puede determinar con confianza (brownfield con codigo ambiguo), indicalo explicitamente como "Por confirmar" en vez de inventarlo.

## Paso 4: Confirmar con el usuario

Presenta un resumen breve de lo documentado (no el fichero entero) y pregunta si es correcto o si falta algo relevante antes de continuar con la tarea original.

## Mantenimiento

Cuando un cambio OpenSpec (`/opsx-archive`) introduzca un modulo, dependencia o decision arquitectonica nueva, actualiza estos ficheros como parte del cierre del cambio, no los dejes desactualizados.
