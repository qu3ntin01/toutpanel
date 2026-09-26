from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from toutpanel.api.deps import current_user, fail, ok
from toutpanel.platform import get_platform
from toutpanel.services import docker, software, tasks

router = APIRouter(prefix="/api/software", tags=["software"], dependencies=[Depends(current_user)])


@router.get("")
def catalog():
    plat = get_platform()
    return ok({"items": software.catalog(), "package_manager": plat.package_manager(), "family": software.distro_family()})


@router.post("/{item_id}/install")
def install(item_id: str):
    try:
        tid = software.install(item_id)
    except ValueError as e:
        fail(str(e))
    return ok({"task_id": tid}, "Installation lancée")


@router.post("/{item_id}/remove")
def remove(item_id: str):
    try:
        tid = software.remove(item_id)
    except ValueError as e:
        fail(str(e))
    return ok({"task_id": tid}, "Suppression lancée")


class ActionIn(BaseModel):
    action: str


@router.post("/{item_id}/service")
def service(item_id: str, data: ActionIn):
    try:
        err = software.service_action(item_id, data.action)
    except ValueError as e:
        fail(str(e))
    if err:
        fail(err)
    return ok(msg=f"{item_id} : {data.action} OK")


# ----------------------------------------------------------------------------- Docker
docker_router = APIRouter(prefix="/api/docker", tags=["docker"], dependencies=[Depends(current_user)])


@docker_router.get("")
def docker_overview():
    if not docker.available():
        return ok({"available": False, "containers": [], "images": []})
    try:
        return ok({"available": True, "containers": docker.containers(), "images": docker.images(), "stats": docker.stats()})
    except RuntimeError as e:
        fail(str(e))


@docker_router.post("/containers/{cid}/{action}")
def container_action(cid: str, action: str):
    try:
        err = docker.container_action(cid, action)
    except ValueError as e:
        fail(str(e))
    if err:
        fail(err)
    return ok(msg=f"Conteneur : {action} OK")


@docker_router.get("/containers/{cid}/logs")
def container_logs(cid: str, tail: int = 200):
    return ok({"content": docker.logs(cid, tail)})


@docker_router.delete("/images/{iid}")
def remove_image(iid: str):
    err = docker.remove_image(iid)
    if err:
        fail(err)
    return ok(msg="Image supprimée")


class PullIn(BaseModel):
    image: str


@docker_router.post("/pull")
def pull(data: PullIn):
    tid = tasks.run_in_background(f"docker pull {data.image}", lambda log: docker.pull(data.image, log))
    return ok({"task_id": tid}, "Téléchargement lancé")


class RunIn(BaseModel):
    image: str
    name: str = ""
    ports: list[str] = []
    env: list[str] = []
    volumes: list[str] = []
    restart: str = "unless-stopped"


@docker_router.post("/run")
def run(data: RunIn):
    try:
        cid = docker.run_container(data.image, data.name, data.ports, data.env, data.volumes, data.restart)
    except (RuntimeError, ValueError) as e:
        fail(str(e))
    return ok({"id": cid}, "Conteneur démarré")
