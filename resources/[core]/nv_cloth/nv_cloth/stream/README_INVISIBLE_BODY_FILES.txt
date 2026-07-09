INVISIBLE BODY MESHES FOR PROP-ONLY ACCESSORY CAPTURE
======================================================

WHY
---
Accessory props attach to a BONE, not to visible skin:
  - hat      -> head bone
  - glasses  -> head bone
  - earrings -> head bone
  - watches  -> wrist bone (lives on the ARMS/UPPR component, index 3)

To capture a prop ALONE with no body skin, we hide the body component that owns
the bone. The bone still exists when the mesh is hidden, so the prop stays
attached and floats by itself.

Head props already work: this resource ships invisible head meshes
(mp_m_freemode_01^head_000_r.ydd / female), so the head is fully hidden and the
hat/glasses/earrings render alone.

The ONLY body part that has no built-in invisible mesh is the ARM (component 3).
Setting arm component 3 to -1 hides it on MOST models, but a few freemode
configs fall back to a default bare arm. On those, the watch shows a stub of
skin. To guarantee a clean, skin-free watch on EVERY model, add invisible arm
override meshes below.

WHAT TO ADD (optional, only if a watch still shows a bare-arm stub)
-------------------------------------------------------------------
Put invisible override .ydd files in THIS stream folder with these EXACT names
(the ^ symbol is required; no spaces, no backslashes):

  mp_m_freemode_01^uppr_000_r.ydd      (male arms/upper - holds the wrist bone)
  mp_f_freemode_01^uppr_000_r.ydd      (female arms/upper)

Optional extras if you ever want other limbs guaranteed skin-free:
  mp_m_freemode_01^lowr_000_r.ydd      (legs)
  mp_f_freemode_01^lowr_000_r.ydd
  mp_m_freemode_01^feet_000_r.ydd      (feet)
  mp_f_freemode_01^feet_000_r.ydd
  mp_m_freemode_01^hand_000_r.ydd      (hands, if separate on your build)
  mp_f_freemode_01^hand_000_r.ydd

HOW TO MAKE AN INVISIBLE OVERRIDE MESH
--------------------------------------
The file must still be SKINNED to the skeleton (keep the bone weights) so the
prop attaches in the right place. You cannot ship an empty/zero-vertex file.
Make it the same way the invisible head files were made:

Tools: OpenIV (to extract the original) + Blender with the Sollumz add-on
       (to edit and re-export). This is the standard free toolchain.

Steps:
  1. In OpenIV, open the game's mp_m_freemode_01 ped and extract the real
     component mesh you want to hide, e.g.:
         models/cdimages/streamedpeds_mp/mp_m_freemode_01.rpf
         -> mp_m_freemode_01^uppr_000_r.ydd
     (female is in mp_f_freemode_01 similarly.)

  2. Import that .ydd into Blender with Sollumz.

  3. Keep the ARMATURE and the vertex groups / bone weights intact. Do NOT
     delete the skeleton binding — that is what positions the wrist bone.

  4. Make the geometry invisible. Two common ways:
       a) Scale every vertex of the mesh to ~0 (collapse it to a point), OR
       b) Assign a fully transparent / alpha-zero material, OR
       c) Move all faces far inside the body so they never show.
     Option (a) is the most reliable — a collapsed mesh renders nothing.

  5. Export back to .ydd with Sollumz, using the SAME filename
     (mp_m_freemode_01^uppr_000_r.ydd).

  6. Drop it in this stream folder. Restart the resource.

Because the file overrides the base game component only while THIS resource is
running (this_is_a_map is set in fxmanifest.lua), it will not affect players
outside the clothing admin.

VERIFY
------
Use /vehgreen and the admin capture on a watch. With the invisible uppr meshes
present, the watch should render alone with no arm/hand skin at all, on every
model, at the default tight watch camera.

NOTE
----
You usually DON'T need these files. The resource already:
  - hides the head for hat/glasses/earrings (prop-only, no skin), and
  - hides the arm (component 3 -> -1) for watches, which is skin-free on most
    models, plus a tight watch camera that crops any leftover stub.
Only add the uppr override meshes if you still see a bare arm on specific watch
models.
