const AdminClinicCredentialRequests = (() => {
  const $ = (id) => document.getElementById(id);
  const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
  function showError(error) { $('requestAlert').className = 'alert error'; $('requestAlert').textContent = error?.message || 'Could not complete this decision.'; }
  async function decide(id, approved) {
    const note = approved ? '' : prompt('Rejection note for the clinic:');
    if (!approved && !note?.trim()) return;
    if (approved && !confirm('Approve this protected registration-number change?')) return;
    try { await API.clinics.decideCredentialChange(id, { approved, decision_note: note?.trim() || '' }); Toast.success(approved ? 'Credential change approved' : 'Credential change rejected'); await load(); }
    catch (error) { showError(error); }
  }
  async function load() {
    try {
      const status = $('requestStatus').value;
      const response = await API.clinics.adminCredentialChangeRequests(status ? { status } : null);
      $('requestList').innerHTML = (response.data || []).length ? response.data.map((row) => `<article class="control-list-item"><div><strong>${esc(row.name_en || row.name_ar)} <small dir="ltr">(${esc(row.owner_email)})</small></strong><small>Current: ${esc(row.current_registration_number || '—')} → Requested: ${esc(row.requested_registration_number)}</small><small>Reason: ${esc(row.reason)}</small>${row.decision_note ? `<small>Decision: ${esc(row.decision_note)}</small>` : ''}</div>${row.status === 'pending' ? `<div><button class="btn btn-primary btn-sm" data-approve="${esc(row.id)}">Approve</button><button class="btn btn-danger btn-sm" data-reject="${esc(row.id)}">Reject</button></div>` : `<span class="request-status">${esc(row.status)}</span>`}</article>`).join('') : '<p class="text-muted">No credential requests in this status.</p>';
      $('requestList').querySelectorAll('[data-approve]').forEach((button) => button.onclick = () => decide(button.dataset.approve, true));
      $('requestList').querySelectorAll('[data-reject]').forEach((button) => button.onclick = () => decide(button.dataset.reject, false));
    } catch (error) { showError(error); }
  }
  async function init() {
    if (!API.requireAuth('admin-clinic-credential-requests.html')) return;
    if (await AuthGate.verifySession() !== 'valid') return;
    if (!['admin', 'super_admin'].includes(AuthGate.getVerifiedUser()?.role)) { location.href = 'dashboard.html'; return; }
    $('requestStatus').addEventListener('change', load); await load();
  }
  return { init };
})();
