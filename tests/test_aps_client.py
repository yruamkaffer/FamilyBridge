"""Offline contract/failure tests. No Autodesk account, Ruby or Revit required."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

BASE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("familybridge", BASE / "aps/familybridge.py")
fb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fb)


class Tests(unittest.TestCase):
    def config(self):
        return {key: {"url": "https://example.org/" + filename} for key, filename in fb.PARAMETERS.items()}

    def package(self, folder):
        (folder / "model.skp").write_bytes(b"mock only: not a real SketchUp file")
        meta = {"schema_version": 1, "product": {"code": "ABC", "name": "Torneira çã"},
                "geometry": {"file": "model.skp", "format": "SketchUp 2020"}}
        (folder / "metadata.json").write_text(json.dumps(meta), encoding="utf-8")
        return meta

    def test_offline_plan_makes_no_network_calls(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(fb, "transfer") as network:
            folder = Path(tmp)
            self.package(folder)
            config = folder / "urls.json"
            config.write_text(json.dumps(self.config()))
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(0, fb.main(["job", str(folder), "--urls", str(config), "--owner", "owner"]))
            network.assert_not_called()
            self.assertIn("nenhum upload", output.getvalue())

    def test_invalid_schema_and_missing_product_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            meta = self.package(folder)
            meta["schema_version"] = 2
            (folder / "metadata.json").write_text(json.dumps(meta))
            with self.assertRaises(fb.BridgeError):
                fb.validate_package(folder)
            meta["schema_version"] = 1
            meta["product"]["code"] = " "
            (folder / "metadata.json").write_text(json.dumps(meta))
            with self.assertRaises(fb.BridgeError):
                fb.validate_package(folder)

    def test_pagination_uses_page_and_returns_second_page(self):
        client = fb.Client()
        with patch.object(client, "api", side_effect=[{"data": ["A"], "paginationToken": "a+b="},
                                                     {"data": [fb.ENGINE]}]) as api:
            self.assertEqual(["A", fb.ENGINE], client.engines())
            self.assertEqual("/engines?page=a%2Bb%3D", api.call_args_list[1].args[1])

    def test_workitem_parameter_contract_and_secret_redaction(self):
        config = self.config()
        config["metadata"]["headers"] = {"Authorization": "secret"}
        job = fb.workitem("owner", "dev", config)
        self.assertEqual("owner.FamilyBridgeRfa2024+dev", job["activityId"])
        self.assertEqual("put", job["arguments"]["result"]["verb"])
        self.assertEqual("get", job["arguments"]["geometry"]["verb"])
        with self.assertRaises(fb.BridgeError):
            fb.workitem("owner.bad", "dev", config)
        config["geometry"]["url"] = "http://insecure.example/"
        with self.assertRaises(fb.BridgeError):
            fb.workitem("owner", "dev", config)

    def test_ambiguous_submit_is_not_retried_and_leaves_receipt(self):
        with tempfile.TemporaryDirectory() as tmp:
            receipt = Path(tmp) / "job.json"
            client = fb.Client()
            with patch.object(client, "api", side_effect=fb.BridgeError("timeout")) as api:
                with self.assertRaises(fb.BridgeError):
                    fb.submit(client, {"activityId": "owner.Activity+dev"}, receipt)
                self.assertEqual(1, api.call_count)
            self.assertEqual("submitting", fb.load_json(receipt)["state"])
            with self.assertRaises(FileExistsError):
                fb.submit(client, {"activityId": "owner.Activity+dev"}, receipt)

    def test_job_receipt_does_not_store_signed_urls(self):
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()):
            receipt = Path(tmp) / "job.json"
            client = fb.Client()
            with patch.object(client, "api", return_value={"id": "abc-123", "status": "pending"}):
                self.assertEqual("abc-123", fb.submit(client, fb.workitem("owner", "dev", self.config()), receipt))
            self.assertNotIn("https", receipt.read_text())

    def test_existing_version_and_alias_only_fallback_on_conflict(self):
        client = fb.Client()
        with patch.object(client, "api", side_effect=[fb.HttpError(409), {"version": 2}]) as api:
            self.assertEqual(2, fb.create_version(client, "appbundles", {"id": "App", "engine": fb.ENGINE})["version"])
            self.assertEqual("/appbundles/App/versions", api.call_args.args[1])
        with patch.object(client, "api", side_effect=fb.HttpError(403)) as api:
            with self.assertRaises(fb.HttpError):
                fb.create_version(client, "appbundles", {"id": "App"})
            self.assertEqual(1, api.call_count)

    def test_poll_stops_on_success_and_failure(self):
        client = fb.Client()
        with patch.object(client, "api", side_effect=[{"status": "pending"}, {"status": "success"}]) as api, \
                patch.object(fb.time, "sleep"), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual("success", fb.status(client, "job-1", wait=10)["status"])
            self.assertEqual(2, api.call_count)
        with patch.object(client, "api", return_value={"status": "failedInstructions"}), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual("failedInstructions", fb.status(client, "job-1", wait=10)["status"])

    def test_download_refuses_html_and_preserves_existing_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "out.rfa"
            with patch.object(fb, "transfer", return_value=b"<html>login</html>"):
                with self.assertRaises(fb.BridgeError):
                    fb.download("https://example.org/out", output)
            self.assertFalse(output.exists())
            output.write_bytes(b"keep")
            with patch.object(fb, "transfer", return_value=bytes.fromhex("D0CF11E0A1B11AE1")):
                with self.assertRaises(FileExistsError):
                    fb.download("https://example.org/out", output)
            self.assertEqual(b"keep", output.read_bytes())

    def test_stage_validates_all_inputs_before_upload(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(fb, "transfer") as network:
            folder = Path(tmp)
            self.package(folder)
            config = self.config()
            config["geometry"]["upload_url"] = "https://example.org/upload"
            with self.assertRaises(fb.BridgeError):
                fb.stage(folder, folder / "missing.rft", config)
            network.assert_not_called()

    def test_multipart_file_is_last_and_binary_is_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            file = Path(tmp) / "bundle.zip"
            file.write_bytes(b"\x00\xffZIP")
            data, content_type = fb.multipart({"key": "folder/file", "policy": "signed"}, file)
            self.assertLess(data.index(b'name="policy"'), data.index(b'name="file"'))
            self.assertIn(b"\x00\xffZIP", data)
            self.assertIn("boundary=FamilyBridge", content_type)

    def bundle(self, folder):
        file = folder / 'bundle.zip'
        with zipfile.ZipFile(file, 'w') as archive:
            for name in ('PackageContents.xml', 'Contents/FamilyBridge.addin',
                         'Contents/FamilyBridge.Automation.dll', 'Contents/DesignAutomationBridge.dll'):
                archive.writestr('FamilyBridgeAutomation.bundle/' + name, b'mock')
        return file

    def test_publish_uploads_before_alias_and_never_starts_job(self):
        with tempfile.TemporaryDirectory() as tmp:
            bundle = self.bundle(Path(tmp))
            client = fb.Client()
            calls = []
            def api(method, route, body=None):
                calls.append(route)
                if route == '/appbundles':
                    return {'version': 1, 'uploadParameters': {'endpointURL': 'https://example.org/upload',
                                                              'formData': {'key': 'zip'}}}
                if route == '/activities':
                    return {'version': 1}
                return {}
            def uploaded(*args):
                calls.append('upload')
                return b''
            with patch.object(client, 'engines', return_value=[fb.ENGINE]), \
                    patch.object(client, 'api', side_effect=api), patch.object(fb, 'transfer', side_effect=uploaded), \
                    contextlib.redirect_stdout(io.StringIO()):
                fb.publish(client, bundle, 'owner', 'dev')
            self.assertEqual(['/appbundles', 'upload', '/appbundles/FamilyBridgeAutomation/aliases',
                              '/activities', '/activities/FamilyBridgeRfa2024/aliases'], calls)

    def test_failed_bundle_upload_does_not_activate_alias(self):
        with tempfile.TemporaryDirectory() as tmp:
            bundle = self.bundle(Path(tmp))
            client = fb.Client()
            result = {'version': 1, 'uploadParameters': {'endpointURL': 'https://example.org/upload', 'formData': {}}}
            with patch.object(client, 'engines', return_value=[fb.ENGINE]), \
                    patch.object(client, 'api', return_value=result) as api, \
                    patch.object(fb, 'transfer', side_effect=fb.HttpError(403)):
                with self.assertRaises(fb.HttpError):
                    fb.publish(client, bundle, 'owner', 'dev')
                self.assertEqual(1, api.call_count)

    def test_stage_uploads_correct_bytes_and_verbs(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            self.package(folder)
            template = folder / 'generic.rft'
            template.write_bytes(b'template mock')
            config = self.config()
            for key in ('geometry', 'metadata', 'familyTemplate'):
                config[key]['upload_url'] = 'https://example.org/put/' + key
            with patch.object(fb, 'transfer') as network, contextlib.redirect_stdout(io.StringIO()):
                fb.stage(folder, template, config)
            self.assertEqual(3, network.call_count)
            self.assertEqual('PUT', network.call_args.args[1])
            self.assertEqual(b'template mock', network.call_args.args[2])

    def test_report_redacts_signed_urls_and_bearer(self):
        with tempfile.TemporaryDirectory() as tmp:
            report = Path(tmp) / 'job.log'
            with patch.object(fb.Client, 'api', return_value={
                    'status': 'failedInstructions', 'reportUrl': 'https://example.org/report?secret=ABC'}), \
                    patch.object(fb, 'transfer', return_value=b'Failed https://example.org/file?secret=ABC Bearer TOKEN'), \
                    contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(1, fb.main(['status', 'job-1', '--report', str(report)]))
            self.assertNotIn('ABC', report.read_text())
            self.assertNotIn('TOKEN', report.read_text())


if __name__ == "__main__":
    unittest.main()
