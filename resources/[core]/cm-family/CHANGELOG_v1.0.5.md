# cm-family v1.0.5

- Detect legacy `cm_family_ranks.grade` columns at startup.
- Dual-write `tier` and `grade` for default and custom rank creation.
- Read the effective rank authority from `grade` on legacy schemas.
- Prevent `Duplicate entry '<family>-0' for key 'uq_rank_grade'`.
- Make founder and invited-member inserts compatible with id-less `cm_family_members` tables.
- Added optional migration `007_rank_grade_compat_v1.0.5.sql`.
