Optional self-hosted fonts. Drop these two files here to stop the dashboard
reaching out to fonts.googleapis.com on open:

  archivo-variable.woff2         https://fonts.google.com/specimen/Archivo
  jetbrains-mono-variable.woff2  https://fonts.google.com/specimen/JetBrains+Mono

Download the family, take the variable .woff2 from the archive, and rename it
to match exactly. fxmanifest.lua already ships html/assets/fonts/*.woff2, so no
manifest edit is needed. With the files absent the stylesheet falls back to
Google Fonts, then to the system stack -- nothing breaks either way.
