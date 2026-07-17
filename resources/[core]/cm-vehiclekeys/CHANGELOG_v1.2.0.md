# cm-vehiclekeys v1.2.0

- Added session-only family vehicle keys without changing legal vehicle ownership.
- Family keys store family ID, family name, vehicle ID and required rank tier.
- Every engine/lock/drive/store/trunk/info lookup revalidates access through cm-family.
- Added allowlisted server exports for family key grant and revocation.
- Family keys are revoked on character unload/disconnect, family or vehicle resource stop, and server restart.
- Manual owner-lent temporary keys remain separate and are not removed by family-only revocation.
