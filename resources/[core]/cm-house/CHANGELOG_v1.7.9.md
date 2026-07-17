# cm-house v1.7.9 — Family access diagnostics and vehicle gate

## Fixed

- Family access denials now report the missing rank permission instead of only a generic owner message.
- Uses cm-family v1.1.6's diagnostic export when available without trusting it as authorization.
- Shared family vehicle release now fails closed if cm-family errors or cannot positively authorize the exact vehicle.
- Private owner vehicles remain private until shared from the Family Vehicles menu.
- Updated the family integration contract version.
