Free Buds Manager
================

INSTALL / INSTALAR
  1. Drag "FreeBudsManager" onto "Applications".
     Arraste "FreeBudsManager" para "Applications" (Aplicativos).
  2. Open it. Allow Bluetooth when macOS asks.
     Abra o app e permita o Bluetooth quando o macOS pedir.

If macOS says it cannot install the app or blocks the first launch, that is because this build is not
notarized by Apple. Just drag the app to Applications yourself, then run this once in Terminal:

Se o macOS disser que nao consegue instalar ou bloquear a primeira abertura, e porque o app nao e
notarizado pela Apple. Arraste o app para Aplicativos e rode isto uma vez no Terminal:

  xattr -dr com.apple.quarantine "/Applications/Free Buds Manager.app"

"Pause when removed": macOS asks to let the app control Music/Spotify (Automation). Browsers and other
players also need Accessibility (System Settings > Privacy & Security > Accessibility).
"Pausar ao remover": o macOS pede para o app controlar o Music/Spotify (Automacao). Navegadores e outros
players tambem precisam de Acessibilidade.
