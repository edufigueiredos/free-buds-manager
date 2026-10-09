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

  xattr -dr com.apple.quarantine /Applications/FreeBudsManager.app

"Pause when removed" also needs Accessibility (System Settings > Privacy & Security > Accessibility)
so the app can pause this Mac's music.
"Pausar ao remover" tambem precisa de Acessibilidade para o app pausar a musica do Mac.
