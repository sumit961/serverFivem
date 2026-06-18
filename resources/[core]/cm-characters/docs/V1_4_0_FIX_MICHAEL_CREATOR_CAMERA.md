# v1.4.0 Fix Michael + Creator Camera Preview

Changes:

- Selector preview dummy can no longer use GTA story models such as Michael/player_zero.
- Preview dummy always uses `mp_m_freemode_01` or `mp_f_freemode_01` based on selected character gender/appearance.
- Real player ped is hidden more aggressively while selector is open so the default GTA player ped cannot appear behind the UI.
- Selector preview now uses the same position/camera style as character creation:
  - position: `916.70, 46.18, 110.66, 57.78`
  - close camera offset like creator camera
  - FOV `30.0`
  - idle animation from creator
- Exact creator Z is preserved instead of forcing ground Z, so the preview does not fall below the creator scene.
