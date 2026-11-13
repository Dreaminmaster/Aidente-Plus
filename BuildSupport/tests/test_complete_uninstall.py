"""Exercise production shell control flow inside disposable fixtures, never /Library or root services.

Only fixed filesystem roots, the expected uid, and system tools are substituted.
The production path, restore, backup-validation, and removal logic is otherwise unchanged.
"""
import os
import pathlib
import plistlib
import shlex
import subprocess
import tempfile
import unittest

PROJECT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = (PROJECT / 'BuildSupport/install_local_control.sh').read_text()


class CompleteUninstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='aidente-uninstall-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.library = self.root / 'Library'
        self.base = self.library / 'PrivilegedHelperTools'
        self.service = self.base / 'com.aidente.app.local'
        self.daemons = self.library / 'LaunchDaemons'
        self.root_library = self.root / 'private/var/root/Library'
        for directory in [self.base, self.daemons, self.root_library / 'Preferences']:
            directory.mkdir(parents=True, exist_ok=True)
        self.log = self.root / 'events'
        self.flags = self.root / 'flags'
        self.flags.mkdir()
        self.tools = self.root / 'tools'
        self.tools.mkdir()
        self.make_tool('launchctl', 'echo "launchctl $*" >> ' + shlex.quote(str(self.log)) + '\nif test "$1" = print; then test -e ' + shlex.quote(str(self.flags / 'stuck-service')) + '; else exit 0; fi\n')
        self.make_tool('codesign', 'echo "codesign $*" >> ' + shlex.quote(str(self.log)) + '\ntest ! -e ' + shlex.quote(str(self.flags / 'bad-signature')) + '\n')
        self.make_tool('defaults', '''
case "$*" in
 'read com.aidente.app.control firmwareLimitBeforeAidente') test -e FLAGS/snapshot ;;
 'read com.aidente.app.control energyModesBeforeAidente') test -e FLAGS/energy-snapshot ;;
 'read com.aidente.app.control nativeLimitBeforeAidente') test -e FLAGS/native-snapshot ;;
 'read com.aidente.app.control nativePreferencesBeforeAidente') test -e FLAGS/native-preferences ;;
 'read com.aidente.app.control') test -e FLAGS/domain ;;
 'delete com.aidente.app.control') echo preferences-deleted >> LOG; rm -f FLAGS/domain FLAGS/snapshot FLAGS/energy-snapshot ;;
 *) exit 99 ;;
esac
'''.replace('FLAGS', shlex.quote(str(self.flags))).replace('LOG', shlex.quote(str(self.log))))
        script = SOURCE.replace('/private/var/root', str(self.root / 'private/var/root'))
        # Replace the system Library only, without rewriting the fixture's /root/Library suffix.
        script = script.replace('=/Library/', '=' + str(self.library) + '/')
        script = script.replace(' /Library', ' ' + str(self.library))
        script = script.replace('app=/Applications/Aidente.app', 'app=' + str(self.root / 'Applications/Aidente.app'))
        script = script.replace('export PATH=/usr/bin:/bin:/usr/sbin:/sbin',
                                'export PATH=' + str(self.tools) + ':/usr/bin:/bin:/usr/sbin:/sbin')
        script = script.replace('test "$(id -u)" = 0', 'test "$(id -u)" = ' + str(os.getuid()))
        script = script.replace('"$(stat -f %u "$1")" = 0', '"$(stat -f %u "$1")" = ' + str(os.getuid()))
        script = script.replace('"$(stat -f %u "$plist")" = 0', '"$(stat -f %u "$plist")" = ' + str(os.getuid()))
        script = script.replace('"$(stat -f %u "$dest/AidenteControl")" = 0',
                                '"$(stat -f %u "$dest/AidenteControl")" = ' + str(os.getuid()))
        script = script.replace('/usr/bin/defaults', str(self.tools / 'defaults'))
        # The uninstaller must have no remaining live system deletion paths.
        self.assertNotIn('base=/Library', script)
        self.assertNotIn('safe_directory /Library', script)
        self.script = self.root / 'installer.sh'
        self.script.write_text(script)

    def make_tool(self, name, body):
        path = self.tools / name
        path.write_text('#!/bin/sh\n' + body)
        path.chmod(0o755)
        return path

    def install_fixture(self, fail_restore=False):
        self.service.mkdir()
        helper = self.service / 'AidenteControl'
        helper.write_text('#!/bin/sh\necho restore >> ' + shlex.quote(str(self.log)) +
                          '\nexit ' + ('1' if fail_restore else '0') + '\n')
        helper.chmod(0o755)
        (self.service / 'client.plist').write_bytes(plistlib.dumps({'clientCDHash': 'a' * 40}))
        (self.daemons / 'com.aidente.app.control.local.plist').write_bytes(plistlib.dumps({'Label': 'com.aidente.app.control.local'}))
        (self.flags / 'domain').touch()

    def run_script(self, mode='complete-uninstall'):
        return subprocess.run(['/bin/sh', str(self.script), mode], text=True, capture_output=True, timeout=10)

    def events(self):
        return self.log.read_text() if self.log.exists() else ''

    def test_success_restores_then_cleans_service_and_backups(self):
        self.install_fixture()
        old = self.base / '.aidente-local.ABCDEFGH'
        old.mkdir()
        (old / 'new-service').mkdir()
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('COMPLETE_SERVICE_REMOVAL_OK', result.stdout)
        self.assertFalse(self.service.exists())
        self.assertFalse(list(self.base.glob('.aidente-local.*')))
        self.assertFalse(list(self.daemons.iterdir()))
        self.assertLess(self.events().index('restore'), self.events().index('preferences-deleted'))

    def test_restore_failure_retains_service_data_and_old_backups(self):
        self.install_fixture(fail_restore=True)
        old = self.base / '.aidente-local.ABCDEFGH'
        old.mkdir()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.service.exists())
        self.assertTrue(old.exists())
        self.assertTrue((self.flags / 'domain').exists())
        self.assertIn('launchctl bootstrap system', self.events())
        self.assertNotIn('preferences-deleted', self.events())

    def test_symlink_backup_rejected_before_restore(self):
        self.install_fixture()
        outside = self.root / 'keep'
        outside.mkdir()
        (outside / 'sentinel').write_text('keep')
        (self.base / '.aidente-local.ABCDEFGH').symlink_to(outside)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((outside / 'sentinel').read_text(), 'keep')
        self.assertNotIn('restore', self.events())

    def test_unknown_backup_contents_not_deleted(self):
        self.install_fixture()
        backup = self.base / '.aidente-local.ABCDEFGH'
        backup.mkdir()
        (backup / 'personal.txt').write_text('keep')
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((backup / 'personal.txt').exists())
        self.assertNotIn('restore', self.events())

    def test_orphan_firmware_snapshot_is_preserved(self):
        (self.flags / 'snapshot').touch()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.flags / 'snapshot').exists())
        self.assertNotIn('preferences-deleted', self.events())

    def test_orphan_energy_snapshot_is_preserved(self):
        (self.flags / 'energy-snapshot').touch()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.flags / 'energy-snapshot').exists())

    def test_no_service_is_idempotent(self):
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.run_script().returncode, 0)
        self.assertFalse(list(self.base.iterdir()))

    def test_normal_disable_keeps_recovery_backup(self):
        self.install_fixture()
        result = self.run_script('uninstall')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(list(self.base.glob('.aidente-local.*'))), 1)
        self.assertTrue((self.flags / 'domain').exists())

    def test_service_must_stop_before_restoration(self):
        self.install_fixture()
        (self.flags / 'stuck-service').touch()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.service.exists())
        self.assertNotIn('restore', self.events())
        self.assertNotIn('preferences-deleted', self.events())

    def test_invalid_signature_retains_recovery_components(self):
        self.install_fixture()
        (self.flags / 'bad-signature').touch()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(self.service.exists())
        self.assertNotIn('restore', self.events())

    def test_missing_executable_retains_service_registration(self):
        self.install_fixture()
        (self.service / 'AidenteControl').unlink()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.daemons / 'com.aidente.app.control.local.plist').exists())
        self.assertNotIn('preferences-deleted', self.events())

    def test_orphan_native_preferences_are_preserved(self):
        (self.flags / 'native-preferences').touch()
        (self.flags / 'domain').touch()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.flags / 'native-preferences').exists())
        self.assertNotIn('preferences-deleted', self.events())

    def test_orphan_native_snapshot_is_preserved(self):
        (self.flags / 'native-snapshot').touch()
        (self.flags / 'domain').touch()
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.flags / 'native-snapshot').exists())
        self.assertNotIn('preferences-deleted', self.events())

    def test_other_app_untouched(self):
        self.install_fixture()
        official = self.base / 'com.apphousekitchen.aldente-pro.helper'
        official.write_text('keep')
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(official.read_text(), 'keep')


if __name__ == '__main__':
    unittest.main(verbosity=2)
