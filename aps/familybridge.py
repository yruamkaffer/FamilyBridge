#!/usr/bin/env python3
"""FamilyBridge APS client. Python 3.9+, standard library only.

Credentials stay in environment; URL configuration stays on the user's machine.
No automatic retry of POSTs: a lost response may already have created a job.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile

BASE = "https://developer.api.autodesk.com/da/us-east/v3"
OAUTH = "https://developer.api.autodesk.com/authentication/v2/token"
ENGINE = "Autodesk.Revit+2024"
TERMINAL = {"success", "cancelled", "failedLimitDataSize", "failedLimitProcessingTime",
            "failedDownload", "failedUpload", "failedInstructions", "failedEnvironment", "failed"}
PARAMETERS = {"geometry": "model.skp", "metadata": "metadata.json",
              "familyTemplate": "template.rft", "result": "output.rfa"}


class BridgeError(Exception):
    pass


class HttpError(BridgeError):
    def __init__(self, status):
        self.status = status
        super().__init__(f"HTTP {status}. Confira permissões, disponibilidade e configuração.")


def transfer(url, method="GET", data=None, headers=None):
    # Never print URLs, response bodies, tokens or request headers on failure.
    try:
        req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
        with urllib.request.urlopen(req, timeout=60) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        raise HttpError(exc.code) from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise BridgeError("Falha de rede. Operações de escrita não são repetidas automaticamente; "
                          "verifique a APS antes de reenviar.") from None


class Client:
    def __init__(self):
        self.token = None
        self.expires = 0

    def authenticate(self):
        cid = os.environ.get("APS_CLIENT_ID", "").strip()
        secret = os.environ.get("APS_CLIENT_SECRET", "").strip()
        if not cid or not secret:
            raise BridgeError("Defina APS_CLIENT_ID e APS_CLIENT_SECRET no ambiente local.")
        basic = base64.b64encode((cid + ":" + secret).encode()).decode()
        body = urllib.parse.urlencode({"grant_type": "client_credentials", "scope": "code:all"}).encode()
        result = json.loads(transfer(OAUTH, "POST", body, {
            "Authorization": "Basic " + basic, "Content-Type": "application/x-www-form-urlencoded"}))
        self.token = result["access_token"]
        self.expires = time.monotonic() + max(0, result.get("expires_in", 3600) - 60)

    def api(self, method, route, body=None):
        if not self.token or time.monotonic() >= self.expires:
            self.authenticate()
        headers = {"Authorization": "Bearer " + self.token, "Accept": "application/json"}
        data = None
        if body is not None:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
        result = transfer(BASE + route, method, data, headers)
        return json.loads(result) if result else {}

    def engines(self):
        page, seen, entries = None, set(), []
        while True:
            result = self.api("GET", "/engines" + ("?" + urllib.parse.urlencode({"page": page}) if page else ""))
            entries.extend(result["data"])
            page = result.get("paginationToken")
            if not page:
                return entries
            if page in seen:
                raise BridgeError("Paginação APS repetida; consulta interrompida.")
            seen.add(page)


def identifier(value):
    if not re.fullmatch(r"[A-Za-z0-9_-]+", value):
        raise BridgeError("Identificador deve conter apenas letras, números, _ ou -.")
    return value


def activity(owner, alias="dev"):
    bundle = f"{identifier(owner)}.FamilyBridgeAutomation+{identifier(alias)}"
    return {
        "id": "FamilyBridgeRfa2024", "engine": ENGINE,
        "description": "FamilyBridge SketchUp to RFA 2024",
        "commandLine": ['"$(engine.path)\\revitcoreconsole.exe" /al "$(appbundles[' + 'FamilyBridgeAutomation' + '].path)"'],
        "appbundles": [bundle],
        "parameters": {key: {"verb": "put" if key == "result" else "get",
                              "required": True, "localName": name} for key, name in PARAMETERS.items()}}


def load_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def validate_package(folder):
    folder = Path(folder)
    for name in ("model.skp", "metadata.json"):
        if not (folder / name).is_file() or not (folder / name).stat().st_size:
            raise BridgeError("Pacote incompleto: " + name)
    meta = load_json(folder / "metadata.json")
    if not isinstance(meta, dict) or meta.get("schema_version") != 1:
        raise BridgeError("Versão de metadata.json não suportada.")
    product = meta.get("product")
    if not isinstance(product, dict) or not all(isinstance(v, str) for v in product.values()):
        raise BridgeError("product deve ser um objeto de textos.")
    if not all(product.get(k, "").strip() for k in ("code", "name")):
        raise BridgeError("Código e nome do produto são obrigatórios.")
    if product.get("category", "Generic Models") not in (
            "Generic Models", "Plumbing Fixtures", "Mechanical Equipment", "Furniture"):
        raise BridgeError("Categoria não suportada.")
    geometry = meta.get("geometry", {})
    if geometry.get("file") != "model.skp" or geometry.get("format") != "SketchUp 2020":
        raise BridgeError("O pacote deve indicar model.skp no formato SketchUp 2020.")
    return meta


def https_url(value):
    if not isinstance(value, str):
        raise BridgeError("URL ausente ou inválida.")
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
        raise BridgeError("Use URLs HTTPS sem usuário, senha ou fragmento.")
    return value


def workitem(owner, alias, config):
    args = {}
    for key in PARAMETERS:
        entry = config.get(key)
        if not isinstance(entry, dict):
            raise BridgeError("Configuração ausente: " + key)
        args[key] = {"url": https_url(entry.get("url")), "verb": "put" if key == "result" else "get"}
        headers = entry.get("headers", {})
        if not isinstance(headers, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in headers.items()):
            raise BridgeError("headers deve ser um objeto de textos.")
        if headers:
            args[key]["headers"] = headers
    if "result_download" in config:
        https_url(config["result_download"])
    return {"activityId": f"{identifier(owner)}.FamilyBridgeRfa2024+{identifier(alias)}", "arguments": args}


def write_new_json(path, value):
    # Exclusive creation prevents replacing a saved job receipt.
    with Path(path).open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)


def multipart(fields, file):
    boundary = "FamilyBridge" + uuid.uuid4().hex
    pieces = []
    for key, val in fields.items():
        if any(c in key for c in '\r\n"'):
            raise BridgeError("Campo de upload inválido.")
        pieces.append((f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{val}\r\n').encode())
    pieces.append((f'--{boundary}\r\nContent-Disposition: form-data; name="file"; '
                   'filename="bundle.zip"\r\nContent-Type: application/zip\r\n\r\n').encode())
    pieces += [Path(file).read_bytes(), f"\r\n--{boundary}--\r\n".encode()]
    return b"".join(pieces), "multipart/form-data; boundary=" + boundary


def create_version(client, resource, body):
    try:
        return client.api("POST", "/" + resource, body)
    except HttpError as exc:
        if exc.status != 409:
            raise
    update = {k: v for k, v in body.items() if k != "id"}
    return client.api("POST", f"/{resource}/{body['id']}/versions", update)


def set_alias(client, resource, name, alias, version):
    route = f"/{resource}/{name}/aliases"
    try:
        client.api("POST", route, {"id": alias, "version": version})
    except HttpError as exc:
        if exc.status != 409:
            raise
        client.api("PATCH", route + "/" + alias, {"version": version})


def publish(client, bundle, owner, alias):
    spec = activity(owner, alias)
    if ENGINE not in client.engines():
        raise BridgeError("Engine Revit 2024 não disponível. Não há troca automática de versão.")
    with zipfile.ZipFile(bundle) as archive:
        required = {"FamilyBridgeAutomation.bundle/PackageContents.xml",
                    "FamilyBridgeAutomation.bundle/Contents/FamilyBridge.addin",
                    "FamilyBridgeAutomation.bundle/Contents/FamilyBridge.Automation.dll",
                    "FamilyBridgeAutomation.bundle/Contents/DesignAutomationBridge.dll"}
        if not required.issubset(archive.namelist()):
            raise BridgeError("AppBundle incompleto. Execute package_bundle.py com DLLs compiladas.")
    result = create_version(client, "appbundles", {"id": "FamilyBridgeAutomation", "engine": ENGINE})
    params = result["uploadParameters"]
    data, content_type = multipart(params["formData"], bundle)
    transfer(https_url(params["endpointURL"]), "POST", data, {"Content-Type": content_type})
    set_alias(client, "appbundles", "FamilyBridgeAutomation", alias, result["version"])
    result = create_version(client, "activities", spec)
    set_alias(client, "activities", spec["id"], alias, result["version"])
    print("AppBundle e Activity publicados. Nenhum WorkItem iniciado.")


def stage(folder, template, config):
    paths = {"geometry": Path(folder) / "model.skp", "metadata": Path(folder) / "metadata.json",
             "familyTemplate": Path(template)}
    # Validate everything before the first upload.
    for key, path in paths.items():
        if not path.is_file() or not path.stat().st_size:
            raise BridgeError("Entrada vazia ou ausente: " + path.name)
        https_url(config[key].get("upload_url"))
        if not isinstance(config[key].get("upload_headers", {}), dict):
            raise BridgeError("upload_headers deve ser objeto.")
        if not all(isinstance(k, str) and isinstance(v, str)
                   for k, v in config[key].get("upload_headers", {}).items()):
            raise BridgeError("upload_headers deve conter apenas textos.")
    for key, path in paths.items():
        transfer(config[key]["upload_url"], "PUT", path.read_bytes(), config[key].get("upload_headers", {}))
        print("Entrada enviada: " + path.name)


def submit(client, payload, receipt):
    # Reserve the receipt before submitting. On ambiguous network errors it stays
    # on disk and prevents an accidental automatic resubmission.
    write_new_json(receipt, {"state": "submitting", "activityId": payload["activityId"]})
    result = client.api("POST", "/workitems", payload)
    job_id = result["id"]
    # Print the id first so it remains recoverable even if persisting fails.
    print("WorkItem criado: " + job_id, flush=True)
    Path(receipt).write_text(json.dumps({"id": job_id, "status": result.get("status"),
                                        "activityId": payload["activityId"]}, indent=2), encoding="utf-8")
    return job_id


def status(client, job_id, wait=0, interval=5):
    identifier(job_id)
    deadline = time.monotonic() + wait
    previous = None
    while True:
        result = client.api("GET", "/workitems/" + job_id)
        current = result["status"]
        if current != previous:
            print("Estado: " + current, flush=True)
            previous = current
        if current in TERMINAL or current.startswith("failed"):
            return result
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return result
        time.sleep(min(interval, remaining))


def download(url, output):
    data = transfer(https_url(url))
    # Basic container check only, not proof of a valid Revit family.
    if not data.startswith(bytes.fromhex("D0CF11E0A1B11AE1")):
        raise BridgeError("Saída não reconhecida como contêiner Revit; nenhum RFA salvo.")
    with Path(output).open("xb") as stream:
        stream.write(data)
    print("RFA baixado. Abra no Revit para conferir geometria, escala e parâmetros.")


def main(argv=None):
    parser = argparse.ArgumentParser(description="FamilyBridge — cliente APS Revit 2024")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("engines", help="Consultar disponibilidade; não inicia conversão")
    validate = sub.add_parser("validate", help="Validar pacote local")
    validate.add_argument("package", type=Path)
    pub = sub.add_parser("publish", help="Publicar DLLs compiladas; não inicia conversão")
    pub.add_argument("bundle", type=Path)
    job = sub.add_parser("job", help="Planejar ou enviar um WorkItem")
    job.add_argument("package", type=Path)
    job.add_argument("--urls", type=Path, required=True)
    job.add_argument("--submit", action="store_true", help="Enviar UMA conversão à APS")
    job.add_argument("--stage", action="store_true", help="Enviar entradas por PUT antes do job")
    job.add_argument("--template", type=Path)
    job.add_argument("--receipt", type=Path, default=Path("familybridge-job.json"))
    for p in (pub, job):
        p.add_argument("--owner", required=True, help="Nickname APS ou client id usado como owner")
        p.add_argument("--alias", default="dev")
    stat = sub.add_parser("status", help="Consultar/acompanhar job existente e baixar saída")
    stat.add_argument("job_id")
    stat.add_argument("--wait", type=int, default=0, help="Tempo máximo em segundos")
    stat.add_argument("--urls", type=Path)
    stat.add_argument("--output", type=Path)
    stat.add_argument("--report", type=Path, help="Salvar log APS com URLs e tokens ocultados")
    args = parser.parse_args(argv)
    client = Client()
    if args.command == "validate":
        meta = validate_package(args.package)
        print("Pacote válido: " + meta["product"]["code"] + " — " + meta["product"]["name"])
    elif args.command == "engines":
        engines = client.engines()
        print("\n".join(e for e in engines if "Revit" in e))
        return 0 if ENGINE in engines else 3
    elif args.command == "publish":
        publish(client, args.bundle, args.owner, args.alias)
    elif args.command == "job":
        validate_package(args.package)
        config = load_json(args.urls)
        payload = workitem(args.owner, args.alias, config)
        if args.stage and not args.template:
            raise BridgeError("--stage exige --template com RFT 2024 local.")
        if not args.submit:
            print("Plano válido: 1 WorkItem para " + payload["activityId"])
            print("Entradas: model.skp, metadata.json, template.rft. Saída: output.rfa.")
            print("Modo local: nenhum upload ou job enviado. Use --submit para executar.")
            return 0
        if args.receipt.exists():
            raise BridgeError("Recibo já existe. Consulte o job anterior antes de iniciar outro.")
        if ENGINE not in client.engines():
            raise BridgeError("Revit 2024 indisponível; conversão não enviada.")
        # Check the configured activity actually uses the expected engine.
        remote = client.api("GET", "/activities/" + urllib.parse.quote(payload["activityId"], safe=""))
        if remote.get("engine") != ENGINE:
            raise BridgeError("Activity usa engine diferente de Revit 2024.")
        if args.stage:
            stage(args.package, args.template, config)
        submit(client, payload, args.receipt)
    elif args.command == "status":
        if args.wait < 0:
            raise BridgeError("--wait deve ser positivo ou zero.")
        if bool(args.urls) != bool(args.output):
            raise BridgeError("Para baixar, informe --urls e --output juntos.")
        config = load_json(args.urls) if args.urls else None
        if config is not None:
            https_url(config.get("result_download"))
            if args.output.exists():
                raise BridgeError("Destino já existe; escolha outro nome de RFA.")
        result = status(client, args.job_id, args.wait)
        if args.report and result.get("reportUrl"):
            report = transfer(https_url(result["reportUrl"])).decode("utf-8", errors="replace")
            report = re.sub(r'https?://[^\s<>"\x27]+', '[URL ocultada]', report)
            report = re.sub(r'(?i)Bearer\s+[A-Za-z0-9._~+/-]+=*', 'Bearer [oculto]', report)
            with args.report.open("x", encoding="utf-8") as stream:
                stream.write(report)
            print("Relatório salvo com URLs e tokens Bearer ocultados. Revise antes de compartilhar.")
        if result["status"] == "success" and config is not None:
            download(config["result_download"], args.output)
        if result["status"] != "success":
            return 1 if result["status"] in TERMINAL or result["status"].startswith("failed") else 4
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (BridgeError, ValueError, KeyError, TypeError, OSError, zipfile.BadZipFile) as error:
        # JSON errors and filesystem errors may contain local paths but no secrets.
        print("FamilyBridge: " + (str(error) if isinstance(error, BridgeError) else
                                  "Arquivo ou resposta inválida; confira a configuração local."), file=sys.stderr)
        sys.exit(2)
