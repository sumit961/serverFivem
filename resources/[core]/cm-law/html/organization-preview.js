/* Deliberate local design fixture. Never supplies data to a FiveM session. */
(() => {
  if (typeof GetParentResourceName === 'function' || location.hostname.startsWith('cfx-nui-')
      || !['http:', 'https:', 'file:'].includes(location.protocol)) return;
  const org = new URLSearchParams(location.search).get('preview');
  if (!org) return;
  const names = ['Zolt Bolt', 'Alexander Stone', 'Sarah Connor', 'Marcus Vance', 'David Miller', 'James Reed'];
  const rankNames = ['Chief of Police', 'Captain', 'Sergeant', 'Officer', 'Cadet'];
  const rankTiers = [12, 9, 6, 3, 1];
  const callsigns = ['1A-01', '1A-02', '1B-12', '2C-05', '3A-22', '4B-01'];
  const labels = {
    'law.mdt': { label: 'MDT Full Access', description: 'Allows creating, editing, and deleting incident reports.' },
    'law.armory': { label: 'Armory Access', description: 'Grant authorization to pull heavy weapons and equipment.' },
    'law.manage_members': { label: 'Roster Management', description: 'Promote, demote, or hire lower-tier officers.' },
    'law.manage_dispatch': { label: 'Dispatch & GPS Overrides', description: 'Assign units to calls and trigger high-priority alerts.' },
    'preview.vault': { label: 'Organization Vault / Payroll', description: 'Manage budget allocations and officer payouts.' },
    'law.fleet': { label: 'Vehicle Fleet Operations', description: 'Spawn tactical units and command vehicles.' },
  };
  const permissions = Object.fromEntries(Object.keys(labels).map(key => [key, key !== 'preview.vault']));
  const ranks = rankNames.map((name, i) => ({ id: i + 1, name, tier: rankTiers[i], is_leader: i === 0, permissions: { ...permissions } }));
  const roster = names.map((name, i) => { const rankIndex = Math.min(i, rankNames.length - 1); return { character_id: String(101 + i), name, rank_id: rankIndex + 1, rank_name: rankNames[rankIndex], tier: rankTiers[rankIndex],
    is_leader: i === 0, on_duty: [0, 1, 4].includes(i), online: [0, 1, 2, 4].includes(i), callsign: callsigns[i] }; });
  const orgNames = { lspd: 'Los Santos Police Department', sheriff: 'Blaine County Sheriff’s Office', sahp: 'San Andreas Highway Patrol', army: 'San Andreas Army', fib: 'Federal Investigation Bureau' };
  window.postMessage({ action: 'open', data: {
    ok: true, characterId: '101',
    organization: { id: org, label: orgNames[org] || 'San Andreas State Police', leaderName: 'Zolt Bolt', hub: {
      tagline: 'Law Enforcement & Tactical Response Command', rating: 'Grade A+', founded: 'Jan 2026', headquarters: 'Mission Row Station', radioFrequency: '100.1 MHz', primaryRecruiter: 'Capt. Alexander Stone',
      announcement: 'All units must review the updated force escalation protocols before starting shift duties. Weekly squad briefings occur every Friday at 20:00. Ensure all equipment is checked out via the armory terminal.',
    } },
    member: { characterId: '101', tier: 12, isLeader: true, suspended: false, permissions },
    summary: { memberCount: 6, onlineCount: 4, onDutyCount: 24, fleetConfigured: 12, balance: 1450000 },
    canManage: true, canInvite: true, canViewMembers: true, canManageRanks: true, canManagePermissions: true, canInspectRankPermissions: true, canViewActivity: true,
    roster, ranks, permissions: labels,
    recentActivity: [
      { createdAt: '2026-09-24 14:32', actorName: 'Zolt Bolt (Chief)', action: 'member_promoted', detail: { targetCid: '102', rank: 'Captain' } },
      { createdAt: '2026-09-24 12:15', actorName: 'Alexander Stone (Captain)', action: 'invite_accepted', detail: { targetCid: '104', rank: 'Officer' } },
    ],
  } }, '*');
})();
