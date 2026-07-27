import subprocess

js_code = """
// ── 8. DELETE A RELEASE RECORD (Sysadmin Only) ──────────────────────────────
router.delete('/:id', auth_middleware_1.authenticateUser, (0, auth_middleware_1.requireRole)('sysadmin'), async (req, res) => {
  const { id } = req.params;
  try {
    const existing = await runBypassingRLS('SELECT file_path FROM app_versions WHERE id = $1', [id]);
    if (existing.rows.length === 0) {
      return res.status(404).json({ error: 'not_found', message: 'Sürüm bulunamadı.' });
    }
    const filePath = existing.rows[0].file_path;
    if (filePath && fs_1.default.existsSync(filePath)) {
      try { fs_1.default.unlinkSync(filePath); } catch (_) {}
    }
    await runBypassingRLS('DELETE FROM app_versions WHERE id = $1', [id]);
    return res.json({ success: true, message: 'Sürüm kaydı silindi.' });
  } catch (err) {
    console.error('Delete release error:', err);
    return res.status(500).json({ error: 'server_error', message: err.message || 'Sürüm silinirken hata oluştu.' });
  }
});
exports.default = router;
"""

node_script = f"""
const fs = require('fs');
const file = '/app/dist/modules/release/release.controller.js';
let content = fs.readFileSync(file, 'utf8');
if (!content.includes("router.delete('/:id'")) {{
  content = content.replace("exports.default = router;", {repr(js_code.strip())});
  fs.writeFileSync(file, content);
  console.log("PATCHED_DIST_RELEASE_CONTROLLER");
}}
"""

res = subprocess.run(['docker', 'exec', 'serenut-backend', 'node', '-e', node_script], capture_output=True, text=True)
print("STDOUT:", res.stdout)
print("STDERR:", res.stderr)
